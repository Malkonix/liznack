import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'datos/catalogo_repo.dart';
import 'datos/modelos.dart';
import 'datos/ventas_repo.dart';
import 'nucleo/sesion.dart';
import 'sync/api_cliente.dart';
import 'sync/sync_service.dart';

enum EstadoSync { sincronizado, pendiente, sincronizando, error, soloLocal }

/// Estado compartido de la app. Toda escritura va primero a SQLite local;
/// la sincronización es un efecto secundario que nunca bloquea una venta.
class Tienda extends ChangeNotifier {
  Tienda({
    required this.db,
    required this.catalogo,
    required this.ventas,
    required this.sync,
    required this.almacen,
    required this.dispositivoId,
    String? servidorUrl,
    this.sesion,
    this.autoSync = true,
  }) : servidorUrl = servidorUrl ?? servidorPorDefecto {
    api = ApiCliente(baseUrl: this.servidorUrl);
    sync.api = api;
  }

  static const servidorPorDefecto = String.fromEnvironment(
    'LIZNACK_SERVIDOR',
    defaultValue: 'http://10.0.2.2:3000',
  );

  final Database db;
  final CatalogoRepo catalogo;
  final VentasRepo ventas;
  final SyncService sync;
  final AlmacenSesion almacen;
  final String dispositivoId;

  /// En pruebas se apaga para sincronizar a mano y no depender de tiempos.
  final bool autoSync;

  late ApiCliente api;
  String servidorUrl;
  Sesion? sesion;

  EstadoGuardado _estado = EstadoGuardado.vacio;
  bool _sincronizando = false;
  String? _error;
  List<String> _avisos = const [];
  int _version = 0;
  Timer? _debounce;
  Timer? _periodico;
  Future<void> _refresco = Future<void>.value();

  int get version => _version;
  int get pendientes => _estado.pendientes;
  DateTime? get ultimaVez => _estado.ultimaVez;
  String? get error => _error;
  List<String> get avisos => _avisos;
  int get ultimaRev => _estado.ultimaRev;

  EstadoSync get estadoSync {
    if (_sincronizando) return EstadoSync.sincronizando;
    if (sesion == null || !sesion!.sincroniza) return EstadoSync.soloLocal;
    if (_error != null) return EstadoSync.error;
    if (pendientes > 0) return EstadoSync.pendiente;
    return EstadoSync.sincronizado;
  }

  bool get sincronizando => _sincronizando;

  static Future<String> obtenerDispositivoId(Database db) async {
    final filas = await db.query('meta', where: 'clave = ?', whereArgs: ['dispositivo_id'], limit: 1);
    if (filas.isNotEmpty) return filas.first['valor'] as String;
    final id = const Uuid().v4();
    await db.insert('meta', {'clave': 'dispositivo_id', 'valor': id});
    return id;
  }

  Future<void> iniciar() async {
    servidorUrl = await almacen.leerServidor() ?? servidorPorDefecto;
    api = ApiCliente(baseUrl: servidorUrl);
    sync.api = api;
    sesion = await almacen.leerSesion();
    await _actualizarUsuarioIdRepos();
    await refrescarEstado();
    if (autoSync) {
      _periodico ??= Timer.periodic(const Duration(seconds: 90), (_) {
        if (sesion?.sincroniza == true) unawaited(sincronizar());
      });
      if (sesion?.sincroniza == true) unawaited(sincronizar());
    }
  }

  Future<void> refrescarEstado() async {
    _estado = await sync.leerEstado();
    _error = _estado.error;
    _avisos = _estado.avisos;
    notifyListeners();
  }

  /// Encadena los refrescos para que no se pisen entre sí ni con el cierre.
  Future<void> _encolarRefresco() {
    final siguiente = _refresco.then((_) => refrescarEstado()).catchError((Object _) {});
    _refresco = siguiente;
    return siguiente;
  }

  Future<void> sincronizar() async {
    final actual = sesion;
    if (actual == null || !actual.sincroniza) {
      await refrescarEstado();
      return;
    }
    if (_sincronizando) return;

    _sincronizando = true;
    notifyListeners();
    try {
      final resultado = await sync.sincronizar(token: actual.token!);
      _error = null;
      _avisos = resultado.avisos;
    } on ErrorApi catch (error) {
      _error = error.mensaje;
    } catch (_) {
      _error = 'No se pudo sincronizar.';
    } finally {
      _sincronizando = false;
      _estado = await sync.leerEstado();
      _error = _estado.error;
      _avisos = _estado.avisos;
      // Sube la versión para que las pantallas vuelvan a leer la base: los
      // badges de "Pendiente" tienen que desaparecer al sincronizar.
      _version++;
      notifyListeners();
    }
  }

  void _programarSincronizacion() {
    _debounce?.cancel();
    if (!autoSync || sesion?.sincroniza != true) return;
    _debounce = Timer(const Duration(seconds: 1), () => unawaited(sincronizar()));
  }

  Future<void> _cambioLocal() {
    _version++;
    notifyListeners();
    _programarSincronizacion();
    return _encolarRefresco();
  }

  Future<Venta> registrarVenta(List<LineaCarrito> lineas) async {
    final venta = await ventas.registrar(lineas);
    await _cambioLocal();
    return venta;
  }

  Future<void> anularVenta(String ventaId) async {
    await ventas.anular(ventaId);
    await _cambioLocal();
  }

  Future<String> crearProducto({
    required String nombre,
    required int precioCentavos,
    required int stockInicial,
  }) async {
    final id = await catalogo.crear(
      nombre: nombre,
      precioCentavos: precioCentavos,
      stockInicial: stockInicial,
    );
    await _cambioLocal();
    return id;
  }

  Future<void> editarProducto({
    required Producto producto,
    required String nombre,
    required int precioCentavos,
  }) async {
    await catalogo.editar(producto: producto, nombre: nombre, precioCentavos: precioCentavos);
    await _cambioLocal();
  }

  Future<void> archivarProducto(String productoId) async {
    await catalogo.archivar(productoId);
    await _cambioLocal();
  }

  Future<void> restaurarProducto(String productoId) async {
    await catalogo.restaurar(productoId);
    await _cambioLocal();
  }

  Future<void> reponerStock(String productoId, int cantidad) async {
    await catalogo.reponer(productoId: productoId, cantidad: cantidad);
    await _cambioLocal();
  }

  Future<void> ingresar({required String email, required String clave}) async {
    final resultado = await api.ingresar(email.trim(), clave);
    await _adoptarCuenta(resultado);
  }

  Future<void> crearCuenta({required String email, required String clave}) async {
    final resultado = await api.registrarse(email.trim(), clave);
    await _adoptarCuenta(resultado);
  }

  Future<void> _adoptarCuenta(ResultadoSesion resultado) async {
    // El dueño de los datos locales se guarda aparte de la sesión: si alguien
    // cierra sesión y entra con otra cuenta, no debe heredar ventas ajenas.
    final propietario = await _leerPropietario();
    final esDeOtraCuenta = propietario != null &&
        !propietario.startsWith('local-') &&
        propietario != resultado.usuarioId;
    if (esDeOtraCuenta) {
      await _borrarDatosLocales();
    } else if (propietario != null && propietario.startsWith('local-')) {
      // Lo vendido sin cuenta pasa a ser de esta cuenta y se sube.
      await _cambiarPropietarioDatos(propietario, resultado.usuarioId);
    }
    sesion = Sesion(
      usuarioId: resultado.usuarioId,
      email: resultado.email,
      token: resultado.token,
    );
    await almacen.guardarSesion(sesion);
    await _fijarPropietario(resultado.usuarioId);
    await _actualizarUsuarioIdRepos();
    await sync.reiniciarRevision();
    _version++;
    notifyListeners();
    await sincronizar();
  }

  Future<void> usarSinCuenta() async {
    sesion = Sesion.local();
    await almacen.guardarSesion(sesion);
    // Si el teléfono ya tiene datos de una cuenta real, se conserva ese dueño:
    // así esos datos nunca se suben a otra cuenta que se cree después.
    final propietario = await _leerPropietario();
    if (propietario == null || propietario.startsWith('local-')) {
      await _fijarPropietario(sesion!.usuarioId);
    }
    await sync.reiniciarRevision();
    await _actualizarUsuarioIdRepos();
    _version++;
    notifyListeners();
    await refrescarEstado();
  }

  /// Los datos del teléfono pertenecen a un dueño, que no siempre coincide con
  /// la sesión: sin cuenta se sigue viendo lo que ya era del teléfono.
  Future<void> _actualizarUsuarioIdRepos() async {
    final actual = sesion;
    final uid = actual == null
        ? ''
        : actual.sincroniza
            ? actual.usuarioId
            : (await _leerPropietario() ?? actual.usuarioId);
    catalogo.usuarioId = uid;
    ventas.usuarioId = uid;
    sync.usuarioId = uid;
  }

  /// Pasa las filas de un dueño a otro sin perderlas (lo vendido sin cuenta
  /// cuando por fin se crea la cuenta).
  Future<void> _cambiarPropietarioDatos(String desde, String hacia) async {
    await db.transaction((txn) async {
      for (final tabla in ['productos', 'ventas', 'venta_items', 'movimientos']) {
        await txn.update(
          tabla,
          {'usuario_id': hacia},
          where: 'usuario_id = ?',
          whereArgs: [desde],
        );
      }
    });
  }

  Future<String?> _leerPropietario() async {
    final filas = await db.query(
      'meta',
      where: 'clave = ?',
      whereArgs: ['propietario_local'],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return filas.first['valor'] as String;
  }

  Future<void> _fijarPropietario(String usuarioId) async {
    await db.insert(
      'meta',
      {
        'clave': 'propietario_local',
        'valor': usuarioId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> cerrarSesion() async {
    sesion = null;
    await almacen.guardarSesion(null);
    await sync.reiniciarRevision();
    await _actualizarUsuarioIdRepos();
    _version++;
    notifyListeners();
    await refrescarEstado();
  }

  Future<void> cambiarServidor(String entrada) async {
    final url = normalizarUrlServidor(entrada);
    if (url == null) {
      throw ErrorApi('Dirección inválida. Ejemplo: http://192.168.0.10:3000');
    }
    servidorUrl = url;
    api = ApiCliente(baseUrl: url);
    sync.api = api;
    await almacen.guardarServidor(url);
    notifyListeners();
  }

  Future<bool> probarServidor() => api.salud();

  Future<void> _borrarDatosLocales() async {
    await db.transaction((txn) async {
      for (final tabla in ['venta_items', 'ventas', 'movimientos', 'productos']) {
        await txn.delete(tabla);
      }
      await txn.delete(
        'meta',
        where: 'clave NOT IN (?, ?)',
        whereArgs: ['dispositivo_id', 'propietario_local'],
      );
    });
  }

  /// Cierra la base cuando ya no queda ningún refresco en curso.
  Future<void> cerrar() async {
    _debounce?.cancel();
    _periodico?.cancel();
    await _refresco;
    dispose();
    await db.close();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodico?.cancel();
    super.dispose();
  }
}

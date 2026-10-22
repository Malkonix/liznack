import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'feed_actualizaciones.dart';
import 'instalador_apk.dart';
import 'version_app.dart';

/// Progreso de la descarga: bytes recibidos y total esperado.
typedef Progreso = void Function(int recibidos, int total);

class ErrorActualizacion implements Exception {
  const ErrorActualizacion(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Lo que se sabe después de mirar el feed.
class EstadoActualizacion {
  const EstadoActualizacion({required this.actual, this.disponible});

  /// La versión que corre en este teléfono.
  final VersionApp actual;

  /// El último release publicado.
  final ReleaseInfo? disponible;

  /// Hay algo para instalar.
  bool get hayNovedad =>
      disponible != null && disponible!.version.esMasNuevaQue(actual);
}

/// Busca, descarga, **verifica** e instala una versión nueva desde GitHub.
///
/// La verificación no es opcional: el APK se compara contra el `SHA256SUMS` del
/// mismo release y, si no cuadra, se borra y no se instala. Es la única defensa
/// contra una descarga cortada, un proxy que devuelve una página de error con
/// código 200, o un adjunto cambiado a mano. Un APK corrupto no llegaría a
/// instalarse —Android verifica la firma— pero uno *sustituido* y firmado con
/// otra clave sí sería un problema real, y el SHA-256 lo corta antes de que el
/// usuario vea el diálogo de instalación.
class ServicioActualizacion {
  ServicioActualizacion({
    FeedActualizaciones? feed,
    this.instalador = const InstaladorApk(),
    http.Client? cliente,
    this.directorio,
  })  : feed = feed ?? FeedActualizaciones(),
        cliente = cliente ?? http.Client();

  final FeedActualizaciones feed;
  final InstaladorApk instalador;
  final http.Client cliente;

  /// De dónde se baja el APK. Por defecto, la caché de la app (la pregunta al
  /// canal nativo); se puede cambiar para probar.
  final Future<Directory> Function()? directorio;
  /// Si un trozo tarda más que esto en llegar, la conexión está muerta aunque
  /// el socket siga abierto. Sin este tope la descarga se queda colgada.
  static const Duration pausaMaxima = Duration(seconds: 45);

  /// Tope de la descarga.
  static const Duration tiempoEspera = Duration(minutes: 10);

  /// Mira el feed y dice si hay algo más nuevo.
  Future<EstadoActualizacion> buscar() async {
    final release = await feed.ultimo();
    return EstadoActualizacion(actual: VersionApp.actual, disponible: release);
  }

  /// La carpeta donde se baja el APK.
  Future<Directory> _carpeta() async {
    if (directorio != null) return directorio!();
    final cache = await instalador.cacheDir();
    if (cache.isEmpty) {
      throw const ErrorActualizacion(
          'No se encontró la carpeta de descargas del teléfono.');
    }
    final dir = Directory('$cache/actualizaciones');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Baja el APK, lo verifica y se lo pasa al instalador del sistema.
  Future<void> descargarEInstalar(ReleaseInfo release, {Progreso? onProgreso}) async {
    // Con la pantalla apagada el sistema duerme la CPU y la descarga se corta a
    // media. El wake lock la mantiene viva; es de CPU, no de pantalla, así que
    // el teléfono se apaga igual.
    await instalador.mantenerDespierto();
    try {
      final esperado = await _shaEsperado(release);
      final dir = await _carpeta();
      final parcial = File('${dir.path}/${release.apkNombre}.part');
      final completo = File('${dir.path}/${release.apkNombre}');

      // Si falla, el fichero a medias NO se borra: la próxima vez se reanuda
      // desde ahí en vez de volver a bajar el APK entero.
      final real = await _descargar(release.apkUrl, parcial, onProgreso);

      if (real != esperado) {
        // Aquí sí se borra: lo descargado no sirve y reanudarlo perpetuaría
        // el error.
        if (await parcial.exists()) await parcial.delete();
        throw ErrorActualizacion(
            'El SHA-256 de ${release.apkNombre} no cuadra con '
            '${FeedActualizaciones.nombreSums}: la descarga se descarta.');
      }
      if (await completo.exists()) await completo.delete();
      await parcial.rename(completo.path);
      await instalador.instalar(completo.path);
    } finally {
      await instalador.soltarDespierto();
    }
  }

  /// El SHA-256 que el release dice que tiene el APK.
  Future<String> _shaEsperado(ReleaseInfo release) async {
    final bytes = await _bajar(release.sumsUrl);
    // Formato de sha256sum: "<hash>  <nombre>", una línea por fichero.
    for (final linea in const LineSplitter().convert(utf8.decode(bytes))) {
      final partes = linea.trim().split(RegExp(r'\s+'));
      if (partes.length >= 2 &&
          partes.last.replaceFirst('*', '') == release.apkNombre) {
        return partes.first.toLowerCase();
      }
    }
    throw ErrorActualizacion(
        '${FeedActualizaciones.nombreSums} no menciona ${release.apkNombre}.');
  }

  Future<List<int>> _bajar(Uri uri) async {
    try {
      final r = await cliente.get(uri).timeout(tiempoEspera);
      if (r.statusCode != 200) {
        throw ErrorActualizacion('$uri respondió ${r.statusCode}.');
      }
      return r.bodyBytes;
    } on ErrorActualizacion {
      rethrow;
    } catch (e) {
      throw ErrorActualizacion('No se pudo descargar $uri: $e');
    }
  }

  /// Descarga a fichero calculando el SHA-256 al vuelo, sin cargar el APK en
  /// memoria.
  ///
  /// Reanuda si ya hay un fichero a medias: pide el resto con una cabecera
  /// `Range` y vuelve a pasar por el hash lo ya descargado, para que el
  /// SHA-256 final cubra el fichero entero y no solo el último tramo.
  Future<String> _descargar(Uri uri, File destino, Progreso? onProgreso) async {
    var yaTengo = await destino.exists() ? await destino.length() : 0;
    final hash = _HashAcumulador();

    if (yaTengo > 0) {
      await for (final trozo in destino.openRead()) {
        hash.anadir(trozo);
      }
    }

    final peticion = http.Request('GET', uri);
    if (yaTengo > 0) peticion.headers['Range'] = 'bytes=$yaTengo-';

    final http.StreamedResponse resp;
    try {
      resp = await cliente.send(peticion).timeout(tiempoEspera);
    } catch (e) {
      throw ErrorActualizacion('No se pudo empezar la descarga: $e');
    }

    if (yaTengo > 0 && resp.statusCode == 200) {
      // El servidor ignoró el Range y manda el fichero entero: hay que empezar
      // de cero, o el hash saldría sobre los bytes duplicados.
      yaTengo = 0;
      hash.reiniciar();
      await destino.delete();
    } else if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw ErrorActualizacion('La descarga respondió ${resp.statusCode}.');
    }

    final total = (resp.contentLength ?? 0) + yaTengo;
    var recibidos = yaTengo;
    final salida =
        destino.openWrite(mode: yaTengo > 0 ? FileMode.append : FileMode.write);
    try {
      await for (final trozo in resp.stream.timeout(pausaMaxima)) {
        salida.add(trozo);
        hash.anadir(trozo);
        recibidos += trozo.length;
        onProgreso?.call(recibidos, total);
      }
    } on TimeoutException {
      throw const ErrorActualizacion(
          'La descarga se quedó parada. Se guarda lo bajado y se reanuda al '
          'reintentar.');
    } finally {
      await salida.close();
    }
    hash.cerrar();
    return hash.hex;
  }

  void cerrar() {
    cliente.close();
    feed.cerrar();
  }
}

/// SHA-256 que se va calculando de a trozos.
class _HashAcumulador {
  _HashAcumulador() {
    _datos = _Acumulador();
    _suma = sha256.startChunkedConversion(_datos);
  }

  late _Acumulador _datos;
  late ByteConversionSink _suma;

  void anadir(List<int> trozo) => _suma.add(trozo);

  /// Empieza de cero: se usa cuando el servidor no respeta el `Range` y hay que
  /// volver a bajar el fichero entero.
  void reiniciar() {
    _datos = _Acumulador();
    _suma = sha256.startChunkedConversion(_datos);
  }

  void cerrar() => _suma.close();

  String get hex => _datos.digest?.toString() ?? '';
}

/// Recibe el resumen del hash.
class _Acumulador implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest datos) {
    digest = datos;
  }

  @override
  void close() {}
}

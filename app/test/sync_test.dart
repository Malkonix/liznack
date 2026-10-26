import 'dart:io';

import 'package:liznack/datos/modelos.dart';
import 'package:liznack/nucleo/sesion.dart';
import 'package:liznack/tienda.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'ayuda_pruebas.dart';

/// Estas pruebas levantan el servidor real (`server/src/server.js`) y usan
/// SQLite real: no hay mocks del protocolo de sincronización.
void main() {
  final hayNode = Process.runSync('node', ['--version']).exitCode == 0;

  group('sincronización real contra el servidor', () {
    late Directory temporal;
    late Process servidor;
    late String baseUrl;

    setUpAll(() async {
      temporal = Directory.systemTemp.createTempSync('liznack_servidor_');
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final puerto = socket.port;
      await socket.close();

      final raiz = p.basename(Directory.current.path) == 'app'
          ? p.dirname(Directory.current.path)
          : Directory.current.path;
      servidor = await Process.start(
        'node',
        ['--disable-warning=ExperimentalWarning', 'src/server.js'],
        workingDirectory: p.join(raiz, 'server'),
        environment: {
          'PORT': '$puerto',
          'DATABASE_FILE': p.join(temporal.path, 'servidor.db'),
        },
      );
      servidor.stdout.drain<void>();
      servidor.stderr.drain<void>();
      baseUrl = 'http://127.0.0.1:$puerto';

      final limite = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(limite)) {
        try {
          final respuesta = await http.get(Uri.parse('$baseUrl/api/salud'));
          if (respuesta.statusCode == 200) return;
        } on Exception {
          // todavía arrancando
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      fail('El servidor no arrancó en $baseUrl');
    });

    tearDownAll(() async {
      servidor.kill();
      try {
        await servidor.exitCode.timeout(const Duration(seconds: 5));
      } on Object {
        // ya terminó
      }
      temporal.deleteSync(recursive: true);
    });

    test('una venta offline llega al servidor y a otro teléfono sin duplicarse', () async {
      final email = 'nene${DateTime.now().microsecondsSinceEpoch}@ejemplo.com';
      final telefono = await tiendaDePrueba(servidor: baseUrl, almacen: AlmacenMemoria());
      addTearDown(telefono.cerrar);

      await telefono.crearCuenta(email: email, clave: 'dulce123');
      expect(telefono.sesion?.sincroniza, isTrue);

      await telefono.crearProducto(nombre: 'Chocolate', precioCentavos: 500, stockInicial: 10);
      final producto = (await telefono.catalogo.listar()).single;
      final venta = await telefono.registrarVenta([
        LineaCarrito(producto: producto, cantidad: 2),
      ]);

      // Vendió sin haber sincronizado: quedó pendiente, pero la venta ya está.
      expect(telefono.estadoSync, EstadoSync.pendiente);
      expect(telefono.pendientes, 2);

      await telefono.sincronizar();
      expect(telefono.estadoSync, EstadoSync.sincronizado);
      expect(telefono.pendientes, 0);

      final token = telefono.sesion!.token!;
      final inventario = await telefono.api.inventario(token);
      expect(inventario.single['stock_actual'], 8);
      final resumenRemoto = await telefono.api.ventasRemotas(token);
      expect(resumenRemoto['cantidad'], 1);
      expect(resumenRemoto['total_centavos'], 1000);

      // Segundo teléfono con la misma cuenta: recibe todo del servidor.
      final otro = await tiendaDePrueba(servidor: baseUrl, dispositivoId: 'tel-2');
      addTearDown(otro.cerrar);
      await otro.ingresar(email: email, clave: 'dulce123');

      final productosOtro = await otro.catalogo.listar();
      expect(productosOtro.single.stockActual, 8);
      final historialOtro = await otro.ventas.recientes();
      expect(historialOtro.single.id, venta.id);
      expect(historialOtro.single.totalCentavos, 1000);
      expect((await otro.ventas.resumenDia()).totalCentavos, 1000);

      // Vende el segundo teléfono y el primero lo ve al sincronizar.
      await otro.registrarVenta([
        LineaCarrito(producto: productosOtro.single, cantidad: 1),
      ]);
      await otro.sincronizar();
      await telefono.sincronizar();

      expect((await telefono.catalogo.listar()).single.stockActual, 7);
      expect((await telefono.ventas.recientes()).length, 2);

      // Reenviar la misma venta (como si el teléfono no supiera si llegó) no duplica.
      await telefono.db.update('ventas', {'pendiente': 1}, where: 'id = ?', whereArgs: [venta.id]);
      await telefono.sincronizar();
      final resumenFinal = await telefono.api.ventasRemotas(token);
      expect(resumenFinal['cantidad'], 2);
      expect((await telefono.catalogo.listar()).single.stockActual, 7);
    });

    test('sin conexión la venta se guarda y sube al volver la red', () async {
      final email = 'offline${DateTime.now().microsecondsSinceEpoch}@ejemplo.com';
      final telefono = await tiendaDePrueba(servidor: baseUrl);
      addTearDown(telefono.cerrar);

      await telefono.crearCuenta(email: email, clave: 'dulce123');
      await telefono.crearProducto(nombre: 'Gomitas', precioCentavos: 250, stockInicial: 5);
      await telefono.sincronizar();

      await telefono.cambiarServidor('http://127.0.0.1:1');
      final producto = (await telefono.catalogo.listar()).single;
      await telefono.registrarVenta([LineaCarrito(producto: producto, cantidad: 1)]);

      await telefono.sincronizar();
      expect(telefono.estadoSync, EstadoSync.error);
      expect(telefono.pendientes, greaterThan(0));
      expect(telefono.error, isNotNull);
      expect((await telefono.catalogo.listar()).single.stockActual, 4);

      await telefono.cambiarServidor(baseUrl);
      await telefono.sincronizar();
      expect(telefono.estadoSync, EstadoSync.sincronizado);
      expect(telefono.pendientes, 0);

      final inventario = await telefono.api.inventario(telefono.sesion!.token!);
      expect(inventario.single['stock_actual'], 4);
    });

    test('cerrar sesión y entrar con otra cuenta no mezcla los datos', () async {
      final emailA = 'cuentaA${DateTime.now().microsecondsSinceEpoch}@ejemplo.com';
      final emailB = 'cuentaB${DateTime.now().microsecondsSinceEpoch}@ejemplo.com';
      final telefono = await tiendaDePrueba(servidor: baseUrl);
      addTearDown(telefono.cerrar);

      await telefono.crearCuenta(email: emailA, clave: 'dulce123');
      await telefono.crearProducto(nombre: 'Chocolate', precioCentavos: 500, stockInicial: 10);
      await telefono.sincronizar();
      await telefono.cerrarSesion();
      expect(telefono.sesion, isNull);

      // Pasa por "sin cuenta" mirando lo que ya era suyo, sin subirlo a nadie.
      await telefono.usarSinCuenta();
      expect((await telefono.catalogo.listar()).single.nombre, 'Chocolate');

      await telefono.crearCuenta(email: emailB, clave: 'dulce123');
      expect(await telefono.catalogo.listar(), isEmpty);
      expect(await telefono.api.inventario(telefono.sesion!.token!), isEmpty);

      // Al volver a la cuenta A, sus datos siguen en el servidor.
      await telefono.cerrarSesion();
      await telefono.ingresar(email: emailA, clave: 'dulce123');
      expect((await telefono.catalogo.listar()).single.nombre, 'Chocolate');
    });

    test('lo vendido sin cuenta se sube al crear la cuenta', () async {
      final email = 'adopta${DateTime.now().microsecondsSinceEpoch}@ejemplo.com';
      final telefono = await tiendaDePrueba(servidor: baseUrl);
      addTearDown(telefono.cerrar);

      await telefono.usarSinCuenta();
      await telefono.crearProducto(nombre: 'Galletita', precioCentavos: 300, stockInicial: 4);
      final producto = (await telefono.catalogo.listar()).single;
      await telefono.registrarVenta([LineaCarrito(producto: producto, cantidad: 1)]);
      expect(telefono.estadoSync, EstadoSync.soloLocal);

      await telefono.crearCuenta(email: email, clave: 'dulce123');
      expect(telefono.estadoSync, EstadoSync.sincronizado);

      final inventario = await telefono.api.inventario(telefono.sesion!.token!);
      expect(inventario.single['stock_actual'], 3);
      final resumen = await telefono.api.ventasRemotas(telefono.sesion!.token!);
      expect(resumen['total_centavos'], 300);
    });

    test('un cambio rechazado no se reintenta en cada sincronización', () async {
      final email = 'rechazo${DateTime.now().microsecondsSinceEpoch}@ejemplo.com';
      final telefono = await tiendaDePrueba(servidor: baseUrl, almacen: AlmacenMemoria());
      addTearDown(telefono.cerrar);
      await telefono.crearCuenta(email: email, clave: 'dulce123');

      // Se inserta directo en la base una fila que la app nunca generaría
      // (nombre vacío): el servidor la va a rechazar.
      await telefono.db.insert('productos', {
        'id': 'producto-invalido',
        'nombre': '',
        'precio_centavos': 100,
        'stock_base': 1,
        'activo': 1,
        'actualizado_en': DateTime.now().millisecondsSinceEpoch,
        'dispositivo_id': telefono.dispositivoId,
        'usuario_id': telefono.sesion!.usuarioId,
        'pendiente': 1,
      });

      await telefono.sincronizar();

      expect(telefono.pendientes, 0, reason: 'no puede quedar como pendiente para siempre');
      expect(telefono.rechazados, 1);
      expect(telefono.avisos.join(' '), contains('rechazó'));
      final fila = (await telefono.db
              .query('productos', where: 'id = ?', whereArgs: ['producto-invalido']))
          .single;
      expect(fila['pendiente'], 2);
      // El dato sigue en el teléfono: no se borra nada de lo que cargó el usuario.
      expect(fila['id'], 'producto-invalido');

      // En la siguiente vuelta no se vuelve a mandar.
      final resultado = await telefono.sync.sincronizar(token: telefono.sesion!.token!);
      expect(resultado.enviados, 0);
      await telefono.refrescarEstado();
      expect(telefono.rechazados, 1);
      expect(telefono.pendientes, 0);

      // Si el vendedor corrige el dato, se reintenta y llega.
      await telefono.db.update(
        'productos',
        {
          'nombre': 'Chocolate',
          'actualizado_en': DateTime.now().millisecondsSinceEpoch + 1000,
          'pendiente': 1,
        },
        where: 'id = ?',
        whereArgs: ['producto-invalido'],
      );
      await telefono.sincronizar();
      expect(telefono.pendientes, 0);
      expect(telefono.rechazados, 0);
      final inventario = await telefono.api.inventario(telefono.sesion!.token!);
      expect(inventario.single['nombre'], 'Chocolate');
    });

    test('un producto editado en dos lados conserva el cambio más reciente', () async {
      final email = 'conflicto${DateTime.now().microsecondsSinceEpoch}@ejemplo.com';
      final telefonoA = await tiendaDePrueba(servidor: baseUrl, dispositivoId: 'tel-1');
      addTearDown(telefonoA.cerrar);
      await telefonoA.crearCuenta(email: email, clave: 'dulce123');
      await telefonoA.crearProducto(nombre: 'Chocolate', precioCentavos: 500, stockInicial: 10);
      await telefonoA.sincronizar();

      final telefonoB = await tiendaDePrueba(servidor: baseUrl, dispositivoId: 'tel-2');
      addTearDown(telefonoB.cerrar);
      await telefonoB.ingresar(email: email, clave: 'dulce123');

      final productoB = (await telefonoB.catalogo.listar()).single;
      final productoA = (await telefonoA.catalogo.listar()).single;

      // B cambia el nombre con un reloj más nuevo y sincroniza primero.
      await telefonoB.db.update(
        'productos',
        {
          'nombre': 'Chocolate grande',
          'actualizado_en': DateTime.now().millisecondsSinceEpoch + 60000,
          'dispositivo_id': 'tel-2',
          'pendiente': 1,
        },
        where: 'id = ?',
        whereArgs: [productoB.id],
      );
      await telefonoB.sincronizar();

      // A cambia el precio con un reloj más viejo: pierde, pero no rompe nada.
      await telefonoA.db.update(
        'productos',
        {
          'precio_centavos': 700,
          'actualizado_en': DateTime.now().millisecondsSinceEpoch - 60000,
          'dispositivo_id': 'tel-1',
          'pendiente': 1,
        },
        where: 'id = ?',
        whereArgs: [productoA.id],
      );
      await telefonoA.sincronizar();

      final enA = (await telefonoA.catalogo.listar()).single;
      expect(enA.nombre, 'Chocolate grande');
      expect(enA.precioCentavos, 500);
      expect(enA.pendiente, isFalse);
      expect(telefonoA.avisos, isNotEmpty);

      final enServidor = await telefonoA.api.inventario(telefonoA.sesion!.token!);
      expect(enServidor.single['nombre'], 'Chocolate grande');
      expect(enServidor.single['precio_centavos'], 500);
    });
  }, skip: hayNode ? false : 'Node no está instalado: no se puede levantar el servidor.');
}

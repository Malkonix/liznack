import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liznack/actualizacion/feed_actualizaciones.dart';
import 'package:liznack/actualizacion/servicio_actualizacion.dart';
import 'package:liznack/actualizacion/version_app.dart';
import 'package:pub_semver/pub_semver.dart';

/// Un release como lo devuelve la API de GitHub.
Map<String, dynamic> releaseJson({
  String etiqueta = 'v0.1.0-build.8',
  List<String> nombres = const ['liznack-0.1.0-build.8.apk', 'SHA256SUMS'],
  int tamanoApk = 1234,
}) {
  return {
    'tag_name': etiqueta,
    'name': 'Liznack 0.1.0 · build 8',
    'body': '**APK**: instalar `liznack-0.1.0-build.8.apk`.\n\n### Cambios\n\n- algo',
    'published_at': '2026-10-22T14:11:04Z',
    'assets': [
      for (final nombre in nombres)
        {
          'name': nombre,
          'size': nombre.endsWith('.apk') ? tamanoApk : 1234,
          'browser_download_url':
              'https://github.com/Malkonix/liznack/releases/download/$etiqueta/$nombre',
        }
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('la versión', () {
    test('se lee de la etiqueta del release', () {
      final v = VersionApp.desdeEtiqueta('v0.1.0-build.8');
      expect(v, isNotNull);
      expect(v!.version, Version(0, 1, 0));
      expect(v.build, 8);
    });

    test('una etiqueta sin build vale, pero con build cero', () {
      final v = VersionApp.desdeEtiqueta('v0.2.1');
      expect(v!.version, Version(0, 2, 1));
      expect(v.build, 0);
    });

    test('una etiqueta que no es versión no vale', () {
      expect(VersionApp.desdeEtiqueta('la ultima'), isNull);
      expect(VersionApp.desdeEtiqueta(''), isNull);
    });

    test('gana la versión más nueva y, a igual, el build más nuevo', () {
      final vieja = VersionApp(Version(0, 1, 0), 8);
      final nueva = VersionApp(Version(0, 1, 0), 9);
      final mayor = VersionApp(Version(0, 2, 0), 1);
      expect(nueva.esMasNuevaQue(vieja), isTrue);
      expect(vieja.esMasNuevaQue(nueva), isFalse);
      expect(mayor.esMasNuevaQue(nueva), isTrue);
      expect(vieja.esMasNuevaQue(mayor), isFalse);
    });
  });

  group('el feed de GitHub', () {
    test('lee el APK y el SHA256SUMS del release', () {
      final release = FeedActualizaciones.leer(releaseJson());
      expect(release.version.version, Version(0, 1, 0));
      expect(release.version.build, 8);
      expect(release.apkNombre, 'liznack-0.1.0-build.8.apk');
      expect(release.apkUrl.toString(),
          'https://github.com/Malkonix/liznack/releases/download/v0.1.0-build.8/liznack-0.1.0-build.8.apk');
      expect(release.sumsUrl.toString(), contains('SHA256SUMS'));
      expect(release.notas, contains('### Cambios'));
    });

    test('sin SHA256SUMS no se instala nada', () {
      expect(
        () => FeedActualizaciones.leer(
            releaseJson(nombres: const ['liznack-0.1.0-build.8.apk'])),
        throwsA(isA<ErrorFeed>()),
      );
    });

    test('sin el APK del release tampoco', () {
      expect(
        () => FeedActualizaciones.leer(releaseJson(nombres: const ['SHA256SUMS'])),
        throwsA(isA<ErrorFeed>()),
      );
    });

    test('el feed toma el release más reciente', () async {
      final cliente = MockClient((_) async => http.Response(
            jsonEncode(releaseJson()),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final feed = FeedActualizaciones(cliente: cliente);
      final release = await feed.ultimo();
      expect(release.etiqueta, 'v0.1.0-build.8');
    });

    test('sin releases publicados avisa, no rompe', () async {
      final cliente = MockClient((_) async => http.Response('{}', 404));
      final feed = FeedActualizaciones(cliente: cliente);
      expect(feed.ultimo(), throwsA(isA<ErrorFeed>()));
    });
  });

  group('la descarga', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('liznack-actualizacion');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    /// Un cliente que responde el APK y el SHA256SUMS.
    MockClient clienteQueResponde(String apk, String sha) {
      return MockClient((peticion) async {
        if (peticion.url.path.endsWith('SHA256SUMS')) {
          return http.Response('$sha  liznack-0.1.0-build.8.apk\n', 200);
        }
        return http.Response.bytes(utf8.encode(apk), 200);
      });
    }

    String shaDe(String texto) => sha256.convert(utf8.encode(texto)).toString();

    test('baja el APK, lo verifica y se lo pasa al instalador', () async {
      const contenido = 'un APK de mentira';
      final rutasInstaladas = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.caramelo.liznack/instalador'),
        (llamada) async {
          if (llamada.method == 'instalar') {
            rutasInstaladas.add((llamada.arguments as Map)['ruta'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('com.caramelo.liznack/instalador'), null);
      });

      final servicio = ServicioActualizacion(
        feed: FeedActualizaciones(cliente: clienteQueResponde(contenido, shaDe(contenido))),
        cliente: clienteQueResponde(contenido, shaDe(contenido)),
        directorio: () async => temp,
      );

      final release = FeedActualizaciones.leer(releaseJson());
      await servicio.descargarEInstalar(release);

      expect(rutasInstaladas, hasLength(1));
      final apk = File(rutasInstaladas.first);
      expect(await apk.exists(), isTrue);
      expect(await apk.readAsString(), contenido);
      // El fichero a medias no queda dando vueltas.
      expect(File('${temp.path}/liznack-0.1.0-build.8.apk.part').existsSync(), isFalse);
    });

    test('si el SHA no cuadra, la descarga se descarta', () async {
      const contenido = 'un APK de mentira';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.caramelo.liznack/instalador'),
        (llamada) async => null,
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('com.caramelo.liznack/instalador'), null);
      });

      final servicio = ServicioActualizacion(
        feed: FeedActualizaciones(cliente: clienteQueResponde(contenido, '0' * 64)),
        cliente: clienteQueResponde(contenido, '0' * 64),
        directorio: () async => temp,
      );

      final release = FeedActualizaciones.leer(releaseJson());
      await expectLater(
        servicio.descargarEInstalar(release),
        throwsA(isA<ErrorActualizacion>()),
      );
      // No queda ni el APK ni el fichero a medias.
      expect(File('${temp.path}/liznack-0.1.0-build.8.apk').existsSync(), isFalse);
      expect(File('${temp.path}/liznack-0.1.0-build.8.apk.part').existsSync(), isFalse);
    });

    test('si lo bajado ya está completo, no se vuelve a pedir', () async {
      // Pasa si la app se cerró después de terminar la descarga y antes de
      // instalarla: pedir el resto daría 416 y quedaría trabada.
      const contenido = 'un APK de mentira';
      final parcial =
          File('${temp.path}/liznack-0.1.0-build.8.apk.part');
      await parcial.writeAsString(contenido);

      final rutasInstaladas = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.caramelo.liznack/instalador'),
        (llamada) async {
          if (llamada.method == 'instalar') {
            rutasInstaladas.add((llamada.arguments as Map)['ruta'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('com.caramelo.liznack/instalador'), null);
      });

      var pedidosDelApk = 0;
      final cliente = MockClient((peticion) async {
        if (peticion.url.path.endsWith('SHA256SUMS')) {
          return http.Response('${shaDe(contenido)}  liznack-0.1.0-build.8.apk\n', 200);
        }
        pedidosDelApk++;
        return http.Response.bytes(utf8.encode(contenido), 200);
      });

      final servicio = ServicioActualizacion(
        feed: FeedActualizaciones(cliente: cliente),
        cliente: cliente,
        directorio: () async => temp,
      );

      final release = FeedActualizaciones.leer(
        releaseJson(tamanoApk: utf8.encode(contenido).length),
      );
      await servicio.descargarEInstalar(release);

      expect(pedidosDelApk, 0, reason: 'no debía pedir el APK de nuevo');
      expect(rutasInstaladas, hasLength(1));
      expect(await File(rutasInstaladas.first).readAsString(), contenido);
    });
  });
}

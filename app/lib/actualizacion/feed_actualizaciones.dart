import 'dart:convert';

import 'package:http/http.dart' as http;

import 'version_app.dart';

/// Un release publicado, reducido a lo que el actualizador necesita.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.etiqueta,
    required this.notas,
    required this.publicado,
    required this.apkNombre,
    required this.apkUrl,
    required this.apkTamano,
    required this.sumsUrl,
  });

  final VersionApp version;

  /// La etiqueta tal cual la publicó el CI (`v0.1.0-build.8`).
  final String etiqueta;

  /// Notas del release: el cuerpo que escribe el workflow.
  final String notas;

  final DateTime? publicado;

  /// Nombre del APK (`liznack-0.1.0-build.8.apk`): es lo que lista el
  /// `SHA256SUMS` y por eso se busca por nombre y no por URL.
  final String apkNombre;
  final Uri apkUrl;
  final int apkTamano;

  /// URL del `SHA256SUMS` del mismo release. Sin él no se instala nada.
  final Uri sumsUrl;
}

class ErrorFeed implements Exception {
  const ErrorFeed(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Lee el último release del repo de Liznack en GitHub.
///
/// El feed va compilado en la app, no configurado en el teléfono: apunta al
/// propio repositorio, que es público, así que no hace falta ni cuenta ni
/// token. La API de GitHub devuelve el release más reciente que no sea
/// borrador ni pre-release, con sus adjuntos y URLs de descarga.
///
/// La API sin sesión tiene un límite de 60 peticiones por hora y por IP: para
/// el uso de la app (un botón y una revisión por día) sobra.
class FeedActualizaciones {
  FeedActualizaciones({http.Client? cliente, this.url = urlPorDefecto})
      : _cliente = cliente ?? http.Client();

  static const urlPorDefecto = String.fromEnvironment(
    'LIZNACK_FEED',
    defaultValue: 'https://api.github.com/repos/Malkonix/liznack/releases/latest',
  );

  /// Nombre del archivo de sumas que publica el release.
  static const nombreSums = 'SHA256SUMS';

  /// Nombre del APK de una versión, tal como lo publica el workflow.
  static String nombreApk(VersionApp version) =>
      'liznack-${version.version}-build.${version.build}.apk';

  final String url;
  final http.Client _cliente;

  /// Cuánto se espera por la respuesta del feed.
  static const Duration tiempoEspera = Duration(seconds: 15);

  /// El último release publicado.
  Future<ReleaseInfo> ultimo() async {
    final uri = Uri.parse(url);
    final http.Response r;
    try {
      r = await _cliente.get(uri, headers: const {
        'Accept': 'application/vnd.github+json',
        // GitHub pide un User-Agent: sin él responde 403.
        'User-Agent': 'Liznack',
      }).timeout(tiempoEspera);
    } catch (e) {
      throw ErrorFeed('No se alcanzó el servidor de actualizaciones: $e');
    }
    if (r.statusCode == 404) {
      throw const ErrorFeed('Todavía no hay ninguna versión publicada.');
    }
    if (r.statusCode == 403) {
      throw const ErrorFeed(
          'GitHub no respondió (límite de peticiones). Probá de nuevo en un rato.');
    }
    if (r.statusCode != 200) {
      throw ErrorFeed('El servidor de actualizaciones respondió ${r.statusCode}.');
    }
    final Object? decodificado;
    try {
      decodificado = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      throw const ErrorFeed('La respuesta no era JSON.');
    }
    if (decodificado is! Map<String, dynamic>) {
      throw const ErrorFeed('La respuesta no es un release.');
    }
    return leer(decodificado);
  }

  /// Convierte el JSON de un release de GitHub. Público para poder probarlo.
  static ReleaseInfo leer(Map<String, dynamic> json) {
    final etiqueta = (json['tag_name'] ?? '').toString();
    final version = VersionApp.desdeEtiqueta(etiqueta);
    if (version == null) {
      throw ErrorFeed('La etiqueta "$etiqueta" no es una versión.');
    }

    final Map<String, Map<String, dynamic>> adjuntos = {};
    for (final a in (json['assets'] as List?)?.whereType<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[]) {
      final nombre = (a['name'] ?? '').toString();
      if (nombre.isEmpty) continue;
      adjuntos[nombre] = a;
    }

    Uri url(Map<String, dynamic> a) =>
        Uri.parse((a['browser_download_url'] ?? '').toString());

    final sums = adjuntos[nombreSums];
    if (sums == null) {
      throw ErrorFeed(
          'La versión $etiqueta no trae $nombreSums: no se instala sin verificar.');
    }

    final apkNombre = nombreApk(version);
    final apk = adjuntos[apkNombre];
    if (apk == null) {
      throw ErrorFeed('La versión $etiqueta no trae el APK $apkNombre.');
    }

    return ReleaseInfo(
      version: version,
      etiqueta: etiqueta,
      notas: (json['body'] ?? '').toString(),
      publicado: DateTime.tryParse((json['published_at'] ?? '').toString()),
      apkNombre: apkNombre,
      apkUrl: url(apk),
      apkTamano: (apk['size'] is num) ? (apk['size'] as num).toInt() : 0,
      sumsUrl: url(sums),
    );
  }

  void cerrar() => _cliente.close();
}

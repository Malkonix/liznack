import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Quién está usando la app en este teléfono.
///
/// `soloLocal` significa: se puede vender sin internet, pero nada se sincroniza.
class Sesion {
  const Sesion({
    required this.usuarioId,
    required this.email,
    this.token,
    this.soloLocal = false,
  });

  final String usuarioId;
  final String email;
  final String? token;
  final bool soloLocal;

  bool get sincroniza => token != null && !soloLocal;

  factory Sesion.local() => Sesion(
        usuarioId: 'local-${const Uuid().v4()}',
        email: 'Sin cuenta',
        soloLocal: true,
      );

  Map<String, Object?> toJson() => {
        'usuario_id': usuarioId,
        'email': email,
        'token': token,
        'solo_local': soloLocal,
      };

  factory Sesion.fromJson(Map<String, Object?> json) => Sesion(
        usuarioId: json['usuario_id'] as String,
        email: json['email'] as String? ?? 'Sin cuenta',
        token: json['token'] as String?,
        soloLocal: json['solo_local'] as bool? ?? false,
      );
}

/// Guarda la sesión y la dirección del servidor fuera de la base de ventas.
abstract class AlmacenSesion {
  Future<void> guardarSesion(Sesion? sesion);
  Future<Sesion?> leerSesion();
  Future<void> guardarServidor(String url);
  Future<String?> leerServidor();
}

class AlmacenPrefs implements AlmacenSesion {
  AlmacenPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const _claveSesion = 'liznack.sesion';
  static const _claveServidor = 'liznack.servidor';

  @override
  Future<void> guardarSesion(Sesion? sesion) async {
    if (sesion == null) {
      await _prefs.remove(_claveSesion);
    } else {
      await _prefs.setString(_claveSesion, jsonEncode(sesion.toJson()));
    }
  }

  @override
  Future<Sesion?> leerSesion() async {
    final texto = _prefs.getString(_claveSesion);
    if (texto == null) return null;
    try {
      return Sesion.fromJson(jsonDecode(texto) as Map<String, Object?>);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> guardarServidor(String url) => _prefs.setString(_claveServidor, url);

  @override
  Future<String?> leerServidor() async => _prefs.getString(_claveServidor);
}

/// Versión en memoria, para pruebas.
class AlmacenMemoria implements AlmacenSesion {
  Sesion? _sesion;
  String? _servidor;

  @override
  Future<void> guardarSesion(Sesion? sesion) async => _sesion = sesion;

  @override
  Future<Sesion?> leerSesion() async => _sesion;

  @override
  Future<void> guardarServidor(String url) async => _servidor = url;

  @override
  Future<String?> leerServidor() async => _servidor;
}

/// Normaliza lo que escribe el usuario: `192.168.0.10:3000` → `http://192.168.0.10:3000`.
String? normalizarUrlServidor(String entrada) {
  var texto = entrada.trim();
  if (texto.isEmpty) return null;
  if (!texto.contains('://')) texto = 'http://$texto';
  while (texto.endsWith('/')) {
    texto = texto.substring(0, texto.length - 1);
  }
  final uri = Uri.tryParse(texto);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return texto;
}

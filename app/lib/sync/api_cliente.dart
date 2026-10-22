import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ErrorApi implements Exception {
  ErrorApi(this.mensaje, {this.codigo});

  final String mensaje;
  final int? codigo;

  @override
  String toString() => mensaje;
}

class ResultadoSesion {
  const ResultadoSesion({required this.token, required this.usuarioId, required this.email});

  final String token;
  final String usuarioId;
  final String email;
}

class RespuestaSync {
  const RespuestaSync({
    required this.ultimaRev,
    required this.hayMas,
    required this.productos,
    required this.ventas,
    required this.movimientos,
    required this.conflictos,
    required this.rechazados,
  });

  final int ultimaRev;
  final bool hayMas;
  final List<Map<String, Object?>> productos;
  final List<Map<String, Object?>> ventas;
  final List<Map<String, Object?>> movimientos;
  final List<Map<String, Object?>> conflictos;
  final List<Map<String, Object?>> rechazados;
}

/// Cliente HTTP del servidor de Liznack.
class ApiCliente {
  ApiCliente({
    required this.baseUrl,
    http.Client? cliente,
    this.tiempoLimite = const Duration(seconds: 8),
  }) : _cliente = cliente ?? http.Client();

  final String baseUrl;
  final http.Client _cliente;
  final Duration tiempoLimite;

  Uri _url(String ruta) {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$ruta');
  }

  Map<String, String> _cabeceras(String? token) => {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, Object?>> _pedir(
    String metodo,
    String ruta, {
    Object? cuerpo,
    String? token,
  }) async {
    try {
      final uri = _url(ruta);
      final respuesta = metodo == 'GET'
          ? await _cliente.get(uri, headers: _cabeceras(token)).timeout(tiempoLimite)
          : await _cliente
              .post(uri, headers: _cabeceras(token), body: jsonEncode(cuerpo ?? const {}))
              .timeout(tiempoLimite);

      Map<String, Object?> datos;
      if (respuesta.bodyBytes.isEmpty) {
        datos = {};
      } else {
        final decodificado = jsonDecode(utf8.decode(respuesta.bodyBytes));
        if (decodificado is! Map) throw const FormatException('Se esperaba un objeto JSON.');
        datos = Map<String, Object?>.from(decodificado);
      }

      if (respuesta.statusCode >= 400) {
        throw ErrorApi(
          datos['error'] as String? ?? 'El servidor respondió con error (${respuesta.statusCode}).',
          codigo: respuesta.statusCode,
        );
      }
      return datos;
    } on ErrorApi {
      rethrow;
    } on TimeoutException {
      throw ErrorApi('El servidor no respondió a tiempo.');
    } on SocketException {
      throw ErrorApi('No se pudo conectar. Revisá el wifi y la dirección del servidor.');
    } on http.ClientException {
      throw ErrorApi('No se pudo conectar con el servidor.');
    } on FormatException {
      throw ErrorApi('El servidor respondió algo que no entendemos.');
    }
  }

  Future<ResultadoSesion> registrarse(String email, String contrasena) async =>
      _sesionDesde(await _pedir('POST', '/api/registro',
          cuerpo: {'email': email, 'contrasena': contrasena}));

  Future<ResultadoSesion> ingresar(String email, String contrasena) async =>
      _sesionDesde(await _pedir('POST', '/api/login',
          cuerpo: {'email': email, 'contrasena': contrasena}));

  ResultadoSesion _sesionDesde(Map<String, Object?> datos) {
    final usuario = Map<String, Object?>.from(datos['usuario'] as Map);
    return ResultadoSesion(
      token: datos['token'] as String,
      usuarioId: usuario['id'] as String,
      email: usuario['email'] as String,
    );
  }

  Future<RespuestaSync> sincronizar({
    required String token,
    required String dispositivoId,
    required int ultimaRev,
    required Map<String, Object?> cambios,
  }) async {
    final datos = await _pedir('POST', '/api/sync', token: token, cuerpo: {
      'dispositivo_id': dispositivoId,
      'ultima_rev': ultimaRev,
      'cambios': cambios,
    });
    final cambiosServidor = Map<String, Object?>.from(datos['cambios'] as Map? ?? const {});

    List<Map<String, Object?>> lista(Object? valor) {
      if (valor is! List) return const [];
      return valor
          .whereType<Map>()
          .map((e) => Map<String, Object?>.from(e))
          .toList(growable: false);
    }

    return RespuestaSync(
      ultimaRev: (datos['ultima_rev'] as num?)?.toInt() ?? ultimaRev,
      hayMas: datos['hay_mas'] as bool? ?? false,
      productos: lista(cambiosServidor['productos']),
      ventas: lista(cambiosServidor['ventas']),
      movimientos: lista(cambiosServidor['movimientos']),
      conflictos: lista(datos['conflictos']),
      rechazados: lista(datos['rechazados']),
    );
  }

  Future<List<Map<String, Object?>>> inventario(String token) async {
    final datos = await _pedir('GET', '/api/inventario', token: token);
    final lista = datos['productos'];
    if (lista is! List) return const [];
    return lista
        .whereType<Map>()
        .map((e) => Map<String, Object?>.from(e))
        .toList(growable: false);
  }

  Future<Map<String, Object?>> ventasRemotas(String token, {int desde = 0}) async =>
      _pedir('GET', '/api/ventas?desde=$desde', token: token);

  Future<bool> salud() async {
    try {
      final datos = await _pedir('GET', '/api/salud');
      return datos['ok'] == true;
    } on ErrorApi {
      return false;
    }
  }

  void cerrar() => _cliente.close();
}

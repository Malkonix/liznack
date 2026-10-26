import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liznack/nucleo/sesion.dart';
import 'package:liznack/sync/api_cliente.dart';
import 'package:liznack/tienda.dart';

import 'ayuda_pruebas.dart';

/// Qué hace la app cuando el servidor deja de reconocer el token.
///
/// Pasa cuando se reinicia la base del servidor o vence la sesión. Antes la app
/// seguía reintentando con el mismo token y sólo mostraba "Sesión vencida" en
/// Ajustes: el vendedor no tenía forma de arreglarlo desde la pantalla.
void main() {
  test('un 401 cierra la sesión y pide volver a entrar', () async {
    final tienda = await tiendaDePrueba();
    addTearDown(tienda.cerrar);

    tienda.sesion = const Sesion(
      usuarioId: 'usuario-1',
      email: 'nene@ejemplo.com',
      token: 'token-vencido',
    );
    tienda.sync.usuarioId = 'usuario-1';

    final cliente = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'error': 'Sesión vencida o inválida. Volvé a ingresar.',
          })),
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));
    tienda.api = ApiCliente(baseUrl: 'http://127.0.0.1:9', cliente: cliente);
    tienda.sync.api = tienda.api;

    await tienda.sincronizar();

    expect(tienda.sesion, isNull, reason: 'no puede seguir con un token vencido');
    expect(tienda.estadoSync, EstadoSync.soloLocal);
    expect(tienda.avisoSesion, contains('sesión venció'));
    // Los datos del teléfono no se tocan: sólo se cierra la sesión.
    expect(tienda.pendientes, 0);
  });
}

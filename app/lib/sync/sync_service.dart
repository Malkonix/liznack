import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'api_cliente.dart';

class ResultadoSincronizacion {
  const ResultadoSincronizacion({
    required this.enviados,
    required this.recibidos,
    required this.ultimaRev,
    required this.avisos,
  });

  final int enviados;
  final int recibidos;
  final int ultimaRev;
  final List<String> avisos;
}

class EstadoGuardado {
  const EstadoGuardado({
    required this.pendientes,
    required this.ultimaVez,
    required this.error,
    required this.avisos,
    required this.ultimaRev,
  });

  final int pendientes;
  final DateTime? ultimaVez;
  final String? error;
  final List<String> avisos;
  final int ultimaRev;

  static const vacio = EstadoGuardado(
    pendientes: 0,
    ultimaVez: null,
    error: null,
    avisos: [],
    ultimaRev: 0,
  );
}

/// Sube los cambios pendientes y baja los del servidor.
///
/// Reglas:
/// - Las ventas se suben con su UUID y el servidor no las duplica.
/// - El stock es derivado (base + ajustes - ventas), no un número que viaja.
/// - Si el mismo producto cambió en dos lados, gana el `actualizado_en` más
///   nuevo y, si empatan, el `dispositivo_id` mayor. El perdedor recibe aviso.
class SyncService {
  SyncService({
    required this.db,
    required this.api,
    required this.dispositivoId,
    this.usuarioId = '',
  });

  final Database db;
  ApiCliente api;
  final String dispositivoId;

  /// Dueño de los datos locales en este momento. Las filas que se bajan del
  /// servidor se guardan con este `usuario_id`, y solo se sube lo que es suyo.
  String usuarioId;

  static const _limiteProductos = 500;
  static const _limiteVentas = 300;
  static const _limiteMovimientos = 500;

  Future<String?> _meta(String clave) async {
    final filas = await db.query('meta', where: 'clave = ?', whereArgs: [clave], limit: 1);
    if (filas.isEmpty) return null;
    return filas.first['valor'] as String;
  }

  Future<void> _guardarMeta(String clave, String valor) async {
    await db.insert(
      'meta',
      {'clave': clave, 'valor': valor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> contarPendientes() async {
    final filas = await db.rawQuery('''
      SELECT (SELECT COUNT(*) FROM productos   WHERE pendiente = 1 AND usuario_id = ?)
           + (SELECT COUNT(*) FROM ventas      WHERE pendiente = 1 AND usuario_id = ?)
           + (SELECT COUNT(*) FROM movimientos WHERE pendiente = 1 AND usuario_id = ?) AS total
    ''', [usuarioId, usuarioId, usuarioId]);
    return (filas.first['total'] as int?) ?? 0;
  }

  Future<int> leerRev() async => int.tryParse(await _meta('ultima_rev') ?? '0') ?? 0;

  Future<void> reiniciarRevision() async {
    await _guardarMeta('ultima_rev', '0');
    await _guardarMeta('ultimo_error', '');
    await _guardarMeta('avisos', '[]');
  }

  Future<void> registrarError(String mensaje) => _guardarMeta('ultimo_error', mensaje);

  Future<EstadoGuardado> leerEstado() async {
    final pendientes = await contarPendientes();
    final milisegundos = int.tryParse(await _meta('ultima_sync') ?? '');
    final error = await _meta('ultimo_error');
    final avisosJson = await _meta('avisos');
    List<String> avisos = const [];
    if (avisosJson != null && avisosJson.isNotEmpty) {
      try {
        avisos = (jsonDecode(avisosJson) as List).map((e) => '$e').toList();
      } on FormatException {
        avisos = const [];
      }
    }
    return EstadoGuardado(
      pendientes: pendientes,
      ultimaVez: milisegundos == null || milisegundos == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(milisegundos),
      error: (error == null || error.isEmpty) ? null : error,
      avisos: avisos,
      ultimaRev: await leerRev(),
    );
  }

  Future<ResultadoSincronizacion> sincronizar({required String token}) async {
    final envio = await _leerPendientes();
    final enviados = envio.productos.length + envio.ventas.length + envio.movimientos.length;
    final avisos = <String>[];
    var recibidos = 0;
    var ultimaRev = await leerRev();

    try {
      for (var pagina = 0; pagina < 25; pagina++) {
        final respuesta = await api.sincronizar(
          token: token,
          dispositivoId: dispositivoId,
          ultimaRev: ultimaRev,
          cambios: pagina == 0 ? envio.aJson() : const {},
        );

        final cambioRev = respuesta.ultimaRev >= ultimaRev;
        await _aplicarRespuesta(
          respuesta: respuesta,
          envio: pagina == 0 ? envio : null,
          avisos: avisos,
        );
        recibidos += respuesta.productos.length + respuesta.ventas.length + respuesta.movimientos.length;
        if (cambioRev) {
          ultimaRev = respuesta.ultimaRev;
          await _guardarMeta('ultima_rev', '$ultimaRev');
        }
        if (!respuesta.hayMas) break;
      }

      await _guardarMeta('ultimo_error', '');
      await _guardarMeta('ultima_sync', '${DateTime.now().millisecondsSinceEpoch}');
      await _guardarMeta('avisos', jsonEncode(avisos.take(10).toList()));
      return ResultadoSincronizacion(
        enviados: enviados,
        recibidos: recibidos,
        ultimaRev: ultimaRev,
        avisos: avisos,
      );
    } on ErrorApi catch (error) {
      await registrarError(error.mensaje);
      rethrow;
    } catch (error) {
      await registrarError('No se pudo sincronizar.');
      rethrow;
    }
  }

  Future<_Envio> _leerPendientes() async {
    final productos = await db.query(
      'productos',
      where: 'pendiente = 1 AND usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'actualizado_en ASC',
      limit: _limiteProductos,
    );
    final ventas = await db.query(
      'ventas',
      where: 'pendiente = 1 AND usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'actualizado_en ASC',
      limit: _limiteVentas,
    );
    final movimientos = await db.query(
      'movimientos',
      where: 'pendiente = 1 AND usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'creado_en ASC',
      limit: _limiteMovimientos,
    );

    final itemsPorVenta = <String, List<Map<String, Object?>>>{};
    if (ventas.isNotEmpty) {
      final ids = ventas.map((v) => v['id'] as String).toList();
      final items = await db.query(
        'venta_items',
        where: 'venta_id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
      );
      for (final item in items) {
        itemsPorVenta.putIfAbsent(item['venta_id'] as String, () => []).add({
          'id': item['id'],
          'producto_id': item['producto_id'],
          'nombre': item['nombre'],
          'precio_centavos': item['precio_centavos'],
          'cantidad': item['cantidad'],
        });
      }
    }

    return _Envio(
      productos: {
        for (final p in productos)
          p['id'] as String: {
            'id': p['id'],
            'nombre': p['nombre'],
            'precio_centavos': p['precio_centavos'],
            'stock_base': p['stock_base'],
            'activo': (p['activo'] as int? ?? 1) == 1,
            'actualizado_en': p['actualizado_en'],
            'dispositivo_id': p['dispositivo_id'],
          },
      },
      ventas: {
        for (final v in ventas)
          v['id'] as String: {
            'id': v['id'],
            'creado_en': v['creado_en'],
            'total_centavos': v['total_centavos'],
            'anulada': (v['anulada'] as int? ?? 0) == 1,
            'actualizado_en': v['actualizado_en'],
            'dispositivo_id': v['dispositivo_id'],
            'items': itemsPorVenta[v['id']] ?? const [],
          },
      },
      movimientos: {
        for (final m in movimientos)
          m['id'] as String: {
            'id': m['id'],
            'producto_id': m['producto_id'],
            'cantidad': m['cantidad'],
            'motivo': m['motivo'],
            'creado_en': m['creado_en'],
            'dispositivo_id': m['dispositivo_id'],
          },
      },
    );
  }

  Future<void> _aplicarRespuesta({
    required RespuestaSync respuesta,
    required _Envio? envio,
    required List<String> avisos,
  }) async {
    final rechazadosProductos = <String>{};
    final rechazadosVentas = <String>{};
    final rechazadosMovimientos = <String>{};
    for (final rechazo in respuesta.rechazados) {
      final tipo = rechazo['tipo'];
      final id = rechazo['id'] as String?;
      final motivo = rechazo['motivo'] ?? 'datos inválidos';
      if (id != null) {
        if (tipo == 'producto') rechazadosProductos.add(id);
        if (tipo == 'venta') rechazadosVentas.add(id);
        if (tipo == 'movimiento') rechazadosMovimientos.add(id);
      }
      avisos.add('El servidor rechazó un cambio: $motivo.');
    }
    for (final conflicto in respuesta.conflictos) {
      final mensaje = conflicto['mensaje'];
      if (mensaje is String && mensaje.isNotEmpty) avisos.add(mensaje);
    }

    await db.transaction((txn) async {
      for (final fila in respuesta.productos) {
        await _aplicarProducto(txn, fila, avisos);
      }
      for (final fila in respuesta.ventas) {
        await _aplicarVenta(txn, fila, avisos);
      }
      for (final fila in respuesta.movimientos) {
        await txn.insert(
          'movimientos',
          {
            'id': fila['id'],
            'producto_id': fila['producto_id'],
            'cantidad': fila['cantidad'],
            'motivo': fila['motivo'],
            'creado_en': fila['creado_en'],
            'dispositivo_id': fila['dispositivo_id'],
            'usuario_id': usuarioId,
            'pendiente': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      if (envio != null) {
        for (final producto in envio.productos.entries) {
          if (rechazadosProductos.contains(producto.key)) continue;
          await txn.update(
            'productos',
            {'pendiente': 0},
            where: 'id = ? AND pendiente = 1 AND actualizado_en = ?',
            whereArgs: [producto.key, producto.value['actualizado_en']],
          );
        }
        for (final venta in envio.ventas.entries) {
          if (rechazadosVentas.contains(venta.key)) continue;
          await txn.update(
            'ventas',
            {'pendiente': 0},
            where: 'id = ? AND pendiente = 1 AND actualizado_en = ?',
            whereArgs: [venta.key, venta.value['actualizado_en']],
          );
        }
        for (final movimiento in envio.movimientos.keys) {
          if (rechazadosMovimientos.contains(movimiento)) continue;
          await txn.update(
            'movimientos',
            {'pendiente': 0},
            where: 'id = ? AND pendiente = 1',
            whereArgs: [movimiento],
          );
        }
      }
    });
  }

  bool _ganaRemoto(int remotoEn, String remotoDispositivo, int localEn, String localDispositivo) {
    if (remotoEn != localEn) return remotoEn > localEn;
    return remotoDispositivo.compareTo(localDispositivo) > 0;
  }

  Future<void> _aplicarProducto(
    Transaction txn,
    Map<String, Object?> remoto,
    List<String> avisos,
  ) async {
    final id = remoto['id'] as String;
    final valores = {
      'nombre': remoto['nombre'],
      'precio_centavos': remoto['precio_centavos'],
      'stock_base': remoto['stock_base'],
      'activo': (remoto['activo'] as bool? ?? true) ? 1 : 0,
      'actualizado_en': remoto['actualizado_en'],
      'dispositivo_id': remoto['dispositivo_id'],
    };
    final filas = await txn.query('productos', where: 'id = ?', whereArgs: [id], limit: 1);

    if (filas.isEmpty) {
      await txn.insert('productos', {'id': id, ...valores, 'usuario_id': usuarioId, 'pendiente': 0});
      return;
    }

    final local = filas.first;
    final localPendiente = (local['pendiente'] as int? ?? 0) == 1;
    final ganaRemoto = _ganaRemoto(
      (remoto['actualizado_en'] as num?)?.toInt() ?? 0,
      '${remoto['dispositivo_id']}',
      (local['actualizado_en'] as num?)?.toInt() ?? 0,
      '${local['dispositivo_id']}',
    );

    if (localPendiente && !ganaRemoto) {
      final difiere = local['nombre'] != valores['nombre'] ||
          local['precio_centavos'] != valores['precio_centavos'] ||
          local['stock_base'] != valores['stock_base'] ||
          local['activo'] != valores['activo'];
      if (difiere) {
        avisos.add('Se conservó tu cambio de "${local['nombre']}".');
      }
      return;
    }

    await txn.update(
      'productos',
      {...valores, 'pendiente': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _aplicarVenta(
    Transaction txn,
    Map<String, Object?> remoto,
    List<String> avisos,
  ) async {
    final id = remoto['id'] as String;
    final anulada = (remoto['anulada'] as bool? ?? false) ? 1 : 0;
    final filas = await txn.query('ventas', where: 'id = ?', whereArgs: [id], limit: 1);

    if (filas.isEmpty) {
      await txn.insert('ventas', {
        'id': id,
        'creado_en': remoto['creado_en'],
        'total_centavos': remoto['total_centavos'],
        'anulada': anulada,
        'actualizado_en': remoto['actualizado_en'],
        'dispositivo_id': remoto['dispositivo_id'],
        'usuario_id': usuarioId,
        'pendiente': 0,
      });
    } else {
      final local = filas.first;
      final localPendiente = (local['pendiente'] as int? ?? 0) == 1;
      final ganaRemoto = _ganaRemoto(
        (remoto['actualizado_en'] as num?)?.toInt() ?? 0,
        '${remoto['dispositivo_id']}',
        (local['actualizado_en'] as num?)?.toInt() ?? 0,
        '${local['dispositivo_id']}',
      );
      if (!localPendiente || ganaRemoto) {
        await txn.update(
          'ventas',
          {
            'total_centavos': remoto['total_centavos'],
            'anulada': anulada,
            'actualizado_en': remoto['actualizado_en'],
            'dispositivo_id': remoto['dispositivo_id'],
            'pendiente': 0,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      } else if (local['anulada'] != anulada) {
        avisos.add('Se conservó el estado local de una venta.');
      }
    }

    final items = remoto['items'];
    if (items is List) {
      for (final item in items.whereType<Map>()) {
        await txn.insert(
          'venta_items',
          {
            'id': item['id'],
            'venta_id': id,
            'producto_id': item['producto_id'],
            'nombre': item['nombre'],
            'precio_centavos': item['precio_centavos'],
            'cantidad': item['cantidad'],
            'usuario_id': usuarioId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }
}

class _Envio {
  const _Envio({required this.productos, required this.ventas, required this.movimientos});

  final Map<String, Map<String, Object?>> productos;
  final Map<String, Map<String, Object?>> ventas;
  final Map<String, Map<String, Object?>> movimientos;

  Map<String, Object?> aJson() => {
        'productos': productos.values.toList(),
        'ventas': ventas.values.toList(),
        'movimientos': movimientos.values.toList(),
      };
}

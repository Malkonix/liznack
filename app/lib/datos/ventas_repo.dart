import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'modelos.dart';

/// Ventas locales. Una venta es un hecho: se inserta una sola vez y no se edita
/// (solo se puede anular), para que sincronizar nunca duplique plata.
class VentasRepo {
  VentasRepo(this.db, this.dispositivoId, [this.usuarioId = '']);

  final Database db;
  final String dispositivoId;
  String usuarioId;

  Future<Venta> registrar(List<LineaCarrito> lineas, {DateTime? cuando}) async {
    if (lineas.isEmpty) throw ArgumentError('El carrito está vacío.');
    final ahora = cuando ?? DateTime.now();
    final id = const Uuid().v4();
    final total = lineas.fold(
      0,
      (suma, linea) => suma + linea.subtotalCentavos,
    );
    final items = <ItemVenta>[];

    await db.transaction((txn) async {
      await txn.insert('ventas', {
        'id': id,
        'creado_en': ahora.millisecondsSinceEpoch,
        'total_centavos': total,
        'anulada': 0,
        'actualizado_en': ahora.millisecondsSinceEpoch,
        'dispositivo_id': dispositivoId,
        'usuario_id': usuarioId,
        'pendiente': 1,
      });
      for (final linea in lineas) {
        final item = ItemVenta(
          id: const Uuid().v4(),
          ventaId: id,
          productoId: linea.producto.id,
          nombre: linea.producto.nombre,
          precioCentavos: linea.producto.precioCentavos,
          cantidad: linea.cantidad,
        );
        items.add(item);
        await txn.insert('venta_items', {
          'id': item.id,
          'venta_id': id,
          'producto_id': item.productoId,
          'nombre': item.nombre,
          'precio_centavos': item.precioCentavos,
          'cantidad': item.cantidad,
          'usuario_id': usuarioId,
        });
      }
    });

    return Venta(
      id: id,
      creadoEn: ahora,
      totalCentavos: total,
      anulada: false,
      pendiente: true,
      items: items,
    );
  }

  Future<void> anular(String ventaId, {DateTime? cuando}) async {
    final ahora = cuando ?? DateTime.now();
    await db.update(
      'ventas',
      {
        'anulada': 1,
        'actualizado_en': ahora.millisecondsSinceEpoch,
        'dispositivo_id': dispositivoId,
        'pendiente': 1,
      },
      where: 'id = ? AND usuario_id = ?',
      whereArgs: [ventaId, usuarioId],
    );
  }

  Future<ResumenDia> resumenDia([DateTime? dia]) async {
    final referencia = dia ?? DateTime.now();
    final inicio = DateTime(referencia.year, referencia.month, referencia.day);
    final fin = inicio.add(const Duration(days: 1));
    final filas = await db.rawQuery(
      '''SELECT COUNT(*) AS cantidad, COALESCE(SUM(total_centavos), 0) AS total
           FROM ventas
          WHERE anulada = 0 AND creado_en >= ? AND creado_en < ? AND usuario_id = ?''',
      [inicio.millisecondsSinceEpoch, fin.millisecondsSinceEpoch, usuarioId],
    );
    final fila = filas.first;
    return ResumenDia(
      cantidadVentas: (fila['cantidad'] as int?) ?? 0,
      totalCentavos: (fila['total'] as int?) ?? 0,
    );
  }

  /// Ventas más recientes con sus ítems, para el historial.
  Future<List<Venta>> recientes({int limite = 100}) async {
    final filas = await db.query(
      'ventas',
      orderBy: 'creado_en DESC',
      limit: limite,
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
    );
    return _conItems(filas);
  }

  /// Ventas de un día (de la más vieja a la más nueva), para el reporte.
  Future<List<Venta>> delDia([DateTime? dia]) async {
    final referencia = dia ?? DateTime.now();
    final inicio = DateTime(referencia.year, referencia.month, referencia.day);
    final fin = inicio.add(const Duration(days: 1));
    final filas = await db.query(
      'ventas',
      where: 'usuario_id = ? AND creado_en >= ? AND creado_en < ?',
      whereArgs: [
        usuarioId,
        inicio.millisecondsSinceEpoch,
        fin.millisecondsSinceEpoch,
      ],
      orderBy: 'creado_en ASC',
    );
    return _conItems(filas);
  }

  Future<List<Venta>> _conItems(List<Map<String, Object?>> filas) async {
    if (filas.isEmpty) return [];

    final ids = filas.map((f) => f['id'] as String).toList();
    final marcadores = List.filled(ids.length, '?').join(',');
    final items = await db.query(
      'venta_items',
      where: 'venta_id IN ($marcadores)',
      whereArgs: ids,
      orderBy: 'rowid ASC',
    );
    final porVenta = <String, List<ItemVenta>>{};
    for (final filaItem in items) {
      final item = ItemVenta.desdeFila(filaItem);
      porVenta.putIfAbsent(item.ventaId, () => []).add(item);
    }
    return filas
        .map((f) => Venta.desdeFila(f, items: porVenta[f['id']] ?? const []))
        .toList();
  }

  Future<int> contarPendientes() async {
    final filas = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ventas WHERE pendiente = 1',
    );
    return (filas.first['total'] as int?) ?? 0;
  }
}

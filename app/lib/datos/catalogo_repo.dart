import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'modelos.dart';

/// Productos y ajustes de stock.
///
/// El stock nunca se guarda como número suelto: se calcula como
/// `stock_base + ajustes - ventas`, igual que en el servidor. Así dos teléfonos
/// que venden sin conexión no se pisan el inventario.
class CatalogoRepo {
  CatalogoRepo(this.db, this.dispositivoId, [this.usuarioId = '']);

  final Database db;
  final String dispositivoId;
  String usuarioId;

  static const _sqlListar = '''
    SELECT p.id, p.nombre, p.precio_centavos, p.stock_base, p.activo,
           p.actualizado_en, p.dispositivo_id, p.pendiente,
           p.stock_base
           + COALESCE((SELECT SUM(m.cantidad) FROM movimientos m
                        WHERE m.producto_id = p.id), 0)
           - COALESCE((SELECT SUM(i.cantidad) FROM venta_items i
                        JOIN ventas v ON v.id = i.venta_id
                       WHERE i.producto_id = p.id AND v.anulada = 0), 0)
           AS stock_actual
      FROM productos p
  ''';

  Future<List<Producto>> listar({bool soloActivos = false}) async {
    final filas = await db.rawQuery(
      '$_sqlListar WHERE p.usuario_id = ? ${soloActivos ? 'AND p.activo = 1' : ''} '
      'ORDER BY p.activo DESC, p.nombre COLLATE NOCASE',
      [usuarioId],
    );
    return filas.map(Producto.desdeFila).toList();
  }

  Future<Producto?> buscar(String id) async {
    final filas = await db.rawQuery('$_sqlListar WHERE p.id = ? AND p.usuario_id = ? LIMIT 1', [id, usuarioId]);
    if (filas.isEmpty) return null;
    return Producto.desdeFila(filas.first);
  }

  Future<String> crear({
    required String nombre,
    required int precioCentavos,
    required int stockInicial,
  }) async {
    final id = const Uuid().v4();
    final ahora = DateTime.now().millisecondsSinceEpoch;
    await db.insert('productos', {
      'id': id,
      'nombre': nombre.trim(),
      'precio_centavos': precioCentavos,
      'stock_base': stockInicial,
      'activo': 1,
      'actualizado_en': ahora,
      'dispositivo_id': dispositivoId,
      'usuario_id': usuarioId,
      'pendiente': 1,
    });
    return id;
  }

  Future<void> editar({
    required Producto producto,
    required String nombre,
    required int precioCentavos,
  }) {
    return db.update(
      'productos',
      {
        'nombre': nombre.trim(),
        'precio_centavos': precioCentavos,
        'actualizado_en': DateTime.now().millisecondsSinceEpoch,
        'dispositivo_id': dispositivoId,
        'pendiente': 1,
      },
      where: 'id = ? AND usuario_id = ?',
      whereArgs: [producto.id, usuarioId],
    );
  }

  Future<void> archivar(String productoId) => _cambiarActivo(productoId, false);

  Future<void> restaurar(String productoId) => _cambiarActivo(productoId, true);

  Future<void> _cambiarActivo(String productoId, bool activo) {
    return db.update(
      'productos',
      {
        'activo': activo ? 1 : 0,
        'actualizado_en': DateTime.now().millisecondsSinceEpoch,
        'dispositivo_id': dispositivoId,
        'pendiente': 1,
      },
      where: 'id = ? AND usuario_id = ?',
      whereArgs: [productoId, usuarioId],
    );
  }

  /// Suma (o resta, con cantidad negativa) stock como un movimiento inmutable.
  /// El productoId debe pertenecer al usuario actual; si no, ignoramos.
  Future<void> reponer({
    required String productoId,
    required int cantidad,
    String motivo = 'reposicion',
  }) async {
    if (cantidad == 0) throw ArgumentError('La cantidad no puede ser cero.');
    await db.insert('movimientos', {
      'id': const Uuid().v4(),
      'producto_id': productoId,
      'cantidad': cantidad,
      'motivo': motivo,
      'creado_en': DateTime.now().millisecondsSinceEpoch,
      'dispositivo_id': dispositivoId,
      'usuario_id': usuarioId,
      'pendiente': 1,
    });
  }

  Future<int> contarPendientes() async {
    final filas = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM productos WHERE pendiente = 1',
    );
    return (filas.first['total'] as int?) ?? 0;
  }
}

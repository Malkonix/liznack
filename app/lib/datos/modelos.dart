/// Modelos de la base local. No tienen lógica de red ni de UI.
class Producto {
  const Producto({
    required this.id,
    required this.nombre,
    required this.precioCentavos,
    required this.stockBase,
    required this.stockActual,
    required this.activo,
    required this.actualizadoEn,
    required this.dispositivoId,
    required this.usuarioId,
    required this.pendiente,
  });

  final String id;
  final String nombre;
  final int precioCentavos;
  final int stockBase;
  final int stockActual;
  final bool activo;
  final int actualizadoEn;
  final String dispositivoId;
  final String usuarioId;
  final bool pendiente;

  bool get sinStock => stockActual <= 0;

  factory Producto.desdeFila(Map<String, Object?> fila) => Producto(
        id: fila['id'] as String,
        nombre: fila['nombre'] as String,
        precioCentavos: fila['precio_centavos'] as int,
        stockBase: fila['stock_base'] as int,
        stockActual: (fila['stock_actual'] as int?) ?? (fila['stock_base'] as int),
        activo: (fila['activo'] as int? ?? 1) == 1,
        actualizadoEn: fila['actualizado_en'] as int,
        dispositivoId: fila['dispositivo_id'] as String? ?? '',
        usuarioId: fila['usuario_id'] as String? ?? '',
        pendiente: (fila['pendiente'] as int? ?? 0) == 1,
      );
}

class ItemVenta {
  const ItemVenta({
    required this.id,
    required this.ventaId,
    required this.productoId,
    required this.nombre,
    required this.precioCentavos,
    required this.cantidad,
  });

  final String id;
  final String ventaId;
  final String productoId;
  final String nombre;
  final int precioCentavos;
  final int cantidad;

  int get subtotalCentavos => precioCentavos * cantidad;

  factory ItemVenta.desdeFila(Map<String, Object?> fila) => ItemVenta(
        id: fila['id'] as String,
        ventaId: fila['venta_id'] as String,
        productoId: fila['producto_id'] as String,
        nombre: fila['nombre'] as String,
        precioCentavos: fila['precio_centavos'] as int,
        cantidad: fila['cantidad'] as int,
      );
}

class Venta {
  const Venta({
    required this.id,
    required this.creadoEn,
    required this.totalCentavos,
    required this.anulada,
    required this.pendiente,
    this.items = const [],
  });

  final String id;
  final DateTime creadoEn;
  final int totalCentavos;
  final bool anulada;
  final bool pendiente;
  final List<ItemVenta> items;

  int get cantidadItems => items.fold(0, (suma, item) => suma + item.cantidad);

  String get resumenItems {
    if (items.isEmpty) return 'Sin detalle';
    return items.map((i) => '${i.cantidad}× ${i.nombre}').join(', ');
  }

  Venta conItems(List<ItemVenta> items) => Venta(
        id: id,
        creadoEn: creadoEn,
        totalCentavos: totalCentavos,
        anulada: anulada,
        pendiente: pendiente,
        items: items,
      );

  factory Venta.desdeFila(Map<String, Object?> fila, {List<ItemVenta> items = const []}) =>
      Venta(
        id: fila['id'] as String,
        creadoEn: DateTime.fromMillisecondsSinceEpoch(fila['creado_en'] as int),
        totalCentavos: fila['total_centavos'] as int,
        anulada: (fila['anulada'] as int? ?? 0) == 1,
        pendiente: (fila['pendiente'] as int? ?? 0) == 1,
        items: items,
      );
}

class ResumenDia {
  const ResumenDia({required this.cantidadVentas, required this.totalCentavos});

  final int cantidadVentas;
  final int totalCentavos;

  static const vacio = ResumenDia(cantidadVentas: 0, totalCentavos: 0);
}

/// Una línea del carrito: producto + cuántos se llevan.
class LineaCarrito {
  const LineaCarrito({required this.producto, required this.cantidad});

  final Producto producto;
  final int cantidad;

  int get subtotalCentavos => producto.precioCentavos * cantidad;
}

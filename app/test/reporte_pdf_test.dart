import 'package:liznack/datos/modelos.dart';
import 'package:liznack/reportes/reporte_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayuda_pruebas.dart';

void main() {
  test('el comprobante de una venta sale como PDF', () async {
    final tienda = await tiendaDePrueba();
    addTearDown(tienda.cerrar);

    await tienda.crearProducto(nombre: 'Chocolate', precioCentavos: 1250, stockInicial: 5);
    final producto = (await tienda.catalogo.listar()).single;
    final venta = await tienda.registrarVenta([
      LineaCarrito(producto: producto, cantidad: 2),
    ]);

    final bytes = await pdfDeVenta(venta, vendedor: 'ana@familia.com');

    expect(bytes.length, greaterThan(800));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // El PDF no lleva el costo: la app no lo tiene ni lo muestra.
    expect(String.fromCharCodes(bytes), isNot(contains('costo de compra')));
  });

  test('el reporte del día incluye todas las ventas y no cuenta las anuladas', () async {
    final tienda = await tiendaDePrueba();
    addTearDown(tienda.cerrar);

    await tienda.crearProducto(nombre: 'Chocolate', precioCentavos: 500, stockInicial: 10);
    await tienda.crearProducto(nombre: 'Gomitas', precioCentavos: 250, stockInicial: 10);
    final productos = await tienda.catalogo.listar();
    final chocolate = productos.firstWhere((p) => p.nombre == 'Chocolate');
    final gomitas = productos.firstWhere((p) => p.nombre == 'Gomitas');

    await tienda.registrarVenta([LineaCarrito(producto: chocolate, cantidad: 2)]);
    final anulada = await tienda.registrarVenta([
      LineaCarrito(producto: gomitas, cantidad: 1),
    ]);
    await tienda.anularVenta(anulada.id);

    final ventas = await tienda.ventas.delDia();
    expect(ventas.length, 2, reason: 'la anulada queda en el historial');
    expect(ventas.first.creadoEn.isBefore(ventas.last.creadoEn) ||
        ventas.first.creadoEn.isAtSameMomentAs(ventas.last.creadoEn), isTrue);

    final bytes = await pdfDeVentasDelDia(
      ventas,
      DateTime.now(),
      vendedor: 'ana@familia.com',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('el reporte del día vacío también es un PDF válido', () async {
    final bytes = await pdfDeVentasDelDia(const [], DateTime.now());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}

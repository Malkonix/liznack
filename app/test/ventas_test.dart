import 'package:liznack/datos/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayuda_pruebas.dart';

void main() {
  test('vender descuenta stock y suma la plata del día', () async {
    final tienda = await tiendaDePrueba();
    addTearDown(tienda.cerrar);

    await tienda.crearProducto(nombre: 'Chocolate', precioCentavos: 500, stockInicial: 10);
    final producto = (await tienda.catalogo.listar()).single;
    expect(producto.stockActual, 10);

    final venta = await tienda.registrarVenta([
      LineaCarrito(producto: producto, cantidad: 2),
    ]);

    expect(venta.totalCentavos, 1000);
    expect((await tienda.catalogo.listar()).single.stockActual, 8);

    final resumen = await tienda.ventas.resumenDia();
    expect(resumen.cantidadVentas, 1);
    expect(resumen.totalCentavos, 1000);

    final historial = await tienda.ventas.recientes();
    expect(historial.single.items.single.cantidad, 2);
    expect(historial.single.pendiente, isTrue);

    expect(tienda.pendientes, 2); // 1 producto + 1 venta
  });

  test('anular devuelve el stock y deja la venta en el historial', () async {
    final tienda = await tiendaDePrueba();
    addTearDown(tienda.cerrar);

    await tienda.crearProducto(nombre: 'Gomitas', precioCentavos: 250, stockInicial: 5);
    final producto = (await tienda.catalogo.listar()).single;
    final venta = await tienda.registrarVenta([
      LineaCarrito(producto: producto, cantidad: 3),
    ]);

    expect((await tienda.catalogo.listar()).single.stockActual, 2);

    await tienda.anularVenta(venta.id);

    expect((await tienda.catalogo.listar()).single.stockActual, 5);
    expect((await tienda.ventas.resumenDia()).totalCentavos, 0);
    final historial = await tienda.ventas.recientes();
    expect(historial.single.anulada, isTrue);
  });

  test('reponer stock suma sin tocar ventas', () async {
    final tienda = await tiendaDePrueba();
    addTearDown(tienda.cerrar);

    await tienda.crearProducto(nombre: 'Galletita', precioCentavos: 300, stockInicial: 2);
    final producto = (await tienda.catalogo.listar()).single;
    await tienda.registrarVenta([LineaCarrito(producto: producto, cantidad: 2)]);
    expect((await tienda.catalogo.listar()).single.stockActual, 0);

    await tienda.reponerStock(producto.id, 12);
    final repuesto = (await tienda.catalogo.listar()).single;
    expect(repuesto.stockActual, 12);
    expect((await tienda.ventas.resumenDia()).totalCentavos, 600);
  });

  test('archivar saca el producto de Vender pero conserva el historial', () async {
    final tienda = await tiendaDePrueba();
    addTearDown(tienda.cerrar);

    await tienda.crearProducto(nombre: 'Bombón', precioCentavos: 700, stockInicial: 3);
    final producto = (await tienda.catalogo.listar()).single;
    await tienda.archivarProducto(producto.id);

    expect(await tienda.catalogo.listar(soloActivos: true), isEmpty);
    expect((await tienda.catalogo.listar()).single.activo, isFalse);

    await tienda.restaurarProducto(producto.id);
    expect((await tienda.catalogo.listar(soloActivos: true)).single.id, producto.id);
  });

  test('los datos sobreviven a cerrar y abrir la app', () async {
    final ruta = rutaTemporalDb();
    final primera = await tiendaDePrueba(rutaDb: ruta);
    await primera.crearProducto(nombre: 'Chocolate', precioCentavos: 500, stockInicial: 4);
    final producto = (await primera.catalogo.listar()).single;
    await primera.registrarVenta([LineaCarrito(producto: producto, cantidad: 1)]);
    await primera.cerrar();

    final segunda = await tiendaDePrueba(rutaDb: ruta);
    addTearDown(segunda.cerrar);
    final recuperado = (await segunda.catalogo.listar()).single;
    expect(recuperado.stockActual, 3);
    expect((await segunda.ventas.resumenDia()).totalCentavos, 500);
    expect(segunda.pendientes, 2);
  });
}

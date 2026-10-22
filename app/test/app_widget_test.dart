import 'package:liznack/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayuda_pruebas.dart';

/// Toca dentro de la zona "real" para que SQLite (FFI) pueda completar, y
/// después dibuja los frames. Sin esto, el I/O queda atrapado en el reloj falso.
Future<void> tocar(WidgetTester tester, Finder objetivo, {int esperaMs = 250}) async {
  await tester.ensureVisible(objetivo);
  await tester.runAsync(() async {
    await tester.tap(objetivo);
    await Future<void>.delayed(Duration(milliseconds: esperaMs));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  Future<void> pantallaDeTelefono(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('el ingreso está en español y ya no ofrece usar sin cuenta', (tester) async {
    await pantallaDeTelefono(tester);
    final tienda = (await tester.runAsync(() => tiendaDePrueba()))!;
    addTearDown(() async => tester.runAsync(tienda.cerrar));

    await tester.pumpWidget(LiznackApp(tienda: tienda));
    await tester.pump();

    expect(find.text('Liznack'), findsOneWidget);
    expect(find.text('Correo'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);

    // La entrada para vender sin cuenta ya no existe.
    expect(find.text('Probar sin cuenta (solo este teléfono)'), findsNothing);
    expect(find.text('Usar sin cuenta'), findsNothing);
  });

  testWidgets('vender y cobrar funciona y descuenta stock', (tester) async {
    await pantallaDeTelefono(tester);
    final tienda = (await tester.runAsync(() async {
      final t = await tiendaDePrueba();
      await t.usarSinCuenta();
      await t.crearProducto(nombre: 'Chocolate', precioCentavos: 500, stockInicial: 5);
      return t;
    }))!;
    addTearDown(() async => tester.runAsync(tienda.cerrar));

    await tester.pumpWidget(LiznackApp(tienda: tienda));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Chocolate'), findsOneWidget);
    expect(find.text(r'$ 5'), findsWidgets);
    expect(find.text('Quedan 5'), findsOneWidget);

    await tocar(tester, find.text('Chocolate'));
    expect(find.text('En el carrito · 1 dulce'), findsOneWidget);
    expect(find.text('Cobrar'), findsOneWidget);

    await tocar(tester, find.text('Cobrar'), esperaMs: 450);

    expect(find.textContaining('Venta registrada'), findsOneWidget);
    final stock = await tester.runAsync(() async =>
        (await tienda.catalogo.listar()).single.stockActual);
    expect(stock, 4);
    final total = await tester.runAsync(() async =>
        (await tienda.ventas.resumenDia()).totalCentavos);
    expect(total, 500);

    await tocar(tester, find.text('Ventas').last);
    expect(find.textContaining('1× Chocolate'), findsOneWidget);
    expect(find.text('Total de hoy'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

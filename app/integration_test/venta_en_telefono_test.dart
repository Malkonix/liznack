import 'package:liznack/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Prueba real en un teléfono/emulador Android.
///
/// Necesita el servidor levantado y el teléfono apuntando a él
/// (`adb reverse tcp:3000 tcp:3000` en el emulador, o la IP de la
/// computadora en Ajustes → Servidor). Se corre con:
///   `flutter test integration_test/venta_en_telefono_test.dart -d <dispositivo>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('crear una cuenta, cargar un producto y cobrar una venta', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    // Primera vez: hay que crear la cuenta. Después queda guardada y la app
    // entra sola.
    if (find.text('Crear cuenta').evaluate().isNotEmpty) {
      final email = 'tab${DateTime.now().millisecondsSinceEpoch}@ejemplo.com';
      final campos = find.byType(TextFormField);
      // Correo y contraseña: el campo del servidor está dentro de una sección
      // plegada y no se construye hasta que se abre.
      expect(campos, findsNWidgets(2));
      await tester.enterText(campos.at(0), email);
      await tester.enterText(campos.at(1), 'dulce123');
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Vendido hoy'), findsOneWidget);

    final nombre = 'Chocolate prueba ${DateTime.now().millisecondsSinceEpoch % 100000}';

    // Inventario → nuevo producto.
    await tester.tap(find.text('Inventario').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo producto'));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    expect(campos, findsNWidgets(3));
    await tester.enterText(campos.at(0), nombre);
    await tester.enterText(campos.at(1), '500');
    await tester.enterText(campos.at(2), '5');
    await tester.tap(find.text('Agregar producto'));
    await tester.pumpAndSettle();
    // Dejar que se vaya el aviso flotante antes de seguir.
    await tester.pump(const Duration(seconds: 3));

    expect(find.text(nombre), findsOneWidget);

    // Vender uno y cobrar.
    await tester.tap(find.text('Vender').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(nombre));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nombre));
    await tester.pumpAndSettle();

    final cobrar = find.widgetWithText(FilledButton, 'Cobrar');
    expect(cobrar, findsOneWidget);
    await tester.ensureVisible(cobrar);
    await tester.pumpAndSettle();
    await tester.tap(cobrar);
    await tester.pumpAndSettle();

    expect(find.textContaining('Venta registrada'), findsOneWidget);

    // El historial muestra la venta de hoy.
    await tester.tap(find.text('Ventas').last);
    await tester.pumpAndSettle();
    expect(find.text('Total de hoy'), findsOneWidget);
    expect(find.textContaining('1× $nombre'), findsOneWidget);

    // Y todo llega al servidor.
    await tester.tap(find.text('Ajustes').last);
    await tester.pumpAndSettle();

    var sincronizado = false;
    for (var intento = 0; intento < 40; intento++) {
      if (find.text('Sincronizado').evaluate().isNotEmpty) {
        sincronizado = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(sincronizado, isTrue, reason: 'La app no llegó a Sincronizado');

    // El bloque de actualizaciones está en Ajustes.
    expect(find.text('Actualizaciones'), findsOneWidget);
    expect(find.text('Buscar actualización'), findsOneWidget);
  });
}

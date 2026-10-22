import 'package:liznack/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Prueba real en un teléfono/emulador Android: carga un producto y lo vende
/// sin cuenta y sin servidor. Se corre con:
///   `flutter test integration_test/venta_en_telefono_test.dart -d <dispositivo>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cargar un producto y cobrar una venta sin internet', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    // Primera vez: entrar en modo local. Si ya hay sesión guardada, se sigue.
    if (find.text('Ingresar').evaluate().isNotEmpty) {
      final sinCuenta = find.text('Probar sin cuenta (solo este teléfono)');
      await tester.ensureVisible(sinCuenta);
      await tester.pumpAndSettle();
      await tester.tap(sinCuenta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar así'));
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

    // Con el servidor levantado y `adb reverse tcp:3000 tcp:3000`, crear una
    // cuenta y comprobar que el mismo teléfono queda sincronizado de verdad.
    await tester.tap(find.text('Ajustes').last);
    await tester.pumpAndSettle();
    final entrar = find.text('Entrar con una cuenta');
    if (entrar.evaluate().isNotEmpty) {
      await tester.tap(entrar);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
    }

    if (find.text('Crear cuenta').evaluate().isNotEmpty) {
      final email = 'tab${DateTime.now().millisecondsSinceEpoch}@ejemplo.com';
      final camposLogin = find.byType(TextFormField);
      await tester.enterText(camposLogin.at(0), email);
      await tester.enterText(camposLogin.at(1), 'dulce123');
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
    }

    var sincronizado = false;
    for (var intento = 0; intento < 40; intento++) {
      if (find.text('Sincronizado').evaluate().isNotEmpty) {
        sincronizado = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(sincronizado, isTrue, reason: 'La app no llegó a Sincronizado');
    expect(find.textContaining(nombre), findsWidgets);
  });
}

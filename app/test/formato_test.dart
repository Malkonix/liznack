import 'package:liznack/nucleo/formato.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatearDinero', () {
    test('usa punto de miles y coma de centavos', () {
      expect(formatearDinero(0), r'$ 0');
      expect(formatearDinero(500), r'$ 5');
      expect(formatearDinero(1250), r'$ 12,50');
      expect(formatearDinero(125000), r'$ 1.250');
      expect(formatearDinero(125050), r'$ 1.250,50');
      expect(formatearDinero(100000000), r'$ 1.000.000');
    });
  });

  group('parsearDinero', () {
    test('entiende lo que escribe una persona', () {
      expect(parsearDinero('500'), 50000);
      expect(parsearDinero('1.250'), 125000);
      expect(parsearDinero('12,50'), 1250);
      expect(parsearDinero('12.50'), 1250);
      expect(parsearDinero(r'$ 1.250,50'), 125050);
      expect(parsearDinero('1.250.000'), 125000000);
      expect(parsearDinero(',5'), 50);
    });

    test('rechaza lo que no es plata', () {
      expect(parsearDinero(''), isNull);
      expect(parsearDinero('abc'), isNull);
      expect(parsearDinero('.'), isNull);
    });
  });

  test('etiquetas de fecha en español', () {
    final ahora = DateTime(2026, 10, 21, 15, 30);
    expect(etiquetaDia(ahora, ahora: ahora), 'Hoy');
    expect(etiquetaDia(DateTime(2026, 10, 20), ahora: ahora), 'Ayer');
    expect(etiquetaDia(DateTime(2026, 10, 19), ahora: ahora), 'lunes 19 de octubre');
    expect(horaCorta(DateTime(2026, 10, 21, 9, 5)), '09:05');
  });
}

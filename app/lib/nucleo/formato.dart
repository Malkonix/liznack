/// Formato y lectura de plata y fechas, en español rioplatense.
///
/// La plata se guarda siempre en centavos (enteros) para no arrastrar errores
/// de coma flotante. La UI la muestra como `$ 1.250` o `$ 1.250,50`.
library;

const List<String> _dias = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

const List<String> _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String _agrupar(String digitos) {
  final buffer = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digitos[i]);
  }
  return buffer.toString();
}

/// 125050 → `$ 1.250,50` · 125000 → `$ 1.250`
String formatearDinero(int centavos) {
  final negativo = centavos < 0;
  final absoluto = centavos.abs();
  final enteros = _agrupar((absoluto ~/ 100).toString());
  final resto = absoluto % 100;
  final texto = resto == 0
      ? '\$ $enteros'
      : '\$ $enteros,${resto.toString().padLeft(2, '0')}';
  return negativo ? '-$texto' : texto;
}

/// Lee lo que escribe una persona: `1250`, `1.250`, `12,50`, `$ 12.50`.
/// Devuelve centavos o `null` si no se entiende.
int? parsearDinero(String entrada) {
  var limpio = entrada.replaceAll(RegExp(r'[^0-9,.]'), '');
  if (limpio.isEmpty || !RegExp(r'\d').hasMatch(limpio)) return null;

  final tieneComa = limpio.contains(',');
  final tienePunto = limpio.contains('.');
  String enteros;
  String decimales;

  if (tieneComa && tienePunto) {
    final separador = limpio.lastIndexOf(',') > limpio.lastIndexOf('.')
        ? limpio.lastIndexOf(',')
        : limpio.lastIndexOf('.');
    enteros = limpio.substring(0, separador).replaceAll(RegExp(r'[.,]'), '');
    decimales = limpio.substring(separador + 1);
  } else if (tieneComa || tienePunto) {
    final separador = tieneComa ? limpio.lastIndexOf(',') : limpio.lastIndexOf('.');
    enteros = limpio.substring(0, separador);
    decimales = limpio.substring(separador + 1);
    // "1.250" son miles; "12.50" son centavos.
    if (decimales.length == 3 && enteros.isNotEmpty) {
      enteros = '$enteros$decimales';
      decimales = '';
    }
    enteros = enteros.replaceAll(RegExp(r'[.,]'), '');
  } else {
    enteros = limpio;
    decimales = '';
  }

  if (enteros.isEmpty) enteros = '0';
  if (enteros.length > 12) return null;
  if (!RegExp(r'^\d+$').hasMatch(enteros)) return null;
  if (decimales.isNotEmpty && !RegExp(r'^\d+$').hasMatch(decimales)) return null;
  if (decimales.length > 2) decimales = decimales.substring(0, 2);

  final pesos = int.tryParse(enteros);
  if (pesos == null) return null;
  final centavos = decimales.isEmpty
      ? 0
      : int.parse(decimales.padRight(2, '0').substring(0, 2));
  return pesos * 100 + centavos;
}

String horaCorta(DateTime fecha) =>
    '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';

bool mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Hoy", "Ayer" o "lunes 12 de mayo".
String etiquetaDia(DateTime fecha, {DateTime? ahora}) {
  final referencia = ahora ?? DateTime.now();
  if (mismoDia(fecha, referencia)) return 'Hoy';
  if (mismoDia(fecha, referencia.subtract(const Duration(days: 1)))) return 'Ayer';
  return '${_dias[fecha.weekday - 1]} ${fecha.day} de ${_meses[fecha.month - 1]}';
}

String fechaHoraLarga(DateTime fecha) =>
    '${fecha.day} de ${_meses[fecha.month - 1]} de ${fecha.year} · ${horaCorta(fecha)}';

String fechaCorta(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

String plural(int cantidad, String singular, String plural_) =>
    '$cantidad ${cantidad == 1 ? singular : plural_}';

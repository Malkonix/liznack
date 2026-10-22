import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../datos/modelos.dart';
import '../nucleo/formato.dart';

/// Reportes en PDF que se generan en el teléfono, sin internet.
///
/// No incluyen el costo de compra: ese dato vive solo en el portal del
/// administrador y nunca llega a la app del vendedor.

const _marron = PdfColor.fromInt(0xFF4E342E);
const _caramelo = PdfColor.fromInt(0xFFB9764B);
const _gris = PdfColor.fromInt(0xFF7A6A63);
const _suave = PdfColor.fromInt(0xFFF9F1EC);
const _borde = PdfColor.fromInt(0xFFE7D8D0);

const _meses = [
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

String _fechaHora(DateTime fecha) =>
    '${fecha.day} de ${_meses[fecha.month - 1]} de ${fecha.year} · ${horaCorta(fecha)}';

pw.Widget _cabecera(String titulo, String subtitulo, {String? vendedor}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Liznack',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: _marron,
                ),
              ),
              pw.Text(
                'Ventas de golosinas',
                style: const pw.TextStyle(fontSize: 9, color: _gris),
              ),
            ],
          ),
          if (vendedor != null)
            pw.Text(
              vendedor,
              style: const pw.TextStyle(fontSize: 9, color: _gris),
            ),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Divider(color: _borde, height: 1),
      pw.SizedBox(height: 12),
      pw.Text(
        titulo,
        style: pw.TextStyle(
          fontSize: 15,
          fontWeight: pw.FontWeight.bold,
          color: _marron,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        subtitulo,
        style: const pw.TextStyle(fontSize: 9.5, color: _gris),
      ),
      pw.SizedBox(height: 14),
    ],
  );
}

pw.Widget _dato(String etiqueta, String valor) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        etiqueta.toUpperCase(),
        style: const pw.TextStyle(
          fontSize: 7.5,
          color: _gris,
          letterSpacing: 0.4,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        valor,
        style: pw.TextStyle(
          fontSize: 11.5,
          fontWeight: pw.FontWeight.bold,
          color: _marron,
        ),
      ),
    ],
  );
}

pw.Widget _tablaItems(List<ItemVenta> items) {
  final estilo = pw.TextStyle(fontSize: 10, color: _marron);
  final encabezado = pw.TextStyle(
    fontSize: 7.5,
    color: _gris,
    fontWeight: pw.FontWeight.bold,
    letterSpacing: 0.4,
  );
  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(5),
      1: pw.FixedColumnWidth(48),
      2: pw.FixedColumnWidth(72),
      3: pw.FixedColumnWidth(78),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _suave),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text('PRODUCTO', style: encabezado),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              'CANT.',
              style: encabezado,
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              'PRECIO',
              style: encabezado,
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              'SUBTOTAL',
              style: encabezado,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
      for (final item in items)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 4,
              ),
              child: pw.Text(item.nombre, style: estilo),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 4,
              ),
              child: pw.Text(
                '${item.cantidad}',
                style: estilo,
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 4,
              ),
              child: pw.Text(
                formatearDinero(item.precioCentavos),
                style: estilo,
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 4,
              ),
              child: pw.Text(
                formatearDinero(item.subtotalCentavos),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _marron,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
    ],
  );
}

pw.Widget _total(String etiqueta, String valor, {bool grande = false}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: const pw.BoxDecoration(color: _suave),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          etiqueta,
          style: pw.TextStyle(
            fontSize: grande ? 12 : 10,
            fontWeight: pw.FontWeight.bold,
            color: _marron,
          ),
        ),
        pw.Text(
          valor,
          style: pw.TextStyle(
            fontSize: grande ? 16 : 11,
            fontWeight: pw.FontWeight.bold,
            color: _caramelo,
          ),
        ),
      ],
    ),
  );
}

/// Comprobante de una venta con el detalle de lo que se cobró.
Future<Uint8List> pdfDeVenta(Venta venta, {String? vendedor}) async {
  final documento = pw.Document(title: 'Liznack · comprobante');
  final cantidad = venta.items.fold(0, (suma, item) => suma + item.cantidad);

  documento.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          'Liznack · comprobante interno · página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7.5, color: _gris),
        ),
      ),
      build: (context) => [
        _cabecera(
          'Comprobante de venta',
          _fechaHora(venta.creadoEn),
          vendedor: vendedor,
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _dato('Estado', venta.anulada ? 'Anulada' : 'Cobrada'),
            _dato('Productos', '${venta.items.length}'),
            _dato('Unidades', '$cantidad'),
          ],
        ),
        pw.SizedBox(height: 16),
        _tablaItems(venta.items),
        pw.SizedBox(height: 14),
        _total('TOTAL', formatearDinero(venta.totalCentavos), grande: true),
        if (venta.anulada) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Esta venta fue anulada: el stock volvió al inventario.',
            style: const pw.TextStyle(fontSize: 9, color: _gris),
          ),
        ],
      ],
    ),
  );
  return documento.save();
}

/// Reporte de las ventas de un día, con cada venta y su detalle.
Future<Uint8List> pdfDeVentasDelDia(
  List<Venta> ventas,
  DateTime dia, {
  String? vendedor,
}) async {
  final documento = pw.Document(title: 'Liznack · reporte de ventas');
  final validas = ventas.where((v) => !v.anulada).toList();
  final total = validas.fold(0, (suma, venta) => suma + venta.totalCentavos);
  final unidades = validas.fold(
    0,
    (suma, venta) => suma + venta.items.fold(0, (s, item) => s + item.cantidad),
  );
  final tituloDia = etiquetaDia(dia, ahora: dia);

  documento.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          'Liznack · reporte de ventas · página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7.5, color: _gris),
        ),
      ),
      build: (context) => [
        _cabecera(
          'Reporte de ventas',
          '${tituloDia == 'Hoy' ? 'Hoy' : tituloDia} · ${ventas.length} ${ventas.length == 1 ? 'venta' : 'ventas'}',
          vendedor: vendedor,
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _dato('Ventas cobradas', '${validas.length}'),
            _dato('Unidades', '$unidades'),
            _dato('Recaudado', formatearDinero(total)),
          ],
        ),
        pw.SizedBox(height: 18),
        if (ventas.isEmpty)
          pw.Text(
            'Todavía no hay ventas para este día.',
            style: const pw.TextStyle(fontSize: 11, color: _gris),
          )
        else
          for (final venta in ventas) ...[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 8,
              ),
              decoration: pw.BoxDecoration(
                color: venta.anulada
                    ? const PdfColor.fromInt(0xFFF3E8E8)
                    : _suave,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${horaCorta(venta.creadoEn)} · ${venta.resumenItems}',
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: venta.anulada ? _gris : _marron,
                      decoration: venta.anulada
                          ? pw.TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  pw.Text(
                    venta.anulada
                        ? 'ANULADA'
                        : formatearDinero(venta.totalCentavos),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: venta.anulada
                          ? const PdfColor.fromInt(0xFFB3261E)
                          : _marron,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 10, bottom: 10),
              child: _tablaItems(venta.items),
            ),
          ],
        pw.SizedBox(height: 6),
        _total('TOTAL DEL DÍA', formatearDinero(total), grande: true),
      ],
    ),
  );
  return documento.save();
}

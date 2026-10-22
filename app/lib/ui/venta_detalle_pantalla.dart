import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../datos/modelos.dart';
import '../nucleo/formato.dart';
import '../reportes/reporte_pdf.dart';
import 'tema.dart';
import 'tienda_scope.dart';

/// Detalle de una venta: qué se vendió, cuánto entró y el PDF para compartir.
class VentaDetallePantalla extends StatefulWidget {
  const VentaDetallePantalla({super.key, required this.venta});

  final Venta venta;

  @override
  State<VentaDetallePantalla> createState() => _VentaDetallePantallaState();
}

class _VentaDetallePantallaState extends State<VentaDetallePantalla> {
  bool _generando = false;

  String get _nombreArchivo {
    final fecha = fechaCorta(widget.venta.creadoEn).replaceAll('/', '-');
    return 'liznack-venta-$fecha.pdf';
  }

  Future<Uint8List?> _generarPdf() async {
    if (_generando) return null;
    final vendedor = TiendaScope.of(context).sesion?.email;
    setState(() => _generando = true);
    try {
      return await pdfDeVenta(widget.venta, vendedor: vendedor);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar el PDF.')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _compartir() async {
    final bytes = await _generarPdf();
    if (bytes == null) return;
    await Printing.sharePdf(bytes: bytes, filename: _nombreArchivo);
  }

  Future<void> _imprimir() async {
    final bytes = await _generarPdf();
    if (bytes == null) return;
    await Printing.layoutPdf(
      name: _nombreArchivo,
      onLayout: (_) async => bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final venta = widget.venta;
    final items = venta.items;
    final unidades = venta.cantidadItems;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de la venta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fechaHoraLarga(venta.creadoEn),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.brown.shade400,
                        ),
                      ),
                    ),
                    _Etiqueta(
                      texto: venta.anulada ? 'Anulada' : 'Cobrada',
                      color: venta.anulada ? rojoError : verdeOk,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  formatearDinero(venta.totalCentavos),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: venta.anulada ? Colors.grey : caramelo,
                    decoration: venta.anulada
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                Text(
                  '${plural(items.length, 'producto', 'productos')} · '
                  '${plural(unidades, 'unidad', 'unidades')}',
                  style: TextStyle(fontSize: 13, color: Colors.brown.shade400),
                ),
                if (venta.pendiente && !venta.anulada) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 15,
                        color: Colors.orange.shade400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Pendiente de sincronizar',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Qué se vendió',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.brown.shade400,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.nombre,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item.cantidad} × ${formatearDinero(item.precioCentavos)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.brown.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatearDinero(item.subtotalCentavos),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Esta venta no tiene el detalle guardado.'),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        formatearDinero(venta.totalCentavos),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _generando ? null : _compartir,
            icon: _generando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_generando ? 'Generando…' : 'Compartir PDF'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _generando ? null : _imprimir,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir'),
          ),
          const SizedBox(height: 8),
          Text(
            'El PDF se genera en el teléfono, sin internet. No incluye el costo '
            'de compra: eso queda en el portal del administrador.',
            style: TextStyle(fontSize: 12, color: Colors.brown.shade300),
          ),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

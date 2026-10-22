import 'dart:async';

import 'package:flutter/material.dart';

import '../datos/modelos.dart';
import '../nucleo/formato.dart';
import '../tienda.dart';
import 'tema.dart';
import 'tienda_scope.dart';

class VentasPantalla extends StatefulWidget {
  const VentasPantalla({super.key});

  @override
  State<VentasPantalla> createState() => _VentasPantallaState();
}

class _VentasPantallaState extends State<VentasPantalla> {
  Tienda? _tienda;
  int _versionVista = -1;
  List<Venta> _ventas = const [];
  ResumenDia _resumen = ResumenDia.vacio;
  bool _cargando = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tienda = TiendaScope.of(context);
    if (!identical(tienda, _tienda)) {
      _tienda?.removeListener(_alCambiarTienda);
      _tienda = tienda..addListener(_alCambiarTienda);
      _versionVista = -1;
    }
    _alCambiarTienda();
  }

  @override
  void dispose() {
    _tienda?.removeListener(_alCambiarTienda);
    super.dispose();
  }

  void _alCambiarTienda() {
    final tienda = _tienda;
    if (tienda == null || tienda.version == _versionVista) return;
    _versionVista = tienda.version;
    unawaited(_cargar());
  }

  Future<void> _cargar() async {
    final tienda = _tienda;
    if (tienda == null) return;
    try {
      final ventas = await tienda.ventas.recientes();
      final resumen = await tienda.ventas.resumenDia();
      if (!mounted) return;
      setState(() {
        _ventas = ventas;
        _resumen = resumen;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _anular(Venta venta) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anular venta'),
        content: Text(
          'Se anula la venta de ${formatearDinero(venta.totalCentavos)} '
          '(${venta.resumenItems}).\n\nEl stock vuelve a sumarse y queda registrada como anulada.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Anular')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    await TiendaScope.of(context).anularVenta(venta.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venta anulada.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    final filas = <Widget>[];
    String? diaMostrado;
    for (final venta in _ventas) {
      final etiqueta = etiquetaDia(venta.creadoEn);
      if (etiqueta != diaMostrado) {
        diaMostrado = etiqueta;
        filas.add(Padding(
          padding: EdgeInsets.only(top: filas.isEmpty ? 0 : 16, bottom: 8),
          child: Text(
            etiqueta,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.brown.shade400,
            ),
          ),
        ));
      }
      filas.add(_FilaVenta(venta: venta, onAnular: () => _anular(venta)));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total de hoy',
                      style: TextStyle(fontSize: 12, color: Colors.brown.shade400),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatearDinero(_resumen.totalCentavos),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      plural(_resumen.cantidadVentas, 'venta', 'ventas'),
                      style: TextStyle(fontSize: 12.5, color: Colors.brown.shade400),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: carameloSuave,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.receipt_long_outlined, color: caramelo),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_ventas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 50),
            child: Column(
              children: [
                const Text('🧾', style: TextStyle(fontSize: 46)),
                const SizedBox(height: 10),
                const Text(
                  'Todavía no hay ventas',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cuando cobres la primera, la vas a ver acá.',
                  style: TextStyle(color: Colors.brown.shade400),
                ),
              ],
            ),
          )
        else
          ...filas,
      ],
    );
  }
}

class _FilaVenta extends StatelessWidget {
  const _FilaVenta({required this.venta, required this.onAnular});

  final Venta venta;
  final VoidCallback onAnular;

  @override
  Widget build(BuildContext context) {
    final anulada = venta.anulada;
    return Opacity(
      opacity: anulada ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: carameloSuave.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                horaCorta(venta.creadoEn),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: caramelo),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    venta.resumenItems,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: anulada ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        formatearDinero(venta.totalCentavos),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: anulada ? Colors.grey : caramelo,
                          decoration: anulada ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (anulada) ...[
                        const SizedBox(width: 8),
                        const Text(
                          'Anulada',
                          style: TextStyle(fontSize: 11, color: rojoError, fontWeight: FontWeight.w700),
                        ),
                      ] else if (venta.pendiente) ...[
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            Icon(Icons.cloud_upload_outlined,
                                size: 13, color: Colors.orange.shade400),
                            const SizedBox(width: 3),
                            Text(
                              'Pendiente',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!anulada)
              PopupMenuButton<String>(
                tooltip: 'Opciones de la venta',
                onSelected: (_) => onAnular(),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'anular', child: Text('Anular venta')),
                ],
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

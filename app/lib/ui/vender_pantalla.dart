import 'dart:async';

import 'package:flutter/material.dart';

import '../datos/modelos.dart';
import '../nucleo/formato.dart';
import '../tienda.dart';
import 'tema.dart';
import 'tienda_scope.dart';

/// Pantalla principal: tocar dulces, ver el total y cobrar.
class VenderPantalla extends StatefulWidget {
  const VenderPantalla({super.key, required this.onIrAInventario});

  final VoidCallback onIrAInventario;

  @override
  State<VenderPantalla> createState() => _VenderPantallaState();
}

class _VenderPantallaState extends State<VenderPantalla> {
  Tienda? _tienda;
  int _versionVista = -1;

  List<Producto> _productos = const [];
  ResumenDia _resumen = ResumenDia.vacio;
  final Map<String, int> _carrito = {};
  bool _cargando = true;
  bool _cobrando = false;
  String? _error;

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
      final productos = await tienda.catalogo.listar(soloActivos: true);
      final resumen = await tienda.ventas.resumenDia();
      if (!mounted) return;
      setState(() {
        _productos = productos;
        _resumen = resumen;
        _cargando = false;
        _error = null;
        _carrito.removeWhere((id, _) => !productos.any((p) => p.id == id));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los productos.';
      });
    }
  }

  Producto? _productoDe(String id) {
    for (final producto in _productos) {
      if (producto.id == id) return producto;
    }
    return null;
  }

  int get _totalCarrito {
    var total = 0;
    _carrito.forEach((id, cantidad) {
      final producto = _productoDe(id);
      if (producto != null) total += producto.precioCentavos * cantidad;
    });
    return total;
  }

  int get _cantidadItems => _carrito.values.fold(0, (suma, cantidad) => suma + cantidad);

  void _sumar(Producto producto, [int cuanto = 1]) {
    setState(() {
      _carrito[producto.id] = (_carrito[producto.id] ?? 0) + cuanto;
    });
  }

  void _restar(Producto producto) {
    final actual = _carrito[producto.id] ?? 0;
    setState(() {
      if (actual <= 1) {
        _carrito.remove(producto.id);
      } else {
        _carrito[producto.id] = actual - 1;
      }
    });
  }

  Future<void> _cobrar() async {
    final tienda = _tienda;
    if (tienda == null || _carrito.isEmpty || _cobrando) return;

    final lineas = <LineaCarrito>[];
    for (final entrada in _carrito.entries) {
      final producto = _productoDe(entrada.key);
      if (producto != null) {
        lineas.add(LineaCarrito(producto: producto, cantidad: entrada.value));
      }
    }
    if (lineas.isEmpty) return;

    final excedidos = lineas.where((linea) => linea.cantidad > linea.producto.stockActual).toList();
    if (excedidos.isNotEmpty) {
      final nombres = excedidos.map((l) => l.producto.nombre).join(', ');
      final seguir = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vas a vender más de lo anotado'),
          content: Text(
            'En el inventario figura menos stock de: $nombres.\n\n'
            '¿Registrar la venta igual? Después podés reponer el stock.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Revisar')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Cobrar igual')),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }

    setState(() => _cobrando = true);
    try {
      final venta = await tienda.registrarVenta(lineas);
      if (!mounted) return;
      setState(() => _carrito.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Venta registrada · ${formatearDinero(venta.totalCentavos)}'),
          action: SnackBarAction(
            label: 'Anular',
            onPressed: () async {
              await tienda.anularVenta(venta.id);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Venta anulada. El stock volvió.')),
              );
            },
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la venta. Intentá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _TarjetaResumenHoy(resumen: _resumen),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: Text(_error!, style: const TextStyle(color: rojoError))),
                TextButton(onPressed: _cargar, child: const Text('Reintentar')),
              ],
            ),
          ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _productos.isEmpty
                  ? _CatalogoVacio(onAgregar: widget.onIrAInventario)
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 230,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.98,
                      ),
                      itemCount: _productos.length,
                      itemBuilder: (context, indice) {
                        final producto = _productos[indice];
                        return _TarjetaProducto(
                          producto: producto,
                          enCarrito: _carrito[producto.id] ?? 0,
                          onTap: () => _sumar(producto),
                        );
                      },
                    ),
        ),
        if (_carrito.isNotEmpty)
          _PanelCarrito(
            entradas: _carrito,
            productoDe: _productoDe,
            total: _totalCarrito,
            cantidadItems: _cantidadItems,
            cobrando: _cobrando,
            onSumar: _sumar,
            onRestar: _restar,
            onCobrar: _cobrar,
          ),
      ],
    );
  }
}

class _TarjetaResumenHoy extends StatelessWidget {
  const _TarjetaResumenHoy({required this.resumen});

  final ResumenDia resumen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [caramelo, Color(0xFFFF7A9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.today_outlined, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      'Vendido hoy',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  formatearDinero(resumen.totalCentavos),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                Text(
                  resumen.cantidadVentas == 0
                      ? 'Todavía no vendiste hoy'
                      : plural(resumen.cantidadVentas, 'venta', 'ventas'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.storefront_outlined, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({
    required this.producto,
    required this.enCarrito,
    required this.onTap,
  });

  final Producto producto;
  final int enCarrito;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sinStock = producto.sinStock;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    producto.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.15),
                  ),
                  const Spacer(),
                  Text(
                    formatearDinero(producto.precioCentavos),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: caramelo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: sinStock
                              ? rojoError.withValues(alpha: 0.1)
                              : verdeOk.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sinStock ? 'Sin stock' : 'Quedan ${producto.stockActual}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: sinStock ? rojoError : verdeOk,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.add_circle, color: caramelo.withValues(alpha: 0.85), size: 24),
                    ],
                  ),
                ],
              ),
            ),
            if (enCarrito > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: caramelo,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$enCarrito',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PanelCarrito extends StatelessWidget {
  const _PanelCarrito({
    required this.entradas,
    required this.productoDe,
    required this.total,
    required this.cantidadItems,
    required this.cobrando,
    required this.onSumar,
    required this.onRestar,
    required this.onCobrar,
  });

  final Map<String, int> entradas;
  final Producto? Function(String) productoDe;
  final int total;
  final int cantidadItems;
  final bool cobrando;
  final void Function(Producto) onSumar;
  final void Function(Producto) onRestar;
  final VoidCallback onCobrar;

  @override
  Widget build(BuildContext context) {
    final lineas = entradas.entries
        .map((e) => (producto: productoDe(e.key), cantidad: e.value))
        .where((l) => l.producto != null)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'En el carrito · ${plural(cantidadItems, 'dulce', 'dulces')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      for (final linea in lineas) {
                        onRestar(linea.producto!);
                      }
                    },
                    child: const Text('Vaciar'),
                  ),
                ],
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 168),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: lineas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, indice) {
                    final linea = lineas[indice];
                    final producto = linea.producto!;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  producto.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  formatearDinero(producto.precioCentavos * linea.cantidad),
                                  style: TextStyle(fontSize: 12, color: Colors.brown.shade300),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Quitar uno',
                            onPressed: () => onRestar(producto),
                            icon: const Icon(Icons.remove_circle_outline, size: 22),
                          ),
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${linea.cantidad}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Agregar uno',
                            onPressed: () => onSumar(producto),
                            icon: const Icon(Icons.add_circle_outline, size: 22),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 12)),
                        Text(
                          formatearDinero(total),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: cobrando ? null : onCobrar,
                    style: FilledButton.styleFrom(minimumSize: const Size(180, 54)),
                    icon: cobrando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(cobrando ? 'Guardando…' : 'Cobrar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogoVacio extends StatelessWidget {
  const _CatalogoVacio({required this.onAgregar});

  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🍭', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            const Text(
              'Todavía no cargaste productos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Agregá tus chocolates, gomitas o galletitas con su precio y stock.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.brown.shade400),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAgregar,
              style: FilledButton.styleFrom(minimumSize: const Size(240, 50)),
              icon: const Icon(Icons.add),
              label: const Text('Cargar mi primer producto'),
            ),
          ],
        ),
      ),
    );
  }
}

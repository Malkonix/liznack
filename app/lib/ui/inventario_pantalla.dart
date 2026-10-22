import 'dart:async';

import 'package:flutter/material.dart';

import '../datos/modelos.dart';
import '../nucleo/formato.dart';
import '../tienda.dart';
import 'producto_editor.dart';
import 'tema.dart';
import 'tienda_scope.dart';

class InventarioPantalla extends StatefulWidget {
  const InventarioPantalla({super.key});

  @override
  State<InventarioPantalla> createState() => _InventarioPantallaState();
}

class _InventarioPantallaState extends State<InventarioPantalla> {
  Tienda? _tienda;
  int _versionVista = -1;
  List<Producto> _productos = const [];
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
      final productos = await tienda.catalogo.listar();
      if (!mounted) return;
      setState(() {
        _productos = productos;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevo() async {
    final guardado = await EditorProducto.abrir(context);
    if (guardado && mounted) {
      _avisar('Producto agregado.');
    }
  }

  Future<void> _editar(Producto producto) async {
    final guardado = await EditorProducto.abrir(context, producto: producto);
    if (guardado && mounted) _avisar('Producto actualizado.');
  }

  Future<void> _reponer(Producto producto) async {
    final cantidad = await pedirCantidadReponer(context, producto);
    if (cantidad == null || cantidad <= 0 || !mounted) return;
    await TiendaScope.of(context).reponerStock(producto.id, cantidad);
    if (mounted) _avisar('Stock actualizado: +$cantidad de ${producto.nombre}.');
  }

  Future<void> _archivar(Producto producto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archivar producto'),
        content: Text(
          '${producto.nombre} deja de aparecer en Vender. '
          'Las ventas que ya hiciste se mantienen en el historial.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Archivar')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    await TiendaScope.of(context).archivarProducto(producto.id);
    if (mounted) _avisar('Producto archivado.');
  }

  Future<void> _restaurar(Producto producto) async {
    await TiendaScope.of(context).restaurarProducto(producto.id);
    if (mounted) _avisar('Producto restaurado.');
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activos = _productos.where((p) => p.activo).toList();
    final archivados = _productos.where((p) => !p.activo).toList();
    final sinStock = activos.where((p) => p.sinStock).length;

    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            Text(
              '${plural(activos.length, 'producto activo', 'productos activos')}'
              '${sinStock > 0 ? ' · $sinStock sin stock' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.brown.shade400),
            ),
            const SizedBox(height: 10),
            if (activos.isEmpty)
              _InventarioVacio(onAgregar: _nuevo)
            else
              for (final producto in activos) ...[
                _FilaProducto(
                  producto: producto,
                  onReponer: () => _reponer(producto),
                  onEditar: () => _editar(producto),
                  onArchivar: () => _archivar(producto),
                  onRestaurar: () => _restaurar(producto),
                ),
                const SizedBox(height: 8),
              ],
            if (archivados.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Archivados',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.brown.shade400,
                ),
              ),
              const SizedBox(height: 8),
              for (final producto in archivados)
                _FilaProducto(
                  producto: producto,
                  onReponer: () => _reponer(producto),
                  onEditar: () => _editar(producto),
                  onArchivar: () => _archivar(producto),
                  onRestaurar: () => _restaurar(producto),
                ),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: carameloSuave.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: caramelo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El stock baja solo con cada venta. Si contás distinto, reponé con el botón + '
                      'para que quede registrado.',
                      style: TextStyle(fontSize: 12.5, color: Colors.brown.shade500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _nuevo,
            backgroundColor: caramelo,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo producto'),
          ),
        ),
      ],
    );
  }
}

class _FilaProducto extends StatelessWidget {
  const _FilaProducto({
    required this.producto,
    required this.onReponer,
    required this.onEditar,
    required this.onArchivar,
    required this.onRestaurar,
  });

  final Producto producto;
  final VoidCallback onReponer;
  final VoidCallback onEditar;
  final VoidCallback onArchivar;
  final VoidCallback onRestaurar;

  @override
  Widget build(BuildContext context) {
    final color = producto.sinStock ? rojoError : verdeOk;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text(
                '${producto.stockActual}',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    producto.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatearDinero(producto.precioCentavos)} · '
                    '${producto.sinStock ? 'sin stock' : plural(producto.stockActual, 'unidad', 'unidades')}',
                    style: TextStyle(fontSize: 12.5, color: Colors.brown.shade400),
                  ),
                ],
              ),
            ),
            if (producto.pendiente)
              Tooltip(
                message: 'Pendiente de sincronizar',
                child: Icon(Icons.cloud_upload_outlined, size: 16, color: Colors.orange.shade400),
              ),
            IconButton(
              tooltip: 'Reponer stock',
              onPressed: onReponer,
              icon: const Icon(Icons.add_box_outlined),
              color: caramelo,
            ),
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              onSelected: (opcion) {
                switch (opcion) {
                  case 'editar':
                    onEditar();
                  case 'archivar':
                    onArchivar();
                  case 'restaurar':
                    onRestaurar();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'editar', child: Text('Editar')),
                if (producto.activo)
                  const PopupMenuItem(value: 'archivar', child: Text('Archivar'))
                else
                  const PopupMenuItem(value: 'restaurar', child: Text('Restaurar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InventarioVacio extends StatelessWidget {
  const _InventarioVacio({required this.onAgregar});

  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Text('🍫', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text(
            'Tu inventario está vacío',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Cargá lo que vendés con su precio y cuántas unidades tenés.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.brown.shade400),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onAgregar, child: const Text('Cargar producto')),
        ],
      ),
    );
  }
}

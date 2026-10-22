import 'package:flutter/material.dart';

import '../datos/modelos.dart';
import '../nucleo/formato.dart';
import 'tema.dart';
import 'tienda_scope.dart';

/// Hoja para cargar o editar un producto. Devuelve `true` si guardó.
class EditorProducto extends StatefulWidget {
  const EditorProducto({super.key, this.producto});

  final Producto? producto;

  static Future<bool> abrir(BuildContext context, {Producto? producto}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: fondoCrema,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditorProducto(producto: producto),
    );
    return guardado ?? false;
  }

  @override
  State<EditorProducto> createState() => _EditorProductoState();
}

class _EditorProductoState extends State<EditorProducto> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _precio;
  final _stock = TextEditingController(text: '0');
  bool _guardando = false;
  String? _error;

  bool get _esNuevo => widget.producto == null;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.producto?.nombre ?? '');
    final precio = widget.producto?.precioCentavos;
    _precio = TextEditingController(
      text: precio == null
          ? ''
          : (precio % 100 == 0
              ? '${precio ~/ 100}'
              : (precio / 100).toStringAsFixed(2).replaceAll('.', ',')),
    );
  }

  @override
  void dispose() {
    _nombre.dispose();
    _precio.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final tienda = TiendaScope.of(context);
    final precioCentavos = parsearDinero(_precio.text);
    final stockInicial = int.tryParse(_stock.text.trim()) ?? 0;

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (_esNuevo) {
        await tienda.crearProducto(
          nombre: _nombre.text,
          precioCentavos: precioCentavos ?? 0,
          stockInicial: stockInicial,
        );
      } else {
        await tienda.editarProducto(
          producto: widget.producto!,
          nombre: _nombre.text,
          precioCentavos: precioCentavos ?? 0,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = 'No se pudo guardar. Intentá de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _esNuevo ? 'Nuevo producto' : 'Editar producto',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: _esNuevo,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    hintText: 'Chocolate con leche',
                  ),
                  validator: (valor) {
                    final texto = (valor ?? '').trim();
                    if (texto.isEmpty) return 'Poné un nombre.';
                    if (texto.length > 60) return 'Máximo 60 caracteres.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _precio,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio',
                    prefixText: r'$ ',
                    hintText: '500',
                    helperText: 'Podés usar centavos: 12,50',
                  ),
                  validator: (valor) {
                    final centavos = parsearDinero(valor ?? '');
                    if (centavos == null) return 'Precio inválido.';
                    if (centavos > 100000000) return 'Ese precio es demasiado alto.';
                    return null;
                  },
                ),
                if (_esNuevo) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stock inicial',
                      hintText: '10',
                      helperText: 'Después podés reponer desde Inventario.',
                    ),
                    validator: (valor) {
                      final numero = int.tryParse((valor ?? '').trim());
                      if (numero == null || numero < 0) return 'Poné un número (0 o más).';
                      if (numero > 100000) return 'Ese número es muy grande.';
                      return null;
                    },
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: rojoError, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(_esNuevo ? 'Agregar producto' : 'Guardar cambios'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo para sumar stock. Devuelve la cantidad o `null`.
Future<int?> pedirCantidadReponer(BuildContext context, Producto producto) {
  return showDialog<int>(
    context: context,
    builder: (context) {
      final controlador = TextEditingController(text: '6');
      return AlertDialog(
        title: const Text('Reponer stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${producto.nombre} · hay ${producto.stockActual}'),
            const SizedBox(height: 12),
            TextField(
              controller: controlador,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '¿Cuántos agregás?'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final cantidad in [1, 6, 12, 24])
                  ActionChip(
                    label: Text('+$cantidad'),
                    onPressed: () => controlador.text = '$cantidad',
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final cantidad = int.tryParse(controlador.text.trim());
              if (cantidad == null || cantidad <= 0) return;
              Navigator.of(context).pop(cantidad);
            },
            child: const Text('Agregar'),
          ),
        ],
      );
    },
  );
}

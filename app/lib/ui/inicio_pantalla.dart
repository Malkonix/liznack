import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../actualizacion/feed_actualizaciones.dart';
import 'ajustes_pantalla.dart';
import 'estado_sync_widget.dart';
import 'inventario_pantalla.dart';
import 'vender_pantalla.dart';
import 'ventas_pantalla.dart';

class InicioPantalla extends StatefulWidget {
  const InicioPantalla({super.key, this.versionNueva});

  /// La versión nueva que encontró la revisión diaria, si la hay.
  ///
  /// La revisión la hace `LiznackApp` al arrancar (ver `app.dart`): acá sólo se
  /// avisa. Nulo en las pruebas y cuando la revisión automática está apagada.
  final ValueListenable<ReleaseInfo?>? versionNueva;

  @override
  State<InicioPantalla> createState() => _InicioPantallaState();
}

class _InicioPantallaState extends State<InicioPantalla> {
  int _indice = 0;

  static const _titulos = ['Vender', 'Inventario', 'Ventas', 'Ajustes'];

  /// La última etiqueta que ya se avisó, para no repetir el aviso.
  String? _avisada;

  @override
  void initState() {
    super.initState();
    widget.versionNueva?.addListener(_avisarVersionNueva);
    // Si la revisión terminó antes de que se abriera esta pantalla (o la app
    // venía del ingreso), el aviso se muestra igual al primer frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _avisarVersionNueva());
  }

  @override
  void dispose() {
    widget.versionNueva?.removeListener(_avisarVersionNueva);
    super.dispose();
  }

  /// Avisa una sola vez por versión y lleva a Ajustes, donde está el botón.
  void _avisarVersionNueva() {
    final release = widget.versionNueva?.value;
    if (!mounted || release == null || release.etiqueta == _avisada) return;
    _avisada = release.etiqueta;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Hay una versión ${release.version} disponible.'),
        action: SnackBarAction(
          label: 'Ver',
          onPressed: () => setState(() => _indice = 3),
        ),
        duration: const Duration(seconds: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titulos[_indice], overflow: TextOverflow.ellipsis),
        actions: const [ChipEstadoSync()],
      ),
      body: IndexedStack(
        index: _indice,
        children: [
          VenderPantalla(onIrAInventario: () => setState(() => _indice = 1)),
          const InventarioPantalla(),
          const VentasPantalla(),
          const AjustesPantalla(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (indice) {
          // Un aviso de la pestaña anterior no debe tapar el botón de cobrar.
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          setState(() => _indice = indice);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Vender',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Ventas',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}

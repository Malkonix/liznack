import 'package:flutter/material.dart';

import 'ajustes_pantalla.dart';
import 'estado_sync_widget.dart';
import 'inventario_pantalla.dart';
import 'vender_pantalla.dart';
import 'ventas_pantalla.dart';

class InicioPantalla extends StatefulWidget {
  const InicioPantalla({super.key});

  @override
  State<InicioPantalla> createState() => _InicioPantallaState();
}

class _InicioPantallaState extends State<InicioPantalla> {
  int _indice = 0;

  static const _titulos = ['Vender', 'Inventario', 'Ventas', 'Ajustes'];

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

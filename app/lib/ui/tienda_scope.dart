import 'package:flutter/widgets.dart';

import '../tienda.dart';

/// Da acceso a la tienda y hace que las pantallas se reconstruyan cuando cambia.
class TiendaScope extends InheritedNotifier<Tienda> {
  const TiendaScope({super.key, required Tienda tienda, required super.child})
      : super(notifier: tienda);

  static Tienda of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TiendaScope>();
    assert(scope != null, 'Falta TiendaScope arriba en el árbol de widgets.');
    return scope!.notifier!;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'tienda.dart';
import 'ui/inicio_pantalla.dart';
import 'ui/login_pantalla.dart';
import 'ui/tema.dart';
import 'ui/tienda_scope.dart';

class LiznackApp extends StatefulWidget {
  const LiznackApp({super.key, required this.tienda});

  final Tienda tienda;

  @override
  State<LiznackApp> createState() => _LiznackAppState();
}

class _LiznackAppState extends State<LiznackApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.tienda.sincronizar());
    }
  }

  @override
  Widget build(BuildContext context) {
    return TiendaScope(
      tienda: widget.tienda,
      child: MaterialApp(
        title: 'Liznack',
        debugShowCheckedModeBanner: false,
        theme: construirTema(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Raiz(),
      ),
    );
  }
}

/// Muestra ingreso o la app según haya sesión. Vive dentro de la misma ruta,
/// así el cambio de cuenta nunca deja pantallas viejas en la pila.
class _Raiz extends StatelessWidget {
  const _Raiz();

  @override
  Widget build(BuildContext context) {
    final tienda = TiendaScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: tienda.sesion == null
          ? const LoginPantalla(key: ValueKey('login'))
          : const InicioPantalla(key: ValueKey('inicio')),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'actualizacion/feed_actualizaciones.dart';
import 'actualizacion/revisor.dart';
import 'tienda.dart';
import 'ui/inicio_pantalla.dart';
import 'ui/login_pantalla.dart';
import 'ui/tema.dart';
import 'ui/tienda_scope.dart';

class LiznackApp extends StatefulWidget {
  const LiznackApp({super.key, required this.tienda, this.revisor});

  final Tienda tienda;

  /// Si se pasa, al abrir la app se mira si hay una versión nueva publicada
  /// (como mucho una vez por día) y se avisa en la pantalla de inicio.
  ///
  /// Lo inyecta `main()`: en las pruebas de widgets no hay red ni
  /// preferencias, así que la app no debe intentar ninguna de las dos.
  final Revisor? revisor;

  @override
  State<LiznackApp> createState() => _LiznackAppState();
}

class _LiznackAppState extends State<LiznackApp> with WidgetsBindingObserver {
  /// La versión nueva, para que la pantalla de inicio la muestre cuando esté.
  final _versionNueva = ValueNotifier<ReleaseInfo?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final revisor = widget.revisor;
    if (revisor != null) unawaited(_mirarVersionNueva(revisor));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _versionNueva.dispose();
    super.dispose();
  }

  /// Busca la versión nueva sin molestar: si no hay red o no hay releases, no
  /// pasa nada. La revisión diaria y lo que se guarda lo maneja [Revisor].
  Future<void> _mirarVersionNueva(Revisor revisor) async {
    try {
      final release = await revisor.revisarSiToca();
      if (mounted) _versionNueva.value = release;
    } catch (_) {
      // Sin red, sin releases o GitHub ocupado: se reintenta en la próxima.
    }
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
        home: _Raiz(versionNueva: _versionNueva),
      ),
    );
  }
}

/// Muestra ingreso o la app según haya sesión. Vive dentro de la misma ruta,
/// así el cambio de cuenta nunca deja pantallas viejas en la pila.
class _Raiz extends StatelessWidget {
  const _Raiz({required this.versionNueva});

  final ValueListenable<ReleaseInfo?> versionNueva;

  @override
  Widget build(BuildContext context) {
    final tienda = TiendaScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: tienda.sesion == null
          ? const LoginPantalla(key: ValueKey('login'))
          : InicioPantalla(key: const ValueKey('inicio'), versionNueva: versionNueva),
    );
  }
}

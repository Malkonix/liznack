import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'datos/base_datos.dart';
import 'datos/catalogo_repo.dart';
import 'datos/ventas_repo.dart';
import 'nucleo/sesion.dart';
import 'sync/api_cliente.dart';
import 'sync/sync_service.dart';
import 'tienda.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Es una app de mostrador: se usa de pie, con una mano.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final db = await BaseDatos.abrir();
  final dispositivoId = await Tienda.obtenerDispositivoId(db);
  final prefs = await SharedPreferences.getInstance();

  final tienda = Tienda(
    db: db,
    catalogo: CatalogoRepo(db, dispositivoId),
    ventas: VentasRepo(db, dispositivoId),
    sync: SyncService(
      db: db,
      api: ApiCliente(baseUrl: Tienda.servidorPorDefecto),
      dispositivoId: dispositivoId,
    ),
    almacen: AlmacenPrefs(prefs),
    dispositivoId: dispositivoId,
  );

  await tienda.iniciar();
  runApp(LiznackApp(tienda: tienda));
}

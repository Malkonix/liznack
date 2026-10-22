import 'dart:io';

import 'package:liznack/datos/base_datos.dart';
import 'package:liznack/datos/catalogo_repo.dart';
import 'package:liznack/datos/ventas_repo.dart';
import 'package:liznack/nucleo/sesion.dart';
import 'package:liznack/sync/api_cliente.dart';
import 'package:liznack/sync/sync_service.dart';
import 'package:liznack/tienda.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Crea una tienda real (SQLite en disco temporal) para probar sin celular.
Future<Tienda> tiendaDePrueba({
  String servidor = 'http://127.0.0.1:9',
  String dispositivoId = 'tel-prueba',
  String usuarioId = 'user-prueba',
  String? rutaDb,
  AlmacenSesion? almacen,
  bool autoSync = false,
}) async {
  sqfliteFfiInit();
  final ruta = rutaDb ?? p.join(Directory.systemTemp.createTempSync('liznack_').path, 'liznack.db');
  // Sin isolate: las consultas resuelven en microtareas, cómodo para widgets.
  final db = await BaseDatos.abrir(ruta: ruta, fabrica: databaseFactoryFfiNoIsolate);
  final api = ApiCliente(baseUrl: servidor, tiempoLimite: const Duration(seconds: 4));
  final tienda = Tienda(
    db: db,
    catalogo: CatalogoRepo(db, dispositivoId, usuarioId),
    ventas: VentasRepo(db, dispositivoId, usuarioId),
    sync: SyncService(
      db: db,
      api: api,
      dispositivoId: dispositivoId,
      usuarioId: usuarioId,
    ),
    almacen: almacen ?? AlmacenMemoria(),
    dispositivoId: dispositivoId,
    servidorUrl: servidor,
    autoSync: autoSync,
  );
  await tienda.refrescarEstado();
  return tienda;
}

String rutaTemporalDb() =>
    p.join(Directory.systemTemp.createTempSync('liznack_').path, 'liznack.db');

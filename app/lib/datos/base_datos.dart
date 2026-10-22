import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base local del teléfono: la fuente de verdad mientras no hay internet.
///
/// `pendiente = 1` marca una fila que todavía no confirmó el servidor.
class BaseDatos {
  static const version = 1;

  static Future<Database> abrir({String? ruta, DatabaseFactory? fabrica}) async {
    final factory = fabrica ?? databaseFactory;
    final camino = ruta ?? p.join(await factory.getDatabasesPath(), 'liznack.db');
    return factory.openDatabase(
      camino,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final sentencia in _esquema) {
            await db.execute(sentencia);
          }
        },
      ),
    );
  }

  static const List<String> _esquema = [
    '''
    CREATE TABLE productos (
      id              TEXT PRIMARY KEY,
      nombre          TEXT NOT NULL,
      precio_centavos INTEGER NOT NULL,
      stock_base      INTEGER NOT NULL,
      activo          INTEGER NOT NULL DEFAULT 1,
      actualizado_en  INTEGER NOT NULL,
      dispositivo_id  TEXT NOT NULL,
      usuario_id      TEXT NOT NULL,
      pendiente       INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE ventas (
      id              TEXT PRIMARY KEY,
      creado_en       INTEGER NOT NULL,
      total_centavos  INTEGER NOT NULL,
      anulada         INTEGER NOT NULL DEFAULT 0,
      actualizado_en  INTEGER NOT NULL,
      dispositivo_id  TEXT NOT NULL,
      usuario_id      TEXT NOT NULL,
      pendiente       INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE venta_items (
      id              TEXT PRIMARY KEY,
      venta_id        TEXT NOT NULL REFERENCES ventas(id) ON DELETE CASCADE,
      producto_id     TEXT NOT NULL,
      nombre          TEXT NOT NULL,
      precio_centavos INTEGER NOT NULL,
      cantidad        INTEGER NOT NULL,
      usuario_id      TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE movimientos (
      id             TEXT PRIMARY KEY,
      producto_id    TEXT NOT NULL,
      cantidad       INTEGER NOT NULL,
      motivo         TEXT NOT NULL,
      creado_en      INTEGER NOT NULL,
      dispositivo_id TEXT NOT NULL,
      usuario_id     TEXT NOT NULL,
      pendiente      INTEGER NOT NULL DEFAULT 1
    )
    ''',
    'CREATE TABLE meta (clave TEXT PRIMARY KEY, valor TEXT NOT NULL)',
    'CREATE INDEX idx_productos_pendiente ON productos (pendiente)',
    'CREATE INDEX idx_ventas_pendiente ON ventas (pendiente)',
    'CREATE INDEX idx_movimientos_pendiente ON movimientos (pendiente)',
    'CREATE INDEX idx_items_venta ON venta_items (venta_id)',
    'CREATE INDEX idx_productos_usuario ON productos (usuario_id)',
    'CREATE INDEX idx_ventas_usuario ON ventas (usuario_id)',
  ];
}

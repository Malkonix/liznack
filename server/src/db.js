import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

/**
 * Abre (o crea) la base SQLite y aplica el esquema.
 * El esquema es libre de migraciones automáticas a propósito: es un MVP de 5 tablas.
 */
export function abrirBase(rutaArchivo = process.env.DATABASE_FILE ?? 'data/liznack.db') {
  const ruta = rutaArchivo === ':memory:' ? ':memory:' : resolve(rutaArchivo);
  if (ruta !== ':memory:') mkdirSync(dirname(ruta), { recursive: true });

  const db = new DatabaseSync(ruta);
  db.exec('PRAGMA journal_mode = WAL;');
  db.exec('PRAGMA foreign_keys = ON;');
  db.exec(ESQUEMA);
  migrar(db);
  return db;
}

/**
 * Ajustes para bases creadas antes de una columna nueva. El esquema no borra ni
 * reescribe nada: solo se agrega lo que falta.
 */
function migrar(db) {
  const columnas = db.prepare('PRAGMA table_info(almacen)').all().map((c) => c.name);
  if (!columnas.includes('costo_centavos')) {
    db.exec('ALTER TABLE almacen ADD COLUMN costo_centavos INTEGER NOT NULL DEFAULT 0');
  }
  const columnasTraslados = db.prepare('PRAGMA table_info(traslados)').all().map((c) => c.name);
  if (!columnasTraslados.includes('tipo')) {
    db.exec("ALTER TABLE traslados ADD COLUMN tipo TEXT NOT NULL DEFAULT 'envio'");
  }
}

const ESQUEMA = `
CREATE TABLE IF NOT EXISTS usuarios (
  id          TEXT PRIMARY KEY,
  email       TEXT NOT NULL UNIQUE,
  hash        TEXT NOT NULL,
  salt        TEXT NOT NULL,
  creado_en   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sesiones (
  token_hash  TEXT PRIMARY KEY,
  usuario_id  TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  creado_en   TEXT NOT NULL,
  expira_en   TEXT NOT NULL
);

-- Contador de revisión por dueño. Cada fila modificada recibe un rev mayor,
-- y el cliente pide "dame todo lo que tenga rev > la última que vi".
CREATE TABLE IF NOT EXISTS contadores (
  usuario_id    TEXT PRIMARY KEY,
  siguiente_rev INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS productos (
  usuario_id      TEXT NOT NULL,
  id              TEXT NOT NULL,
  nombre          TEXT NOT NULL,
  precio_centavos INTEGER NOT NULL,
  stock_base      INTEGER NOT NULL,
  activo          INTEGER NOT NULL DEFAULT 1,
  actualizado_en  INTEGER NOT NULL,
  dispositivo_id  TEXT NOT NULL,
  rev             INTEGER NOT NULL,
  PRIMARY KEY (usuario_id, id)
);

CREATE TABLE IF NOT EXISTS ventas (
  usuario_id      TEXT NOT NULL,
  id              TEXT NOT NULL,
  creado_en       INTEGER NOT NULL,
  total_centavos  INTEGER NOT NULL,
  anulada         INTEGER NOT NULL DEFAULT 0,
  actualizado_en  INTEGER NOT NULL,
  dispositivo_id  TEXT NOT NULL,
  rev             INTEGER NOT NULL,
  PRIMARY KEY (usuario_id, id)
);

CREATE TABLE IF NOT EXISTS venta_items (
  usuario_id      TEXT NOT NULL,
  id              TEXT NOT NULL,
  venta_id        TEXT NOT NULL,
  producto_id     TEXT NOT NULL,
  nombre          TEXT NOT NULL,
  precio_centavos INTEGER NOT NULL,
  cantidad        INTEGER NOT NULL,
  PRIMARY KEY (usuario_id, id)
);

-- Ajustes de stock (reposición, merma). La venta NO se guarda acá: se deriva
-- de venta_items, así dos teléfonos que venden el mismo producto no se pisan.
CREATE TABLE IF NOT EXISTS movimientos (
  usuario_id     TEXT NOT NULL,
  id             TEXT NOT NULL,
  producto_id    TEXT NOT NULL,
  cantidad       INTEGER NOT NULL,
  motivo         TEXT NOT NULL,
  creado_en      INTEGER NOT NULL,
  dispositivo_id TEXT NOT NULL,
  rev            INTEGER NOT NULL,
  PRIMARY KEY (usuario_id, id)
);

CREATE INDEX IF NOT EXISTS idx_productos_rev ON productos (usuario_id, rev);
CREATE INDEX IF NOT EXISTS idx_ventas_rev    ON ventas    (usuario_id, rev);
CREATE INDEX IF NOT EXISTS idx_movs_rev      ON movimientos (usuario_id, rev);
CREATE INDEX IF NOT EXISTS idx_items_venta   ON venta_items (usuario_id, venta_id);
CREATE INDEX IF NOT EXISTS idx_ventas_fecha  ON ventas (usuario_id, creado_en);

-- Depósito central del padre. No se sincroniza con los teléfonos: es la
-- bodega desde la que se reparte stock a cada vendedor.
CREATE TABLE IF NOT EXISTS almacen (
  id              TEXT PRIMARY KEY,
  nombre          TEXT NOT NULL,
  nombre_clave    TEXT NOT NULL UNIQUE,
  costo_centavos  INTEGER NOT NULL DEFAULT 0,
  precio_centavos INTEGER NOT NULL DEFAULT 0,
  stock           INTEGER NOT NULL DEFAULT 0,
  creado_en       TEXT NOT NULL
);

-- Cada movimiento del depósito hacia un vendedor (envio) o de vuelta
-- (devolucion).
CREATE TABLE IF NOT EXISTS traslados (
  id          TEXT PRIMARY KEY,
  almacen_id  TEXT NOT NULL REFERENCES almacen (id) ON DELETE CASCADE,
  usuario_id  TEXT NOT NULL,
  producto_id TEXT NOT NULL,
  cantidad    INTEGER NOT NULL,
  tipo        TEXT NOT NULL DEFAULT 'envio',
  creado_en   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_traslados_almacen ON traslados (almacen_id);

-- El stock se calcula, no se guarda: misma fórmula que usa el teléfono.
CREATE VIEW IF NOT EXISTS vista_stock AS
SELECT p.usuario_id,
       p.id AS producto_id,
       p.stock_base
       + COALESCE((SELECT SUM(m.cantidad) FROM movimientos m
                    WHERE m.usuario_id = p.usuario_id AND m.producto_id = p.id), 0)
       - COALESCE((SELECT SUM(i.cantidad) FROM venta_items i
                    JOIN ventas v ON v.usuario_id = i.usuario_id AND v.id = i.venta_id
                    WHERE i.usuario_id = p.usuario_id AND i.producto_id = p.id
                      AND v.anulada = 0), 0)
       AS stock_actual
  FROM productos p;
`;

/** Devuelve un rev nuevo y exclusivo para ese dueño. */
export function siguienteRev(db, usuarioId) {
  db.prepare(
    `INSERT INTO contadores (usuario_id, siguiente_rev) VALUES (?, 1)
     ON CONFLICT(usuario_id) DO NOTHING`,
  ).run(usuarioId);
  const fila = db.prepare('SELECT siguiente_rev FROM contadores WHERE usuario_id = ?').get(usuarioId);
  db.prepare('UPDATE contadores SET siguiente_rev = siguiente_rev + 1 WHERE usuario_id = ?').run(usuarioId);
  return fila.siguiente_rev;
}

/** Rev actual (el último entregado) para ese dueño. */
export function revActual(db, usuarioId) {
  const fila = db.prepare('SELECT siguiente_rev FROM contadores WHERE usuario_id = ?').get(usuarioId);
  return fila ? fila.siguiente_rev - 1 : 0;
}

export function enTransaccion(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const resultado = fn();
    db.exec('COMMIT');
    return resultado;
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}

/** Fórmula única de stock: base + ajustes - ventas activas. */
export const SQL_STOCK = `
  p.stock_base
  + COALESCE((SELECT SUM(m.cantidad) FROM movimientos m
              WHERE m.usuario_id = p.usuario_id AND m.producto_id = p.id), 0)
  - COALESCE((SELECT SUM(i.cantidad) FROM venta_items i
              JOIN ventas v ON v.usuario_id = i.usuario_id AND v.id = i.venta_id
              WHERE i.usuario_id = p.usuario_id AND i.producto_id = p.id AND v.anulada = 0), 0)
`;

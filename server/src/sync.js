import { siguienteRev, revActual } from './db.js';

/**
 * Sincronización por revisión + resolución de conflictos.
 *
 * - Las ventas son hechos: se insertan una sola vez (id UUID del teléfono) y
 *   nunca se pisan, así que reintentar un envío no duplica plata.
 * - El stock no viaja como número absoluto: se deriva de stock_base + ajustes
 *   - ventas. Dos teléfonos que venden sin conexión no se pisan el stock.
 * - Nombre/precio/activo de un producto usan "gana el último cambio" con
 *   desempate por dispositivo_id, y el servidor avisa cuando descartó algo.
 */

const LIMITE_PRODUCTOS = 500;
const LIMITE_VENTAS = 300;
const LIMITE_MOVIMIENTOS = 500;

const esEntero = (v, min, max) => Number.isInteger(v) && v >= min && v <= max;
const esTexto = (v, max) => typeof v === 'string' && v.trim().length > 0 && v.length <= max;
const esId = (v) => esTexto(v, 100);
const esFechaMs = (v) => esEntero(v, 1, 4_200_000_000_000);

/** Gana el cambio más reciente; si empatan, gana el dispositivo con id mayor. */
export function ganaCliente(entrante, actual) {
  if (entrante.actualizado_en !== actual.actualizado_en) {
    return entrante.actualizado_en > actual.actualizado_en;
  }
  return String(entrante.dispositivo_id) > String(actual.dispositivo_id);
}

function validarProducto(p) {
  if (!esId(p?.id)) return 'id inválido';
  if (!esTexto(p?.nombre, 80)) return 'nombre inválido';
  if (!esEntero(p?.precio_centavos, 0, 100_000_000)) return 'precio inválido';
  if (!esEntero(p?.stock_base, -1_000_000, 1_000_000)) return 'stock inválido';
  if (typeof p?.activo !== 'boolean' && ![0, 1].includes(p?.activo)) return 'activo inválido';
  if (!esFechaMs(p?.actualizado_en)) return 'actualizado_en inválido';
  if (!esId(p?.dispositivo_id)) return 'dispositivo_id inválido';
  return null;
}

function validarVenta(v) {
  if (!esId(v?.id)) return 'id inválido';
  if (!esFechaMs(v?.creado_en)) return 'creado_en inválido';
  if (!esFechaMs(v?.actualizado_en)) return 'actualizado_en inválido';
  if (!esId(v?.dispositivo_id)) return 'dispositivo_id inválido';
  if (typeof v?.anulada !== 'boolean' && ![0, 1].includes(v?.anulada)) return 'anulada inválida';
  if (!Array.isArray(v?.items) || v.items.length === 0) return 'sin ítems';
  if (v.items.length > 100) return 'demasiados ítems';
  for (const item of v.items) {
    if (!esId(item?.id)) return 'ítem con id inválido';
    if (!esId(item?.producto_id)) return 'ítem sin producto';
    if (!esTexto(item?.nombre, 80)) return 'ítem con nombre inválido';
    if (!esEntero(item?.precio_centavos, 0, 100_000_000)) return 'ítem con precio inválido';
    if (!esEntero(item?.cantidad, 1, 10_000)) return 'ítem con cantidad inválida';
  }
  return null;
}

function validarMovimiento(m) {
  if (!esId(m?.id)) return 'id inválido';
  if (!esId(m?.producto_id)) return 'producto_id inválido';
  if (!esEntero(m?.cantidad, -1_000_000, 1_000_000) || m.cantidad === 0) return 'cantidad inválida';
  if (!esTexto(m?.motivo, 40)) return 'motivo inválido';
  if (!esFechaMs(m?.creado_en)) return 'creado_en inválido';
  if (!esId(m?.dispositivo_id)) return 'dispositivo_id inválido';
  return null;
}

const totalDeItems = (items) =>
  items.reduce((suma, i) => suma + i.precio_centavos * i.cantidad, 0);

/**
 * Aplica los cambios que mandó un dispositivo.
 * Devuelve { aplicados, conflictos, rechazados }.
 */
export function aplicarCambios(db, usuarioId, cambios = {}) {
  const productos = Array.isArray(cambios.productos) ? cambios.productos.slice(0, LIMITE_PRODUCTOS) : [];
  const ventas = Array.isArray(cambios.ventas) ? cambios.ventas.slice(0, LIMITE_VENTAS) : [];
  const movimientos = Array.isArray(cambios.movimientos) ? cambios.movimientos.slice(0, LIMITE_MOVIMIENTOS) : [];

  const resultado = {
    aplicados: { productos: 0, ventas: 0, movimientos: 0 },
    conflictos: [],
    rechazados: [],
  };

  for (const p of productos) {
    const error = validarProducto(p);
    if (error) {
      resultado.rechazados.push({ tipo: 'producto', id: p?.id ?? null, motivo: error });
      continue;
    }
    const actual = db
      .prepare('SELECT * FROM productos WHERE usuario_id = ? AND id = ?')
      .get(usuarioId, p.id);
    const activo = p.activo ? 1 : 0;

    if (!actual) {
      db.prepare(
        `INSERT INTO productos (usuario_id, id, nombre, precio_centavos, stock_base, activo,
                                actualizado_en, dispositivo_id, rev)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        usuarioId, p.id, p.nombre.trim(), p.precio_centavos, p.stock_base, activo,
        p.actualizado_en, p.dispositivo_id, siguienteRev(db, usuarioId),
      );
      resultado.aplicados.productos++;
      continue;
    }

    const cambiaContenido =
      actual.nombre !== p.nombre.trim() ||
      actual.precio_centavos !== p.precio_centavos ||
      actual.stock_base !== p.stock_base ||
      actual.activo !== activo;

    if (!cambiaContenido) continue;

    if (ganaCliente(p, actual)) {
      db.prepare(
        `UPDATE productos
            SET nombre = ?, precio_centavos = ?, stock_base = ?, activo = ?,
                actualizado_en = ?, dispositivo_id = ?, rev = ?
          WHERE usuario_id = ? AND id = ?`,
      ).run(
        p.nombre.trim(), p.precio_centavos, p.stock_base, activo,
        p.actualizado_en, p.dispositivo_id, siguienteRev(db, usuarioId), usuarioId, p.id,
      );
      resultado.aplicados.productos++;
      resultado.conflictos.push({
        tipo: 'producto',
        id: p.id,
        resolucion: 'cliente',
        mensaje: 'Se guardó el cambio más reciente del teléfono.',
      });
    } else {
      resultado.conflictos.push({
        tipo: 'producto',
        id: p.id,
        resolucion: 'servidor',
        mensaje: 'Había un cambio más reciente en el servidor; se conservó ese.',
      });
    }
  }

  for (const v of ventas) {
    const error = validarVenta(v);
    if (error) {
      resultado.rechazados.push({ tipo: 'venta', id: v?.id ?? null, motivo: error });
      continue;
    }
    const anulada = v.anulada ? 1 : 0;
    const actual = db
      .prepare('SELECT * FROM ventas WHERE usuario_id = ? AND id = ?')
      .get(usuarioId, v.id);

    if (!actual) {
      // Si algún ítem ya existe bajo otra venta, rechazamos la venta completa.
      const idsItems = v.items.map((i) => i.id);
      const choque = idsItems.length
        ? db.prepare(
            `SELECT id FROM venta_items
              WHERE usuario_id = ? AND id IN (${idsItems.map(() => '?').join(',')})
              LIMIT 1`,
          ).get(usuarioId, ...idsItems)
        : null;
      if (choque) {
        resultado.rechazados.push({
          tipo: 'venta',
          id: v.id,
          motivo: `ítem duplicado (${choque.id})`,
        });
        continue;
      }

      const rev = siguienteRev(db, usuarioId);
      // El total se recalcula acá: la plata no se confía al cliente.
      const total = totalDeItems(v.items);
      db.prepare(
        `INSERT INTO ventas (usuario_id, id, creado_en, total_centavos, anulada,
                             actualizado_en, dispositivo_id, rev)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(usuarioId, v.id, v.creado_en, total, anulada, v.actualizado_en, v.dispositivo_id, rev);
      const insertarItem = db.prepare(
        `INSERT INTO venta_items (usuario_id, id, venta_id, producto_id, nombre,
                                  precio_centavos, cantidad)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      );
      for (const i of v.items) {
        insertarItem.run(
          usuarioId, i.id, v.id, i.producto_id, i.nombre.trim(), i.precio_centavos, i.cantidad,
        );
      }
      resultado.aplicados.ventas++;
      continue;
    }

    // La venta ya existía: solo puede cambiar "anulada" (nunca se duplica).
    if (actual.anulada === anulada) continue;
    if (ganaCliente(v, actual)) {
      db.prepare(
        `UPDATE ventas SET anulada = ?, actualizado_en = ?, dispositivo_id = ?, rev = ?
          WHERE usuario_id = ? AND id = ?`,
      ).run(anulada, v.actualizado_en, v.dispositivo_id, siguienteRev(db, usuarioId), usuarioId, v.id);
      resultado.aplicados.ventas++;
      resultado.conflictos.push({
        tipo: 'venta',
        id: v.id,
        resolucion: 'cliente',
        mensaje: 'Se anuló/restauró la venta con el cambio más reciente.',
      });
    } else {
      resultado.conflictos.push({
        tipo: 'venta',
        id: v.id,
        resolucion: 'servidor',
        mensaje: 'La venta conserva el estado del servidor.',
      });
    }
  }

  for (const m of movimientos) {
    const error = validarMovimiento(m);
    if (error) {
      resultado.rechazados.push({ tipo: 'movimiento', id: m?.id ?? null, motivo: error });
      continue;
    }
    const existe = db
      .prepare('SELECT 1 AS x FROM movimientos WHERE usuario_id = ? AND id = ?')
      .get(usuarioId, m.id);
    if (existe) continue; // idempotente: los ajustes son inmutables
    db.prepare(
      `INSERT INTO movimientos (usuario_id, id, producto_id, cantidad, motivo,
                                creado_en, dispositivo_id, rev)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(usuarioId, m.id, m.producto_id, m.cantidad, m.motivo.trim(), m.creado_en,
      m.dispositivo_id, siguienteRev(db, usuarioId));
    resultado.aplicados.movimientos++;
  }

  return resultado;
}

/** Devuelve todo lo cambiado después de `desdeRev`, con tope por tabla. */
export function obtenerCambios(db, usuarioId, desdeRev) {
  const desde = Number.isInteger(desdeRev) && desdeRev >= 0 ? desdeRev : 0;

  const productos = db
    .prepare(
      `SELECT id, nombre, precio_centavos, stock_base, activo, actualizado_en, dispositivo_id, rev
         FROM productos WHERE usuario_id = ? AND rev > ? ORDER BY rev LIMIT ?`,
    )
    .all(usuarioId, desde, LIMITE_PRODUCTOS + 1);

  const ventas = db
    .prepare(
      `SELECT id, creado_en, total_centavos, anulada, actualizado_en, dispositivo_id, rev
         FROM ventas WHERE usuario_id = ? AND rev > ? ORDER BY rev LIMIT ?`,
    )
    .all(usuarioId, desde, LIMITE_VENTAS + 1);

  const movimientos = db
    .prepare(
      `SELECT id, producto_id, cantidad, motivo, creado_en, dispositivo_id, rev
         FROM movimientos WHERE usuario_id = ? AND rev > ? ORDER BY rev LIMIT ?`,
    )
    .all(usuarioId, desde, LIMITE_MOVIMIENTOS + 1);

  const hay = {
    productos: productos.length > LIMITE_PRODUCTOS,
    ventas: ventas.length > LIMITE_VENTAS,
    movimientos: movimientos.length > LIMITE_MOVIMIENTOS,
  };
  const recortar = (filas, limite) => filas.slice(0, limite);
  const productosCortados = recortar(productos, LIMITE_PRODUCTOS);
  const ventasCortadas = recortar(ventas, LIMITE_VENTAS);
  const movimientosCortados = recortar(movimientos, LIMITE_MOVIMIENTOS);

  // El `rev` es un contador único por usuario, no uno por tabla. Si una tabla
  // se corta en el rev 500 y otra en el 800, la página no puede avanzar hasta
  // el 800: las filas de la primera con rev 501..800 quedarían afuera para
  // siempre. Se avanza hasta el corte MÁS CHICO y todo lo que tenga rev mayor
  // se manda en las páginas siguientes. Cada página siempre avanza, porque
  // las filas devueltas tienen rev > desde.
  const cortes = [];
  if (hay.productos) cortes.push(productosCortados.at(-1).rev);
  if (hay.ventas) cortes.push(ventasCortadas.at(-1).rev);
  if (hay.movimientos) cortes.push(movimientosCortados.at(-1).rev);
  const hayMas = cortes.length > 0;
  const corte = hayMas ? Math.min(...cortes) : null;
  const hastaElCorte = (filas) => (hayMas ? filas.filter((f) => f.rev <= corte) : filas);

  const productosFinal = hastaElCorte(productosCortados);
  const ventasFinal = hastaElCorte(ventasCortadas);
  const movimientosFinal = hastaElCorte(movimientosCortados);

  const itemsPorVenta = new Map();
  if (ventasFinal.length > 0) {
    const marcadores = ventasFinal.map(() => '?').join(',');
    const items = db
      .prepare(
        `SELECT id, venta_id, producto_id, nombre, precio_centavos, cantidad
           FROM venta_items
          WHERE usuario_id = ? AND venta_id IN (${marcadores})`,
      )
      .all(usuarioId, ...ventasFinal.map((v) => v.id));
    for (const item of items) {
      if (!itemsPorVenta.has(item.venta_id)) itemsPorVenta.set(item.venta_id, []);
      itemsPorVenta.get(item.venta_id).push(item);
    }
  }

  return {
    // Si no hay más páginas, avanzamos directo al último rev del servidor.
    rev: hayMas ? corte : Math.max(revActual(db, usuarioId), desde),
    hay_mas: hayMas,
    productos: productosFinal.map(({ rev, ...resto }) => ({ ...resto, activo: resto.activo === 1 })),
    movimientos: movimientosFinal.map(({ rev, ...resto }) => resto),
    ventas: ventasFinal.map(({ rev, ...resto }) => ({
      ...resto,
      anulada: resto.anulada === 1,
      items: (itemsPorVenta.get(resto.id) ?? []).sort((a, b) => a.id.localeCompare(b.id)),
    })),
  };
}

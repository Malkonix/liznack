import { randomUUID } from 'node:crypto';
import { emailValido, hashClave, normalizarEmail } from './auth.js';
import { siguienteRev } from './db.js';
import { ErrorHttp } from './http.js';

/** Todo lo que el portal escribe en nombre de un dueño queda marcado así. */
export const DISPOSITIVO_PORTAL = 'portal-admin';
const MOTIVOS = new Set(['reposicion', 'merma', 'ajuste', 'devolucion']);

export function inicioDelDia(ahora = Date.now()) {
  const d = new Date(ahora);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

export function inicioHaceDias(dias, ahora = Date.now()) {
  const d = new Date(ahora);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() - dias).getTime();
}

const numero = (v) => (typeof v === 'bigint' ? Number(v) : Number(v ?? 0));

/**
 * Costo de compra por producto del almacén, por nombre normalizado.
 *
 * El costo vive solo en el portal: no se guarda en `productos` ni viaja en la
 * sincronización, así que el teléfono del vendedor nunca lo ve.
 */
function costosPorClave(db) {
  const mapa = new Map();
  for (const fila of db.prepare('SELECT nombre_clave, costo_centavos FROM almacen').all()) {
    mapa.set(String(fila.nombre_clave), numero(fila.costo_centavos));
  }
  return mapa;
}

/**
 * Ganancia de una venta a partir de sus ítems.
 *
 * Si algún ítem no está en el almacén no hay costo conocido y la ganancia queda
 * en `null` (mejor no mostrar un número inventado). Los ítems se buscan por
 * nombre, igual que los traslados.
 */
function gananciaDeVenta(items, costos) {
  let ingresos = 0;
  let costo = 0;
  let sinCosto = 0;
  for (const item of items) {
    ingresos += item.cantidad * item.precio_centavos;
    const unitario = costos.get(nombreClave(item.nombre));
    if (unitario === undefined) {
      sinCosto += 1;
      continue;
    }
    costo += item.cantidad * unitario;
  }
  return {
    ingresos,
    costo,
    ganancia: sinCosto > 0 ? null : ingresos - costo,
    sinCosto,
  };
}

/** Ítems de varias ventas, agrupados por venta y dueño. */
function itemsDeVentas(db, ventas) {
  const porUsuario = new Map();
  for (const venta of ventas) {
    if (!porUsuario.has(venta.usuario_id)) porUsuario.set(venta.usuario_id, []);
    porUsuario.get(venta.usuario_id).push(venta.id);
  }
  const mapa = new Map();
  for (const [usuarioId, ids] of porUsuario) {
    const marcas = ids.map(() => '?').join(',');
    const filas = db
      .prepare(
        `SELECT venta_id, nombre, cantidad, precio_centavos
           FROM venta_items
          WHERE usuario_id = ? AND venta_id IN (${marcas})`,
      )
      .all(usuarioId, ...ids);
    for (const fila of filas) {
      const clave = `${usuarioId}|${fila.venta_id}`;
      if (!mapa.has(clave)) mapa.set(clave, []);
      mapa.get(clave).push({
        nombre: fila.nombre,
        cantidad: numero(fila.cantidad),
        precio_centavos: numero(fila.precio_centavos),
      });
    }
  }
  return mapa;
}

/** Agrega a cada venta qué se vendió y cuánta ganancia dejó. */
function conDetalleYGanancia(db, ventas) {
  const items = itemsDeVentas(db, ventas);
  const costos = costosPorClave(db);
  return ventas.map((venta) => {
    const detalle = items.get(`${venta.usuario_id}|${venta.id}`) ?? [];
    const resultado = gananciaDeVenta(detalle, costos);
    return {
      ...venta,
      detalle,
      ganancia: resultado.ganancia,
      costo: resultado.costo,
      sinCosto: resultado.sinCosto,
    };
  });
}

/** Ganancia de todas las ventas activas de un rango de fechas. */
function gananciaEnRango(db, desde, hasta) {
  const costos = costosPorClave(db);
  const filas = db
    .prepare(
      `SELECT i.usuario_id, i.venta_id, i.nombre, i.cantidad, i.precio_centavos
         FROM venta_items i
         JOIN ventas v ON v.usuario_id = i.usuario_id AND v.id = i.venta_id
        WHERE v.anulada = 0 AND v.creado_en >= ? AND v.creado_en < ?`,
    )
    .all(desde, hasta);
  const porVenta = new Map();
  for (const fila of filas) {
    const clave = `${fila.usuario_id}|${fila.venta_id}`;
    if (!porVenta.has(clave)) porVenta.set(clave, []);
    porVenta.get(clave).push({
      nombre: fila.nombre,
      cantidad: numero(fila.cantidad),
      precio_centavos: numero(fila.precio_centavos),
    });
  }
  let ganancia = 0;
  let sinCosto = 0;
  for (const items of porVenta.values()) {
    const resultado = gananciaDeVenta(items, costos);
    if (resultado.ganancia === null) sinCosto += 1;
    else ganancia += resultado.ganancia;
  }
  return { ganancia, sinCosto };
}

/** Números para las tarjetas de arriba. */
export function resumenGeneral(db) {
  const desdeHoy = inicioDelDia();
  const desdeSemana = inicioHaceDias(6);
  const cuentas = numero(db.prepare('SELECT COUNT(*) AS n FROM usuarios').get()?.n);
  const productos = numero(
    db.prepare('SELECT COUNT(*) AS n FROM productos WHERE activo = 1').get()?.n,
  );
  const stock = numero(
    db
      .prepare(
        `SELECT COALESCE(SUM(s.stock_actual), 0) AS n
           FROM vista_stock s
           JOIN productos p ON p.usuario_id = s.usuario_id AND p.id = s.producto_id
          WHERE p.activo = 1`,
      )
      .get()?.n,
  );
  const hoy = db
    .prepare(
      `SELECT COUNT(*) AS ventas, COALESCE(SUM(total_centavos), 0) AS plata
         FROM ventas WHERE anulada = 0 AND creado_en >= ?`,
    )
    .get(desdeHoy);
  const semana = db
    .prepare(
      `SELECT COUNT(*) AS ventas, COALESCE(SUM(total_centavos), 0) AS plata
         FROM ventas WHERE anulada = 0 AND creado_en >= ?`,
    )
    .get(desdeSemana);
  const gananciaHoy = gananciaEnRango(db, desdeHoy, Number.MAX_SAFE_INTEGER);
  const gananciaSemana = gananciaEnRango(db, desdeSemana, Number.MAX_SAFE_INTEGER);

  return {
    cuentas,
    productos,
    stock,
    hoy: {
      ventas: numero(hoy.ventas),
      plata: numero(hoy.plata),
      ganancia: gananciaHoy.ganancia,
      sinCosto: gananciaHoy.sinCosto,
    },
    semana: {
      ventas: numero(semana.ventas),
      plata: numero(semana.plata),
      ganancia: gananciaSemana.ganancia,
      sinCosto: gananciaSemana.sinCosto,
    },
  };
}

export function listarCuentas(db) {
  const desdeHoy = inicioDelDia();
  return db
    .prepare(
      `SELECT u.id, u.email, u.creado_en,
              (SELECT COUNT(*) FROM productos p
                WHERE p.usuario_id = u.id) AS productos,
              (SELECT COUNT(*) FROM productos p
                WHERE p.usuario_id = u.id AND p.activo = 1) AS activos,
              (SELECT COALESCE(SUM(s.stock_actual), 0)
                 FROM vista_stock s
                 JOIN productos p ON p.usuario_id = s.usuario_id AND p.id = s.producto_id
                WHERE p.usuario_id = u.id AND p.activo = 1) AS stock,
              (SELECT COUNT(*) FROM ventas v
                WHERE v.usuario_id = u.id AND v.anulada = 0) AS ventas,
              (SELECT COALESCE(SUM(v.total_centavos), 0) FROM ventas v
                WHERE v.usuario_id = u.id AND v.anulada = 0) AS total,
              (SELECT COALESCE(SUM(v.total_centavos), 0) FROM ventas v
                WHERE v.usuario_id = u.id AND v.anulada = 0 AND v.creado_en >= ?) AS hoy,
              (SELECT MAX(v.creado_en) FROM ventas v
                WHERE v.usuario_id = u.id) AS ultima_venta
         FROM usuarios u
        ORDER BY u.creado_en ASC`,
    )
    .all(desdeHoy)
    .map((f) => ({
      ...f,
      productos: numero(f.productos),
      activos: numero(f.activos),
      stock: numero(f.stock),
      ventas: numero(f.ventas),
      total: numero(f.total),
      hoy: numero(f.hoy),
      ultima_venta: f.ultima_venta == null ? null : numero(f.ultima_venta),
    }));
}

export function obtenerCuenta(db, usuarioId) {
  const fila = db
    .prepare('SELECT id, email, creado_en FROM usuarios WHERE id = ?')
    .get(usuarioId);
  return fila ?? null;
}

export function productosDe(db, usuarioId) {
  return db
    .prepare(
      `SELECT p.id, p.nombre, p.precio_centavos, p.activo, p.actualizado_en,
              COALESCE(s.stock_actual, p.stock_base) AS stock_actual
         FROM productos p
         LEFT JOIN vista_stock s
           ON s.usuario_id = p.usuario_id AND s.producto_id = p.id
        WHERE p.usuario_id = ?
        ORDER BY p.activo DESC, p.nombre COLLATE NOCASE`,
    )
    .all(usuarioId)
    .map((f) => ({
      ...f,
      activo: f.activo === 1,
      precio_centavos: numero(f.precio_centavos),
      stock_actual: numero(f.stock_actual),
    }));
}

export function ventasDe(db, usuarioId, limite = 50) {
  const ventas = db
    .prepare(
      `SELECT v.id, v.usuario_id, v.creado_en, v.total_centavos, v.anulada,
              (SELECT COUNT(*) FROM venta_items i
                WHERE i.usuario_id = v.usuario_id AND i.venta_id = v.id) AS items
         FROM ventas v
        WHERE v.usuario_id = ?
        ORDER BY v.creado_en DESC
        LIMIT ?`,
    )
    .all(usuarioId, limite)
    .map((f) => ({
      ...f,
      anulada: f.anulada === 1,
      total_centavos: numero(f.total_centavos),
      items: numero(f.items),
    }));
  return conDetalleYGanancia(db, ventas);
}

/** Ítems de varias ventas juntos, para no consultar una vez por fila. */
/** Una venta con su detalle, para el comprobante en pantalla y en PDF. */
export function detalleVenta(db, usuarioId, ventaId) {
  const fila = db
    .prepare(
      `SELECT v.id, v.usuario_id, v.creado_en, v.total_centavos, v.anulada,
              u.email,
              (SELECT COUNT(*) FROM venta_items i
                WHERE i.usuario_id = v.usuario_id AND i.venta_id = v.id) AS items
         FROM ventas v
         JOIN usuarios u ON u.id = v.usuario_id
        WHERE v.usuario_id = ? AND v.id = ?`,
    )
    .get(usuarioId, ventaId);
  if (!fila) return null;
  const [venta] = conDetalleYGanancia(db, [
    {
      ...fila,
      anulada: fila.anulada === 1,
      total_centavos: numero(fila.total_centavos),
      items: numero(fila.items),
    },
  ]);
  return venta;
}

export function itemsPorVenta(db, usuarioId, ventaIds) {
  const mapa = new Map();
  if (!Array.isArray(ventaIds) || ventaIds.length === 0) return mapa;
  const marcas = ventaIds.map(() => '?').join(',');
  const filas = db
    .prepare(
      `SELECT venta_id, nombre, cantidad, precio_centavos
         FROM venta_items
        WHERE usuario_id = ? AND venta_id IN (${marcas})
        ORDER BY nombre COLLATE NOCASE`,
    )
    .all(usuarioId, ...ventaIds);
  for (const fila of filas) {
    if (!mapa.has(fila.venta_id)) mapa.set(fila.venta_id, []);
    mapa.get(fila.venta_id).push({
      nombre: fila.nombre,
      cantidad: numero(fila.cantidad),
      precio_centavos: numero(fila.precio_centavos),
    });
  }
  return mapa;
}

export function movimientosDe(db, usuarioId, limite = 30) {
  return db
    .prepare(
      `SELECT m.id, m.producto_id, m.cantidad, m.motivo, m.creado_en, m.dispositivo_id,
              p.nombre AS producto
         FROM movimientos m
         LEFT JOIN productos p ON p.usuario_id = m.usuario_id AND p.id = m.producto_id
        WHERE m.usuario_id = ?
        ORDER BY m.creado_en DESC
        LIMIT ?`,
    )
    .all(usuarioId, limite)
    .map((f) => ({
      ...f,
      cantidad: numero(f.cantidad),
      producto: f.producto ?? '(producto borrado)',
    }));
}

export function ventasRecientes(db, limite = 12) {
  const ventas = db
    .prepare(
      `SELECT v.id, v.usuario_id, v.creado_en, v.total_centavos, v.anulada,
              u.email,
              (SELECT COUNT(*) FROM venta_items i
                WHERE i.usuario_id = v.usuario_id AND i.venta_id = v.id) AS items
         FROM ventas v
         JOIN usuarios u ON u.id = v.usuario_id
        ORDER BY v.creado_en DESC
        LIMIT ?`,
    )
    .all(limite)
    .map((f) => ({
      ...f,
      anulada: f.anulada === 1,
      total_centavos: numero(f.total_centavos),
      items: numero(f.items),
    }));
  return conDetalleYGanancia(db, ventas);
}

/** Productos por agotarse: el padre quiere verlos sin abrir cada cuenta. */
export function stockBajo(db, minimo = 2, limite = 20) {
  return db
    .prepare(
      `SELECT p.usuario_id, p.id, p.nombre, p.precio_centavos, u.email,
              COALESCE(s.stock_actual, p.stock_base) AS stock_actual
         FROM productos p
         JOIN usuarios u ON u.id = p.usuario_id
         LEFT JOIN vista_stock s ON s.usuario_id = p.usuario_id AND s.producto_id = p.id
        WHERE p.activo = 1 AND COALESCE(s.stock_actual, p.stock_base) <= ?
        ORDER BY COALESCE(s.stock_actual, p.stock_base) ASC, p.nombre COLLATE NOCASE
        LIMIT ?`,
    )
    .all(minimo, limite)
    .map((f) => ({
      ...f,
      stock_actual: numero(f.stock_actual),
      precio_centavos: numero(f.precio_centavos),
    }));
}

export function listarVentas(db, { desde, hasta, usuarioId, limite = 200 } = {}) {
  const condiciones = [];
  const parametros = [];
  if (Number.isFinite(desde)) {
    condiciones.push('v.creado_en >= ?');
    parametros.push(desde);
  }
  if (Number.isFinite(hasta)) {
    condiciones.push('v.creado_en < ?');
    parametros.push(hasta);
  }
  if (usuarioId) {
    condiciones.push('v.usuario_id = ?');
    parametros.push(usuarioId);
  }
  const donde = condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '';
  const filas = db
    .prepare(
      `SELECT v.id, v.usuario_id, v.creado_en, v.total_centavos, v.anulada,
              u.email,
              (SELECT COUNT(*) FROM venta_items i
                WHERE i.usuario_id = v.usuario_id AND i.venta_id = v.id) AS items
         FROM ventas v
         JOIN usuarios u ON u.id = v.usuario_id
         ${donde}
        ORDER BY v.creado_en DESC
        LIMIT ?`,
    )
    .all(...parametros, limite);
  const ventas = conDetalleYGanancia(
    db,
    filas.map((f) => ({
      ...f,
      anulada: f.anulada === 1,
      total_centavos: numero(f.total_centavos),
      items: numero(f.items),
    })),
  );
  const activas = ventas.filter((v) => !v.anulada);
  return {
    ventas,
    total_centavos: activas.reduce((s, v) => s + v.total_centavos, 0),
    cantidad: activas.length,
    ganancia_total: activas.reduce((s, v) => s + (v.ganancia ?? 0), 0),
    sin_costo: activas.filter((v) => v.ganancia === null).length,
  };
}

// ---------------------------------------------------------------- escrituras

const textoProducto = (valor, campo) => {
  const texto = String(valor ?? '').trim();
  if (!texto) throw new ErrorHttp(400, `Falta el ${campo}.`);
  if (texto.length > 80) throw new ErrorHttp(400, `El ${campo} es demasiado largo (máx. 80).`);
  return texto;
};

const enteroEnRango = (valor, min, max, campo) => {
  if (!Number.isInteger(valor) || valor < min || valor > max) {
    throw new ErrorHttp(400, `El ${campo} está fuera de rango.`);
  }
  return valor;
};

export function crearProducto(db, usuarioId, { nombre, precioCentavos, stock }) {
  if (!obtenerCuenta(db, usuarioId)) throw new ErrorHttp(404, 'Esa cuenta no existe.');
  const limpio = textoProducto(nombre, 'nombre');
  const precio = enteroEnRango(precioCentavos, 0, 100_000_000, 'precio');
  const cantidad = enteroEnRango(stock, -1_000_000, 1_000_000, 'stock');
  const id = randomUUID();
  db.prepare(
    `INSERT INTO productos (usuario_id, id, nombre, precio_centavos, stock_base, activo,
                            actualizado_en, dispositivo_id, rev)
     VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)`,
  ).run(usuarioId, id, limpio, precio, cantidad, Date.now(), DISPOSITIVO_PORTAL,
    siguienteRev(db, usuarioId));
  return id;
}

export function editarProducto(db, usuarioId, productoId, { nombre, precioCentavos, activo }) {
  const existe = db
    .prepare('SELECT 1 AS x FROM productos WHERE usuario_id = ? AND id = ?')
    .get(usuarioId, productoId);
  if (!existe) throw new ErrorHttp(404, 'Ese producto no existe.');
  db.prepare(
    `UPDATE productos
        SET nombre = ?, precio_centavos = ?, activo = ?, actualizado_en = ?,
            dispositivo_id = ?, rev = ?
      WHERE usuario_id = ? AND id = ?`,
  ).run(
    textoProducto(nombre, 'nombre'),
    enteroEnRango(precioCentavos, 0, 100_000_000, 'precio'),
    activo ? 1 : 0,
    Date.now(),
    DISPOSITIVO_PORTAL,
    siguienteRev(db, usuarioId),
    usuarioId,
    productoId,
  );
}

export function reponerStock(db, usuarioId, productoId, cantidad, motivo = 'reposicion') {
  const existe = db
    .prepare('SELECT 1 AS x FROM productos WHERE usuario_id = ? AND id = ?')
    .get(usuarioId, productoId);
  if (!existe) throw new ErrorHttp(404, 'Ese producto no existe.');
  if (!Number.isInteger(cantidad) || cantidad === 0 || Math.abs(cantidad) > 1_000_000) {
    throw new ErrorHttp(400, 'La cantidad tiene que ser distinta de cero.');
  }
  const tipo = MOTIVOS.has(motivo) ? motivo : 'ajuste';
  db.prepare(
    `INSERT INTO movimientos (usuario_id, id, producto_id, cantidad, motivo,
                              creado_en, dispositivo_id, rev)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    usuarioId, randomUUID(), productoId, cantidad, tipo,
    Date.now(), DISPOSITIVO_PORTAL, siguienteRev(db, usuarioId),
  );
}

/** Activa o archiva un producto sin cambiarle nombre ni precio. */
export function cambiarEstadoProducto(db, usuarioId, productoId, activo) {
  const existe = db
    .prepare('SELECT activo FROM productos WHERE usuario_id = ? AND id = ?')
    .get(usuarioId, productoId);
  if (!existe) throw new ErrorHttp(404, 'Ese producto no existe.');
  const nuevo = activo ? 1 : 0;
  if (existe.activo === nuevo) return { activo: nuevo, yaEstaba: true };
  db.prepare(
    `UPDATE productos
        SET activo = ?, actualizado_en = ?, dispositivo_id = ?, rev = ?
      WHERE usuario_id = ? AND id = ?`,
  ).run(nuevo, Date.now(), DISPOSITIVO_PORTAL, siguienteRev(db, usuarioId), usuarioId, productoId);
  return { activo: nuevo, yaEstaba: false };
}

/** Arma el WHERE del inventario; las mismas condiciones sirven para los totales. */
function filtroInventario({ usuarioId, busqueda, soloBajo, incluirArchivados } = {}) {
  const condiciones = [];
  const parametros = [];
  if (usuarioId) {
    condiciones.push('p.usuario_id = ?');
    parametros.push(usuarioId);
  }
  const texto = String(busqueda ?? '').trim();
  if (texto) {
    condiciones.push('p.nombre LIKE ?');
    parametros.push(`%${texto}%`);
  }
  if (soloBajo) condiciones.push('COALESCE(s.stock_actual, p.stock_base) <= 2');
  if (!incluirArchivados) condiciones.push('p.activo = 1');
  return { donde: condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '', parametros };
}

/**
 * Todos los productos de todas las cuentas, con filtros. Es la vista que el
 * padre usa para reponer y archivar sin entrar cuenta por cuenta.
 */
export function inventario(db, filtros = {}) {
  const { donde, parametros } = filtroInventario(filtros);
  const productos = db
    .prepare(
      `SELECT p.usuario_id, p.id, p.nombre, p.precio_centavos, p.activo,
              u.email,
              COALESCE(s.stock_actual, p.stock_base) AS stock_actual
         FROM productos p
         JOIN usuarios u ON u.id = p.usuario_id
         LEFT JOIN vista_stock s
           ON s.usuario_id = p.usuario_id AND s.producto_id = p.id
         ${donde}
        ORDER BY u.email COLLATE NOCASE, p.activo DESC, p.nombre COLLATE NOCASE
        LIMIT 500`,
    )
    .all(...parametros)
    .map((f) => ({
      ...f,
      activo: f.activo === 1,
      precio_centavos: numero(f.precio_centavos),
      stock_actual: numero(f.stock_actual),
    }));

  const totales = db
    .prepare(
      `SELECT COUNT(*) AS productos,
              COALESCE(SUM(t.stock), 0) AS unidades,
              COALESCE(SUM(t.stock * t.precio_centavos), 0) AS valor,
              COALESCE(SUM(CASE WHEN t.stock <= 0 THEN 1 ELSE 0 END), 0) AS agotados
         FROM (SELECT p.precio_centavos,
                      COALESCE(s.stock_actual, p.stock_base) AS stock
                 FROM productos p
                 JOIN usuarios u ON u.id = p.usuario_id
                 LEFT JOIN vista_stock s
                   ON s.usuario_id = p.usuario_id AND s.producto_id = p.id
                 ${donde}) t`,
    )
    .get(...parametros);

  return {
    productos,
    totales: {
      productos: numero(totales.productos),
      unidades: numero(totales.unidades),
      valor: numero(totales.valor),
      agotados: numero(totales.agotados),
    },
  };
}

export function anularVenta(db, usuarioId, ventaId) {
  const venta = db
    .prepare('SELECT anulada FROM ventas WHERE usuario_id = ? AND id = ?')
    .get(usuarioId, ventaId);
  if (!venta) throw new ErrorHttp(404, 'Esa venta no existe.');
  if (venta.anulada === 1) return { anulada: true, yaEstaba: true };
  db.prepare(
    `UPDATE ventas
        SET anulada = 1, actualizado_en = ?, dispositivo_id = ?, rev = ?
      WHERE usuario_id = ? AND id = ?`,
  ).run(Date.now(), DISPOSITIVO_PORTAL, siguienteRev(db, usuarioId), usuarioId, ventaId);
  return { anulada: true, yaEstaba: false };
}

export function crearCuenta(db, { email, clave }) {
  const limpio = normalizarEmail(email);
  if (!emailValido(limpio)) throw new ErrorHttp(400, 'Ingresá un correo válido.');
  validarClave(clave);
  if (db.prepare('SELECT 1 AS x FROM usuarios WHERE email = ?').get(limpio)) {
    throw new ErrorHttp(409, 'Ese correo ya tiene una cuenta.');
  }
  const { hash, salt } = hashClave(clave);
  const id = randomUUID();
  db.prepare(
    'INSERT INTO usuarios (id, email, hash, salt, creado_en) VALUES (?, ?, ?, ?, ?)',
  ).run(id, limpio, hash, salt, new Date().toISOString());
  return { id, email: limpio };
}

export function validarClave(clave) {
  const texto = String(clave ?? '');
  if (texto.length < 6) throw new ErrorHttp(400, 'La contraseña debe tener al menos 6 caracteres.');
  if (texto.length > 200) throw new ErrorHttp(400, 'La contraseña es demasiado larga.');
  return texto;
}

export function cambiarClave(db, usuarioId, clave) {
  if (!obtenerCuenta(db, usuarioId)) throw new ErrorHttp(404, 'Esa cuenta no existe.');
  const texto = validarClave(clave);
  const { hash, salt } = hashClave(texto);
  db.prepare('UPDATE usuarios SET hash = ?, salt = ? WHERE id = ?').run(hash, salt, usuarioId);
  // Cerrar las sesiones abiertas: el teléfono tiene que volver a entrar.
  db.prepare('DELETE FROM sesiones WHERE usuario_id = ?').run(usuarioId);
}

export function borrarCuenta(db, usuarioId) {
  if (!obtenerCuenta(db, usuarioId)) throw new ErrorHttp(404, 'Esa cuenta no existe.');
  db.exec('BEGIN IMMEDIATE');
  try {
    for (const tabla of ['venta_items', 'ventas', 'movimientos', 'productos', 'contadores']) {
      db.prepare(`DELETE FROM ${tabla} WHERE usuario_id = ?`).run(usuarioId);
    }
    db.prepare('DELETE FROM sesiones WHERE usuario_id = ?').run(usuarioId);
    db.prepare('DELETE FROM usuarios WHERE id = ?').run(usuarioId);
    db.exec('COMMIT');
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}

// ------------------------------------------------------- almacén central

/** Clave para reconocer el mismo producto aunque cambien mayúsculas o espacios. */
export function nombreClave(texto) {
  return String(texto ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

export function resumenAlmacen(db) {
  const fila = db
    .prepare(
      `SELECT COUNT(*) AS productos,
              COALESCE(SUM(stock), 0) AS unidades,
              COALESCE(SUM(stock * precio_centavos), 0) AS valor,
              COALESCE(SUM(stock * costo_centavos), 0) AS invertido
         FROM almacen`,
    )
    .get();
  const valor = numero(fila.valor);
  const invertido = numero(fila.invertido);
  return {
    productos: numero(fila.productos),
    unidades: numero(fila.unidades),
    valor,
    invertido,
    ganancia: valor - invertido,
  };
}

/**
 * El almacén con el detalle de dónde está cada producto: qué vendedores lo
 * tienen en su inventario individual y cuántas unidades.
 */
export function listarAlmacen(db) {
  const items = db
    .prepare(
      `SELECT id, nombre, nombre_clave, costo_centavos, precio_centavos, stock, creado_en
         FROM almacen
        ORDER BY nombre COLLATE NOCASE`,
    )
    .all()
    .map((f) => ({
      ...f,
      costo_centavos: numero(f.costo_centavos),
      precio_centavos: numero(f.precio_centavos),
      stock: numero(f.stock),
    }));

  const productos = db
    .prepare(
      `SELECT p.usuario_id, p.id, p.nombre, p.activo, u.email,
              COALESCE(s.stock_actual, p.stock_base) AS stock_actual
         FROM productos p
         JOIN usuarios u ON u.id = p.usuario_id
         LEFT JOIN vista_stock s
           ON s.usuario_id = p.usuario_id AND s.producto_id = p.id
        ORDER BY u.email COLLATE NOCASE`,
    )
    .all();

  const porClave = new Map();
  for (const p of productos) {
    const clave = nombreClave(p.nombre);
    if (!porClave.has(clave)) porClave.set(clave, []);
    porClave.get(clave).push({
      usuario_id: p.usuario_id,
      producto_id: p.id,
      email: p.email,
      stock_actual: numero(p.stock_actual),
      activo: p.activo === 1,
    });
  }

  return items.map((item) => {
    const vendedores = porClave.get(item.nombre_clave) ?? [];
    return {
      ...item,
      margen: item.precio_centavos - item.costo_centavos,
      vendedores,
      total_vendedores: vendedores
        .filter((v) => v.activo)
        .reduce((suma, v) => suma + v.stock_actual, 0),
    };
  });
}

/**
 * Lo que tiene cada vendedor en su teléfono, agrupado por cuenta, con el
 * vínculo al artículo del almacén cuando existe. Es la vista para devolver
 * mercadería al depósito o corregirle el precio.
 */
export function stockPorVendedor(db) {
  const articulos = new Map(
    db
      .prepare('SELECT id, nombre_clave FROM almacen')
      .all()
      .map((a) => [String(a.nombre_clave), a.id]),
  );
  const filas = db
    .prepare(
      `SELECT u.id AS usuario_id, u.email, p.id AS producto_id, p.nombre,
              p.precio_centavos, p.activo,
              COALESCE(s.stock_actual, p.stock_base) AS stock_actual
         FROM productos p
         JOIN usuarios u ON u.id = p.usuario_id
         LEFT JOIN vista_stock s
           ON s.usuario_id = p.usuario_id AND s.producto_id = p.id
        ORDER BY u.email COLLATE NOCASE, p.nombre COLLATE NOCASE`,
    )
    .all();

  const porUsuario = new Map();
  for (const fila of filas) {
    if (!porUsuario.has(fila.usuario_id)) {
      porUsuario.set(fila.usuario_id, {
        id: fila.usuario_id,
        email: fila.email,
        productos: [],
        unidades: 0,
        valor: 0,
      });
    }
    const grupo = porUsuario.get(fila.usuario_id);
    const producto = {
      id: fila.producto_id,
      nombre: fila.nombre,
      precio_centavos: numero(fila.precio_centavos),
      stock_actual: numero(fila.stock_actual),
      activo: fila.activo === 1,
      almacen_id: articulos.get(nombreClave(fila.nombre)) ?? null,
    };
    grupo.productos.push(producto);
    if (producto.activo) {
      grupo.unidades += producto.stock_actual;
      grupo.valor += producto.stock_actual * producto.precio_centavos;
    }
  }
  return [...porUsuario.values()];
}

export function trasladosRecientes(db, limite = 20) {
  return db
    .prepare(
      `SELECT t.id, t.cantidad, t.tipo, t.creado_en, a.nombre AS producto, u.email
         FROM traslados t
         JOIN almacen a ON a.id = t.almacen_id
         JOIN usuarios u ON u.id = t.usuario_id
        ORDER BY t.creado_en DESC
        LIMIT ?`,
    )
    .all(limite)
    .map((f) => ({ ...f, cantidad: numero(f.cantidad), tipo: f.tipo ?? 'envio' }));
}

export function crearArticuloAlmacen(db, { nombre, costoCentavos, precioCentavos, stock }) {
  const limpio = textoProducto(nombre, 'nombre');
  const costo = enteroEnRango(costoCentavos, 0, 100_000_000, 'costo');
  const precio = enteroEnRango(precioCentavos, 0, 100_000_000, 'precio');
  const cantidad = enteroEnRango(stock, 0, 1_000_000, 'stock');
  const clave = nombreClave(limpio);
  if (db.prepare('SELECT 1 AS x FROM almacen WHERE nombre_clave = ?').get(clave)) {
    throw new ErrorHttp(409, `En el almacén ya está "${limpio}".`);
  }
  const id = randomUUID();
  db.prepare(
    `INSERT INTO almacen (id, nombre, nombre_clave, costo_centavos, precio_centavos, stock, creado_en)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).run(id, limpio, clave, costo, precio, cantidad, new Date().toISOString());
  return { id, nombre: limpio };
}

export function ingresarStockAlmacen(db, almacenId, cantidad) {
  const item = db.prepare('SELECT stock FROM almacen WHERE id = ?').get(almacenId);
  if (!item) throw new ErrorHttp(404, 'Ese producto no está en el almacén.');
  if (!Number.isInteger(cantidad) || cantidad === 0 || Math.abs(cantidad) > 1_000_000) {
    throw new ErrorHttp(400, 'La cantidad tiene que ser distinta de cero.');
  }
  if (numero(item.stock) + cantidad < 0) {
    throw new ErrorHttp(400, `En el almacén hay ${numero(item.stock)}.`);
  }
  db.prepare('UPDATE almacen SET stock = stock + ? WHERE id = ?').run(cantidad, almacenId);
  return { stock: numero(item.stock) + cantidad };
}

export function editarArticuloAlmacen(db, almacenId, { nombre, costoCentavos, precioCentavos }) {
  const item = db.prepare('SELECT id FROM almacen WHERE id = ?').get(almacenId);
  if (!item) throw new ErrorHttp(404, 'Ese producto no está en el almacén.');
  const limpio = textoProducto(nombre, 'nombre');
  const clave = nombreClave(limpio);
  const choque = db
    .prepare('SELECT id FROM almacen WHERE nombre_clave = ? AND id <> ?')
    .get(clave, almacenId);
  if (choque) throw new ErrorHttp(409, `Ya hay otro "${limpio}" en el almacén.`);
  db.prepare(
    `UPDATE almacen
        SET nombre = ?, nombre_clave = ?, costo_centavos = ?, precio_centavos = ?
      WHERE id = ?`,
  ).run(
    limpio,
    clave,
    enteroEnRango(costoCentavos, 0, 100_000_000, 'costo'),
    enteroEnRango(precioCentavos, 0, 100_000_000, 'precio'),
    almacenId,
  );
  return { nombre: limpio };
}

/**
 * Quita un producto del almacén. Solo se permite cuando no queda stock: así no
 * desaparece mercadería por accidente. El historial de envíos de ese producto se
 * borra con él.
 */
export function eliminarArticuloAlmacen(db, almacenId) {
  const item = db.prepare('SELECT nombre, stock FROM almacen WHERE id = ?').get(almacenId);
  if (!item) throw new ErrorHttp(404, 'Ese producto no está en el almacén.');
  if (numero(item.stock) > 0) {
    throw new ErrorHttp(
      400,
      `Todavía quedan ${numero(item.stock)} de ${item.nombre}. Dejalo en 0 para quitarlo.`,
    );
  }
  db.prepare('DELETE FROM almacen WHERE id = ?').run(almacenId);
  return { nombre: item.nombre };
}

/**
 * Mueve stock del almacén al inventario de un vendedor.
 *
 * Si el vendedor ya tiene ese producto (mismo nombre, sin importar mayúsculas
 * ni espacios), se le suma una reposición y se reactiva si estaba archivado.
 * Si no lo tiene, se le crea con el precio del almacén. En ambos casos se sube
 * la revisión para que el teléfono lo reciba en la próxima sincronización.
 */
export function trasladarAVendedor(db, almacenId, usuarioId, cantidad) {
  const item = db
    .prepare('SELECT id, nombre, nombre_clave, precio_centavos, stock FROM almacen WHERE id = ?')
    .get(almacenId);
  if (!item) throw new ErrorHttp(404, 'Ese producto no está en el almacén.');
  const cuenta = obtenerCuenta(db, usuarioId);
  if (!cuenta) throw new ErrorHttp(404, 'Esa cuenta no existe.');
  if (!Number.isInteger(cantidad) || cantidad <= 0 || cantidad > 1_000_000) {
    throw new ErrorHttp(400, 'La cantidad tiene que ser mayor que cero.');
  }
  if (cantidad > numero(item.stock)) {
    throw new ErrorHttp(400, `En el almacén quedan ${numero(item.stock)} de ${item.nombre}.`);
  }

  const productos = db
    .prepare('SELECT id, nombre, activo FROM productos WHERE usuario_id = ?')
    .all(usuarioId);
  const existente = productos.find((p) => nombreClave(p.nombre) === item.nombre_clave);

  db.exec('BEGIN IMMEDIATE');
  try {
    let productoId;
    if (existente) {
      productoId = existente.id;
      if (existente.activo !== 1) {
        db.prepare(
          `UPDATE productos
              SET activo = 1, actualizado_en = ?, dispositivo_id = ?, rev = ?
            WHERE usuario_id = ? AND id = ?`,
        ).run(Date.now(), DISPOSITIVO_PORTAL, siguienteRev(db, usuarioId), usuarioId, productoId);
      }
    } else {
      productoId = randomUUID();
      db.prepare(
        `INSERT INTO productos (usuario_id, id, nombre, precio_centavos, stock_base, activo,
                                actualizado_en, dispositivo_id, rev)
         VALUES (?, ?, ?, ?, 0, 1, ?, ?, ?)`,
      ).run(
        usuarioId, productoId, item.nombre, numero(item.precio_centavos),
        Date.now(), DISPOSITIVO_PORTAL, siguienteRev(db, usuarioId),
      );
    }

    db.prepare(
      `INSERT INTO movimientos (usuario_id, id, producto_id, cantidad, motivo,
                                creado_en, dispositivo_id, rev)
       VALUES (?, ?, ?, ?, 'reposicion', ?, ?, ?)`,
    ).run(
      usuarioId, randomUUID(), productoId, cantidad,
      Date.now(), DISPOSITIVO_PORTAL, siguienteRev(db, usuarioId),
    );

    db.prepare('UPDATE almacen SET stock = stock - ? WHERE id = ?').run(cantidad, item.id);
    db.prepare(
      `INSERT INTO traslados (id, almacen_id, usuario_id, producto_id, cantidad, tipo, creado_en)
       VALUES (?, ?, ?, ?, ?, 'envio', ?)`,
    ).run(randomUUID(), item.id, usuarioId, productoId, cantidad, new Date().toISOString());

    db.exec('COMMIT');
    return {
      productoId,
      creado: !existente,
      email: cuenta.email,
      quedan: numero(item.stock) - cantidad,
    };
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}

/**
 * Devuelve mercadería del inventario de un vendedor al almacén.
 *
 * No borra el producto ni la venta: registra un movimiento negativo
 * (`devolucion`) en la cuenta del vendedor, que sube de revisión y le llega al
 * teléfono en la próxima sincronización. En el almacén suma las unidades y
 * registra el traslado de vuelta. Si el producto no estaba en el depósito (por
 * ejemplo, lo creó el vendedor desde el teléfono), se crea con costo 0 y el
 * precio que tenía el vendedor: así la mercadería no queda sin dueño.
 */
export function devolverAlAlmacen(db, usuarioId, productoId, cantidad) {
  const cuenta = obtenerCuenta(db, usuarioId);
  if (!cuenta) throw new ErrorHttp(404, 'Esa cuenta no existe.');
  const producto = db
    .prepare(
      `SELECT p.id, p.nombre, p.activo, p.precio_centavos,
              COALESCE(s.stock_actual, p.stock_base) AS stock_actual
         FROM productos p
         LEFT JOIN vista_stock s
           ON s.usuario_id = p.usuario_id AND s.producto_id = p.id
        WHERE p.usuario_id = ? AND p.id = ?`,
    )
    .get(usuarioId, productoId);
  if (!producto) throw new ErrorHttp(404, 'Ese producto no está en manos del vendedor.');
  if (!Number.isInteger(cantidad) || cantidad <= 0 || cantidad > 1_000_000) {
    throw new ErrorHttp(400, 'La cantidad tiene que ser mayor que cero.');
  }
  const enMano = numero(producto.stock_actual);
  if (cantidad > enMano) {
    throw new ErrorHttp(
      400,
      `${cuenta.email} tiene ${enMano} de ${producto.nombre}. No se pueden devolver ${cantidad}.`,
    );
  }

  const clave = nombreClave(producto.nombre);
  const existente = db
    .prepare('SELECT id, stock FROM almacen WHERE nombre_clave = ?')
    .get(clave);

  db.exec('BEGIN IMMEDIATE');
  try {
    let almacenId = existente?.id;
    if (!almacenId) {
      almacenId = randomUUID();
      db.prepare(
        `INSERT INTO almacen (id, nombre, nombre_clave, costo_centavos, precio_centavos, stock, creado_en)
         VALUES (?, ?, ?, 0, ?, 0, ?)`,
      ).run(
        almacenId,
        String(producto.nombre).trim(),
        clave,
        numero(producto.precio_centavos),
        new Date().toISOString(),
      );
    }

    db.prepare(
      `INSERT INTO movimientos (usuario_id, id, producto_id, cantidad, motivo,
                                creado_en, dispositivo_id, rev)
       VALUES (?, ?, ?, ?, 'devolucion', ?, ?, ?)`,
    ).run(
      usuarioId, randomUUID(), productoId, -cantidad,
      Date.now(), DISPOSITIVO_PORTAL, siguienteRev(db, usuarioId),
    );

    db.prepare('UPDATE almacen SET stock = stock + ? WHERE id = ?').run(cantidad, almacenId);
    db.prepare(
      `INSERT INTO traslados (id, almacen_id, usuario_id, producto_id, cantidad, tipo, creado_en)
       VALUES (?, ?, ?, ?, ?, 'devolucion', ?)`,
    ).run(randomUUID(), almacenId, usuarioId, productoId, cantidad, new Date().toISOString());

    db.exec('COMMIT');
    return {
      email: cuenta.email,
      producto: producto.nombre,
      devueltas: cantidad,
      quedan: enMano - cantidad,
      creado: !existente,
    };
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}

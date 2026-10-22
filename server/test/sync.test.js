import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { abrirBase } from '../src/db.js';
import { crearManejador } from '../src/app.js';

async function arrancar() {
  const db = abrirBase(':memory:');
  const servidor = createServer(crearManejador(db, { log: () => {} }));
  await new Promise((listo) => servidor.listen(0, '127.0.0.1', listo));
  const url = `http://127.0.0.1:${servidor.address().port}`;
  return {
    db,
    url,
    cerrar: () =>
      new Promise((listo) => {
        servidor.close(listo);
        db.close();
      }),
  };
}

async function pedir(url, ruta, { metodo = 'GET', token, cuerpo } = {}) {
  const respuesta = await fetch(`${url}${ruta}`, {
    method: metodo,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  const texto = await respuesta.text();
  return { estado: respuesta.status, datos: texto ? JSON.parse(texto) : null };
}

async function cuenta(url, email = `nene${randomUUID()}@ejemplo.com`) {
  const respuesta = await pedir(url, '/api/registro', {
    metodo: 'POST',
    cuerpo: { email, contrasena: 'dulce123' },
  });
  assert.equal(respuesta.estado, 201);
  return { token: respuesta.datos.token, usuario: respuesta.datos.usuario, email };
}

const producto = (extra = {}) => ({
  id: randomUUID(),
  nombre: 'Chocolate',
  precio_centavos: 500,
  stock_base: 10,
  activo: true,
  actualizado_en: Date.now(),
  dispositivo_id: 'tel-a',
  ...extra,
});

function venta(productoId, cantidad, extra = {}) {
  const ahora = Date.now();
  return {
    id: randomUUID(),
    creado_en: ahora,
    actualizado_en: ahora,
    anulada: false,
    dispositivo_id: 'tel-a',
    items: [
      {
        id: randomUUID(),
        producto_id: productoId,
        nombre: 'Chocolate',
        precio_centavos: 500,
        cantidad,
      },
    ],
    ...extra,
  };
}

const sincronizar = (url, token, cuerpo) =>
  pedir(url, '/api/sync', { metodo: 'POST', token, cuerpo });

test('registro, login y sesión', async (t) => {
  const s = await arrancar();
  t.after(s.cerrar);
  const { email } = await cuenta(s.url);

  const repetido = await pedir(s.url, '/api/registro', {
    metodo: 'POST',
    cuerpo: { email, contrasena: 'dulce123' },
  });
  assert.equal(repetido.estado, 409);

  const malo = await pedir(s.url, '/api/login', {
    metodo: 'POST',
    cuerpo: { email, contrasena: 'otra-clave' },
  });
  assert.equal(malo.estado, 401);

  const bueno = await pedir(s.url, '/api/login', {
    metodo: 'POST',
    cuerpo: { email: email.toUpperCase(), contrasena: 'dulce123' },
  });
  assert.equal(bueno.estado, 200);
  assert.ok(bueno.datos.token);

  const perfil = await pedir(s.url, '/api/sesion', { token: bueno.datos.token });
  assert.equal(perfil.estado, 200);
  assert.equal(perfil.datos.usuario.email, email);

  assert.equal((await pedir(s.url, '/api/sesion', { token: 'inventado' })).estado, 401);
});

test('venta offline se sube una sola vez y descuenta stock', async (t) => {
  const s = await arrancar();
  t.after(s.cerrar);
  const { token } = await cuenta(s.url);
  const p = producto({ stock_base: 10 });
  const v = venta(p.id, 2);

  const subida = await sincronizar(s.url, token, {
    dispositivo_id: 'tel-a',
    ultima_rev: 0,
    cambios: { productos: [p], ventas: [v], movimientos: [] },
  });
  assert.equal(subida.estado, 200, JSON.stringify(subida.datos));
  assert.equal(subida.datos.aplicados.productos, 1);
  assert.equal(subida.datos.aplicados.ventas, 1);
  assert.equal(subida.datos.cambios.ventas[0].total_centavos, 1000);

  const rev = subida.datos.ultima_rev;
  assert.ok(rev > 0);

  // Reintento (el teléfono no supo si llegó): no duplica nada.
  const reintento = await sincronizar(s.url, token, {
    dispositivo_id: 'tel-a',
    ultima_rev: rev,
    cambios: { productos: [p], ventas: [v] },
  });
  assert.equal(reintento.estado, 200);
  assert.equal(reintento.datos.aplicados.ventas, 0);
  assert.equal(reintento.datos.aplicados.productos, 0);

  const inventario = await pedir(s.url, '/api/inventario', { token });
  assert.equal(inventario.datos.productos[0].stock_actual, 8);

  const resumen = await pedir(s.url, '/api/ventas', { token });
  assert.equal(resumen.datos.cantidad, 1);
  assert.equal(resumen.datos.total_centavos, 1000);

  // Pull incremental: nada nuevo.
  const quieto = await sincronizar(s.url, token, {
    dispositivo_id: 'tel-a',
    ultima_rev: reintento.datos.ultima_rev,
    cambios: {},
  });
  assert.equal(quieto.datos.cambios.ventas.length, 0);
  assert.equal(quieto.datos.cambios.productos.length, 0);
});

test('dos teléfonos vendiendo sin conexión no se pisan el stock ni la plata', async (t) => {
  const s = await arrancar();
  t.after(s.cerrar);
  const { token } = await cuenta(s.url);
  const p = producto({ stock_base: 10 });

  const base = await sincronizar(s.url, token, {
    dispositivo_id: 'tel-a',
    ultima_rev: 0,
    cambios: { productos: [p] },
  });

  const ventaA = venta(p.id, 1, { dispositivo_id: 'tel-a' });
  const ventaB = venta(p.id, 3, { dispositivo_id: 'tel-b' });

  await sincronizar(s.url, token, {
    dispositivo_id: 'tel-b',
    ultima_rev: base.datos.ultima_rev,
    cambios: { ventas: [ventaB] },
  });
  await sincronizar(s.url, token, {
    dispositivo_id: 'tel-a',
    ultima_rev: base.datos.ultima_rev,
    cambios: { ventas: [ventaA] },
  });

  const inventario = await pedir(s.url, '/api/inventario', { token });
  assert.equal(inventario.datos.productos[0].stock_actual, 6);

  const resumen = await pedir(s.url, '/api/ventas', { token });
  assert.equal(resumen.datos.cantidad, 2);
  assert.equal(resumen.datos.total_centavos, 2000);
});

test('el último cambio de producto gana y el perdedor recibe aviso', async (t) => {
  const s = await arrancar();
  t.after(s.cerrar);
  const { token } = await cuenta(s.url);
  const p = producto({ actualizado_en: 1_700_000_000_000 });
  await sincronizar(s.url, token, { dispositivo_id: 'tel-a', cambios: { productos: [p] } });

  const viejo = { ...p, nombre: 'Chocolate viejo', actualizado_en: 1_600_000_000_000 };
  const r1 = await sincronizar(s.url, token, {
    dispositivo_id: 'tel-b',
    cambios: { productos: [viejo] },
  });
  assert.equal(r1.datos.aplicados.productos, 0);
  assert.equal(r1.datos.conflictos[0].resolucion, 'servidor');

  const nuevo = { ...p, nombre: 'Chocolate grande', actualizado_en: 1_800_000_000_000 };
  const r2 = await sincronizar(s.url, token, {
    dispositivo_id: 'tel-b',
    cambios: { productos: [nuevo] },
  });
  assert.equal(r2.datos.aplicados.productos, 1);
  assert.equal(r2.datos.conflictos[0].resolucion, 'cliente');

  const inventario = await pedir(s.url, '/api/inventario', { token });
  assert.equal(inventario.datos.productos[0].nombre, 'Chocolate grande');

  // El teléfono que quedó atrás recibe el nombre nuevo al pedir cambios.
  const pull = await sincronizar(s.url, token, { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: {} });
  assert.equal(pull.datos.cambios.productos[0].nombre, 'Chocolate grande');
});

test('anular una venta devuelve el stock y no borra el historial', async (t) => {
  const s = await arrancar();
  t.after(s.cerrar);
  const { token } = await cuenta(s.url);
  const p = producto({ stock_base: 5 });
  const v = venta(p.id, 2);
  await sincronizar(s.url, token, { dispositivo_id: 'tel-a', cambios: { productos: [p], ventas: [v] } });

  const anulada = { ...v, anulada: true, actualizado_en: Date.now() + 1000, dispositivo_id: 'tel-b' };
  const r = await sincronizar(s.url, token, {
    dispositivo_id: 'tel-b',
    cambios: { ventas: [anulada] },
  });
  assert.equal(r.datos.aplicados.ventas, 1);

  const inventario = await pedir(s.url, '/api/inventario', { token });
  assert.equal(inventario.datos.productos[0].stock_actual, 5);

  const resumen = await pedir(s.url, '/api/ventas', { token });
  assert.equal(resumen.datos.cantidad, 0);
  assert.equal(resumen.datos.total_centavos, 0);
  assert.equal(resumen.datos.ventas.length, 1);
  assert.equal(resumen.datos.ventas[0].anulada, true);
});

test('ajustes de stock se suman y son idempotentes', async (t) => {
  const s = await arrancar();
  t.after(s.cerrar);
  const { token } = await cuenta(s.url);
  const p = producto({ stock_base: 2 });
  await sincronizar(s.url, token, { dispositivo_id: 'tel-a', cambios: { productos: [p] } });

  const ajuste = {
    id: randomUUID(),
    producto_id: p.id,
    cantidad: 24,
    motivo: 'reposicion',
    creado_en: Date.now(),
    dispositivo_id: 'tel-a',
  };
  const r1 = await sincronizar(s.url, token, { dispositivo_id: 'tel-a', cambios: { movimientos: [ajuste] } });
  assert.equal(r1.datos.aplicados.movimientos, 1);
  const r2 = await sincronizar(s.url, token, { dispositivo_id: 'tel-a', cambios: { movimientos: [ajuste] } });
  assert.equal(r2.datos.aplicados.movimientos, 0);

  const inventario = await pedir(s.url, '/api/inventario', { token });
  assert.equal(inventario.datos.productos[0].stock_actual, 26);
});

test('datos inválidos se rechazan y cada cuenta ve solo lo suyo', async (t) => {
  const s = await arrancar();
  t.after(s.cerrar);
  const a = await cuenta(s.url);
  const b = await cuenta(s.url);

  const r = await sincronizar(s.url, a.token, {
    dispositivo_id: 'tel-a',
    cambios: { ventas: [{ ...venta('x', 1), items: [] }] },
  });
  assert.equal(r.estado, 200);
  assert.equal(r.datos.rechazados.length, 1);
  assert.match(r.datos.rechazados[0].motivo, /ítems/);

  await sincronizar(s.url, a.token, {
    dispositivo_id: 'tel-a',
    cambios: { productos: [producto()] },
  });

  const deB = await sincronizar(s.url, b.token, { dispositivo_id: 'tel-b', cambios: {} });
  assert.equal(deB.datos.cambios.productos.length, 0);
  assert.equal(deB.datos.ultima_rev, 0);

  assert.equal((await pedir(s.url, '/api/inventario')).estado, 401);
});

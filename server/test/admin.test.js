import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { abrirBase } from '../src/db.js';
import { crearManejador } from '../src/app.js';

const CLAVE_ADMIN = 'clave-del-padre';

async function arrancar({ adminClave = CLAVE_ADMIN } = {}) {
  const db = abrirBase(':memory:');
  const servidor = createServer(crearManejador(db, { log: () => {}, adminClave }));
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

async function api(url, ruta, { metodo = 'GET', token, cuerpo } = {}) {
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

async function entrarAlPortal(url, clave = CLAVE_ADMIN) {
  const respuesta = await fetch(`${url}/admin/entrar`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ clave }),
    redirect: 'manual',
  });
  return respuesta;
}

async function sesionAdmin(url) {
  const respuesta = await entrarAlPortal(url);
  assert.equal(respuesta.status, 303, 'con la clave correcta tiene que redirigir');
  const galletas = respuesta.headers.getSetCookie();
  assert.equal(galletas.length, 1);
  assert.match(galletas[0], /HttpOnly/);
  assert.match(galletas[0], /SameSite=Lax/);
  return galletas[0].split(';')[0];
}

async function pagina(url, ruta, cookie) {
  const respuesta = await fetch(`${url}${ruta}`, {
    headers: cookie ? { cookie } : {},
    redirect: 'manual',
  });
  const texto = await respuesta.text();
  return { estado: respuesta.status, texto, ubicacion: respuesta.headers.get('location') };
}

function csrfDe(texto) {
  const encontrado = /name="csrf" value="([^"]+)"/.exec(texto);
  assert.ok(encontrado, 'la página tiene que traer un token CSRF');
  return encontrado[1];
}

/** Descarga binaria (PDF): no se puede leer como texto. */
async function descarga(url, ruta, cookie) {
  const respuesta = await fetch(`${url}${ruta}`, {
    headers: cookie ? { cookie } : {},
    redirect: 'manual',
  });
  return {
    estado: respuesta.status,
    tipo: respuesta.headers.get('content-type') ?? '',
    contenido: Buffer.from(await respuesta.arrayBuffer()),
  };
}

async function enviarFormulario(url, ruta, cookie, csrf, campos) {
  return fetch(`${url}${ruta}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      cookie,
    },
    body: new URLSearchParams({ csrf, ...campos }),
    redirect: 'manual',
  });
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

test('sin LIZNACK_ADMIN el portal queda apagado y lo explica', async () => {
  const s = await arrancar({ adminClave: '' });
  try {
    const respuesta = await fetch(`${s.url}/admin`);
    assert.equal(respuesta.status, 200);
    const texto = await respuesta.text();
    assert.match(texto, /Portal desactivado/);
    assert.match(texto, /LIZNACK_ADMIN/);
    // La API sigue funcionando como siempre.
    const salud = await api(s.url, '/api/salud');
    assert.equal(salud.estado, 200);
  } finally {
    await s.cerrar();
  }
});

test('sin sesión no se ve ningún dato y la clave incorrecta no entra', async () => {
  const s = await arrancar();
  try {
    const ingreso = await pagina(s.url, '/admin/cuentas');
    assert.equal(ingreso.estado, 200);
    assert.match(ingreso.texto, /type="password"/);
    assert.doesNotMatch(ingreso.texto, /Todas las cuentas/);

    const mal = await entrarAlPortal(s.url, 'no-es-la-clave');
    assert.equal(mal.status, 401);
    assert.equal(mal.headers.getSetCookie().length, 0);
    assert.match(await mal.text(), /Contraseña incorrecta/);

    // La raíz, pedida por un navegador, lleva al portal.
    const raiz = await fetch(`${s.url}/`, { headers: { accept: 'text/html' }, redirect: 'manual' });
    assert.equal(raiz.status, 303);
    assert.equal(raiz.headers.get('location'), '/admin');
  } finally {
    await s.cerrar();
  }
});

test('un formulario sin token CSRF se rechaza', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const respuesta = await enviarFormulario(s.url, '/admin/cuentas', cookie, 'token-falso', {
      email: 'intruso@ejemplo.com',
      clave: 'dulce123',
    });
    assert.equal(respuesta.status, 400);
    assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM usuarios').get().n, 0);
  } finally {
    await s.cerrar();
  }
});

test('el padre crea una cuenta y el hijo puede entrar desde la app', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const panel = await pagina(s.url, '/admin/cuentas', cookie);
    assert.equal(panel.estado, 200);
    assert.match(panel.texto, /Nueva cuenta/);
    const csrf = csrfDe(panel.texto);

    const email = `hijo${randomUUID().slice(0, 8)}@ejemplo.com`;
    const alta = await enviarFormulario(s.url, '/admin/cuentas', cookie, csrf, {
      email,
      clave: 'dulce123',
    });
    assert.equal(alta.status, 303);
    assert.match(alta.headers.get('location'), /^\/admin\/cuenta\//);

    const fila = s.db.prepare('SELECT id FROM usuarios WHERE email = ?').get(email);
    assert.ok(fila);

    // La cuenta recién creada entra por la API igual que cualquier otra.
    const ingresoApp = await api(s.url, '/api/login', {
      metodo: 'POST',
      cuerpo: { email, contrasena: 'dulce123' },
    });
    assert.equal(ingresoApp.estado, 200);
    assert.ok(ingresoApp.datos.token);

    const detalle = await pagina(s.url, `/admin/cuenta/${fila.id}`, cookie);
    assert.equal(detalle.estado, 200);
    assert.match(detalle.texto, new RegExp(email.replace('.', '\\.')));
  } finally {
    await s.cerrar();
  }
});

test('lo que carga el padre llega al teléfono por sincronización', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const alta = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `nene${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const token = alta.datos.token;
    const usuarioId = alta.datos.usuario.id;

    const panel = await pagina(s.url, `/admin/cuenta/${usuarioId}`, cookie);
    const csrf = csrfDe(panel.texto);

    // 1. Producto nuevo con stock 7 a $12,50.
    const creado = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto`,
      cookie,
      csrf,
      { nombre: 'Gomitas', precio: '12,50', stock: '7' },
    );
    assert.equal(creado.status, 303);
    assert.doesNotMatch(creado.headers.get('location'), /error=/);

    const inventario = await api(s.url, '/api/inventario', { token });
    const gomitas = inventario.datos.productos.find((p) => p.nombre === 'Gomitas');
    assert.ok(gomitas, 'el producto tiene que estar en el servidor');
    assert.equal(gomitas.precio_centavos, 1250);
    assert.equal(gomitas.stock_actual, 7);
    assert.equal(gomitas.activo, true);

    // 2. El teléfono lo baja en la próxima sincronización.
    const bajada = await api(s.url, '/api/sync', {
      metodo: 'POST',
      token,
      cuerpo: { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: {} },
    });
    assert.equal(bajada.estado, 200);
    const remoto = bajada.datos.cambios.productos.find((p) => p.id === gomitas.id);
    assert.ok(remoto, 'el teléfono tiene que recibir el producto');

    // 3. Reponer 5 y editar el precio.
    const reponer = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${gomitas.id}/reponer`,
      cookie,
      csrf,
      { cantidad: '5' },
    );
    assert.equal(reponer.status, 303);

    const editar = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${gomitas.id}`,
      cookie,
      csrf,
      { nombre: 'Gomitas de osito', precio: '15,00', activo: '1' },
    );
    assert.equal(editar.status, 303);

    const despues = await api(s.url, '/api/inventario', { token });
    const actualizado = despues.datos.productos.find((p) => p.id === gomitas.id);
    assert.equal(actualizado.nombre, 'Gomitas de osito');
    assert.equal(actualizado.precio_centavos, 1500);
    assert.equal(actualizado.stock_actual, 12);

    // 4. Archivar: deja de venderse.
    await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${gomitas.id}`,
      cookie,
      csrf,
      { nombre: 'Gomitas de osito', precio: '15,00' },
    );
    const archivado = await api(s.url, '/api/inventario', { token });
    assert.equal(archivado.datos.productos.find((p) => p.id === gomitas.id).activo, false);

    // 5. El padre ve el producto archivado en el detalle de la cuenta.
    const detalle = await pagina(s.url, `/admin/cuenta/${usuarioId}`, cookie);
    assert.match(detalle.texto, /Gomitas de osito/);
    assert.match(detalle.texto, /archivado/);
    assert.match(detalle.texto, /Reposiciones y ajustes/);
    assert.match(detalle.texto, /\+5/);
  } finally {
    await s.cerrar();
  }
});

test('el padre anula una venta y el stock vuelve en el servidor', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const alta = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `nene${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const token = alta.datos.token;
    const usuarioId = alta.datos.usuario.id;

    const p = producto({ dispositivo_id: 'tel-a' });
    const ventaId = randomUUID();
    const sincronizado = await api(s.url, '/api/sync', {
      metodo: 'POST',
      token,
      cuerpo: {
        dispositivo_id: 'tel-a',
        ultima_rev: 0,
        cambios: {
          productos: [p],
          ventas: [{
            id: ventaId,
            creado_en: Date.now(),
            total_centavos: 1000,
            anulada: false,
            actualizado_en: Date.now(),
            dispositivo_id: 'tel-a',
            items: [{ id: randomUUID(), producto_id: p.id, nombre: p.nombre, precio_centavos: 500, cantidad: 2 }],
          }],
        },
      },
    });
    assert.equal(sincronizado.estado, 200);

    const antes = await api(s.url, '/api/inventario', { token });
    assert.equal(antes.datos.productos[0].stock_actual, 8);

    const panel = await pagina(s.url, `/admin/cuenta/${usuarioId}`, cookie);
    assert.match(panel.texto, /cobrada/);
    const csrf = csrfDe(panel.texto);

    const anulada = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/venta/${ventaId}/anular`,
      cookie,
      csrf,
      {},
    );
    assert.equal(anulada.status, 303);

    const despues = await api(s.url, '/api/inventario', { token });
    assert.equal(despues.datos.productos[0].stock_actual, 10);

    const bajada = await api(s.url, '/api/sync', {
      metodo: 'POST',
      token,
      cuerpo: { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: {} },
    });
    const venta = bajada.datos.cambios.ventas.find((v) => v.id === ventaId);
    assert.equal(venta.anulada, true, 'el teléfono tiene que enterarse de la anulación');

    // Anular dos veces no rompe nada.
    const otraVez = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/venta/${ventaId}/anular`,
      cookie,
      csrf,
      {},
    );
    assert.match(otraVez.headers.get('location'), /ok=/);
  } finally {
    await s.cerrar();
  }
});

test('cambiar la contraseña cierra las sesiones del teléfono', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const alta = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `nene${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const usuarioId = alta.datos.usuario.id;
    const tokenViejo = alta.datos.token;

    const panel = await pagina(s.url, `/admin/cuenta/${usuarioId}`, cookie);
    const csrf = csrfDe(panel.texto);
    const cambio = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/clave`,
      cookie,
      csrf,
      { clave: 'clave-nueva-1' },
    );
    assert.equal(cambio.status, 303);

    const sesion = await api(s.url, '/api/sesion', { token: tokenViejo });
    assert.equal(sesion.estado, 401, 'el token viejo tiene que quedar inválido');

    const email = s.db.prepare('SELECT email FROM usuarios WHERE id = ?').get(usuarioId).email;
    const conNueva = await api(s.url, '/api/login', {
      metodo: 'POST',
      cuerpo: { email, contrasena: 'clave-nueva-1' },
    });
    assert.equal(conNueva.estado, 200);
    const conVieja = await api(s.url, '/api/login', {
      metodo: 'POST',
      cuerpo: { email, contrasena: 'dulce123' },
    });
    assert.equal(conVieja.estado, 401);
  } finally {
    await s.cerrar();
  }
});

test('borrar una cuenta exige confirmar el correo y borra todos sus datos', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const alta = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `nene${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const token = alta.datos.token;
    const usuarioId = alta.datos.usuario.id;

    const p = producto();
    await api(s.url, '/api/sync', {
      metodo: 'POST',
      token,
      cuerpo: { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: { productos: [p] } },
    });

    const panel = await pagina(s.url, `/admin/cuenta/${usuarioId}`, cookie);
    const csrf = csrfDe(panel.texto);

    const mal = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/borrar`,
      cookie,
      csrf,
      { confirmacion: 'otra-cosa' },
    );
    assert.equal(mal.status, 303);
    assert.match(mal.headers.get('location'), /error=/);
    assert.ok(s.db.prepare('SELECT 1 AS x FROM usuarios WHERE id = ?').get(usuarioId));

    const email = s.db.prepare('SELECT email FROM usuarios WHERE id = ?').get(usuarioId).email;
    const bien = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/borrar`,
      cookie,
      csrf,
      { confirmacion: email },
    );
    assert.equal(bien.status, 303);
    assert.match(bien.headers.get('location'), /^\/admin\/cuentas\?ok=/);

    assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM usuarios').get().n, 0);
    assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM productos').get().n, 0);
    assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM sesiones').get().n, 0);

    const sesion = await api(s.url, '/api/sesion', { token });
    assert.equal(sesion.estado, 401);
  } finally {
    await s.cerrar();
  }
});

test('el portal se cierra con el botón Salir', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const panel = await pagina(s.url, '/admin', cookie);
    assert.match(panel.texto, /Resumen/);
    const csrf = csrfDe(panel.texto);

    const salida = await enviarFormulario(s.url, '/admin/salir', cookie, csrf, {});
    assert.equal(salida.status, 303);
    assert.match(salida.headers.getSetCookie()[0], /Max-Age=0/);

    const despues = await pagina(s.url, '/admin', salida.headers.getSetCookie()[0].split(';')[0]);
    assert.match(despues.texto, /type="password"/);
  } finally {
    await s.cerrar();
  }
});

test('el inventario junta los productos de todas las cuentas y filtra', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const ana = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `ana${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const tomi = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `tomi${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });

    await api(s.url, '/api/sync', {
      metodo: 'POST',
      token: ana.datos.token,
      cuerpo: {
        dispositivo_id: 'tel-a',
        ultima_rev: 0,
        cambios: {
          productos: [
            producto({ nombre: 'Chocolate', stock_base: 10 }),
            producto({ nombre: 'Gomitas', stock_base: 1 }),
          ],
        },
      },
    });
    await api(s.url, '/api/sync', {
      metodo: 'POST',
      token: tomi.datos.token,
      cuerpo: {
        dispositivo_id: 'tel-b',
        ultima_rev: 0,
        cambios: { productos: [producto({ nombre: 'Alfajor', stock_base: 0 })] },
      },
    });

    const todo = await pagina(s.url, '/admin/inventario', cookie);
    assert.equal(todo.estado, 200);
    assert.match(todo.texto, /<h1>Inventario<\/h1>/);
    for (const nombre of ['Chocolate', 'Gomitas', 'Alfajor']) {
      assert.match(todo.texto, new RegExp(`${nombre}</td>`), `falta ${nombre}`);
    }
    assert.match(todo.texto, /Valor del stock/);

    // Por cuenta.
    const porCuenta = await pagina(s.url, `/admin/inventario?cuenta=${ana.datos.usuario.id}`, cookie);
    assert.match(porCuenta.texto, /Chocolate<\/td>/);
    assert.match(porCuenta.texto, /Gomitas<\/td>/);
    assert.doesNotMatch(porCuenta.texto, /Alfajor<\/td>/);

    // Por nombre.
    const buscado = await pagina(s.url, '/admin/inventario?buscar=gom', cookie);
    assert.match(buscado.texto, /Gomitas<\/td>/);
    assert.doesNotMatch(buscado.texto, /Chocolate<\/td>/);
    assert.doesNotMatch(buscado.texto, /Alfajor<\/td>/);

    // Solo los que están por agotarse (Alfajor 0, Gomitas 1).
    const bajo = await pagina(s.url, '/admin/inventario?solo_bajo=1', cookie);
    assert.match(bajo.texto, /Gomitas<\/td>/);
    assert.match(bajo.texto, /Alfajor<\/td>/);
    assert.doesNotMatch(bajo.texto, /Chocolate<\/td>/);
  } finally {
    await s.cerrar();
  }
});

test('desde el inventario se repone, se archiva y se vuelve a la misma lista', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const alta = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `nene${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const token = alta.datos.token;
    const usuarioId = alta.datos.usuario.id;

    const p = producto({ nombre: 'Chupetín', stock_base: 4 });
    await api(s.url, '/api/sync', {
      metodo: 'POST',
      token,
      cuerpo: { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: { productos: [p] } },
    });

    const panel = await pagina(s.url, '/admin/inventario', cookie);
    const csrf = csrfDe(panel.texto);
    const volver = '/admin/inventario?buscar=Chup';

    // Reponer vuelve a la lista con el filtro puesto.
    const repuesto = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${p.id}/reponer`,
      cookie,
      csrf,
      { cantidad: '6', volver },
    );
    assert.equal(repuesto.status, 303);
    assert.match(repuesto.headers.get('location'), /^\/admin\/inventario\?buscar=Chup&ok=Stock/);

    let inventario = await api(s.url, '/api/inventario', { token });
    assert.equal(inventario.datos.productos[0].stock_actual, 10);

    // Archivar desde el inventario.
    const archivado = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${p.id}/estado`,
      cookie,
      csrf,
      { activo: '0', volver },
    );
    assert.equal(archivado.status, 303);
    inventario = await api(s.url, '/api/inventario', { token });
    assert.equal(inventario.datos.productos[0].activo, false, 'el teléfono tiene que verlo archivado');

    // Y reactivarlo.
    await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${p.id}/estado`,
      cookie,
      csrf,
      { activo: '1', volver },
    );
    inventario = await api(s.url, '/api/inventario', { token });
    assert.equal(inventario.datos.productos[0].activo, true);

    // Alta desde el inventario, eligiendo la cuenta.
    const nuevo = await enviarFormulario(s.url, '/admin/inventario/producto', cookie, csrf, {
      cuenta: usuarioId,
      nombre: 'Maní',
      precio: '3,50',
      stock: '9',
      volver,
    });
    assert.equal(nuevo.status, 303);
    inventario = await api(s.url, '/api/inventario', { token });
    const mani = inventario.datos.productos.find((x) => x.nombre === 'Maní');
    assert.ok(mani);
    assert.equal(mani.precio_centavos, 350);
    assert.equal(mani.stock_actual, 9);

    // Un `volver` que apunta afuera del portal se ignora.
    const sospechoso = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${p.id}/reponer`,
      cookie,
      csrf,
      { cantidad: '1', volver: 'https://ejemplo-externo.com/robo' },
    );
    assert.equal(sospechoso.status, 303);
    assert.match(sospechoso.headers.get('location'), /^\/admin\/cuenta\//);
    assert.doesNotMatch(sospechoso.headers.get('location'), /ejemplo-externo/);
  } finally {
    await s.cerrar();
  }
});

test('el almacén reparte stock a los vendedores y muestra dónde está cada producto', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const ana = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `ana${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const tomi = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `tomi${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const stockAlmacen = () => Number(s.db.prepare('SELECT stock FROM almacen').get()?.stock ?? 0);

    const panel = await pagina(s.url, '/admin/almacen', cookie);
    assert.equal(panel.estado, 200);
    assert.match(panel.texto, /<h1>Almacén<\/h1>/);
    const csrf = csrfDe(panel.texto);

    // 1. Cargar el depósito: 10 unidades a $5,00 que costaron $3,00.
    const alta = await enviarFormulario(s.url, '/admin/almacen', cookie, csrf, {
      nombre: 'Chocolate',
      costo: '3,00',
      precio: '5,00',
      stock: '10',
      volver: '/admin/almacen',
    });
    assert.equal(alta.status, 303);
    assert.doesNotMatch(alta.headers.get('location'), /error=/);
    const articuloId = s.db.prepare('SELECT id FROM almacen').get().id;

    // El costo de compra se ve en el portal, junto con la ganancia por unidad.
    const sinDueño = await pagina(s.url, '/admin/almacen', cookie);
    assert.match(sinDueño.texto, /Compra → venta/);
    assert.match(sinDueño.texto, /\$ 3,00 → \$ 5,00/);
    assert.match(sinDueño.texto, /\+\$ 2,00 · 40%/);
    assert.match(sinDueño.texto, /Invertido/);
    assert.match(sinDueño.texto, /nadie todavía/);

    // 2. Ingresar mercadería nueva.
    const ingreso = await enviarFormulario(
      s.url,
      `/admin/almacen/${articuloId}/ingresar`,
      cookie,
      csrf,
      { cantidad: '5', volver: '/admin/almacen' },
    );
    assert.equal(ingreso.status, 303);
    assert.equal(stockAlmacen(), 15);

    // 3. Enviar 4 a Ana: le crea el producto con el precio del almacén.
    const envio = await enviarFormulario(
      s.url,
      `/admin/almacen/${articuloId}/enviar`,
      cookie,
      csrf,
      { cuenta: ana.datos.usuario.id, cantidad: '4', volver: '/admin/almacen' },
    );
    assert.equal(envio.status, 303);
    assert.match(decodeURIComponent(envio.headers.get('location')), /Enviado a .*le creamos el producto/);
    assert.equal(stockAlmacen(), 11);

    let invAna = await api(s.url, '/api/inventario', { token: ana.datos.token });
    let chocolates = invAna.datos.productos.filter((p) => p.nombre === 'Chocolate');
    assert.equal(chocolates.length, 1, 'no se duplica el producto');
    assert.equal(chocolates[0].stock_actual, 4);
    assert.equal(chocolates[0].precio_centavos, 500);
    assert.equal(chocolates[0].activo, true);

    // 4. El almacén dice en qué vendedor está.
    const conVendedor = await pagina(s.url, '/admin/almacen', cookie);
    assert.ok(conVendedor.texto.includes(ana.datos.usuario.email), 'tiene que nombrar al vendedor');
    assert.match(conVendedor.texto, /· 4</);
    assert.doesNotMatch(conVendedor.texto, /nadie todavía/);
    assert.match(conVendedor.texto, /Últimos movimientos/);
    assert.match(conVendedor.texto, /En manos de los vendedores/);
    assert.match(conVendedor.texto, /Devolver/);

    // 5. Segundo envío al mismo vendedor: suma, no duplica.
    await enviarFormulario(s.url, `/admin/almacen/${articuloId}/enviar`, cookie, csrf, {
      cuenta: ana.datos.usuario.id,
      cantidad: '2',
      volver: '/admin/almacen',
    });
    invAna = await api(s.url, '/api/inventario', { token: ana.datos.token });
    chocolates = invAna.datos.productos.filter((p) => p.nombre === 'Chocolate');
    assert.equal(chocolates.length, 1);
    assert.equal(chocolates[0].stock_actual, 6);

    // 6. A otro vendedor le crea su propio producto.
    await enviarFormulario(s.url, `/admin/almacen/${articuloId}/enviar`, cookie, csrf, {
      cuenta: tomi.datos.usuario.id,
      cantidad: '3',
      volver: '/admin/almacen',
    });
    const invTomi = await api(s.url, '/api/inventario', { token: tomi.datos.token });
    assert.equal(invTomi.datos.productos.find((p) => p.nombre === 'Chocolate').stock_actual, 3);
    assert.equal(stockAlmacen(), 6);

    // 7. Y el teléfono lo baja por sincronización (revisión nueva).
    const bajada = await api(s.url, '/api/sync', {
      metodo: 'POST',
      token: tomi.datos.token,
      cuerpo: { dispositivo_id: 'tel-b', ultima_rev: 0, cambios: {} },
    });
    assert.ok(bajada.datos.cambios.productos.find((p) => p.nombre === 'Chocolate'));

    // 8. No se puede enviar más de lo que hay.
    const exceso = await enviarFormulario(
      s.url,
      `/admin/almacen/${articuloId}/enviar`,
      cookie,
      csrf,
      { cuenta: ana.datos.usuario.id, cantidad: '999', volver: '/admin/almacen' },
    );
    assert.match(exceso.headers.get('location'), /error=/);
    assert.equal(stockAlmacen(), 6, 'el stock no se toca si falla');

    // 9. Un producto archivado se reactiva al recibir stock.
    const productoAna = s.db
      .prepare('SELECT id FROM productos WHERE usuario_id = ?')
      .get(ana.datos.usuario.id).id;
    await enviarFormulario(
      s.url,
      `/admin/cuenta/${ana.datos.usuario.id}/producto/${productoAna}/estado`,
      cookie,
      csrf,
      { activo: '0', volver: '/admin/almacen' },
    );
    await enviarFormulario(s.url, `/admin/almacen/${articuloId}/enviar`, cookie, csrf, {
      cuenta: ana.datos.usuario.id,
      cantidad: '1',
      volver: '/admin/almacen',
    });
    invAna = await api(s.url, '/api/inventario', { token: ana.datos.token });
    const reactivado = invAna.datos.productos.find((p) => p.nombre === 'Chocolate');
    assert.equal(reactivado.activo, true, 'al enviarle stock vuelve a estar activo');
    assert.equal(reactivado.stock_actual, 7);

    // 10. El almacén no acepta dos veces el mismo producto.
    const repetido = await enviarFormulario(s.url, '/admin/almacen', cookie, csrf, {
      nombre: '  CHOCOLATE ',
      costo: '3,00',
      precio: '5,00',
      stock: '1',
      volver: '/admin/almacen',
    });
    assert.match(repetido.headers.get('location'), /error=/);
    assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM almacen').get().n, 1);

    // 11. Quitar: no deja mientras haya stock; con 0 se va y borra su historial.
    const conStock = await enviarFormulario(
      s.url,
      `/admin/almacen/${articuloId}/quitar`,
      cookie,
      csrf,
      { volver: '/admin/almacen' },
    );
    assert.match(conStock.headers.get('location'), /error=/);
    assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM almacen').get().n, 1);

    await enviarFormulario(s.url, `/admin/almacen/${articuloId}/ingresar`, cookie, csrf, {
      cantidad: '-5',
      volver: '/admin/almacen',
    });
    assert.equal(stockAlmacen(), 0);

    const quitado = await enviarFormulario(
      s.url,
      `/admin/almacen/${articuloId}/quitar`,
      cookie,
      csrf,
      { volver: '/admin/almacen' },
    );
    assert.equal(quitado.status, 303);
    assert.doesNotMatch(quitado.headers.get('location'), /error=/);
    assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM almacen').get().n, 0);
    assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM traslados').get().n, 0);
  } finally {
    await s.cerrar();
  }
});

test('el portal muestra qué se vendió y la ganancia de cada venta', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const alta = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `nene${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const token = alta.datos.token;

    // En el almacén el chocolate costó $3,00 y se vende a $5,00.
    const panel = await pagina(s.url, '/admin/almacen', cookie);
    const csrf = csrfDe(panel.texto);
    const creado = await enviarFormulario(s.url, '/admin/almacen', cookie, csrf, {
      nombre: 'Chocolate',
      costo: '3,00',
      precio: '5,00',
      stock: '10',
      volver: '/admin/almacen',
    });
    assert.equal(creado.status, 303);
    assert.doesNotMatch(creado.headers.get('location'), /error=/);

    const p = producto();
    await api(s.url, '/api/sync', {
      metodo: 'POST',
      token,
      cuerpo: { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: { productos: [p] } },
    });

    const vender = (items, total) =>
      api(s.url, '/api/sync', {
        metodo: 'POST',
        token,
        cuerpo: {
          dispositivo_id: 'tel-a',
          ultima_rev: 0,
          cambios: {
            ventas: [
              {
                id: randomUUID(),
                creado_en: Date.now(),
                total_centavos: total,
                anulada: false,
                actualizado_en: Date.now(),
                dispositivo_id: 'tel-a',
                items: items.map((i) => ({
                  id: randomUUID(),
                  producto_id: i.producto_id ?? p.id,
                  nombre: i.nombre,
                  precio_centavos: i.precio_centavos,
                  cantidad: i.cantidad,
                })),
              },
            ],
          },
        },
      });

    const venta = await vender([{ nombre: 'Chocolate', precio_centavos: 500, cantidad: 2 }], 1000);
    assert.equal(venta.estado, 200);

    // Ventas: qué se vendió, cuánto entró y cuánto quedó de ganancia.
    const ventas = await pagina(s.url, '/admin/ventas', cookie);
    assert.match(ventas.texto, /Qué se vendió/);
    assert.match(ventas.texto, /2× Chocolate/);
    assert.match(ventas.texto, /\$ 10,00/);
    assert.match(ventas.texto, /\$ 4,00/, 'ganancia = 2 × ($5,00 − $3,00)');

    // Resumen: la ganancia del día y el detalle en las últimas ventas.
    const resumen = await pagina(s.url, '/admin', cookie);
    assert.match(resumen.texto, /Ganancia hoy/);
    assert.match(resumen.texto, /\$ 4,00/);
    assert.match(resumen.texto, /2× Chocolate/);

    // Y en el detalle de la cuenta.
    const cuenta = s.db.prepare('SELECT id FROM usuarios').get().id;
    const detalle = await pagina(s.url, `/admin/cuenta/${cuenta}`, cookie);
    assert.match(detalle.texto, /\$ 4,00/);

    // Un producto que nunca pasó por el almacén no tiene costo: se avisa,
    // en vez de mostrar una ganancia inventada.
    const gomitas = producto({ id: randomUUID(), nombre: 'Gomitas', precio_centavos: 200, stock_base: 5 });
    await api(s.url, '/api/sync', {
      metodo: 'POST',
      token,
      cuerpo: { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: { productos: [gomitas] } },
    });
    await vender(
      [{ nombre: 'Gomitas', precio_centavos: 200, cantidad: 1, producto_id: gomitas.id }],
      200,
    );

    const ventasSinCosto = await pagina(s.url, '/admin/ventas', cookie);
    assert.match(ventasSinCosto.texto, /sin costo/);
    assert.match(ventasSinCosto.texto, /1 venta sin costo/);
  } finally {
    await s.cerrar();
  }
});

test('el vendedor devuelve mercadería al almacén y el padre le corrige el precio', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const ana = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `ana${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const usuarioId = ana.datos.usuario.id;

    const panel = await pagina(s.url, '/admin/almacen', cookie);
    const csrf = csrfDe(panel.texto);
    await enviarFormulario(s.url, '/admin/almacen', cookie, csrf, {
      nombre: 'Chocolate',
      costo: '3,00',
      precio: '5,00',
      stock: '10',
      volver: '/admin/almacen',
    });
    const articuloId = s.db.prepare('SELECT id FROM almacen').get().id;
    await enviarFormulario(s.url, `/admin/almacen/${articuloId}/enviar`, cookie, csrf, {
      cuenta: usuarioId,
      cantidad: '5',
      volver: '/admin/almacen',
    });
    const productoId = s.db
      .prepare('SELECT id FROM productos WHERE usuario_id = ?')
      .get(usuarioId).id;

    // La sección nueva muestra qué tiene cada vendedor.
    const conStock = await pagina(s.url, '/admin/almacen', cookie);
    assert.match(conStock.texto, /En manos de los vendedores/);
    assert.ok(conStock.texto.includes(ana.datos.usuario.email));
    assert.match(conStock.texto, /5 unidades/);

    // Devolver 2: sale de su inventario y vuelve al depósito.
    const devolucion = await enviarFormulario(s.url, '/admin/almacen/devolucion', cookie, csrf, {
      cuenta: usuarioId,
      producto: productoId,
      cantidad: '2',
      volver: '/admin/almacen',
    });
    assert.equal(devolucion.status, 303);
    assert.doesNotMatch(devolucion.headers.get('location'), /error=/);
    assert.equal(Number(s.db.prepare('SELECT stock FROM almacen').get().stock), 7);

    const inventarioAna = await api(s.url, '/api/inventario', { token: ana.datos.token });
    assert.equal(
      inventarioAna.datos.productos.find((p) => p.id === productoId).stock_actual,
      3,
    );

    const movimiento = s.db
      .prepare('SELECT cantidad, motivo, dispositivo_id FROM movimientos WHERE usuario_id = ? ORDER BY rowid DESC')
      .get(usuarioId);
    assert.equal(movimiento.motivo, 'devolucion');
    assert.equal(Number(movimiento.cantidad), -2);
    assert.equal(movimiento.dispositivo_id, 'portal-admin');
    assert.equal(
      s.db.prepare('SELECT tipo FROM traslados ORDER BY rowid DESC').get().tipo,
      'devolucion',
    );

    // No se puede devolver más de lo que tiene.
    const exceso = await enviarFormulario(s.url, '/admin/almacen/devolucion', cookie, csrf, {
      cuenta: usuarioId,
      producto: productoId,
      cantidad: '9',
      volver: '/admin/almacen',
    });
    assert.match(exceso.headers.get('location'), /error=/);
    assert.equal(Number(s.db.prepare('SELECT stock FROM almacen').get().stock), 7);

    // El padre le cambia el precio y el costo desde el almacén (incluso en manos
    // del vendedor): el costo se guarda en el depósito, no viaja al teléfono.
    const editar = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${productoId}`,
      cookie,
      csrf,
      { nombre: 'Chocolate', precio: '7,50', costo: '2,25', activo: '1', volver: '/admin/almacen' },
    );
    assert.equal(editar.status, 303);
    assert.doesNotMatch(editar.headers.get('location'), /error=/);
    assert.equal(
      Number(s.db.prepare('SELECT costo_centavos FROM almacen').get().costo_centavos),
      225,
    );

    const inventarioNuevo = await api(s.url, '/api/inventario', { token: ana.datos.token });
    assert.equal(
      inventarioNuevo.datos.productos.find((p) => p.id === productoId).precio_centavos,
      750,
    );

    const conPrecio = await pagina(s.url, '/admin/almacen', cookie);
    assert.match(conPrecio.texto, /\$ 7,50/);
    assert.match(conPrecio.texto, /\$ 2,25/);
    assert.match(conPrecio.texto, /value="2,25"/, 'el modal tiene que venir con el costo cargado');
    assert.match(conPrecio.texto, /−2/);
    assert.match(conPrecio.texto, /devolución/);

    // Un producto que nunca pasó por el almacén también se puede devolver:
    // queda cargado en el depósito con costo 0 para corregirlo después.
    await enviarFormulario(s.url, '/admin/inventario/producto', cookie, csrf, {
      cuenta: usuarioId,
      nombre: 'Gomitas',
      precio: '2,00',
      stock: '4',
      volver: '/admin/almacen',
    });
    const gomitasId = s.db
      .prepare('SELECT id FROM productos WHERE usuario_id = ? AND nombre = ?')
      .get(usuarioId, 'Gomitas').id;
    const devolucionNueva = await enviarFormulario(
      s.url,
      '/admin/almacen/devolucion',
      cookie,
      csrf,
      { cuenta: usuarioId, producto: gomitasId, cantidad: '1', volver: '/admin/almacen' },
    );
    assert.equal(devolucionNueva.status, 303);
    assert.match(decodeURIComponent(devolucionNueva.headers.get('location')), /costo 0/);
    const gomitasAlmacen = s.db
      .prepare('SELECT costo_centavos, stock FROM almacen WHERE nombre_clave = ?')
      .get('gomitas');
    assert.equal(Number(gomitasAlmacen.costo_centavos), 0);
    assert.equal(Number(gomitasAlmacen.stock), 1);

    // Y el movimiento de devolución le llega al teléfono al sincronizar.
    const bajada = await api(s.url, '/api/sync', {
      metodo: 'POST',
      token: ana.datos.token,
      cuerpo: { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: {} },
    });
    assert.ok(
      bajada.datos.cambios.movimientos.some((m) => m.motivo === 'devolucion'),
      'el teléfono tiene que recibir la devolución',
    );
  } finally {
    await s.cerrar();
  }
});

test('el costo de compra se edita desde el producto del vendedor y queda en el almacén', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const ana = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `ana${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const usuarioId = ana.datos.usuario.id;
    const choco = producto({ nombre: 'Chocolate', precio_centavos: 500, stock_base: 7 });

    // Producto del teléfono: todavía no existe en el almacén.
    await api(s.url, '/api/sync', {
      metodo: 'POST',
      token: ana.datos.token,
      cuerpo: { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: { productos: [choco] } },
    });

    const inventario = await pagina(s.url, '/admin/inventario', cookie);
    const csrf = csrfDe(inventario.texto);
    assert.match(inventario.texto, /name="costo"/, 'el modal tiene que tener costo de compra');

    // Al guardarlo se crea el artículo en el almacén con stock 0.
    const editar = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${choco.id}`,
      cookie,
      csrf,
      {
        nombre: 'Chocolate',
        precio: '5,00',
        costo: '3,25',
        activo: '1',
        volver: '/admin/inventario',
      },
    );
    assert.equal(editar.status, 303);
    assert.doesNotMatch(editar.headers.get('location'), /error=/);

    const articulo = s.db
      .prepare('SELECT * FROM almacen WHERE nombre_clave = ?')
      .get('chocolate');
    assert.ok(articulo, 'el costo tiene que crear el artículo del almacén');
    assert.equal(Number(articulo.costo_centavos), 325);
    assert.equal(Number(articulo.precio_centavos), 500);
    assert.equal(Number(articulo.stock), 0);

    // Inventario, almacén y cuenta muestran el costo cargado en el modal.
    const inv = await pagina(s.url, '/admin/inventario', cookie);
    assert.match(inv.texto, /value="3,25"/);
    const almacen = await pagina(s.url, '/admin/almacen', cookie);
    assert.match(almacen.texto, /value="3,25"/);
    const cuenta = await pagina(s.url, `/admin/cuenta/${usuarioId}`, cookie);
    assert.match(cuenta.texto, /value="3,25"/);

    // Un monto inválido no pisa nada y se avisa en el portal.
    const malo = await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${choco.id}`,
      cookie,
      csrf,
      { nombre: 'Chocolate', precio: '5,00', costo: 'tres', activo: '1' },
    );
    assert.match(malo.headers.get('location'), /error=/);
    assert.equal(Number(s.db.prepare('SELECT costo_centavos FROM almacen').get().costo_centavos), 325);

    // Vacío deja el costo como estaba.
    await enviarFormulario(
      s.url,
      `/admin/cuenta/${usuarioId}/producto/${choco.id}`,
      cookie,
      csrf,
      { nombre: 'Chocolate', precio: '5,00', costo: '', activo: '1' },
    );
    assert.equal(Number(s.db.prepare('SELECT costo_centavos FROM almacen').get().costo_centavos), 325);
  } finally {
    await s.cerrar();
  }
});

test('cada venta se ve en pantalla y se descarga en PDF', async () => {
  const s = await arrancar();
  try {
    const cookie = await sesionAdmin(s.url);
    const alta = await api(s.url, '/api/registro', {
      metodo: 'POST',
      cuerpo: { email: `nene${randomUUID().slice(0, 8)}@ejemplo.com`, contrasena: 'dulce123' },
    });
    const token = alta.datos.token;
    const usuarioId = alta.datos.usuario.id;

    const p = producto();
    const ventaId = randomUUID();
    await api(s.url, '/api/sync', {
      metodo: 'POST',
      token,
      cuerpo: { dispositivo_id: 'tel-a', ultima_rev: 0, cambios: { productos: [p] } },
    });
    await api(s.url, '/api/sync', {
      metodo: 'POST',
      token,
      cuerpo: {
        dispositivo_id: 'tel-a',
        ultima_rev: 0,
        cambios: {
          ventas: [
            {
              id: ventaId,
              creado_en: Date.now(),
              total_centavos: 1000,
              anulada: false,
              actualizado_en: Date.now(),
              dispositivo_id: 'tel-a',
              items: [
                {
                  id: randomUUID(),
                  producto_id: p.id,
                  nombre: 'Chocolate',
                  precio_centavos: 500,
                  cantidad: 2,
                },
              ],
            },
          ],
        },
      },
    });

    // Detalle en pantalla.
    const detalle = await pagina(s.url, `/admin/venta/${usuarioId}/${ventaId}`, cookie);
    assert.equal(detalle.estado, 200);
    assert.match(detalle.texto, /Venta del/);
    assert.match(detalle.texto, /Chocolate/);
    assert.match(detalle.texto, /\$ 10,00/);
    assert.match(detalle.texto, /Descargar PDF/);

    // Comprobante en PDF.
    const pdfVenta = await descarga(s.url, `/admin/venta/${usuarioId}/${ventaId}/pdf`, cookie);
    assert.equal(pdfVenta.estado, 200);
    assert.match(pdfVenta.tipo, /application\/pdf/);
    assert.equal(pdfVenta.contenido.subarray(0, 5).toString(), '%PDF-');
    const textoVenta = pdfVenta.contenido.toString('latin1');
    assert.match(textoVenta, /Comprobante de venta/);
    assert.ok(textoVenta.includes('Chocolate'));
    assert.ok(textoVenta.includes('10,00'));

    // Reporte con la lista y el detalle de cada venta.
    const pdfLista = await descarga(s.url, '/admin/ventas.pdf', cookie);
    assert.equal(pdfLista.estado, 200);
    assert.match(pdfLista.tipo, /application\/pdf/);
    assert.equal(pdfLista.contenido.subarray(0, 5).toString(), '%PDF-');
    const textoLista = pdfLista.contenido.toString('latin1');
    assert.match(textoLista, /Reporte de ventas/);
    assert.match(textoLista, /Liznack/);
    assert.ok(textoLista.includes('Chocolate'));
    assert.ok(textoLista.includes('RECAUDADO'));

    // Sin sesión no se descarga nada: devuelve el ingreso, no un PDF.
    const anonimo = await descarga(s.url, '/admin/ventas.pdf');
    assert.doesNotMatch(anonimo.tipo, /application\/pdf/);
    assert.notEqual(anonimo.contenido.subarray(0, 5).toString(), '%PDF-');
  } finally {
    await s.cerrar();
  }
});

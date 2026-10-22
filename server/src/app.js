import { randomUUID } from 'node:crypto';
import { enTransaccion, SQL_STOCK } from './db.js';
import {
  claveValida, crearSesion, emailValido, hashClave, normalizarEmail,
  tokenDeRequest, usuarioDeToken,
} from './auth.js';
import { aplicarCambios, obtenerCambios } from './sync.js';
import { ErrorHttp, enviarHtml, enviarJson, leerJson, obtenerIp, redirigir } from './http.js';
import { crearPortalAdmin } from './admin.js';
import { paginaSinPortal } from './admin_vistas.js';

const MAX_INTENTOS_POR_MINUTO = 20;
const intentos = new Map();

function limitarIntentos(ip) {
  const ahora = Date.now();
  const previos = (intentos.get(ip) ?? []).filter((t) => ahora - t < 60_000);
  previos.push(ahora);
  intentos.set(ip, previos);
  if (intentos.size > 5_000) intentos.clear();
  if (previos.length > MAX_INTENTOS_POR_MINUTO) {
    throw new ErrorHttp(429, 'Demasiados intentos. Esperá un minuto.');
  }
}

function validarCredenciales(cuerpo) {
  const email = normalizarEmail(cuerpo?.email);
  const clave = String(cuerpo?.contrasena ?? cuerpo?.password ?? '');
  if (!emailValido(email)) throw new ErrorHttp(400, 'Ingresá un correo válido.');
  if (clave.length < 6) throw new ErrorHttp(400, 'La contraseña debe tener al menos 6 caracteres.');
  if (clave.length > 200) throw new ErrorHttp(400, 'La contraseña es demasiado larga.');
  return { email, clave };
}

function sesionRequerida(db, req) {
  const usuario = usuarioDeToken(db, tokenDeRequest(req));
  if (!usuario) throw new ErrorHttp(401, 'Sesión vencida o inválida. Volvé a ingresar.');
  return usuario;
}

/** Devuelve un manejador (req, res) listo para node:http. */
export function crearManejador(db, { log = console.log, adminClave = process.env.LIZNACK_ADMIN } = {}) {
  const portal = crearPortalAdmin(db, { clave: adminClave, log });

  return async function manejar(req, res) {
    const inicio = Date.now();
    let ruta = '/';
    try {
      const url = new URL(req.url, 'http://localhost');
      ruta = url.pathname.replace(/\/+$/, '') || '/';
      const metodo = req.method ?? 'GET';

      // Portal del administrador: HTML, sesión propia con cookie.
      if (ruta === '/admin' || ruta.startsWith('/admin/')) {
        if (portal) return await portal(req, res, url);
        return enviarHtml(res, 200, paginaSinPortal());
      }

      // Un navegador que entra a la raíz va al portal; una API recibe JSON.
      if (metodo === 'GET' && ruta === '/') {
        if (String(req.headers.accept ?? '').includes('text/html')) {
          return redirigir(res, '/admin');
        }
        return enviarJson(res, 200, { ok: true, servicio: 'liznack', version: 1 });
      }

      if (metodo === 'GET' && ruta === '/api/salud') {
        return enviarJson(res, 200, { ok: true, servicio: 'liznack', version: 1 });
      }

      if (metodo === 'POST' && (ruta === '/api/registro' || ruta === '/api/login')) {
        limitarIntentos(obtenerIp(req));
        const { email, clave } = validarCredenciales(await leerJson(req));
        if (ruta === '/api/registro') {
          const existente = db.prepare('SELECT id FROM usuarios WHERE email = ?').get(email);
          if (existente) throw new ErrorHttp(409, 'Ese correo ya tiene una cuenta. Ingresá.');
          const { hash, salt } = hashClave(clave);
          const id = randomUUID();
          db.prepare(
            'INSERT INTO usuarios (id, email, hash, salt, creado_en) VALUES (?, ?, ?, ?, ?)',
          ).run(id, email, hash, salt, new Date().toISOString());
          const token = crearSesion(db, id);
          return enviarJson(res, 201, { token, usuario: { id, email } });
        }
        const usuario = db
          .prepare('SELECT id, email, hash, salt FROM usuarios WHERE email = ?')
          .get(email);
        if (!usuario || !claveValida(clave, usuario.salt, usuario.hash)) {
          throw new ErrorHttp(401, 'Correo o contraseña incorrectos.');
        }
        const token = crearSesion(db, usuario.id);
        return enviarJson(res, 200, { token, usuario: { id: usuario.id, email: usuario.email } });
      }

      if (metodo === 'GET' && ruta === '/api/sesion') {
        const usuario = sesionRequerida(db, req);
        return enviarJson(res, 200, { usuario });
      }

      if (metodo === 'POST' && ruta === '/api/sync') {
        const usuario = sesionRequerida(db, req);
        const cuerpo = await leerJson(req);
        const dispositivo = String(cuerpo.dispositivo_id ?? '').slice(0, 100) || 'desconocido';
        const desdeRev = Number.isInteger(cuerpo.ultima_rev) && cuerpo.ultima_rev >= 0
          ? cuerpo.ultima_rev
          : 0;

        const aplicado = enTransaccion(db, () => aplicarCambios(db, usuario.id, cuerpo.cambios ?? {}));
        const cambios = obtenerCambios(db, usuario.id, desdeRev);
        return enviarJson(res, 200, {
          servidor_en: Date.now(),
          dispositivo_id: dispositivo,
          ultima_rev: cambios.rev,
          hay_mas: cambios.hay_mas,
          cambios: {
            productos: cambios.productos,
            ventas: cambios.ventas,
            movimientos: cambios.movimientos,
          },
          ...aplicado,
        });
      }

      if (metodo === 'GET' && ruta === '/api/inventario') {
        const usuario = sesionRequerida(db, req);
        const filas = db.prepare(
          `SELECT p.id, p.nombre, p.precio_centavos,
                  ${SQL_STOCK} AS stock_actual, p.activo, p.actualizado_en
             FROM productos p
            WHERE p.usuario_id = ?
            ORDER BY p.activo DESC, p.nombre COLLATE NOCASE`,
        ).all(usuario.id);
        return enviarJson(res, 200, {
          productos: filas.map((f) => ({ ...f, activo: f.activo === 1, stock_actual: Number(f.stock_actual) })),
        });
      }

      if (metodo === 'GET' && ruta === '/api/ventas') {
        const usuario = sesionRequerida(db, req);
        const desde = Number.parseInt(url.searchParams.get('desde') ?? '0', 10) || 0;
        const limite = Math.min(Math.max(Number.parseInt(url.searchParams.get('limite') ?? '100', 10) || 100, 1), 500);
        const ventas = db.prepare(
          `SELECT id, creado_en, total_centavos, anulada
             FROM ventas WHERE usuario_id = ? AND creado_en >= ?
            ORDER BY creado_en DESC LIMIT ?`,
        ).all(usuario.id, desde, limite);
        const totalCentavos = ventas
          .filter((v) => v.anulada === 0)
          .reduce((s, v) => s + v.total_centavos, 0);
        return enviarJson(res, 200, {
          total_centavos: totalCentavos,
          cantidad: ventas.filter((v) => v.anulada === 0).length,
          ventas: ventas.map((v) => ({ ...v, anulada: v.anulada === 1 })),
        });
      }

      throw new ErrorHttp(404, 'Ruta no encontrada.');
    } catch (error) {
      if (error instanceof ErrorHttp) {
        return enviarJson(res, error.codigo, { error: error.message });
      }
      log(`[error] ${req.method} ${ruta}:`, error);
      return enviarJson(res, 500, { error: 'Error interno del servidor.' });
    } finally {
      if (ruta !== '/api/salud' && ruta !== '/') {
        log(`${req.method} ${ruta} ${res.statusCode} ${Date.now() - inicio}ms`);
      }
    }
  };
}

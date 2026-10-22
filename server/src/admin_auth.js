import { createHmac, timingSafeEqual } from 'node:crypto';

export const COOKIE_ADMIN = 'liznack_admin';
const DURACION_MS = 12 * 60 * 60 * 1000;

/**
 * El portal no tiene usuarios propios: se entra con una única contraseña que
 * vive en la variable de entorno `LIZNACK_ADMIN`. La sesión es una cookie
 * firmada, así no hace falta guardar nada en la base.
 */
export function crearSeguridad(clave) {
  const llave = createHmac('sha256', 'liznack-portal').update(String(clave)).digest();

  const firmar = (texto) => createHmac('sha256', llave).update(texto).digest('base64url');

  function iguales(a, b) {
    const x = Buffer.from(String(a), 'utf8');
    const y = Buffer.from(String(b), 'utf8');
    return x.length === y.length && timingSafeEqual(x, y);
  }

  return {
    /** Compara en tiempo constante: no filtra el largo de la clave. */
    claveCorrecta(entrada) {
      const a = Buffer.from(String(entrada ?? ''), 'utf8');
      const b = Buffer.from(String(clave), 'utf8');
      if (a.length !== b.length) {
        timingSafeEqual(b, b);
        return false;
      }
      return timingSafeEqual(a, b);
    },

    tokenNuevo(ahora = Date.now()) {
      const expira = ahora + DURACION_MS;
      return `${expira}.${firmar(`sesion:${expira}`)}`;
    },

    tokenValido(token, ahora = Date.now()) {
      if (typeof token !== 'string') return false;
      const corte = token.indexOf('.');
      if (corte <= 0) return false;
      const expira = Number.parseInt(token.slice(0, corte), 10);
      if (!Number.isFinite(expira) || expira <= ahora) return false;
      return iguales(token.slice(corte + 1), firmar(`sesion:${expira}`));
    },

    cookie(token) {
      const partes = [
        `${COOKIE_ADMIN}=${encodeURIComponent(token)}`,
        'Path=/',
        'HttpOnly',
        'SameSite=Lax',
        `Max-Age=${Math.floor(DURACION_MS / 1000)}`,
      ];
      return partes.join('; ');
    },

    cookieBorrada() {
      return `${COOKIE_ADMIN}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`;
    },
  };
}

export function leerCookies(req) {
  const salida = {};
  for (const parte of String(req.headers.cookie ?? '').split(';')) {
    const corte = parte.indexOf('=');
    if (corte < 0) continue;
    const nombre = parte.slice(0, corte).trim();
    if (!nombre) continue;
    try {
      salida[nombre] = decodeURIComponent(parte.slice(corte + 1).trim());
    } catch {
      // cookie mal formada: se ignora
    }
  }
  return salida;
}

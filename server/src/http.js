export class ErrorHttp extends Error {
  constructor(codigo, mensaje) {
    super(mensaje);
    this.codigo = codigo;
  }
}

export function enviarJson(res, codigo, cuerpo) {
  const texto = JSON.stringify(cuerpo);
  res.writeHead(codigo, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(texto),
    'Cache-Control': 'no-store',
  });
  res.end(texto);
}

export async function leerJson(req, limiteBytes = 2 * 1024 * 1024) {
  const partes = [];
  let total = 0;
  for await (const parte of req) {
    total += parte.length;
    if (total > limiteBytes) throw new ErrorHttp(413, 'El cuerpo es demasiado grande.');
    partes.push(parte);
  }
  const texto = Buffer.concat(partes).toString('utf8');
  if (!texto.trim()) return {};
  try {
    const datos = JSON.parse(texto);
    if (datos === null || typeof datos !== 'object' || Array.isArray(datos)) {
      throw new ErrorHttp(400, 'Se esperaba un objeto JSON.');
    }
    return datos;
  } catch (error) {
    if (error instanceof ErrorHttp) throw error;
    throw new ErrorHttp(400, 'JSON inválido.');
  }
}

export const obtenerIp = (req) =>
  String(req.headers['x-forwarded-for'] ?? '').split(',')[0].trim() ||
  req.socket.remoteAddress ||
  'desconocida';

/** Lee un formulario HTML (`application/x-www-form-urlencoded`). */
export async function leerFormulario(req, limiteBytes = 64 * 1024) {
  const partes = [];
  let total = 0;
  for await (const parte of req) {
    total += parte.length;
    if (total > limiteBytes) throw new ErrorHttp(413, 'El formulario es demasiado grande.');
    partes.push(parte);
  }
  return new URLSearchParams(Buffer.concat(partes).toString('utf8'));
}

export function redirigir(res, ruta, { cookie } = {}) {
  const cabeceras = { Location: ruta, 'Cache-Control': 'no-store' };
  if (cookie) cabeceras['Set-Cookie'] = cookie;
  res.writeHead(303, cabeceras);
  res.end();
}

/** Envía HTML con las cabeceras de seguridad del portal. */
export function enviarHtml(res, codigo, html, cabecerasExtra = {}) {
  const buf = Buffer.from(html, 'utf8');
  res.writeHead(codigo, {
    'Content-Type': 'text/html; charset=utf-8',
    'Content-Length': buf.length,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy':
      "default-src 'none'; style-src 'self'; script-src 'self'; img-src 'self' data:; " +
      "form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
    ...cabecerasExtra,
  });
  res.end(buf);
}

/** Envía un archivo estático del portal (la URL lleva la huella del contenido). */
export function enviarEstatico(res, tipo, contenido) {
  const buf = Buffer.isBuffer(contenido) ? contenido : Buffer.from(contenido, 'utf8');
  res.writeHead(200, {
    'Content-Type': tipo,
    'Content-Length': buf.length,
    'Cache-Control': 'public, max-age=86400',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(buf);
}

import { randomBytes, scryptSync, timingSafeEqual, createHash } from 'node:crypto';

const DIAS_SESION = 90;

export function normalizarEmail(email) {
  return String(email ?? '').trim().toLowerCase();
}

export function emailValido(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) && email.length <= 160;
}

export function hashClave(clave, salt = randomBytes(16).toString('hex')) {
  const hash = scryptSync(clave, salt, 64).toString('hex');
  return { hash, salt };
}

export function claveValida(clave, salt, hashEsperado) {
  const calculado = scryptSync(clave, salt, 64);
  const esperado = Buffer.from(hashEsperado, 'hex');
  return calculado.length === esperado.length && timingSafeEqual(calculado, esperado);
}

function huellaToken(token) {
  return createHash('sha256').update(token).digest('hex');
}

/** Crea una sesión y devuelve el token en claro (solo se guarda su huella). */
export function crearSesion(db, usuarioId) {
  const token = randomBytes(32).toString('base64url');
  const ahora = new Date();
  const expira = new Date(ahora.getTime() + DIAS_SESION * 24 * 60 * 60 * 1000);
  db.prepare(
    'INSERT INTO sesiones (token_hash, usuario_id, creado_en, expira_en) VALUES (?, ?, ?, ?)',
  ).run(huellaToken(token), usuarioId, ahora.toISOString(), expira.toISOString());
  return token;
}

export function usuarioDeToken(db, token) {
  if (!token) return null;
  const fila = db
    .prepare(
      `SELECT u.id, u.email, s.expira_en
         FROM sesiones s JOIN usuarios u ON u.id = s.usuario_id
        WHERE s.token_hash = ?`,
    )
    .get(huellaToken(token));
  if (!fila) return null;
  if (new Date(fila.expira_en).getTime() < Date.now()) {
    db.prepare('DELETE FROM sesiones WHERE token_hash = ?').run(huellaToken(token));
    return null;
  }
  return { id: fila.id, email: fila.email };
}

export function tokenDeRequest(req) {
  const cabecera = req.headers.authorization ?? '';
  const [tipo, valor] = cabecera.split(' ');
  return tipo?.toLowerCase() === 'bearer' && valor ? valor : null;
}

import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { ErrorHttp, enviarEstatico, enviarHtml, enviarPdf, leerFormulario, obtenerIp, redirigir } from './http.js';
import { COOKIE_ADMIN, crearSeguridad, leerCookies } from './admin_auth.js';
import * as datos from './admin_datos.js';
import { reporteVentasPdf, ventaPdf } from './admin_pdf.js';
import * as vistas from './admin_vistas.js';

const CSS = readFileSync(new URL('./public/portal.css', import.meta.url), 'utf8');
const JS = readFileSync(new URL('./public/portal.js', import.meta.url), 'utf8');
// La URL de los estáticos lleva la huella del contenido: si cambian, el
// navegador los vuelve a bajar sin que nadie tenga que refrescar a mano.
const HUELLA = createHash('sha256').update(CSS).update(JS).digest('hex').slice(0, 10);
vistas.fijarVersionEstaticos(HUELLA);

const MAX_INTENTOS = 10;
const VENTANA_INTENTOS_MS = 5 * 60 * 1000;

function diaMs(texto) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(texto ?? ''));
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(d.getTime()) ? null : d.getTime();
}

/** Filtros de la lista de ventas: los usan la pantalla y el PDF. */
function filtrosVentas(url) {
  const usuarioId = url.searchParams.get('cuenta') || '';
  const desdeTexto = url.searchParams.get('desde') ?? '';
  const hastaTexto = url.searchParams.get('hasta') ?? '';
  const desde = diaMs(desdeTexto);
  const hastaBase = diaMs(hastaTexto);
  return {
    usuarioId,
    desdeTexto,
    hastaTexto,
    desde: desde ?? undefined,
    hasta: hastaBase == null ? undefined : hastaBase + 24 * 60 * 60 * 1000,
  };
}

function conAviso(ruta, tipo, texto) {
  const clave = tipo === 'error' ? 'error' : 'ok';
  return `${ruta}${ruta.includes('?') ? '&' : '?'}${clave}=${encodeURIComponent(texto)}`;
}

function leerAviso(url) {
  const error = url.searchParams.get('error');
  if (error) return { tipo: 'error', texto: error };
  const ok = url.searchParams.get('ok');
  if (ok) return { tipo: 'ok', texto: ok };
  return null;
}

/** Ruta actual sin los avisos, para volver a la misma lista después de un POST. */
function rutaActual(url) {
  const parametros = new URLSearchParams(url.searchParams);
  parametros.delete('ok');
  parametros.delete('error');
  const ruta = url.pathname.replace(/\/+$/, '') || '/admin';
  const consulta = parametros.toString();
  return consulta ? `${ruta}?${consulta}` : ruta;
}

/** Solo se acepta volver a una página del portal, nunca a otro sitio. */
function rutaVolver(cuerpo, porDefecto) {
  const pedida = String(cuerpo.get('volver') ?? '').trim();
  if (pedida.startsWith('/admin') && !pedida.startsWith('//') && !/[\r\n]/.test(pedida)) {
    return pedida;
  }
  return porDefecto;
}

/**
 * Portal del administrador (el padre). Se monta en /admin y comparte la base
 * con la API: lo que se cambia acá sube de revisión y llega al teléfono en la
 * próxima sincronización.
 */
export function crearPortalAdmin(db, { clave, log = console.log } = {}) {
  if (!clave) return null;
  const seguridad = crearSeguridad(clave);
  const intentos = new Map();

  function limitar(ip) {
    const ahora = Date.now();
    const previos = (intentos.get(ip) ?? []).filter((t) => ahora - t < VENTANA_INTENTOS_MS);
    previos.push(ahora);
    intentos.set(ip, previos);
    if (intentos.size > 2_000) intentos.clear();
    if (previos.length > MAX_INTENTOS) {
      throw new ErrorHttp(429, 'Demasiados intentos. Esperá unos minutos.');
    }
  }

  function tokenDe(req) {
    const token = leerCookies(req)[COOKIE_ADMIN];
    return seguridad.tokenValido(token) ? token : null;
  }

  function verificarCsrf(cuerpo, token) {
    if (!token || cuerpo.get('csrf') !== token) {
      throw new ErrorHttp(400, 'El formulario venció. Volvé a cargar la página.');
    }
  }

  function cuentaDeLaRuta(segmentos) {
    const cuenta = datos.obtenerCuenta(db, segmentos[2]);
    if (!cuenta) throw new ErrorHttp(404, 'Esa cuenta no existe.');
    return cuenta;
  }

  function renderCuenta(res, cuenta, flash, csrf) {
    const ventas = datos.ventasDe(db, cuenta.id);
    const items = datos.itemsPorVenta(db, cuenta.id, ventas.map((v) => v.id));
    enviarHtml(
      res,
      200,
      vistas.paginaCuenta({
        cuenta,
        productos: datos.productosDe(db, cuenta.id),
        ventas,
        items,
        movimientos: datos.movimientosDe(db, cuenta.id),
        flash,
        csrf,
      }),
    );
  }

  return async function manejarAdmin(req, res, url) {
    const metodo = (req.method ?? 'GET').toUpperCase();
    const ruta = url.pathname.replace(/\/+$/, '') || '/admin';
    const segmentos = ruta.split('/').filter(Boolean); // ['admin', ...]

    try {
      // --- estáticos (no llevan sesión) -------------------------------------
      if (metodo === 'GET' && ruta === '/admin/portal.css') {
        return enviarEstatico(res, 'text/css; charset=utf-8', CSS);
      }
      if (metodo === 'GET' && ruta === '/admin/portal.js') {
        return enviarEstatico(res, 'text/javascript; charset=utf-8', JS);
      }

      // --- ingreso ----------------------------------------------------------
      if (metodo === 'POST' && ruta === '/admin/entrar') {
        limitar(obtenerIp(req));
        const cuerpo = await leerFormulario(req);
        const entrada = cuerpo.get('clave') ?? '';
        if (!seguridad.claveCorrecta(entrada)) {
          return enviarHtml(res, 401, vistas.paginaIngreso({ error: 'Contraseña incorrecta.' }));
        }
        const token = seguridad.tokenNuevo();
        return redirigir(res, '/admin', { cookie: seguridad.cookie(token) });
      }

      const token = tokenDe(req);

      if (metodo === 'POST' && ruta === '/admin/salir') {
        return redirigir(res, '/admin', { cookie: seguridad.cookieBorrada() });
      }

      // Sin sesión: solo se muestra el ingreso.
      if (!token) {
        if (metodo === 'GET') return enviarHtml(res, 200, vistas.paginaIngreso());
        return redirigir(res, '/admin');
      }

      const csrf = token;
      res.locals = { token };

      // --- resumen ----------------------------------------------------------
      if (metodo === 'GET' && ruta === '/admin') {
        return enviarHtml(
          res,
          200,
          vistas.paginaResumen({
            resumen: datos.resumenGeneral(db),
            cuentas: datos.listarCuentas(db),
            stockBajo: datos.stockBajo(db),
            ventas: datos.ventasRecientes(db),
            flash: leerAviso(url),
            csrf,
          }),
        );
      }

      // --- cuentas ----------------------------------------------------------
      if (metodo === 'GET' && ruta === '/admin/cuentas') {
        return enviarHtml(
          res,
          200,
          vistas.paginaCuentas({
            cuentas: datos.listarCuentas(db),
            flash: leerAviso(url),
            csrf,
          }),
        );
      }

      if (metodo === 'POST' && ruta === '/admin/cuentas') {
        const cuerpo = await leerFormulario(req);
        verificarCsrf(cuerpo, token);
        try {
          const creada = datos.crearCuenta(db, {
            email: cuerpo.get('email'),
            clave: cuerpo.get('clave'),
          });
          return redirigir(
            res,
            conAviso(`/admin/cuenta/${encodeURIComponent(creada.id)}`, 'ok', `Cuenta ${creada.email} creada.`),
          );
        } catch (error) {
          if (error instanceof ErrorHttp) {
            return redirigir(res, conAviso('/admin/cuentas', 'error', error.message));
          }
          throw error;
        }
      }

      // --- almacén -----------------------------------------------------------
      if (metodo === 'GET' && ruta === '/admin/almacen') {
        return enviarHtml(
          res,
          200,
          vistas.paginaAlmacen({
            items: datos.listarAlmacen(db),
            resumen: datos.resumenAlmacen(db),
            traslados: datos.trasladosRecientes(db),
            cuentas: datos.listarCuentas(db),
            porVendedor: datos.stockPorVendedor(db),
            flash: leerAviso(url),
            csrf,
            volver: rutaActual(url),
          }),
        );
      }

      if (metodo === 'POST' && ruta === '/admin/almacen') {
        const cuerpo = await leerFormulario(req);
        verificarCsrf(cuerpo, token);
        const volver = rutaVolver(cuerpo, '/admin/almacen');
        try {
          datos.crearArticuloAlmacen(db, {
            nombre: cuerpo.get('nombre'),
            costoCentavos: vistas.centavosDe(cuerpo.get('costo')),
            precioCentavos: vistas.centavosDe(cuerpo.get('precio')),
            stock: Number.parseInt(cuerpo.get('stock') ?? '', 10),
          });
          return redirigir(res, conAviso(volver, 'ok', 'Producto agregado al almacén.'));
        } catch (error) {
          if (error instanceof ErrorHttp) {
            return redirigir(res, conAviso(volver, 'error', error.message));
          }
          throw error;
        }
      }

      if (metodo === 'POST' && segmentos[1] === 'almacen' && segmentos[2] === 'devolucion') {
        const cuerpo = await leerFormulario(req);
        verificarCsrf(cuerpo, token);
        const volver = rutaVolver(cuerpo, '/admin/almacen');
        try {
          const resultado = datos.devolverAlAlmacen(
            db,
            String(cuerpo.get('cuenta') ?? ''),
            String(cuerpo.get('producto') ?? ''),
            Number.parseInt(cuerpo.get('cantidad') ?? '', 10),
          );
          const extra = resultado.creado
            ? ' Quedó cargado en el almacén con costo 0: corregilo cuando sepas cuánto salió.'
            : '';
          return redirigir(
            res,
            conAviso(
              volver,
              'ok',
              `Volvieron ${resultado.devueltas} de "${resultado.producto}" al almacén.${extra}`,
            ),
          );
        } catch (error) {
          if (error instanceof ErrorHttp) {
            return redirigir(res, conAviso(volver, 'error', error.message));
          }
          throw error;
        }
      }

      if (metodo === 'POST' && segmentos[1] === 'almacen' && segmentos.length === 4) {
        const cuerpo = await leerFormulario(req);
        verificarCsrf(cuerpo, token);
        const volver = rutaVolver(cuerpo, '/admin/almacen');
        const articuloId = segmentos[2];
        const accion = segmentos[3];
        try {
          if (accion === 'ingresar') {
            const resultado = datos.ingresarStockAlmacen(
              db,
              articuloId,
              Number.parseInt(cuerpo.get('cantidad') ?? '', 10),
            );
            return redirigir(res, conAviso(volver, 'ok', `Ahora hay ${resultado.stock} en el almacén.`));
          }
          if (accion === 'editar') {
            datos.editarArticuloAlmacen(db, articuloId, {
              nombre: cuerpo.get('nombre'),
              costoCentavos: vistas.centavosDe(cuerpo.get('costo')),
              precioCentavos: vistas.centavosDe(cuerpo.get('precio')),
            });
            return redirigir(res, conAviso(volver, 'ok', 'Producto del almacén actualizado.'));
          }
          if (accion === 'quitar') {
            const resultado = datos.eliminarArticuloAlmacen(db, articuloId);
            return redirigir(
              res,
              conAviso(volver, 'ok', `"${resultado.nombre}" ya no está en el almacén.`),
            );
          }
          if (accion === 'enviar') {
            const resultado = datos.trasladarAVendedor(
              db,
              articuloId,
              String(cuerpo.get('cuenta') ?? ''),
              Number.parseInt(cuerpo.get('cantidad') ?? '', 10),
            );
            const texto = resultado.creado
              ? `Enviado a ${resultado.email}: le creamos el producto. Quedan ${resultado.quedan}.`
              : `Enviado a ${resultado.email}. Quedan ${resultado.quedan} en el almacén.`;
            return redirigir(res, conAviso(volver, 'ok', texto));
          }
          throw new ErrorHttp(404, 'Ruta no encontrada.');
        } catch (error) {
          if (error instanceof ErrorHttp) {
            return redirigir(res, conAviso(volver, 'error', error.message));
          }
          throw error;
        }
      }

      // --- inventario --------------------------------------------------------
      if (metodo === 'GET' && ruta === '/admin/inventario') {
        const usuarioId = url.searchParams.get('cuenta') || '';
        const busqueda = url.searchParams.get('buscar') ?? '';
        const soloBajo = url.searchParams.get('solo_bajo') === '1';
        const incluirArchivados = url.searchParams.get('archivados') === '1';
        const { productos, totales } = datos.inventario(db, {
          usuarioId,
          busqueda,
          soloBajo,
          incluirArchivados,
        });
        return enviarHtml(
          res,
          200,
          vistas.paginaInventario({
            productos,
            totales,
            cuentas: datos.listarCuentas(db),
            filtros: { usuarioId, busqueda, soloBajo, incluirArchivados },
            flash: leerAviso(url),
            csrf,
            volver: rutaActual(url),
          }),
        );
      }

      if (metodo === 'POST' && ruta === '/admin/inventario/producto') {
        const cuerpo = await leerFormulario(req);
        verificarCsrf(cuerpo, token);
        const volver = rutaVolver(cuerpo, '/admin/inventario');
        try {
          datos.crearProducto(db, String(cuerpo.get('cuenta') ?? ''), {
            nombre: cuerpo.get('nombre'),
            precioCentavos: vistas.centavosDe(cuerpo.get('precio')),
            stock: Number.parseInt(cuerpo.get('stock') ?? '', 10),
          });
          return redirigir(res, conAviso(volver, 'ok', 'Producto agregado.'));
        } catch (error) {
          if (error instanceof ErrorHttp) {
            return redirigir(res, conAviso(volver, 'error', error.message));
          }
          throw error;
        }
      }

      if (metodo === 'GET' && segmentos[1] === 'cuenta' && segmentos.length === 3) {
        const cuenta = cuentaDeLaRuta(segmentos);
        return renderCuenta(res, cuenta, leerAviso(url), csrf);
      }

      // --- productos de una cuenta -----------------------------------------
      if (
        metodo === 'POST' &&
        segmentos[1] === 'cuenta' &&
        segmentos[3] === 'producto'
      ) {
        const cuenta = cuentaDeLaRuta(segmentos);
        const cuerpo = await leerFormulario(req);
        verificarCsrf(cuerpo, token);
        const volver = rutaVolver(cuerpo, `/admin/cuenta/${encodeURIComponent(cuenta.id)}`);
        try {
          if (segmentos.length === 4) {
            datos.crearProducto(db, cuenta.id, {
              nombre: cuerpo.get('nombre'),
              precioCentavos: vistas.centavosDe(cuerpo.get('precio')),
              stock: Number.parseInt(cuerpo.get('stock') ?? '', 10),
            });
            return redirigir(res, conAviso(volver, 'ok', 'Producto agregado.'));
          }
          if (segmentos.length === 5) {
            const costoTexto = String(cuerpo.get('costo') ?? '').trim();
            const costoCentavos = costoTexto ? vistas.centavosDe(costoTexto) : null;
            if (costoTexto && costoCentavos === null) {
              throw new ErrorHttp(400, 'El costo de compra no es un monto válido.');
            }
            datos.editarProducto(db, cuenta.id, segmentos[4], {
              nombre: cuerpo.get('nombre'),
              precioCentavos: vistas.centavosDe(cuerpo.get('precio')),
              costoCentavos,
              activo: cuerpo.get('activo') === '1',
            });
            return redirigir(res, conAviso(volver, 'ok', 'Producto actualizado.'));
          }
          if (segmentos.length === 6 && segmentos[5] === 'reponer') {
            datos.reponerStock(db, cuenta.id, segmentos[4], Number.parseInt(cuerpo.get('cantidad') ?? '', 10));
            return redirigir(res, conAviso(volver, 'ok', 'Stock repuesto.'));
          }
          if (segmentos.length === 6 && segmentos[5] === 'estado') {
            const activo = cuerpo.get('activo') === '1';
            const resultado = datos.cambiarEstadoProducto(db, cuenta.id, segmentos[4], activo);
            const texto = resultado.yaEstaba
              ? 'El producto ya estaba así.'
              : activo
                ? 'Producto reactivado.'
                : 'Producto archivado.';
            return redirigir(res, conAviso(volver, 'ok', texto));
          }
          throw new ErrorHttp(404, 'Ruta no encontrada.');
        } catch (error) {
          if (error instanceof ErrorHttp) {
            return redirigir(res, conAviso(volver, 'error', error.message));
          }
          throw error;
        }
      }

      // --- anular venta -----------------------------------------------------
      if (
        metodo === 'POST' &&
        segmentos[1] === 'cuenta' &&
        segmentos[3] === 'venta' &&
        segmentos.length === 6 &&
        segmentos[5] === 'anular'
      ) {
        const cuenta = cuentaDeLaRuta(segmentos);
        const cuerpo = await leerFormulario(req);
        verificarCsrf(cuerpo, token);
        const volver = rutaVolver(cuerpo, `/admin/cuenta/${encodeURIComponent(cuenta.id)}`);
        try {
          const resultado = datos.anularVenta(db, cuenta.id, segmentos[4]);
          return redirigir(
            res,
            conAviso(volver, 'ok', resultado.yaEstaba ? 'Esa venta ya estaba anulada.' : 'Venta anulada. El stock volvió.'),
          );
        } catch (error) {
          if (error instanceof ErrorHttp) {
            return redirigir(res, conAviso(volver, 'error', error.message));
          }
          throw error;
        }
      }

      // --- clave y borrado --------------------------------------------------
      if (metodo === 'POST' && segmentos[1] === 'cuenta' && segmentos.length === 4) {
        const cuenta = cuentaDeLaRuta(segmentos);
        const volver = `/admin/cuenta/${encodeURIComponent(cuenta.id)}`;
        const cuerpo = await leerFormulario(req);
        verificarCsrf(cuerpo, token);

        if (segmentos[3] === 'clave') {
          try {
            datos.cambiarClave(db, cuenta.id, cuerpo.get('clave'));
            return redirigir(res, conAviso(volver, 'ok', 'Contraseña cambiada. Las sesiones abiertas se cerraron.'));
          } catch (error) {
            if (error instanceof ErrorHttp) return redirigir(res, conAviso(volver, 'error', error.message));
            throw error;
          }
        }

        if (segmentos[3] === 'borrar') {
          const confirmacion = String(cuerpo.get('confirmacion') ?? '').trim().toLowerCase();
          if (confirmacion !== cuenta.email.toLowerCase()) {
            return redirigir(res, conAviso(volver, 'error', 'La confirmación no coincide con el correo.'));
          }
          datos.borrarCuenta(db, cuenta.id);
          return redirigir(res, conAviso('/admin/cuentas', 'ok', `Cuenta ${cuenta.email} borrada.`));
        }

        throw new ErrorHttp(404, 'Ruta no encontrada.');
      }

      // --- ventas globales --------------------------------------------------
      if (metodo === 'GET' && ruta === '/admin/ventas') {
        const filtros = filtrosVentas(url);
        const resultado = datos.listarVentas(db, {
          desde: filtros.desde,
          hasta: filtros.hasta,
          usuarioId: filtros.usuarioId || undefined,
        });
        return enviarHtml(
          res,
          200,
          vistas.paginaVentas({
            ventas: resultado.ventas,
            total: resultado.total_centavos,
            cantidad: resultado.cantidad,
            gananciaTotal: resultado.ganancia_total,
            sinCosto: resultado.sin_costo,
            cuentas: datos.listarCuentas(db),
            filtros: {
              usuarioId: filtros.usuarioId,
              desde: filtros.desdeTexto,
              hasta: filtros.hastaTexto,
            },
            flash: leerAviso(url),
            csrf,
          }),
        );
      }

      if (metodo === 'GET' && ruta === '/admin/ventas.pdf') {
        const filtros = filtrosVentas(url);
        const resultado = datos.listarVentas(db, {
          desde: filtros.desde,
          hasta: filtros.hasta,
          usuarioId: filtros.usuarioId || undefined,
          limite: 5000,
        });
        const cuenta = filtros.usuarioId ? datos.obtenerCuenta(db, filtros.usuarioId) : null;
        const pdf = reporteVentasPdf({
          ventas: resultado.ventas,
          total: resultado.total_centavos,
          cantidad: resultado.cantidad,
          ganancia: resultado.ganancia_total,
          sinCosto: resultado.sin_costo,
          desde: filtros.desdeTexto,
          hasta: filtros.hastaTexto,
          cuenta,
        });
        const nombre = `liznack-ventas-${vistas.iso(Date.now())}.pdf`;
        return enviarPdf(res, pdf, nombre);
      }

      // --- una venta: detalle en pantalla y comprobante en PDF --------------
      if (metodo === 'GET' && segmentos[1] === 'venta' && segmentos.length >= 4) {
        const cuenta = datos.obtenerCuenta(db, segmentos[2]);
        if (!cuenta) throw new ErrorHttp(404, 'Esa cuenta no existe.');
        const venta = datos.detalleVenta(db, cuenta.id, segmentos[3]);
        if (!venta) throw new ErrorHttp(404, 'Esa venta no existe.');

        if (segmentos.length === 5 && segmentos[4] === 'pdf') {
          const pdf = ventaPdf({ venta, cuenta });
          return enviarPdf(res, pdf, `liznack-venta-${String(venta.id).slice(0, 8)}.pdf`);
        }
        if (segmentos.length === 4) {
          return enviarHtml(
            res,
            200,
            vistas.paginaVenta({ venta, cuenta, flash: leerAviso(url), csrf }),
          );
        }
        throw new ErrorHttp(404, 'Ruta no encontrada.');
      }

      throw new ErrorHttp(404, 'Ruta no encontrada.');
    } catch (error) {
      if (error instanceof ErrorHttp) {
        return enviarHtml(
          res,
          error.codigo,
          vistas.paginaError({ codigo: error.codigo, mensaje: error.message, csrf: res.locals?.token }),
        );
      }
      log(`[portal] ${req.method} ${ruta}:`, error);
      return enviarHtml(
        res,
        500,
        vistas.paginaError({
          codigo: 500,
          mensaje: 'Error interno del servidor.',
          csrf: res.locals?.token,
        }),
      );
    }
  };
}

const MESES = 'ene feb mar abr may jun jul ago sep oct nov dic'.split(' ');

/** Huella de los estáticos, para que el navegador no use una copia vieja. */
let versionEstaticos = '1';
export function fijarVersionEstaticos(version) {
  versionEstaticos = String(version);
}

export function escapar(valor) {
  return String(valor ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function pesos(centavos) {
  const valor = (Number(centavos) || 0) / 100;
  return `$ ${valor.toLocaleString('es-AR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

/** Centavos a "12,50", para rellenar un input. */
function editable(centavos) {
  return (Number(centavos) / 100).toFixed(2).replace('.', ',');
}

/** Acepta "12,50", "12.50", "$ 1.234,50" y devuelve centavos. */
export function centavosDe(texto) {
  let limpio = String(texto ?? '').trim().replace(/[\s$]/g, '');
  if (!limpio) return null;
  if (limpio.includes(',') && limpio.includes('.')) {
    limpio = limpio.replaceAll('.', '').replace(',', '.');
  } else if (limpio.includes(',')) {
    limpio = limpio.replace(',', '.');
  }
  if (!/^\d{1,10}(\.\d{1,2})?$/.test(limpio)) return null;
  const [entero, decimales = ''] = limpio.split('.');
  return Number.parseInt(entero, 10) * 100 + Number.parseInt(decimales.padEnd(2, '0'), 10);
}

const dos = (n) => String(n).padStart(2, '0');

export function fecha(ms) {
  if (ms == null) return '—';
  const d = new Date(Number(ms));
  return `${dos(d.getDate())}/${dos(d.getMonth() + 1)}/${d.getFullYear()}`;
}

export function fechaHora(ms) {
  if (ms == null) return '—';
  const d = new Date(Number(ms));
  return `${dos(d.getDate())} ${MESES[d.getMonth()]} ${dos(d.getHours())}:${dos(d.getMinutes())}`;
}

export function hace(ms) {
  if (ms == null) return 'nunca';
  const minutos = Math.max(0, Math.round((Date.now() - Number(ms)) / 60_000));
  if (minutos < 1) return 'recién';
  if (minutos < 60) return `hace ${minutos} min`;
  const horas = Math.round(minutos / 60);
  if (horas < 24) return `hace ${horas} h`;
  const dias = Math.round(horas / 24);
  if (dias < 30) return `hace ${dias} d`;
  return fecha(ms);
}

export function iso(ms) {
  const d = new Date(Number(ms));
  return `${d.getFullYear()}-${dos(d.getMonth() + 1)}-${dos(d.getDate())}`;
}

const NAV = [
  { ruta: '/admin', nombre: 'Resumen', clave: 'resumen' },
  { ruta: '/admin/almacen', nombre: 'Almacén', clave: 'almacen' },
  { ruta: '/admin/inventario', nombre: 'Inventario', clave: 'inventario' },
  { ruta: '/admin/cuentas', nombre: 'Cuentas', clave: 'cuentas' },
  { ruta: '/admin/ventas', nombre: 'Ventas', clave: 'ventas' },
];

function aviso(flash) {
  if (!flash?.texto) return '';
  const tipo = flash.tipo === 'error' ? 'error' : 'ok';
  return `<div class="aviso ${tipo}" role="status">${escapar(flash.texto)}</div>`;
}

function documento({ titulo, contenido, activo, csrf, salir = true }) {
  const nav = salir
    ? `<nav class="nav">${NAV.map(
        (item) =>
          `<a href="${item.ruta}"${item.clave === activo ? ' class="activo"' : ''}>${item.nombre}</a>`,
      ).join('')}</nav>`
    : '';
  const botonSalir = salir
    ? `<form method="post" action="/admin/salir" class="salir">
         <input type="hidden" name="csrf" value="${escapar(csrf)}">
         <button type="submit" class="boton fantasma">Salir</button>
       </form>`
    : '';

  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapar(titulo)} · Liznack</title>
<link rel="stylesheet" href="/admin/portal.css?v=${escapar(versionEstaticos)}">
<script src="/admin/portal.js?v=${escapar(versionEstaticos)}" defer></script>
</head>
<body>
<header class="barra">
  <a class="marca" href="/admin"><span class="logo">🍬</span> Liznack <small>portal del administrador</small></a>
  ${nav}
  ${botonSalir}
</header>
<main class="contenido">
${contenido}
</main>
<footer class="pie">Liznack · portal del administrador</footer>
</body>
</html>`;
}

export function paginaIngreso({ error, csrf = '' } = {}) {
  return documento({
    titulo: 'Entrar',
    activo: 'ingreso',
    salir: false,
    contenido: `
<section class="ingreso">
  <div class="tarjeta-ingreso">
    <h1><span class="logo">🍬</span> Liznack</h1>
    <p class="ayuda">Portal del administrador. Entrá con la contraseña del servidor.</p>
    ${aviso(error ? { tipo: 'error', texto: error } : null)}
    <form method="post" action="/admin/entrar">
      <input type="hidden" name="csrf" value="${escapar(csrf)}">
      <label>Contraseña
        <input type="password" name="clave" autocomplete="current-password" required autofocus>
      </label>
      <button type="submit" class="boton primario ancho">Entrar</button>
    </form>
  </div>
</section>`,
  });
}

function tarjeta(etiqueta, valor, pie = '') {
  return `<div class="tarjeta">
    <span class="etiqueta">${escapar(etiqueta)}</span>
    <strong class="valor">${escapar(valor)}</strong>
    ${pie ? `<span class="pie-tarjeta">${escapar(pie)}</span>` : ''}
  </div>`;
}

/** Margen sobre el precio de venta, redondeado. */
function porcentaje(margen, precio) {
  if (!(precio > 0)) return '—';
  return `${Math.round((margen / precio) * 100)}%`;
}

/** Qué se vendió, en una línea: "2× Chocolate · 1× Gomitas". */
function detalleVenta(detalle) {
  if (!detalle || detalle.length === 0) return '<span class="tenue">—</span>';
  return detalle.map((item) => `${item.cantidad}× ${escapar(item.nombre)}`).join(' · ');
}

/** Ganancia de una venta; "sin costo" si falta el costo de algún producto. */
function celdaGanancia(venta) {
  if (venta.anulada) return '<span class="tenue">—</span>';
  if (venta.ganancia == null) {
    return '<span class="tenue" title="Falta el costo de algún producto en el almacén">sin costo</span>';
  }
  return pesos(venta.ganancia);
}

export function paginaResumen({ resumen, cuentas, stockBajo, ventas, flash, csrf }) {
  const filasCuentas = cuentas.length
    ? cuentas
        .map(
          (c) => `<tr>
      <td><a href="/admin/cuenta/${encodeURIComponent(c.id)}">${escapar(c.email)}</a></td>
      <td class="num">${c.activos}/${c.productos}</td>
      <td class="num">${c.stock}</td>
      <td class="num">${pesos(c.hoy)}</td>
      <td class="num">${pesos(c.total)}</td>
      <td class="tenue">${escapar(hace(c.ultima_venta))}</td>
    </tr>`,
        )
        .join('')
    : '<tr><td colspan="6" class="vacio">Todavía no hay cuentas. Creá la primera en <a href="/admin/cuentas">Cuentas</a>.</td></tr>';

  const filasBajo = stockBajo.length
    ? stockBajo
        .map(
          (p) => `<tr>
      <td><a href="/admin/cuenta/${encodeURIComponent(p.usuario_id)}">${escapar(p.nombre)}</a></td>
      <td class="tenue">${escapar(p.email)}</td>
      <td class="num"><span class="chip ${p.stock_actual <= 0 ? 'rojo' : 'ambar'}">${p.stock_actual}</span></td>
    </tr>`,
        )
        .join('')
    : '<tr><td colspan="3" class="vacio">Nada por agotarse. 👌</td></tr>';

  const filasVentas = ventas.length
    ? ventas
        .map(
          (v) => `<tr>
      <td class="tenue">${escapar(fechaHora(v.creado_en))}</td>
      <td><a href="/admin/cuenta/${encodeURIComponent(v.usuario_id)}">${escapar(v.email)}</a></td>
      <td>${detalleVenta(v.detalle)}${v.anulada ? ' <span class="chip rojo">anulada</span>' : ''}</td>
      <td class="num">${pesos(v.total_centavos)}</td>
    </tr>`,
        )
        .join('')
    : '<tr><td colspan="4" class="vacio">Todavía no hay ventas.</td></tr>';

  return documento({
    titulo: 'Resumen',
    activo: 'resumen',
    csrf,
    contenido: `
<h1>Resumen</h1>
${aviso(flash)}
<section class="tarjetas">
  ${tarjeta('Vendido hoy', pesos(resumen.hoy.plata), `${resumen.hoy.ventas} ventas`)}
  ${tarjeta('Ganancia hoy', pesos(resumen.hoy.ganancia), resumen.hoy.sinCosto ? `${resumen.hoy.sinCosto} ${resumen.hoy.sinCosto === 1 ? 'venta' : 'ventas'} sin costo` : 'venta − compra')}
  ${tarjeta('Últimos 7 días', pesos(resumen.semana.plata), `${resumen.semana.ventas} ventas`)}
  ${tarjeta('Ganancia 7 días', pesos(resumen.semana.ganancia), resumen.semana.sinCosto ? `${resumen.semana.sinCosto} ${resumen.semana.sinCosto === 1 ? 'venta' : 'ventas'} sin costo` : 'venta − compra')}
  ${tarjeta('Cuentas', String(resumen.cuentas), 'en este servidor')}
  ${tarjeta('Productos activos', String(resumen.productos), `${resumen.stock} unidades en stock`)}
</section>

<section class="panel">
  <h2>Cuentas</h2>
  <div class="tabla-scroll">
  <table class="tabla">
    <thead><tr><th>Cuenta</th><th class="num">Activos</th><th class="num">Stock</th><th class="num">Hoy</th><th class="num">Total</th><th>Última venta</th></tr></thead>
    <tbody>${filasCuentas}</tbody>
  </table>
  </div>
</section>

<div class="dos-columnas">
  <section class="panel">
    <h2>Stock bajo</h2>
    <div class="tabla-scroll">
    <table class="tabla">
      <thead><tr><th>Producto</th><th>Cuenta</th><th class="num">Quedan</th></tr></thead>
      <tbody>${filasBajo}</tbody>
    </table>
    </div>
  </section>

  <section class="panel">
    <h2>Últimas ventas</h2>
    <div class="tabla-scroll">
    <table class="tabla">
      <thead><tr><th>Cuándo</th><th>Cuenta</th><th>Qué se vendió</th><th class="num">Total</th></tr></thead>
      <tbody>${filasVentas}</tbody>
    </table>
    </div>
  </section>
</div>`,
  });
}

export function paginaCuentas({ cuentas, flash, csrf, valores = {} }) {
  const filas = cuentas.length
    ? cuentas
        .map(
          (c) => `<tr>
      <td><a href="/admin/cuenta/${encodeURIComponent(c.id)}">${escapar(c.email)}</a><br>
          <small class="tenue">desde ${escapar(fecha(new Date(c.creado_en).getTime()))}</small></td>
      <td class="num">${c.activos}/${c.productos}</td>
      <td class="num">${c.stock}</td>
      <td class="num">${pesos(c.hoy)}</td>
      <td class="num">${pesos(c.total)}</td>
      <td class="tenue">${escapar(hace(c.ultima_venta))}</td>
    </tr>`,
        )
        .join('')
    : '<tr><td colspan="6" class="vacio">Todavía no hay cuentas.</td></tr>';

  return documento({
    titulo: 'Cuentas',
    activo: 'cuentas',
    csrf,
    contenido: `
<h1>Cuentas</h1>
${aviso(flash)}

<section class="panel">
  <h2>Nueva cuenta</h2>
  <p class="ayuda">Sirve para crearle el acceso a un hijo. Después entra desde la app con ese correo y contraseña.</p>
  <form method="post" action="/admin/cuentas" class="formulario en-linea-form">
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <label>Correo
      <input type="email" name="email" value="${escapar(valores.email ?? '')}" required maxlength="160" placeholder="hijo@ejemplo.com">
    </label>
    <label>Contraseña
      <input type="password" name="clave" required minlength="6" maxlength="200" autocomplete="new-password">
    </label>
    <button type="submit" class="boton primario">Crear cuenta</button>
  </form>
</section>

<section class="panel">
  <h2>Todas las cuentas</h2>
  <div class="tabla-scroll">
  <table class="tabla">
    <thead><tr><th>Cuenta</th><th class="num">Activos</th><th class="num">Stock</th><th class="num">Hoy</th><th class="num">Total</th><th>Última venta</th></tr></thead>
    <tbody>${filas}</tbody>
  </table>
  </div>
</section>`,
  });
}

export function paginaAlmacen({ items, resumen, traslados, cuentas, flash, csrf, volver }) {
  const opcionesCuentas = cuentas
    .map((c) => `<option value="${escapar(c.id)}">${escapar(c.email)}</option>`)
    .join('');

  const dialogos = [];
  const filas = items.length
    ? items
        .map((p) => {
          const dialogoEditar = `alm-editar-${p.id}`;
          const dialogoEnviar = `alm-enviar-${p.id}`;
          const donde = p.vendedores.length
            ? `<div class="vendedores">${p.vendedores
                .map(
                  (v) =>
                    `<span class="chip${v.activo ? '' : ' cero'}"${v.activo ? '' : ' title="archivado"'}>${escapar(v.email)} · ${v.stock_actual}</span>`,
                )
                .join('')}</div><small class="tenue">${p.total_vendedores} en total</small>`
            : '<span class="tenue">nadie todavía</span>';

          dialogos.push(`<dialog class="modal" id="${dialogoEditar}">
  <form method="post" action="/admin/almacen/${encodeURIComponent(p.id)}/editar">
    <h3>Editar producto del almacén</h3>
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <input type="hidden" name="volver" value="${escapar(volver)}">
    <label>Nombre <input name="nombre" value="${escapar(p.nombre)}" required maxlength="80"></label>
    <label>Costo de compra <input name="costo" value="${editable(p.costo_centavos)}" required inputmode="decimal"></label>
    <label>Precio de venta <input name="precio" value="${editable(p.precio_centavos)}" required inputmode="decimal"></label>
    <div class="modal-acciones">
      <button type="button" class="boton fantasma" data-cerrar>Cerrar</button>
      <button type="submit" class="boton primario">Guardar</button>
    </div>
  </form>
</dialog>`);

          if (p.stock > 0 && cuentas.length) {
            dialogos.push(`<dialog class="modal" id="${dialogoEnviar}">
  <form method="post" action="/admin/almacen/${encodeURIComponent(p.id)}/enviar">
    <h3>Enviar a un vendedor</h3>
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <input type="hidden" name="volver" value="${escapar(volver)}">
    <p class="ayuda">Quedan <strong>${p.stock}</strong> de ${escapar(p.nombre)}. Al enviarlos, entran al inventario del vendedor y le llegan al teléfono en la próxima sincronización.</p>
    <label>Vendedor <select name="cuenta" required>${opcionesCuentas}</select></label>
    <label>Cantidad <input type="number" name="cantidad" value="1" min="1" max="${p.stock}" step="1" required class="corto"></label>
    <div class="modal-acciones">
      <button type="button" class="boton fantasma" data-cerrar>Cancelar</button>
      <button type="submit" class="boton primario">Enviar</button>
    </div>
  </form>
</dialog>`);
          }

          return `<tr>
      <td>${escapar(p.nombre)}</td>
      <td class="num">
        <div>${pesos(p.costo_centavos)} → ${pesos(p.precio_centavos)}</div>
        <small class="tenue">+${pesos(p.margen)} · ${porcentaje(p.margen, p.precio_centavos)}</small>
      </td>
      <td class="num"><span class="chip ${p.stock <= 0 ? 'rojo' : p.stock <= 2 ? 'ambar' : 'verde'}">${p.stock}</span></td>
      <td>${donde}</td>
      <td class="acciones">
        <form method="post" action="/admin/almacen/${encodeURIComponent(p.id)}/ingresar" class="formulario-en-linea">
          <input type="hidden" name="csrf" value="${escapar(csrf)}">
          <input type="hidden" name="volver" value="${escapar(volver)}">
          <input type="number" name="cantidad" value="10" step="1" min="-1000000" max="1000000" class="corto" aria-label="Cantidad a ingresar">
          <button type="submit" class="boton mini">Ingresar</button>
        </form>
        ${p.stock > 0 && cuentas.length ? `<button type="button" class="boton mini primario" data-abrir="${dialogoEnviar}">Enviar</button>` : ''}
        <button type="button" class="boton mini" data-abrir="${dialogoEditar}">Editar</button>
        ${p.stock <= 0 ? `<form method="post" action="/admin/almacen/${encodeURIComponent(p.id)}/quitar" class="formulario-en-linea">
          <input type="hidden" name="csrf" value="${escapar(csrf)}">
          <input type="hidden" name="volver" value="${escapar(volver)}">
          <button type="submit" class="boton mini peligro" data-confirmar="${escapar(`Se quita ${p.nombre} del almacén y su historial de envíos. ¿Seguir?`)}">Quitar</button>
        </form>` : ''}
      </td>
    </tr>`;
        })
        .join('')
    : '<tr><td colspan="5" class="vacio">El almacén está vacío. Cargá el primer producto abajo.</td></tr>';

  const filasTraslados = traslados.length
    ? traslados
        .map(
          (t) => `<tr>
      <td class="tenue">${escapar(fechaHora(new Date(t.creado_en).getTime()))}</td>
      <td>${escapar(t.producto)}</td>
      <td><a href="/admin/cuentas">${escapar(t.email)}</a></td>
      <td class="num">+${t.cantidad}</td>
    </tr>`,
        )
        .join('')
    : '<tr><td colspan="4" class="vacio">Todavía no se envió nada a los vendedores.</td></tr>';

  return documento({
    titulo: 'Almacén',
    activo: 'almacen',
    csrf,
    contenido: `
<h1>Almacén</h1>
${aviso(flash)}
<p class="ayuda">Lo que hay en el depósito y en qué vendedor está cada producto. Al enviarlo, sale del almacén y entra al inventario del vendedor.</p>
${cuentas.length === 0 ? '<p class="ayuda">Todavía no hay cuentas de vendedor: creá una en <a href="/admin/cuentas">Cuentas</a> para poder enviarles stock.</p>' : ''}

<section class="tarjetas">
  ${tarjeta('Productos', String(resumen.productos), 'en el depósito')}
  ${tarjeta('Unidades', String(resumen.unidades), 'disponibles')}
  ${tarjeta('Invertido', pesos(resumen.invertido), 'costo × unidades')}
  ${tarjeta('Valor de venta', pesos(resumen.valor), 'precio × unidades')}
  ${tarjeta('Ganancia', pesos(resumen.ganancia), 'si se vende todo')}
</section>

<section class="panel">
  <div class="tabla-scroll">
  <table class="tabla compacta">
    <thead><tr><th>Producto</th><th class="num">Compra → venta</th><th class="num">Almacén</th><th>Dónde está</th><th></th></tr></thead>
    <tbody>${filas}</tbody>
  </table>
  </div>
  ${dialogos.join('\n  ')}
</section>

<section class="panel">
  <h2>Agregar al almacén</h2>
  <form method="post" action="/admin/almacen" class="formulario en-linea-form">
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <input type="hidden" name="volver" value="${escapar(volver)}">
    <label>Nombre <input name="nombre" required maxlength="80" placeholder="Chocolate"></label>
    <label>Costo <input name="costo" required inputmode="decimal" placeholder="8,00"></label>
    <label>Precio <input name="precio" required inputmode="decimal" placeholder="12,50"></label>
    <label>Stock inicial <input type="number" name="stock" value="0" step="1" min="0" max="1000000" required></label>
    <button type="submit" class="boton primario">Agregar</button>
  </form>
</section>

<section class="panel">
  <h2>Últimos envíos a vendedores</h2>
  <div class="tabla-scroll">
  <table class="tabla">
    <thead><tr><th>Cuándo</th><th>Producto</th><th>Vendedor</th><th class="num">Cantidad</th></tr></thead>
    <tbody>${filasTraslados}</tbody>
  </table>
  </div>
</section>`,
  });
}

export function paginaInventario({ productos, totales, cuentas, filtros, flash, csrf, volver }) {
  const opcionesCuentas = cuentas
    .map(
      (c) =>
        `<option value="${escapar(c.id)}"${c.id === filtros.usuarioId ? ' selected' : ''}>${escapar(c.email)}</option>`,
    )
    .join('');

  const dialogos = [];
  const filas = productos.length
    ? productos
        .map((p) => {
          const cuentaId = encodeURIComponent(p.usuario_id);
          const base = `/admin/cuenta/${cuentaId}/producto/${encodeURIComponent(p.id)}`;
          const dialogoId = `inv-editar-${p.id}`;
          dialogos.push(`<dialog class="modal" id="${dialogoId}">
  <form method="post" action="${base}">
    <h3>Editar producto</h3>
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <input type="hidden" name="volver" value="${escapar(volver)}">
    <label>Cuenta <input type="text" value="${escapar(p.email)}" disabled></label>
    <label>Nombre <input name="nombre" value="${escapar(p.nombre)}" required maxlength="80"></label>
    <label>Precio <input name="precio" value="${(p.precio_centavos / 100).toFixed(2).replace('.', ',')}" required inputmode="decimal"></label>
    <label class="check"><input type="checkbox" name="activo" value="1"${p.activo ? ' checked' : ''}> Activo (se puede vender)</label>
    <div class="modal-acciones">
      <button type="button" class="boton fantasma" data-cerrar>Cerrar</button>
      <button type="submit" class="boton primario">Guardar</button>
    </div>
  </form>
</dialog>`);
          return `<tr>
      <td>${escapar(p.nombre)}${p.activo ? '' : ' <span class="chip gris">archivado</span>'}</td>
      <td><a href="/admin/cuenta/${cuentaId}">${escapar(p.email)}</a></td>
      <td class="num">${pesos(p.precio_centavos)}</td>
      <td class="num"><span class="chip ${p.stock_actual <= 0 ? 'rojo' : p.stock_actual <= 2 ? 'ambar' : 'verde'}">${p.stock_actual}</span></td>
      <td class="acciones">
        <button type="button" class="boton mini" data-abrir="${dialogoId}">Editar</button>
        <form method="post" action="${base}/reponer" class="formulario-en-linea">
          <input type="hidden" name="csrf" value="${escapar(csrf)}">
          <input type="hidden" name="volver" value="${escapar(volver)}">
          <input type="number" name="cantidad" value="10" step="1" min="-1000000" max="1000000" class="corto" aria-label="Cantidad a reponer">
          <button type="submit" class="boton mini">Reponer</button>
        </form>
        <form method="post" action="${base}/estado" class="formulario-en-linea">
          <input type="hidden" name="csrf" value="${escapar(csrf)}">
          <input type="hidden" name="volver" value="${escapar(volver)}">
          <input type="hidden" name="activo" value="${p.activo ? '0' : '1'}">
          <button type="submit" class="boton mini${p.activo ? '' : ' primario'}">${p.activo ? 'Archivar' : 'Reactivar'}</button>
        </form>
      </td>
    </tr>`;
        })
        .join('')
    : '<tr><td colspan="5" class="vacio">No hay productos con esos filtros.</td></tr>';

  const alta = cuentas.length
    ? `<form method="post" action="/admin/inventario/producto" class="formulario en-linea-form">
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <input type="hidden" name="volver" value="${escapar(volver)}">
    <label>Cuenta
      <select name="cuenta" required>
        ${cuentas
          .map(
            (c) =>
              `<option value="${escapar(c.id)}"${c.id === filtros.usuarioId ? ' selected' : ''}>${escapar(c.email)}</option>`,
          )
          .join('')}
      </select>
    </label>
    <label>Nombre <input name="nombre" required maxlength="80" placeholder="Chocolate"></label>
    <label>Precio <input name="precio" required inputmode="decimal" placeholder="12,50"></label>
    <label>Stock inicial <input type="number" name="stock" value="0" step="1" min="-1000000" max="1000000" required></label>
    <button type="submit" class="boton primario">Agregar</button>
  </form>`
    : '<p class="ayuda">Primero creá una cuenta en <a href="/admin/cuentas">Cuentas</a>: los productos pertenecen a una cuenta.</p>';

  return documento({
    titulo: 'Inventario',
    activo: 'inventario',
    csrf,
    contenido: `
<h1>Inventario</h1>
${aviso(flash)}

<section class="tarjetas">
  ${tarjeta('Productos', String(totales.productos), 'con estos filtros')}
  ${tarjeta('Unidades', String(totales.unidades), 'en stock')}
  ${tarjeta('Valor del stock', pesos(totales.valor), 'precio × unidades')}
  ${tarjeta('Agotados', String(totales.agotados), 'sin unidades')}
</section>

<section class="panel">
  <form method="get" action="/admin/inventario" class="formulario en-linea-form">
    <label>Cuenta
      <select name="cuenta"><option value="">Todas</option>${opcionesCuentas}</select>
    </label>
    <label>Buscar <input type="search" name="buscar" value="${escapar(filtros.busqueda ?? '')}" placeholder="nombre del producto" maxlength="80"></label>
    <label class="check"><input type="checkbox" name="solo_bajo" value="1"${filtros.soloBajo ? ' checked' : ''}> Solo stock bajo</label>
    <label class="check"><input type="checkbox" name="archivados" value="1"${filtros.incluirArchivados ? ' checked' : ''}> Incluir archivados</label>
    <button type="submit" class="boton primario">Filtrar</button>
    <a class="boton fantasma" href="/admin/inventario">Limpiar</a>
  </form>
</section>

<section class="panel">
  <div class="tabla-scroll">
  <table class="tabla">
    <thead><tr><th>Producto</th><th>Cuenta</th><th class="num">Precio</th><th class="num">Stock</th><th></th></tr></thead>
    <tbody>${filas}</tbody>
  </table>
  </div>
  ${dialogos.join('\n  ')}
</section>

<section class="panel">
  <h2>Agregar producto</h2>
  ${alta}
</section>`,
  });
}

export function paginaCuenta({ cuenta, productos, ventas, items, movimientos, flash, csrf }) {
  const dialogos = [];
  const filasProductos = productos.length
    ? productos
        .map((p) => {
          const base = `/admin/cuenta/${encodeURIComponent(cuenta.id)}/producto/${encodeURIComponent(p.id)}`;
          const dialogoId = `editar-${p.id}`;
          dialogos.push(`<dialog class="modal" id="${dialogoId}">
  <form method="post" action="${base}">
    <h3>Editar producto</h3>
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <label>Nombre <input name="nombre" value="${escapar(p.nombre)}" required maxlength="80"></label>
    <label>Precio <input name="precio" value="${(p.precio_centavos / 100).toFixed(2).replace('.', ',')}" required inputmode="decimal"></label>
    <label class="check"><input type="checkbox" name="activo" value="1"${p.activo ? ' checked' : ''}> Activo (se puede vender)</label>
    <div class="modal-acciones">
      <button type="button" class="boton fantasma" data-cerrar>Cerrar</button>
      <button type="submit" class="boton primario">Guardar</button>
    </div>
  </form>
</dialog>`);
          return `<tr>
      <td>${escapar(p.nombre)}${p.activo ? '' : ' <span class="chip gris">archivado</span>'}</td>
      <td class="num">${pesos(p.precio_centavos)}</td>
      <td class="num"><span class="chip ${p.stock_actual <= 0 ? 'rojo' : p.stock_actual <= 2 ? 'ambar' : 'verde'}">${p.stock_actual}</span></td>
      <td class="acciones">
        <button type="button" class="boton mini" data-abrir="${dialogoId}">Editar</button>
        <form method="post" action="${base}/reponer" class="formulario-en-linea">
          <input type="hidden" name="csrf" value="${escapar(csrf)}">
          <input type="number" name="cantidad" value="10" step="1" min="-1000000" max="1000000" class="corto" aria-label="Cantidad a reponer">
          <button type="submit" class="boton mini">Reponer</button>
        </form>
      </td>
    </tr>`;
        })
        .join('')
    : '<tr><td colspan="4" class="vacio">Sin productos. Cargá el primero abajo.</td></tr>';

  const filasVentas = ventas.length
    ? ventas
        .map((v) => {
          const base = `/admin/cuenta/${encodeURIComponent(cuenta.id)}/venta/${encodeURIComponent(v.id)}`;
          const detalle = (items.get(v.id) ?? [])
            .map(
              (i) =>
                `<li>${i.cantidad} × ${escapar(i.nombre)} <span class="tenue">${pesos(i.precio_centavos)}</span></li>`,
            )
            .join('');
          return `<tr>
      <td class="tenue">${escapar(fechaHora(v.creado_en))}</td>
      <td class="num">${pesos(v.total_centavos)}</td>
      <td class="num">${celdaGanancia(v)}</td>
      <td>${v.anulada ? '<span class="chip rojo">anulada</span>' : '<span class="chip verde">cobrada</span>'}</td>
      <td class="acciones">
        <details><summary class="boton mini">${v.items} ítem${v.items === 1 ? '' : 's'}</summary><ul class="items">${detalle}</ul></details>
        ${v.anulada ? '' : `<form method="post" action="${base}/anular" class="formulario-en-linea">
          <input type="hidden" name="csrf" value="${escapar(csrf)}">
          <button type="submit" class="boton mini peligro" data-confirmar="¿Anular esta venta? El stock vuelve a la cuenta.">Anular</button>
        </form>`}
      </td>
    </tr>`;
        })
        .join('')
    : '<tr><td colspan="4" class="vacio">Sin ventas todavía.</td></tr>';

  const filasMovimientos = movimientos.length
    ? movimientos
        .map(
          (m) => `<tr>
      <td class="tenue">${escapar(fechaHora(m.creado_en))}</td>
      <td>${escapar(m.producto)}</td>
      <td class="num ${m.cantidad < 0 ? 'rojo-texto' : 'verde-texto'}">${m.cantidad > 0 ? '+' : ''}${m.cantidad}</td>
      <td class="tenue">${escapar(m.motivo)}</td>
    </tr>`,
        )
        .join('')
    : '<tr><td colspan="4" class="vacio">Sin reposiciones.</td></tr>';

  const stockTotal = productos.reduce((s, p) => s + (p.activo ? p.stock_actual : 0), 0);
  const vendidoHoy = ventas
    .filter((v) => !v.anulada && v.creado_en >= inicioDia())
    .reduce((s, v) => s + v.total_centavos, 0);

  return documento({
    titulo: cuenta.email,
    activo: 'cuentas',
    csrf,
    contenido: `
<p class="migas"><a href="/admin/cuentas">Cuentas</a> / ${escapar(cuenta.email)}</p>
<h1>${escapar(cuenta.email)}</h1>
${aviso(flash)}

<section class="tarjetas">
  ${tarjeta('Stock activo', String(stockTotal), `${productos.filter((p) => p.activo).length} productos`)}
  ${tarjeta('Vendido hoy', pesos(vendidoHoy), '')}
  ${tarjeta('Ventas registradas', String(ventas.length), 'últimas 50')}
  ${tarjeta('Creada', fecha(new Date(cuenta.creado_en).getTime()), '')}
</section>

<section class="panel">
  <h2>Productos</h2>
  <div class="tabla-scroll">
  <table class="tabla">
    <thead><tr><th>Producto</th><th class="num">Precio</th><th class="num">Stock</th><th></th></tr></thead>
    <tbody>${filasProductos}</tbody>
  </table>
  </div>
  ${dialogos.join('\n  ')}
  <h3>Agregar producto</h3>
  <form method="post" action="/admin/cuenta/${encodeURIComponent(cuenta.id)}/producto" class="formulario en-linea-form">
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <label>Nombre <input name="nombre" required maxlength="80" placeholder="Chocolate"></label>
    <label>Precio <input name="precio" required inputmode="decimal" placeholder="12,50"></label>
    <label>Stock inicial <input type="number" name="stock" value="0" step="1" min="-1000000" max="1000000" required></label>
    <button type="submit" class="boton primario">Agregar</button>
  </form>
</section>

<section class="panel">
  <h2>Ventas</h2>
  <div class="tabla-scroll">
  <table class="tabla">
    <thead><tr><th>Cuándo</th><th class="num">Total</th><th class="num">Ganancia</th><th>Estado</th><th></th></tr></thead>
    <tbody>${filasVentas}</tbody>
  </table>
  </div>
</section>

<section class="panel">
  <h2>Reposiciones y ajustes</h2>
  <div class="tabla-scroll">
  <table class="tabla">
    <thead><tr><th>Cuándo</th><th>Producto</th><th class="num">Cantidad</th><th>Motivo</th></tr></thead>
    <tbody>${filasMovimientos}</tbody>
  </table>
  </div>
</section>

<section class="panel peligro-panel">
  <h2>Cuenta</h2>
  <form method="post" action="/admin/cuenta/${encodeURIComponent(cuenta.id)}/clave" class="formulario en-linea-form">
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <label>Nueva contraseña
      <input type="password" name="clave" minlength="6" maxlength="200" required autocomplete="new-password">
    </label>
    <button type="submit" class="boton">Cambiar contraseña</button>
  </form>
  <p class="ayuda">Al cambiarla se cierran las sesiones abiertas: el teléfono tiene que volver a entrar.</p>

  <hr>
  <h3>Borrar cuenta</h3>
  <p class="ayuda">Se borran sus productos, ventas y reposiciones de este servidor. No se puede deshacer.</p>
  <form method="post" action="/admin/cuenta/${encodeURIComponent(cuenta.id)}/borrar" class="formulario en-linea-form">
    <input type="hidden" name="csrf" value="${escapar(csrf)}">
    <label><span>Escribí <strong>${escapar(cuenta.email)}</strong> para confirmar</span>
      <input name="confirmacion" required autocomplete="off" spellcheck="false">
    </label>
    <button type="submit" class="boton peligro" data-confirmar="Se borra la cuenta y todos sus datos. ¿Seguir?">Borrar cuenta</button>
  </form>
</section>`,
  });
}

export function paginaVentas({
  ventas,
  total,
  cantidad,
  gananciaTotal = 0,
  sinCosto = 0,
  cuentas,
  filtros,
  flash,
  csrf,
}) {
  const opciones = cuentas
    .map(
      (c) =>
        `<option value="${escapar(c.id)}"${c.id === filtros.usuarioId ? ' selected' : ''}>${escapar(c.email)}</option>`,
    )
    .join('');

  const filas = ventas.length
    ? ventas
        .map(
          (v) => `<tr>
      <td class="tenue">${escapar(fechaHora(v.creado_en))}</td>
      <td><a href="/admin/cuenta/${encodeURIComponent(v.usuario_id)}">${escapar(v.email)}</a></td>
      <td>${detalleVenta(v.detalle)}</td>
      <td class="num">${pesos(v.total_centavos)}</td>
      <td class="num">${celdaGanancia(v)}</td>
      <td>${v.anulada ? '<span class="chip rojo">anulada</span>' : '<span class="chip verde">cobrada</span>'}</td>
    </tr>`,
        )
        .join('')
    : '<tr><td colspan="6" class="vacio">No hay ventas en ese período.</td></tr>';

  return documento({
    titulo: 'Ventas',
    activo: 'ventas',
    csrf,
    contenido: `
<h1>Ventas</h1>
${aviso(flash)}

<section class="panel">
  <form method="get" action="/admin/ventas" class="formulario en-linea-form">
    <label>Cuenta
      <select name="cuenta"><option value="">Todas</option>${opciones}</select>
    </label>
    <label>Desde <input type="date" name="desde" value="${escapar(filtros.desde ?? '')}"></label>
    <label>Hasta <input type="date" name="hasta" value="${escapar(filtros.hasta ?? '')}"></label>
    <button type="submit" class="boton primario">Filtrar</button>
    <a class="boton fantasma" href="/admin/ventas">Limpiar</a>
  </form>
</section>

<section class="tarjetas">
  ${tarjeta('Recaudado', pesos(total), `${cantidad} ventas cobradas`)}
  ${tarjeta('Ganancia', pesos(gananciaTotal), sinCosto ? `${sinCosto} ${sinCosto === 1 ? 'venta' : 'ventas'} sin costo` : 'venta − compra')}
</section>

<section class="panel">
  <div class="tabla-scroll">
  <table class="tabla">
    <thead><tr><th>Cuándo</th><th>Cuenta</th><th>Qué se vendió</th><th class="num">Total</th><th class="num">Ganancia</th><th>Estado</th></tr></thead>
    <tbody>${filas}</tbody>
  </table>
  </div>
</section>`,
  });
}

export function paginaError({ codigo, mensaje, csrf }) {
  return documento({
    titulo: `Error ${codigo}`,
    activo: '',
    csrf,
    contenido: `
<section class="panel">
  <h1>Algo salió mal</h1>
  <p class="aviso error">${escapar(mensaje)}</p>
  <p><a class="boton" href="/admin">Volver al resumen</a></p>
</section>`,
  });
}

export function paginaSinPortal() {
  return `<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>Portal desactivado</title><style>
body{font-family:system-ui,sans-serif;background:#FFF8F4;color:#3E2723;display:grid;place-items:center;height:100vh;margin:0}
div{max-width:34rem;background:#fff;padding:2rem;border-radius:16px;box-shadow:0 10px 30px rgba(62,39,35,.08)}
code{background:#FFE3EC;padding:.15rem .4rem;border-radius:6px}
</style></head><body><div>
<h1>Portal desactivado</h1>
<p>Para usar el portal del administrador, arrancá el servidor con una contraseña:</p>
<p><code>LIZNACK_ADMIN=tu-clave npm start</code></p>
</div></body></html>`;
}

function inicioDia() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

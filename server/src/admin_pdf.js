/**
 * Reportes en PDF del portal: la lista de ventas y el comprobante de una venta.
 * Todo se dibuja con `pdf.js` (sin dependencias) sobre una hoja A4.
 */
import { ALTO_A4, ANCHO_A4, Pdf } from './pdf.js';

const MARGEN = 48;
const DERECHA = ANCHO_A4 - MARGEN;
const MESES = 'ene feb mar abr may jun jul ago sep oct nov dic'.split(' ');

const dos = (n) => String(n).padStart(2, '0');

function money(centavos) {
  const valor = (Number(centavos) || 0) / 100;
  return `$ ${valor.toLocaleString('es-AR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

function fechaHora(ms) {
  const d = new Date(Number(ms));
  return `${dos(d.getDate())} ${MESES[d.getMonth()]} ${dos(d.getHours())}:${dos(d.getMinutes())}`;
}

function fechaLarga(d = new Date()) {
  return `${dos(d.getDate())}/${dos(d.getMonth() + 1)}/${d.getFullYear()} ${dos(d.getHours())}:${dos(d.getMinutes())}`;
}

function diaLegible(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso ?? ''));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : null;
}

function periodo(desde, hasta) {
  const d = diaLegible(desde);
  const h = diaLegible(hasta);
  if (d && h) return d === h ? `Día ${d}` : `Del ${d} al ${h}`;
  if (d) return `Desde el ${d}`;
  if (h) return `Hasta el ${h}`;
  return 'Todo el historial';
}

function cabecera(pdf, titulo, subtitulo) {
  pdf.texto('Liznack', MARGEN, ALTO_A4 - 58, { tamano: 21, negrita: true });
  pdf.texto('Portal del administrador', MARGEN, ALTO_A4 - 74, { tamano: 9, gris: 0.45 });
  pdf.textoDerecha(`Generado ${fechaLarga()}`, DERECHA, ALTO_A4 - 62, { tamano: 8.5, gris: 0.45 });
  pdf.texto(titulo, MARGEN, ALTO_A4 - 112, { tamano: 15, negrita: true });
  if (subtitulo) pdf.texto(subtitulo, MARGEN, ALTO_A4 - 128, { tamano: 9, gris: 0.4 });
  pdf.linea(MARGEN, ALTO_A4 - 142, DERECHA, ALTO_A4 - 142);
  return ALTO_A4 - 168;
}

function bloqueDato(pdf, x, y, etiqueta, valor, ancho) {
  pdf.texto(etiqueta.toUpperCase(), x, y, { tamano: 7.5, gris: 0.45 });
  pdf.texto(valor, x, y - 15, { tamano: 12, negrita: true });
  if (ancho) pdf.linea(x, y - 26, x + ancho, y - 26, { gris: 0.9 });
}

function salto(pdf, y, alto) {
  if (y - alto >= 64) return y;
  pdf.nuevaPagina();
  return ALTO_A4 - 64;
}

/**
 * Reporte de ventas: encabezado, resumen y cada venta con lo que se vendió.
 * `ventas` ya trae `detalle`, `ganancia` y `email` desde admin_datos.
 */
export function reporteVentasPdf({
  ventas = [],
  total = 0,
  cantidad = 0,
  ganancia = 0,
  sinCosto = 0,
  desde = '',
  hasta = '',
  cuenta = null,
}) {
  const pdf = new Pdf({ titulo: 'Reporte de ventas' });
  const detalleCuenta = cuenta ? ` · ${cuenta.email}` : '';
  let y = cabecera(pdf, 'Reporte de ventas', `${periodo(desde, hasta)}${detalleCuenta}`);

  const tercio = (DERECHA - MARGEN - 32) / 3;
  bloqueDato(pdf, MARGEN, y, 'Ventas cobradas', String(cantidad), tercio);
  bloqueDato(pdf, MARGEN + tercio + 16, y, 'Recaudado', money(total), tercio);
  bloqueDato(
    pdf,
    MARGEN + (tercio + 16) * 2,
    y,
    'Ganancia',
    sinCosto ? 'sin costo' : money(ganancia),
    tercio,
  );
  y -= 48;

  if (sinCosto) {
    pdf.texto(
      `${sinCosto} ${sinCosto === 1 ? 'venta' : 'ventas'} sin costo conocido: no se suman a la ganancia.`,
      MARGEN,
      y,
      { tamano: 8.5, gris: 0.45 },
    );
    y -= 16;
  }

  if (ventas.length === 0) {
    pdf.texto('No hay ventas en ese período.', MARGEN, y - 10, { tamano: 11, gris: 0.4 });
    return pdf.construir();
  }

  y -= 6;
  for (const venta of ventas) {
    const items = venta.detalle ?? [];
    const alto = 30 + items.length * 14 + (venta.ganancia !== undefined ? 14 : 0) + (venta.anulada ? 14 : 0);
    y = salto(pdf, y, alto);

    pdf.rectangulo(MARGEN, y - 16, DERECHA - MARGEN, 19, { gris: 0.95 });
    pdf.texto(`${fechaHora(venta.creado_en)} · ${venta.email}`, MARGEN + 6, y - 12, {
      tamano: 9.5,
      negrita: true,
    });
    pdf.textoDerecha(money(venta.total_centavos), DERECHA - 6, y - 12, { tamano: 9.5, negrita: true });
    y -= 28;

    for (const item of items) {
      pdf.texto(`${item.cantidad}× ${item.nombre}`, MARGEN + 10, y, { tamano: 9 });
      pdf.textoDerecha(`${item.cantidad} × ${money(item.precio_centavos)}`, DERECHA - 96, y, {
        tamano: 8.5,
        gris: 0.45,
      });
      pdf.textoDerecha(money(item.cantidad * item.precio_centavos), DERECHA, y, { tamano: 9 });
      y -= 14;
    }

    if (venta.ganancia !== undefined) {
      const texto =
        venta.ganancia == null
          ? 'Ganancia: sin costo'
          : `Ganancia: ${money(venta.ganancia)}`;
      pdf.texto(texto, MARGEN + 10, y, { tamano: 8.5, gris: 0.45 });
      y -= 14;
    }
    if (venta.anulada) {
      pdf.texto('ANULADA (no suma al total)', MARGEN + 10, y, {
        tamano: 8.5,
        color: [0.72, 0.1, 0.14],
      });
      y -= 14;
    }
    pdf.linea(MARGEN, y + 4, DERECHA, y + 4, { gris: 0.9 });
    y -= 10;
  }

  y = salto(pdf, y, 40);
  pdf.linea(MARGEN, y, DERECHA, y, { grosor: 1, gris: 0.55 });
  pdf.texto('Total recaudado', MARGEN, y - 18, { tamano: 11, negrita: true });
  pdf.textoDerecha(money(total), DERECHA, y - 18, { tamano: 12, negrita: true });
  if (!sinCosto) {
    pdf.texto('Ganancia', MARGEN, y - 34, { tamano: 9, gris: 0.45 });
    pdf.textoDerecha(money(ganancia), DERECHA, y - 34, { tamano: 10, negrita: true });
  }

  return pdf.construir();
}

/** Comprobante de una venta, con el detalle ítem por ítem. */
export function ventaPdf({ venta, cuenta, items = venta?.detalle ?? [] }) {
  const pdf = new Pdf({ titulo: 'Comprobante de venta' });
  let y = cabecera(pdf, 'Comprobante de venta', `Venta del ${fechaHora(venta.creado_en)}`);

  pdf.texto('Cuenta', MARGEN, y, { tamano: 7.5, gris: 0.45 });
  pdf.texto(cuenta?.email ?? venta.email ?? '—', MARGEN, y - 15, { tamano: 11, negrita: true });
  pdf.texto('Estado', DERECHA - 120, y, { tamano: 7.5, gris: 0.45 });
  pdf.texto(venta.anulada ? 'Anulada' : 'Cobrada', DERECHA - 120, y - 15, {
    tamano: 11,
    negrita: true,
    color: venta.anulada ? [0.72, 0.1, 0.14] : null,
  });
  y -= 44;
  pdf.linea(MARGEN, y, DERECHA, y, { gris: 0.88 });
  y -= 22;

  pdf.texto('PRODUCTO', MARGEN, y, { tamano: 7.5, gris: 0.45 });
  pdf.textoDerecha('CANT.', DERECHA - 135, y, { tamano: 7.5, gris: 0.45 });
  pdf.textoDerecha('PRECIO', DERECHA - 80, y, { tamano: 7.5, gris: 0.45 });
  pdf.textoDerecha('SUBTOTAL', DERECHA, y, { tamano: 7.5, gris: 0.45 });
  y -= 8;
  pdf.linea(MARGEN, y, DERECHA, y, { gris: 0.88 });
  y -= 16;

  if (items.length === 0) {
    pdf.texto('La venta no tiene ítems guardados.', MARGEN, y, { tamano: 9.5, gris: 0.45 });
    y -= 16;
  }
  for (const item of items) {
    y = salto(pdf, y, 20);
    pdf.texto(item.nombre, MARGEN, y, { tamano: 10 });
    pdf.textoDerecha(String(item.cantidad), DERECHA - 135, y, { tamano: 10 });
    pdf.textoDerecha(money(item.precio_centavos), DERECHA - 80, y, { tamano: 10 });
    pdf.textoDerecha(money(item.cantidad * item.precio_centavos), DERECHA, y, { tamano: 10 });
    y -= 18;
    pdf.linea(MARGEN, y + 5, DERECHA, y + 5, { gris: 0.93 });
  }

  y = salto(pdf, y, 60);
  pdf.linea(MARGEN, y, DERECHA, y, { grosor: 1, gris: 0.55 });
  pdf.texto('TOTAL', MARGEN, y - 20, { tamano: 12, negrita: true });
  pdf.textoDerecha(money(venta.total_centavos), DERECHA, y - 20, { tamano: 15, negrita: true });

  if (venta.ganancia !== undefined && venta.ganancia !== null) {
    pdf.texto('Ganancia', MARGEN, y - 42, { tamano: 9, gris: 0.45 });
    pdf.textoDerecha(money(venta.ganancia), DERECHA, y - 42, { tamano: 10, negrita: true });
  }

  pdf.texto('Comprobante interno de Liznack.', MARGEN, 70, { tamano: 8, gris: 0.5 });
  return pdf.construir();
}

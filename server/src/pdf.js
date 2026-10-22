/**
 * Generador mínimo de PDF (A4) sin dependencias.
 *
 * Usa las fuentes estándar Helvetica y Helvetica-Bold con WinAnsiEncoding, así
 * que alcanza para reportes de texto, líneas y tablas. El contenido se escribe
 * sin comprimir a propósito: los tests pueden buscar el texto dentro del PDF.
 */

export const ANCHO_A4 = 595.28;
export const ALTO_A4 = 841.89;

// Anchos AFM de Helvetica en milésimas de em (para alinear importes a la
// derecha). Los caracteres que faltan usan 556, que es el ancho promedio.
const ANCHOS = {
  ' ': 278, '!': 278, '"': 355, '#': 556, $: 556, '%': 889, '&': 667, "'": 191,
  '(': 333, ')': 333, '*': 389, '+': 584, ',': 278, '-': 333, '.': 278, '/': 278,
  0: 556, 1: 556, 2: 556, 3: 556, 4: 556, 5: 556, 6: 556, 7: 556, 8: 556, 9: 556,
  ':': 278, ';': 278, '<': 584, '=': 584, '>': 584, '?': 556, '@': 1015,
  A: 667, B: 667, C: 722, D: 722, E: 667, F: 611, G: 778, H: 722, I: 278,
  J: 500, K: 667, L: 556, M: 833, N: 722, O: 778, P: 667, Q: 778, R: 722,
  S: 667, T: 611, U: 722, V: 667, W: 944, X: 667, Y: 667, Z: 611,
  '[': 278, '\\': 278, ']': 278, '^': 469, _: 556, '`': 333,
  a: 556, b: 556, c: 500, d: 556, e: 556, f: 278, g: 556, h: 556, i: 222,
  j: 222, k: 500, l: 222, m: 833, n: 556, o: 556, p: 556, q: 556, r: 333,
  s: 500, t: 278, u: 556, v: 500, w: 722, x: 500, y: 500, z: 500,
  '{': 334, '|': 260, '}': 334, '~': 584,
  '·': 278, '×': 584, '°': 400, '—': 1000, '–': 556,
  á: 556, é: 556, í: 278, ó: 556, ú: 556, ñ: 556,
  Á: 667, É: 667, Í: 278, Ó: 778, Ú: 722, Ñ: 722, '¿': 611, '¡': 333,
};

const ANCHO_PROMEDIO = 556;

/** Ancho de un texto, en puntos, para alinear a la derecha. */
export function anchoTexto(texto, tamano = 10) {
  let milesimas = 0;
  for (const caracter of String(texto)) {
    milesimas += ANCHOS[caracter] ?? ANCHO_PROMEDIO;
  }
  return (milesimas * tamano) / 1000;
}

const numero = (valor) => String(Number(Number(valor).toFixed(2)));

/** Escapa el texto para un literal PDF y lo deja en Latin-1 (WinAnsi). */
function literal(texto) {
  const limpio = String(texto ?? '');
  let salida = '';
  for (const caracter of limpio) {
    const codigo = caracter.codePointAt(0);
    if (caracter === '\\' || caracter === '(' || caracter === ')') {
      salida += `\\${caracter}`;
    } else if (codigo < 32) {
      salida += ' ';
    } else if (codigo > 255) {
      salida += '?';
    } else {
      salida += caracter;
    }
  }
  return salida;
}

export class Pdf {
  constructor({ titulo = 'Liznack', pie = true } = {}) {
    this.titulo = titulo;
    this.conPie = pie;
    this.paginas = [];
    this.actual = null;
    this.cerrado = false;
    this.nuevaPagina();
  }

  nuevaPagina() {
    if (this.cerrado) throw new Error('El PDF ya está cerrado.');
    this.actual = { operaciones: [] };
    this.paginas.push(this.actual);
    return this;
  }

  /** Escribe texto en (x, y), con y medida desde el borde inferior. */
  texto(texto, x, y, { tamano = 10, negrita = false, gris = null, color = null } = {}) {
    const fuente = negrita ? 'F2' : 'F1';
    // El color de relleno se fija siempre: si no, el texto hereda el gris del
    // último rectángulo y queda invisible.
    let pintura = '0 0 0 rg ';
    if (color) pintura = `${numero(color[0])} ${numero(color[1])} ${numero(color[2])} rg `;
    else if (gris != null) pintura = `${numero(gris)} ${numero(gris)} ${numero(gris)} rg `;
    this.actual.operaciones.push(
      `BT ${pintura}/${fuente} ${numero(tamano)} Tf 1 0 0 1 ${numero(x)} ${numero(y)} Tm (${literal(texto)}) Tj ET`,
    );
    return this;
  }

  /** Texto alineado a la derecha en `derecha`. */
  textoDerecha(texto, derecha, y, opciones = {}) {
    const ancho = anchoTexto(texto, opciones.tamano ?? 10);
    return this.texto(texto, derecha - ancho, y, opciones);
  }

  /** Texto centrado entre dos x. */
  textoCentrado(texto, centro, y, opciones = {}) {
    const ancho = anchoTexto(texto, opciones.tamano ?? 10);
    return this.texto(texto, centro - ancho / 2, y, opciones);
  }

  linea(x1, y1, x2, y2, { grosor = 0.6, gris = 0.8 } = {}) {
    this.actual.operaciones.push(
      `${numero(grosor)} w ${numero(gris)} ${numero(gris)} ${numero(gris)} RG ` +
        `${numero(x1)} ${numero(y1)} m ${numero(x2)} ${numero(y2)} l S`,
    );
    return this;
  }

  rectangulo(x, y, ancho, alto, { gris = 0.95 } = {}) {
    this.actual.operaciones.push(
      `${numero(gris)} ${numero(gris)} ${numero(gris)} rg ${numero(x)} ${numero(y)} ` +
        `${numero(ancho)} ${numero(alto)} re f`,
    );
    return this;
  }

  /** Arma el archivo PDF completo. */
  construir() {
    this.cerrado = true;
    if (this.conPie) {
      const total = this.paginas.length;
      this.paginas.forEach((pagina, indice) => {
        pagina.operaciones.push(
          `0.75 w 0.82 0.82 0.82 RG 48 42 m ${numero(ANCHO_A4 - 48)} 42 l S`,
          `BT /F1 8 Tf 1 0 0 1 48 ${numero(28)} Tm (Liznack) Tj ET`,
        );
        const pie = `Página ${indice + 1} de ${total}`;
        const ancho = anchoTexto(pie, 8);
        pagina.operaciones.push(
          `BT /F1 8 Tf 1 0 0 1 ${numero(ANCHO_A4 - 48 - ancho)} ${numero(28)} Tm (${literal(pie)}) Tj ET`,
        );
      });
    }

    const objetos = [];
    const sumar = (texto) => {
      objetos.push(Buffer.from(texto, 'latin1'));
      return objetos.length;
    };

    // 1 catálogo · 2 páginas · 3 Helvetica · 4 Helvetica-Bold · 5 Courier.
    sumar('<< /Type /Catalog /Pages 2 0 R >>');
    sumar(''); // se completa al final
    sumar('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
    sumar('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
    sumar('<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>');

    const idsPaginas = [];
    for (const pagina of this.paginas) {
      const contenido = pagina.operaciones.join('\n');
      const idContenido = sumar(
        `<< /Length ${Buffer.byteLength(contenido, 'latin1')} >>\nstream\n${contenido}\nendstream`,
      );
      const idPagina = sumar(
        `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${numero(ANCHO_A4)} ${numero(ALTO_A4)}] ` +
          '/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> ' +
          `/Contents ${idContenido} 0 R >>`,
      );
      idsPaginas.push(idPagina);
    }
    objetos[1] = Buffer.from(
      `<< /Type /Pages /Kids [${idsPaginas.map((id) => `${id} 0 R`).join(' ')}] /Count ${idsPaginas.length} >>`,
      'latin1',
    );
    sumar(
      `<< /Title (${literal(this.titulo)}) /Producer (Liznack) /Creator (Liznack) >>`,
    );

    const partes = [Buffer.from('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n', 'latin1')];
    let offset = partes[0].length;
    const posiciones = [];
    objetos.forEach((cuerpo, indice) => {
      const id = indice + 1;
      posiciones[id] = offset;
      const bloque = Buffer.from(`${id} 0 obj\n`, 'latin1');
      const fin = Buffer.from('\nendobj\n', 'latin1');
      partes.push(bloque, cuerpo, fin);
      offset += bloque.length + cuerpo.length + fin.length;
    });

    const inicioXref = offset;
    let xref = `xref\n0 ${objetos.length + 1}\n0000000000 65535 f \n`;
    for (let id = 1; id <= objetos.length; id += 1) {
      xref += `${String(posiciones[id]).padStart(10, '0')} 00000 n \n`;
    }
    xref += `trailer\n<< /Size ${objetos.length + 1} /Root 1 0 R /Info ${objetos.length} 0 R >>\n`;
    xref += `startxref\n${inicioXref}\n%%EOF\n`;
    partes.push(Buffer.from(xref, 'latin1'));

    return Buffer.concat(partes);
  }
}

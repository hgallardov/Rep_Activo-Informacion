#!/usr/bin/env node
'use strict';
/**
 * Convierte un manual Markdown de docs/ a Word (.docx) con formato corporativo:
 * portada, hoja de control, índice, encabezado con clasificación, pie con numeración,
 * tablas con encabezado repetido, bloques de código y recuadros de verificación / evidencia / hito.
 *
 * Uso:  node tools/md_to_docx.js docs/07_Manual_de_Implementacion_Paso_a_Paso.md docs/07_Manual_de_Implementacion_Paso_a_Paso.docx
 * Soporta el subconjunto de Markdown usado en docs/: #, ##, ###, párrafos, listas "- ", tablas "|", ``` código,
 * "> " citas, **negrita**, *cursiva*, `código` y [vínculos](url).
 */
const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  HeadingLevel, AlignmentType, Header, Footer, PageNumber, TableOfContents, ExternalHyperlink, LevelFormat,
  PageBreak, TabStopType, VerticalAlign,
} = require('docx');

const [, , entrada, salida] = process.argv;
if (!entrada || !salida) { console.error('Uso: node tools/md_to_docx.js <entrada.md> <salida.docx>'); process.exit(1); }
const lineas = fs.readFileSync(entrada, 'utf8').replace(/\r/g, '').split('\n');

// ---------- Estilo ----------
const FUENTE = 'Calibri';
const MONO = 'Consolas';
const AZUL = '1F3864';
const AZUL_CLARO = 'D9E2F3';
const GRIS = 'F2F2F2';
const ANCHO = 11906 - 2 * 1134; // A4 menos márgenes de 2 cm = 9638 DXA
const borde = { style: BorderStyle.SINGLE, size: 4, color: 'BFBFBF' };
const bordes = { top: borde, bottom: borde, left: borde, right: borde };

// ---------- Texto en línea ----------
function inline(texto, base = {}) {
  texto = texto.replace(/🔍\s*/g, '').replace(/📁\s*/g, '').replace(/🏁\s*/g, '');
  const runs = [];
  const re = /(\*\*([^*]+)\*\*|`([^`]+)`|\*([^*\s][^*]*)\*|\[([^\]]+)\]\(([^)]+)\))/g;
  let ultimo = 0; let m;
  const push = (t, extra = {}) => { if (t) runs.push(new TextRun({ text: t, font: FUENTE, ...base, ...extra })); };
  while ((m = re.exec(texto)) !== null) {
    push(texto.slice(ultimo, m.index));
    if (m[2]) push(m[2], { bold: true });
    else if (m[3]) push(m[3], { font: MONO, size: Math.max((base.size || 21) - 2, 15), color: '7B2C2C' });
    else if (m[4]) push(m[4], { italics: true });
    else if (m[5]) {
      if (/^https?:/.test(m[6])) {
        runs.push(new ExternalHyperlink({ link: m[6], children: [new TextRun({ text: m[5], style: 'Hyperlink', font: FUENTE, ...base })] }));
      } else {
        push(m[5].replace(/`/g, ''), { font: MONO, size: Math.max((base.size || 21) - 2, 15), color: '7B2C2C' });
      }
    }
    ultimo = re.lastIndex;
  }
  push(texto.slice(ultimo));
  return runs;
}

// ---------- Bloques especiales ----------
function recuadro(texto, etiqueta, colorFondo, colorBorde) {
  const b = { style: BorderStyle.SINGLE, size: 12, color: colorBorde, space: 4 };
  return new Paragraph({
    children: [new TextRun({ text: etiqueta ? `${etiqueta} ` : '', bold: true, font: FUENTE, size: 20, color: colorBorde }), ...inline(texto, { size: 20 })],
    shading: { type: ShadingType.CLEAR, fill: colorFondo, color: 'auto' },
    border: { left: b },
    indent: { left: 120 },
    spacing: { before: 100, after: 140 },
  });
}

function tabla(filas) {
  const celdas = filas.map((f) => f.replace(/^\|/, '').replace(/\|\s*$/, '').split('|').map((c) => c.trim()));
  const nCol = celdas[0].length;
  const datos = celdas.filter((_, i) => i !== 1); // sin separador ---
  // Anchos proporcionales al contenido (con mínimo y máximo) que suman el ancho útil
  const largo = Array.from({ length: nCol }, (_, j) => Math.min(60, Math.max(4, Math.max(...(datos[0][j] || '').split(/\s+/).map((w) => w.length)) + 1, ...datos.map((r) => (r[j] || '').replace(/[*`]/g, '').length))));
  const total = largo.reduce((a, b) => a + b, 0);
  const anchos = largo.map((l) => Math.floor((l / total) * ANCHO));
  // Ancho mínimo por columna según su encabezado (evita cortar palabras cortas como "CISO" o "Flujo")
  const minimo = (j) => Math.max(450, (Math.max(...(datos[0][j] || '').split(/\s+/).map((w) => w.replace(/[*`]/g, '').length)) + 2) * 110);
  for (let j = 0; j < nCol; j++) {
    const falta = minimo(j) - anchos[j];
    if (falta > 0) { const k = anchos.indexOf(Math.max(...anchos)); anchos[k] -= falta; anchos[j] += falta; }
  }
  anchos[anchos.length - 1] += ANCHO - anchos.reduce((a, b) => a + b, 0);
  const tam = nCol >= 6 ? 15 : nCol >= 4 ? 17 : 18;
  const rows = datos.map((r, i) => new TableRow({
    tableHeader: i === 0,
    cantSplit: true,
    children: Array.from({ length: nCol }, (_, j) => new TableCell({
      width: { size: anchos[j], type: WidthType.DXA },
      borders: bordes,
      verticalAlign: VerticalAlign.CENTER,
      shading: i === 0 ? { type: ShadingType.CLEAR, fill: AZUL, color: 'auto' } : (i % 2 === 0 ? { type: ShadingType.CLEAR, fill: 'F7F9FC', color: 'auto' } : undefined),
      margins: { top: 50, bottom: 50, left: 80, right: 80 },
      children: [new Paragraph({
        spacing: { before: 0, after: 0 },
        children: inline(r[j] || '', i === 0 ? { size: tam, bold: true, color: 'FFFFFF' } : { size: tam }),
      })],
    })),
  }));
  return new Table({ width: { size: ANCHO, type: WidthType.DXA }, columnWidths: anchos, rows });
}

function codigo(lineasCodigo) {
  return lineasCodigo.map((l, i) => new Paragraph({
    children: [new TextRun({ text: l.length ? l : ' ', font: MONO, size: 16 })],
    shading: { type: ShadingType.CLEAR, fill: GRIS, color: 'auto' },
    spacing: { before: i === 0 ? 80 : 0, after: i === lineasCodigo.length - 1 ? 140 : 0, line: 240 },
    indent: { left: 120, right: 120 },
    keepLines: true,
    keepNext: i < lineasCodigo.length - 1,
  }));
}

// ---------- Recorrido del Markdown ----------
const cuerpo = [];
let titulo = '';
let primerH1 = true;
for (let i = 0; i < lineas.length; i++) {
  const l = lineas[i];
  if (!titulo && l.startsWith('# ')) { titulo = l.slice(2).trim(); continue; }
  if (/^\s*$/.test(l) || /^---\s*$/.test(l)) continue;
  if (/^\*\*(Solución|Entidades|Audiencia|Clasificación):\*\*/.test(l)) continue; // van en la hoja de control
  if (l.startsWith('```')) {
    const bloque = [];
    for (i++; i < lineas.length && !lineas[i].startsWith('```'); i++) bloque.push(lineas[i]);
    cuerpo.push(...codigo(bloque));
    continue;
  }
  if (l.startsWith('|')) {
    const filas = [];
    for (; i < lineas.length && lineas[i].startsWith('|'); i++) filas.push(lineas[i]);
    i--;
    cuerpo.push(tabla(filas), new Paragraph({ spacing: { before: 0, after: 120 }, children: [] }));
    continue;
  }
  let m;
  if ((m = l.match(/^(#{1,3}) (.*)$/))) {
    const nivel = m[1].length;
    const txt = m[2].trim();
    if (txt === 'Índice') continue; // lo reemplaza la tabla de contenido de Word
    const h = [HeadingLevel.HEADING_1, HeadingLevel.HEADING_2, HeadingLevel.HEADING_3][nivel - 1];
    cuerpo.push(new Paragraph({ heading: h, pageBreakBefore: nivel === 1 && !primerH1, children: inline(txt) }));
    if (nivel === 1) primerH1 = false;
    continue;
  }
  if (l.startsWith('> ')) {
    let txt = l.slice(2);
    for (; i + 1 < lineas.length && lineas[i + 1].startsWith('> '); i++) txt += ' ' + lineas[i + 1].slice(2);
    if (txt.includes('Convenciones')) {
      txt = '**Convenciones.** ☐ = tarea a marcar. Los recuadros verdes son **puntos de verificación** (no continuar si fallan); los grises indican la **evidencia** a archivar en la carpeta del proyecto; los azules marcan el **hito** de cada fase. `<AMB>` = DEV, TEST o PROD. Los comandos PowerShell se ejecutan desde la raíz del repositorio.';
    }
    cuerpo.push(recuadro(txt, '', 'EEF3FA', '2F5597'));
    continue;
  }
  if (l.startsWith('🔍')) { cuerpo.push(recuadro(l.replace(/^🔍\s*/, ''), '', 'E8F5E9', '2E7D32')); continue; }
  if (l.startsWith('📁')) { cuerpo.push(recuadro(l.replace(/^📁\s*/, ''), 'Evidencia:', 'F2F2F2', '595959')); continue; }
  if (l.startsWith('**🏁')) { cuerpo.push(recuadro(l.replace('**🏁 ', '**'), '', 'DEEAF6', AZUL)); continue; }
  if ((m = l.match(/^(\s*)- (.*)$/))) {
    cuerpo.push(new Paragraph({ numbering: { reference: 'vinetas', level: m[1].length >= 2 ? 1 : 0 }, spacing: { before: 0, after: 60 }, children: inline(m[2]) }));
    continue;
  }
  if ((m = l.match(/^☐ (.*)$/))) {
    const sigueHito = (lineas.slice(i + 1).find((x) => x.trim()) || '').startsWith('**🏁');
    cuerpo.push(new Paragraph({ keepNext: sigueHito, indent: { left: 360, hanging: 360 }, spacing: { before: 40, after: 80 },
      children: [new TextRun({ text: '☐\t', font: 'Segoe UI Symbol', size: 22, color: AZUL }), ...inline(m[1])],
      tabStops: [{ type: TabStopType.LEFT, position: 360 }] }));
    continue;
  }
  // Párrafo normal (une líneas contiguas)
  let txt = l;
  for (; i + 1 < lineas.length && lineas[i + 1].trim() && !/^(#|\||```|> |- |☐|🔍|📁|\*\*🏁|---)/.test(lineas[i + 1]); i++) txt += ' ' + lineas[i + 1].trim();
  cuerpo.push(new Paragraph({ spacing: { before: 60, after: 120 }, children: inline(txt) }));
}

// ---------- Portada y hoja de control ----------
const metadatos = {};
for (const l of lineas.slice(0, 12)) { const m = l.match(/^\*\*(.+?):\*\* (.*)$/); if (m) metadatos[m[1]] = m[2]; }
const tituloLimpio = titulo.replace(/^\d+\s*·\s*/, '');
const clasificacion = metadatos['Clasificación'] || 'Uso Interno';
const fila = (a, b, enc = false) => new TableRow({ children: [a, b].map((t, j) => new TableCell({
  width: { size: j === 0 ? 2800 : ANCHO - 2800, type: WidthType.DXA }, borders: bordes,
  shading: enc || j === 0 ? { type: ShadingType.CLEAR, fill: enc ? AZUL : AZUL_CLARO, color: 'auto' } : undefined,
  margins: { top: 60, bottom: 60, left: 100, right: 100 },
  children: [new Paragraph({ children: inline(t, { size: 19, bold: enc || j === 0, color: enc ? 'FFFFFF' : undefined }) })],
})) });
const tablaControl = (filas) => new Table({ width: { size: ANCHO, type: WidthType.DXA }, columnWidths: [2800, ANCHO - 2800], rows: filas });

const portada = [
  new Paragraph({ spacing: { before: 1200, after: 0 }, alignment: AlignmentType.LEFT, children: [new TextRun({ text: 'Renta Nacional Compañía de Seguros Generales S.A.', font: FUENTE, size: 24, color: '595959' })] }),
  new Paragraph({ spacing: { after: 1000 }, children: [new TextRun({ text: 'Renta Nacional Compañía de Seguros de Vida S.A.', font: FUENTE, size: 24, color: '595959' })] }),
  new Paragraph({ border: { bottom: { style: BorderStyle.SINGLE, size: 18, color: AZUL, space: 8 } }, spacing: { after: 240 },
    children: [new TextRun({ text: tituloLimpio.toUpperCase(), font: FUENTE, size: 44, bold: true, color: AZUL })] }),
  new Paragraph({ spacing: { after: 120 }, children: [new TextRun({ text: 'Solución de Inventario y Clasificación de Activos de Información – Plataforma Microsoft 365', font: FUENTE, size: 28, color: AZUL })] }),
  new Paragraph({ spacing: { after: 1600 }, children: [new TextRun({ text: 'Documento base: ER[ZZ].GR_1.0(2026)', font: FUENTE, size: 22, color: '595959' })] }),
  new Paragraph({ children: [new TextRun({ text: 'Gerencia de Riesgos y Cumplimiento · Oficial de Seguridad de la Información (CISO)', font: FUENTE, size: 22 })] }),
  new Paragraph({ spacing: { after: 600 }, children: [new TextRun({ text: 'Noviembre 2026', font: FUENTE, size: 22 })] }),
  new Paragraph({ shading: { type: ShadingType.CLEAR, fill: 'FDECEA', color: 'auto' }, border: { left: { style: BorderStyle.SINGLE, size: 18, color: 'C00000', space: 6 } },
    children: [new TextRun({ text: `Clasificación: ${clasificacion.toUpperCase()}. `, bold: true, font: FUENTE, size: 18, color: 'C00000' }),
      new TextRun({ text: 'Documento de uso interno de las Compañías. Su divulgación a terceros requiere autorización expresa del Comité de Gerentes.', font: FUENTE, size: 18 })] }),
  new Paragraph({ children: [new PageBreak()] }),
  new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun('Hoja de control')] }),
  new Paragraph({ spacing: { after: 80 }, children: [new TextRun({ text: 'Matriz de identificación', bold: true, font: FUENTE, size: 22, color: AZUL })] }),
  tablaControl([
    fila('Campo', 'Detalle', true),
    fila('Denominación', tituloLimpio),
    fila('Solución', metadatos['Solución'] || 'Inventario y Clasificación de Activos de Información – Microsoft 365'),
    fila('Entidades alcanzadas', metadatos['Entidades'] || 'RNSG y RNSV'),
    fila('Audiencia', metadatos['Audiencia'] || ''),
    fila('Documento base', 'ER[ZZ].GR_1.0(2026) – Especificación de Requerimientos'),
    fila('Documentos relacionados', 'Diseño de la solución (01), Manual de instalación (02), Manual de administración (03), Manual de usuario (04), Plan de pruebas (05), Matriz de trazabilidad (06)'),
    fila('Fuente', 'Repositorio de la solución, archivo docs/' + path.basename(entrada)),
    fila('Clasificación', clasificacion),
  ]),
  new Paragraph({ spacing: { before: 240, after: 80 }, children: [new TextRun({ text: 'Matriz de versiones', bold: true, font: FUENTE, size: 22, color: AZUL })] }),
  new Table({ width: { size: ANCHO, type: WidthType.DXA }, columnWidths: [1200, 1800, 4238, 2400], rows: [
    ['Versión', 'Fecha', 'Descripción', 'Aprobado por'], ['1.0', 'Noviembre 2026', 'Versión original para revisión.', 'Pendiente (CSI)'],
  ].map((r, i) => new TableRow({ tableHeader: i === 0, children: r.map((t, j) => new TableCell({
    width: { size: [1200, 1800, 4238, 2400][j], type: WidthType.DXA }, borders: bordes,
    shading: i === 0 ? { type: ShadingType.CLEAR, fill: AZUL, color: 'auto' } : undefined, margins: { top: 60, bottom: 60, left: 100, right: 100 },
    children: [new Paragraph({ children: [new TextRun({ text: t, font: FUENTE, size: 19, bold: i === 0, color: i === 0 ? 'FFFFFF' : undefined })] })],
  })) })) }),
  new Paragraph({ children: [new PageBreak()] }),
  new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun('Contenido')] }),
  new TableOfContents('Contenido', { hyperlink: true, headingStyleRange: '1-2' }),
  new Paragraph({ children: [new PageBreak()] }),
];

// ---------- Documento ----------
const doc = new Document({
  creator: 'Gerencia de Riesgos y Cumplimiento – CISO',
  title: tituloLimpio,
  subject: 'Solución de Inventario y Clasificación de Activos de Información – Microsoft 365',
  keywords: `SGSI; Inventario de activos; ${clasificacion}`,
  features: { updateFields: true },
  styles: {
    default: { document: { run: { font: FUENTE, size: 21 }, paragraph: { spacing: { line: 276 } } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: FUENTE, size: 34, bold: true, color: AZUL }, paragraph: { spacing: { before: 240, after: 160 }, keepNext: true, outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: FUENTE, size: 26, bold: true, color: '2F5597' }, paragraph: { spacing: { before: 300, after: 100 }, keepNext: true, outlineLevel: 1,
          border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: 'BFBFBF', space: 2 } } } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: FUENTE, size: 23, bold: true, color: '404040' }, paragraph: { spacing: { before: 200, after: 80 }, keepNext: true, outlineLevel: 2 } },
    ],
  },
  numbering: { config: [{ reference: 'vinetas', levels: [
    { level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 300 } } } },
    { level: 1, format: LevelFormat.BULLET, text: '–', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 1080, hanging: 300 } } } },
  ] }] },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1134, bottom: 1134, left: 1134, right: 1134, header: 567, footer: 567 } }, titlePage: true },
    headers: {
      default: new Header({ children: [new Paragraph({
        tabStops: [{ type: TabStopType.RIGHT, position: ANCHO }],
        border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: 'BFBFBF', space: 4 } },
        children: [new TextRun({ text: `Renta Nacional · ${tituloLimpio}`, font: FUENTE, size: 16, color: '595959' }),
          new TextRun({ text: `\t${clasificacion.toUpperCase()}`, font: FUENTE, size: 16, bold: true, color: 'C00000' })],
      })] }),
      first: new Header({ children: [new Paragraph({ children: [] })] }),
    },
    footers: {
      default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [
        new TextRun({ text: 'Página ', font: FUENTE, size: 16, color: '595959' }), new TextRun({ children: [PageNumber.CURRENT], font: FUENTE, size: 16, color: '595959' }),
        new TextRun({ text: ' de ', font: FUENTE, size: 16, color: '595959' }), new TextRun({ children: [PageNumber.TOTAL_PAGES], font: FUENTE, size: 16, color: '595959' }),
      ] })] }),
      first: new Footer({ children: [new Paragraph({ children: [] })] }),
    },
    children: [...portada, ...cuerpo],
  }],
});

Packer.toBuffer(doc).then((buf) => { fs.writeFileSync(salida, buf); console.log(`Generado ${salida}`); });

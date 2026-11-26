#!/usr/bin/env node
'use strict';
/**
 * Validación estática de la configuración de la solución (se ejecuta con `npm run validar`).
 * Verifica restricciones de SharePoint y la coherencia entre catálogo, listas, parámetros, flujos y reglas:
 *  - 61 campos del Catálogo (F01–F61) presentes, nombres internos únicos y ASCII.
 *  - Máximo 20 columnas indexadas por lista; máximo 12 columnas de búsqueda/persona en Activos (incl. Autor/Editor).
 *  - Las listas de búsqueda referenciadas existen.
 *  - Toda clave de parámetro citada en flujos/app/scripts existe en parametros.json.
 *  - Los códigos de alerta de reglas.js aparecen en FL-02 y en App.Formulas (consistencia de la regla en las 3 capas).
 */
const fs = require('fs');
const path = require('path');

const raiz = path.resolve(__dirname, '..');
const leer = (p) => fs.readFileSync(path.join(raiz, p), 'utf8');
const json = (p) => JSON.parse(leer(p));
const errores = [];
const ok = (m) => console.log(`  ✔ ${m}`);
const fallo = (m) => { errores.push(m); console.log(`  ✘ ${m}`); };

const cat = json('config/catalogo-campos.json');
const sop = json('config/listas-soporte.json');
const par = json('config/parametros.json');

console.log('Catálogo (lista Activos)');
const codigos = cat.campos.map((c) => c.codigo);
const faltan = Array.from({ length: 61 }, (_, i) => `F${String(i + 1).padStart(2, '0')}`).filter((c) => !codigos.includes(c));
faltan.length ? fallo(`Faltan campos del Catálogo: ${faltan.join(', ')}`) : ok('Campos F01–F61 presentes');
const internos = cat.campos.map((c) => c.interno);
new Set(internos).size === internos.length ? ok('Nombres internos únicos') : fallo('Nombres internos duplicados');
internos.every((n) => /^[A-Za-z][A-Za-z0-9_]{0,31}$/.test(n)) ? ok('Nombres internos ASCII ≤ 32') : fallo('Nombre interno inválido');
const idx = cat.campos.filter((c) => c.indexado).length;
idx <= 20 ? ok(`${idx} columnas indexadas (máx. 20)`) : fallo(`${idx} columnas indexadas > 20`);
const busq = cat.campos.filter((c) => ['Lookup', 'User', 'UserMulti'].includes(c.tipo)).length + 2;
busq <= 12 ? ok(`${busq} columnas de búsqueda/persona incl. Autor/Editor (umbral 12)`) : fallo(`${busq} columnas de búsqueda/persona > 12`);
cat.campos.filter((c) => ['Choice', 'MultiChoice'].includes(c.tipo)).forEach((c) => {
  if (!Array.isArray(c.opciones) || c.opciones.length === 0) fallo(`${c.interno}: elección sin opciones`);
  if (c.default && !c.opciones.includes(c.default)) fallo(`${c.interno}: valor por defecto fuera de opciones`);
});
ok('Columnas de elección con opciones válidas');

console.log('Listas de soporte');
const nombresListas = new Set(['Activos', ...sop.listas.map((l) => l.nombre), ...sop.bibliotecas.map((b) => b.nombre)]);
const todas = [{ nombre: 'Activos', campos: cat.campos }, ...sop.listas, ...sop.bibliotecas];
for (const l of todas) {
  for (const c of l.campos) {
    if (c.tipo === 'Lookup' && !nombresListas.has(c.lookupLista)) fallo(`${l.nombre}.${c.interno}: lista de búsqueda inexistente ${c.lookupLista}`);
  }
  const n = l.campos.filter((c) => c.indexado).length;
  if (n > 20) fallo(`${l.nombre}: ${n} índices > 20`);
}
ok('Búsquedas resuelven a listas existentes y ≤ 20 índices por lista');

console.log('Parámetros referenciados');
const claves = new Set(par.parametros.map((p) => p.clave));
const archivos = [];
const recorrer = (dir) => fs.readdirSync(path.join(raiz, dir), { withFileTypes: true }).forEach((d) => {
  const rel = path.join(dir, d.name);
  if (d.isDirectory()) recorrer(rel); else if (/\.(md|fx|ps1|psm1|dax|pq)$/.test(d.name)) archivos.push(rel);
});
['powerautomate', 'powerapps', 'scripts', 'powerbi'].forEach(recorrer);
const usadas = new Set();
const patrones = [/outputs\('P'\)\?\['([A-Z_]+)'\]/g, /Par(?:Texto|Numero)\("([A-Z_]+)"\)/g, /\$par\['([A-Z_]+)'\]/g, /Parametros\['([A-Z_]+)'\]/g, /Set-RNParametro '([A-Z_]+)'/g];
for (const a of archivos) {
  const t = leer(a);
  for (const re of patrones) for (const m of t.matchAll(re)) usadas.add(m[1]);
}
const noDef = [...usadas].filter((k) => !claves.has(k));
noDef.length ? fallo(`Parámetros usados sin definir: ${noDef.join(', ')}`) : ok(`${usadas.size} claves de parámetro usadas y definidas`);

console.log('Consistencia de reglas entre capas');
const reglas = leer('tests/reglas/reglas.js');
const codAlertas = [...new Set([...reglas.matchAll(/add\('([AB]\d\d)'/g)].map((m) => m[1]))];
const fl02 = leer('powerautomate/FL-02_Calculos_Alertas_e_Historial.md');
const app = leer('powerapps/src/App.Formulas.fx');
const ps = leer('scripts/modules/RNInventario.Reglas.psm1');
const bloqueantes = codAlertas.filter((c) => c.startsWith('A'));
const faltaFL = codAlertas.filter((c) => !fl02.includes(`'${c} `));
const faltaApp = bloqueantes.filter((c) => !app.includes(`"${c}"`));
const faltaPS = codAlertas.filter((c) => !['B07', 'B08'].includes(c) && !ps.includes(`'${c}'`));
faltaFL.length ? fallo(`Alertas sin implementar en FL-02: ${faltaFL.join(', ')}`) : ok(`FL-02 implementa los ${codAlertas.length} códigos de alerta`);
faltaApp.length ? fallo(`Alertas bloqueantes sin implementar en la app: ${faltaApp.join(', ')}`) : ok(`App implementa las ${bloqueantes.length} alertas bloqueantes`);
faltaPS.length ? fallo(`Alertas sin implementar en RNInventario.Reglas.psm1: ${faltaPS.join(', ')}`) : ok('Módulo PowerShell implementa las alertas de validación');

console.log(errores.length ? `\n${errores.length} error(es)` : '\nConfiguración válida');
process.exit(errores.length ? 1 : 0);

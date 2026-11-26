'use strict';
// Pruebas de las reglas de negocio y de los criterios de aceptación automatizables (sección 16 del ER).
// Ejecutar: node --test tests/reglas   (o npm test)
const test = require('node:test');
const assert = require('node:assert/strict');
const R = require('./reglas');

const F = (s) => new Date(`${s}T12:00:00Z`);

/** Activo completo y válido de referencia; cada prueba altera lo que necesita. */
const base = () => ({
  entidad: 'RNSG', nombre: 'Base de pólizas', descripcion: 'Pólizas vigentes', categoria: 'Información / datos',
  proceso: 'Suscripción', gerencia: 'Gerencia Técnica', duenoCargo: 'Gerente Técnico', formato: 'Digital estructurado',
  ubicacion: 'Core de seguros', confidencialidad: 'Media', integridad: 'Media', disponibilidad: 'Media',
  confiadaTerceros: 'No', nivel: 'Uso Interno', datosPersonales: 'No', datosSensibles: 'No',
  reglasUso: 'NC Anexo 1 – Uso Interno', periodoRetencion: '10 años', fundamentoRetencion: 'Norma CMF',
  fechaAlta: F('2026-01-10'),
});

const codigos = (a, hoy = F('2026-02-01')) => R.calcularAlertas(a, R.PARAMETROS_DEFECTO, hoy).map((x) => x.codigo);

test('activo de referencia no tiene alertas bloqueantes', () => {
  assert.equal(R.tieneBloqueantes(R.calcularAlertas(base(), undefined, F('2026-02-01'))), false);
});

test('CA-01 / RF-18: datos personales clasificado Uso Interno se bloquea; mínimo Reservado', () => {
  const a = { ...base(), datosPersonales: 'Sí', idRAT: 'RAT-001' };
  assert.equal(R.nivelMinimo(a), 'Reservado');
  const al = R.calcularAlertas(a, undefined, F('2026-02-01'));
  const a04 = al.find((x) => x.codigo === 'A04');
  assert.ok(a04 && a04.bloqueante);
  assert.match(a04.mensaje, /mínimo exigido \(Reservado\)/);
});

test('RN-02: datos sensibles exigen Confidencial', () => {
  assert.equal(R.nivelMinimo({ datosPersonales: 'Sí', datosSensibles: 'Sí' }), 'Confidencial');
});

test('RN-08: información confiada por terceros no puede quedar bajo el nivel acordado', () => {
  assert.equal(R.nivelMinimo({ confiadaTerceros: 'Sí', nivelAcordadoTerceros: 'Confidencial' }), 'Confidencial');
});

test('RN-07 / RF-19: agregación sugiere el nivel más alto', () => {
  assert.equal(R.nivelMinimo({ nivelesAgregados: ['Uso Interno', 'Reservado', 'Pública'] }), 'Reservado');
});

test('RN-03 / RF-17: crítico si alguna dimensión es Alta', () => {
  assert.equal(R.esCritico({ confidencialidad: 'Baja', integridad: 'Alta', disponibilidad: 'Baja' }), true);
  assert.equal(R.esCritico({ confidencialidad: 'Media', integridad: 'Media', disponibilidad: 'Baja' }), false);
});

test('RN-06 / RF-20: sin clasificar se reporta como Confidencial y es bloqueante', () => {
  assert.equal(R.nivelEfectivo(''), 'Confidencial');
  assert.ok(codigos({ ...base(), nivel: '' }).includes('A03'));
});

test('CA-04 / RF-28: activo crítico revisado el 1 de marzo vence el 1 de septiembre', () => {
  const a = { ...base(), integridad: 'Alta', fechaUltimaRevision: F('2027-03-01') };
  assert.equal(R.proximaRevision(a).toISOString().slice(0, 10), '2027-09-01');
});

test('CA-04 / RF-31: avisos a 30, 15 y 0 días y escalamiento, sin duplicar', () => {
  const venc = F('2027-09-01');
  assert.equal(R.avisoCorrespondiente(venc, F('2027-07-15')), null);
  assert.equal(R.avisoCorrespondiente(venc, F('2027-08-02')), '30');
  assert.equal(R.avisoCorrespondiente(venc, F('2027-08-02'), ['30']), null);
  assert.equal(R.avisoCorrespondiente(venc, F('2027-08-17'), ['30']), '15');
  assert.equal(R.avisoCorrespondiente(venc, F('2027-09-01'), ['30', '15']), '0');
  assert.equal(R.avisoCorrespondiente(venc, F('2027-09-02'), ['30', '15', '0']), 'ESC');
  assert.equal(R.avisoCorrespondiente(venc, F('2027-09-10'), ['30', '15', '0', 'ESC']), null);
});

test('RN-04: revisión anual para no crítico sin datos personales; semestral con datos personales', () => {
  assert.equal(R.mesesRevisionIntegral(base()), 12);
  assert.equal(R.mesesRevisionIntegral({ ...base(), datosPersonales: 'Sí' }), 6);
});

test('RN-05: revisión de accesos semestral solo Confidencial y Reservado', () => {
  assert.equal(R.proximaRevisionAccesos(base()), null);
  const a = { ...base(), nivel: 'Reservado', fechaRevisionAccesos: F('2026-03-31') };
  assert.equal(R.proximaRevisionAccesos(a).toISOString().slice(0, 10), '2026-09-30');
  // Sin clasificar => Confidencial => sí tiene revisión de accesos
  assert.ok(R.proximaRevisionAccesos({ ...base(), nivel: '' }));
});

test('sumarMeses ajusta fin de mes como .NET AddMonths', () => {
  assert.equal(R.sumarMeses(F('2026-08-31'), 6).toISOString().slice(0, 10), '2027-02-28');
});

test('CA-05 / RF-21: Confidencial sin cargos autorizados no puede pasar a Vigente', () => {
  const a = { ...base(), nivel: 'Confidencial' };
  assert.ok(codigos(a).includes('A06'));
  assert.equal(R.tieneBloqueantes(R.calcularAlertas({ ...a, cargosAutorizados: 'Gerente Técnico; Subgerente' })), false);
});

test('RF-21: Reservado con tercero exige terceros autorizados', () => {
  const a = { ...base(), nivel: 'Reservado', cargosAutorizados: 'X', tercero: 'Proveedor SA', tipoAlojamiento: 'Nube pública – SaaS', pais: 'Chile' };
  assert.ok(codigos(a).includes('A07'));
});

test('RN-09: datos personales sin RAT bloquea; sin retención bloquea', () => {
  assert.ok(codigos({ ...base(), nivel: 'Reservado', cargosAutorizados: 'X', datosPersonales: 'Sí' }).includes('A05'));
  assert.ok(codigos({ ...base(), periodoRetencion: '' }).includes('A08'));
});

test('RF-08: activo "Ambas" exige gerencia contraparte', () => {
  assert.ok(codigos({ ...base(), entidad: 'Ambas' }).includes('A10'));
  assert.ok(!codigos({ ...base(), entidad: 'Ambas', gerenciaContraparte: 'GTI RNSV' }).includes('A10'));
});

test('alertas no bloqueantes de gestión de brechas', () => {
  const a = { ...base(), categoria: 'Software / aplicación', integridad: 'Alta', tipoAlojamiento: 'Nube pública – SaaS', fechaUltimaRevision: F('2025-01-01') };
  const c = codigos(a, F('2026-02-01'));
  for (const k of ['B01', 'B02', 'B03', 'B04']) assert.ok(c.includes(k), k);
  assert.equal(R.tieneBloqueantes(R.calcularAlertas(a, undefined, F('2026-02-01'))), false);
});

test('RF-07 / RN-01: formato del ID', () => {
  const id = R.generarId('rnsg', 'gti', 7);
  assert.equal(id, 'AI-RNSG-GTI-00007');
  assert.match(id, R.PATRON_ID);
  assert.match(R.generarId('AMBAS', 'GRC', 12345), R.PATRON_ID);
  assert.throws(() => R.generarId('RNSG', '', 1));
  assert.throws(() => R.generarId('RNSG', 'GTI', 0));
});

test('CA-07 / RN-10: excepción de 18 meses se rechaza; 12 meses se acepta', () => {
  const comun = { fundamento: 'f', riesgo: 'r', controlesCompensatorios: 'c', fechaInicio: F('2026-12-01') };
  assert.deepEqual(R.validarExcepcion({ ...comun, fechaFin: F('2027-12-01') }), []);
  assert.ok(R.validarExcepcion({ ...comun, fechaFin: F('2028-06-01') }).some((e) => /12 meses/.test(e)));
});

test('CA-08 / RF-34: baja Confidencial por proveedor sin certificado no se cierra', () => {
  const b = { nivel: 'Confidencial', metodo: 'Destrucción segura y certificada', ejecutadaPorProveedor: true, autorizadaPorDueno: true };
  assert.ok(R.validarBaja({ ...b, certificadoAdjunto: false }).includes('Certificado de destrucción obligatorio'));
  assert.deepEqual(R.validarBaja({ ...b, certificadoAdjunto: true }), []);
});

test('RN-11: método de baja según nivel; Uso Interno por proveedor también exige certificado', () => {
  assert.ok(R.validarBaja({ nivel: 'Reservado', metodo: 'Eliminación por canales corporativos', autorizadaPorDueno: true }).length > 0);
  assert.deepEqual(R.validarBaja({ nivel: 'Uso Interno', metodo: 'Eliminación por canales corporativos', autorizadaPorDueno: true }), []);
  assert.ok(R.validarBaja({ nivel: 'Uso Interno', metodo: 'Eliminación por canales corporativos', autorizadaPorDueno: true, ejecutadaPorProveedor: true })
    .includes('Certificado de destrucción obligatorio'));
});

test('RF-26: el Delegado no puede declarar; titular y subrogante sí', () => {
  const cargo = { titular: 'gerente.ti@rentanacional.cl', subrogante: 'subgerente.ti@rentanacional.cl' };
  assert.equal(R.puedeDeclarar('GERENTE.TI@rentanacional.cl', cargo), true);
  assert.equal(R.puedeDeclarar('subgerente.ti@rentanacional.cl', cargo), true);
  assert.equal(R.puedeDeclarar('delegado@rentanacional.cl', cargo), false);
});

test('CA-06 / RF-32: reclasificar un activo Vigente exige motivo', () => {
  assert.deepEqual(R.validarReclasificacion({ estado: 'Vigente', nivelAnterior: 'Reservado', nivelNuevo: 'Confidencial', motivo: '' }), ['Motivo de reclasificación obligatorio']);
  assert.deepEqual(R.validarReclasificacion({ estado: 'Borrador', nivelAnterior: 'Reservado', nivelNuevo: 'Confidencial', motivo: '' }), []);
});

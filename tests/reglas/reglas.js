'use strict';
/**
 * Especificación ejecutable de las reglas de negocio (sección 9 del ER).
 *
 * Es la referencia contra la que se construyen y prueban:
 *   - las fórmulas Power Fx de la app      (powerapps/src/App.Formulas.fx)
 *   - las expresiones de Power Automate    (powerautomate/FL-02_Calculos_y_Alertas.md)
 *   - el validador de carga masiva          (scripts/modules/RNInventario.Reglas.psm1)
 * Si cambia una regla, se cambia aquí primero y se ejecutan las pruebas (npm test).
 * Los parámetros por defecto replican config/parametros.json.
 */

const PARAMETROS_DEFECTO = Object.freeze({
  FREC_REVISION_MESES: 12,
  FREC_REVISION_CRITICO_MESES: 6,
  FREC_REVISION_ACCESOS_MESES: 6,
  NIVELES_CON_REVISION_ACCESOS: ['Confidencial', 'Reservado'],
  AVISOS_DIAS_ANTES: [30, 15, 0],
  EXCEPCION_MAX_MESES: 12,
  NIVEL_MIN_DATOS_PERSONALES: 'Reservado',
  NIVEL_MIN_DATOS_SENSIBLES: 'Confidencial',
  NIVEL_POR_DEFECTO: 'Confidencial',
  ORDEN_NIVELES: { 'Pública': 1, 'Uso Interno': 2, 'Reservado': 3, 'Confidencial': 4 },
  METODO_BAJA_POR_NIVEL: {
    'Confidencial': 'Destrucción segura y certificada',
    'Reservado': 'Destrucción segura con registro',
    'Uso Interno': 'Eliminación por canales corporativos',
    'Pública': 'Eliminación por canales corporativos',
  },
  CERTIFICADO_OBLIGATORIO_NIVELES: ['Confidencial'],
  CATEGORIAS_TECNOLOGICAS: ['Software / aplicación', 'Hardware / equipamiento', 'Infraestructura de comunicaciones', 'Servicio (TI o de tercero)'],
  ALOJAMIENTOS_EXTERNOS: ['Nube pública – SaaS', 'Nube pública – IaaS / PaaS', 'Proveedor (hosting / outsourcing)', 'Dependencias físicas de tercero'],
});

const vacio = (v) => v === undefined || v === null || (typeof v === 'string' && v.trim() === '') || (Array.isArray(v) && v.length === 0);

function ordenNivel(nivel, p = PARAMETROS_DEFECTO) {
  return p.ORDEN_NIVELES[nivel] || 0;
}

/** Devuelve el nivel más sensible de una lista (ignora vacíos). */
function nivelMasAlto(niveles, p = PARAMETROS_DEFECTO) {
  return niveles.filter((n) => !vacio(n)).reduce((max, n) => (ordenNivel(n, p) > ordenNivel(max, p) ? n : max), 'Pública');
}

/** RN-03: crítico si alguna dimensión C-I-D es Alta. */
function esCritico({ confidencialidad, integridad, disponibilidad }) {
  return [confidencialidad, integridad, disponibilidad].includes('Alta');
}

/** RN-06 / RF-20: sin clasificar se trata como Confidencial. */
function nivelEfectivo(nivel, p = PARAMETROS_DEFECTO) {
  return vacio(nivel) ? p.NIVEL_POR_DEFECTO : nivel;
}

/**
 * RN-02, RN-07, RN-08: nivel mínimo exigido.
 *  - datos personales → Reservado; datos sensibles → Confidencial (parametrizable, D-03)
 *  - información confiada por terceros → no inferior al nivel acordado
 *  - agregación → el más alto de los activos que reúne (sugerencia RF-19)
 */
function nivelMinimo(a, p = PARAMETROS_DEFECTO) {
  const candidatos = ['Pública'];
  if (a.datosPersonales === 'Sí') candidatos.push(p.NIVEL_MIN_DATOS_PERSONALES);
  if (a.datosSensibles === 'Sí') candidatos.push(p.NIVEL_MIN_DATOS_SENSIBLES);
  if (a.confiadaTerceros === 'Sí' && !vacio(a.nivelAcordadoTerceros)) candidatos.push(a.nivelAcordadoTerceros);
  if (Array.isArray(a.nivelesAgregados)) candidatos.push(...a.nivelesAgregados);
  return nivelMasAlto(candidatos, p);
}

/** Suma meses como .NET AddMonths / Power Fx DateAdd / addToTime(...,'Month'): fin de mes se ajusta. */
function sumarMeses(fecha, meses) {
  const d = new Date(fecha.getTime()); // conserva la hora del día
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + meses);
  const ultimoDia = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  d.setUTCDate(Math.min(fecha.getUTCDate(), ultimoDia));
  return d;
}

function sumarDias(fecha, dias) {
  return new Date(fecha.getTime() + dias * 86400000);
}

function diasEntre(desde, hasta) {
  const a = Date.UTC(desde.getUTCFullYear(), desde.getUTCMonth(), desde.getUTCDate());
  const b = Date.UTC(hasta.getUTCFullYear(), hasta.getUTCMonth(), hasta.getUTCDate());
  return Math.round((b - a) / 86400000);
}

/** RN-04: meses de la revisión integral. */
function mesesRevisionIntegral(a, p = PARAMETROS_DEFECTO) {
  return esCritico(a) || a.datosPersonales === 'Sí' ? p.FREC_REVISION_CRITICO_MESES : p.FREC_REVISION_MESES;
}

/** F53: próxima revisión integral a partir de la última revisión (o de la fecha de alta). */
function proximaRevision(a, p = PARAMETROS_DEFECTO) {
  const base = a.fechaUltimaRevision || a.fechaAlta;
  if (!base) return null;
  return sumarMeses(base, mesesRevisionIntegral(a, p));
}

/** RN-05 / F41: próxima revisión de accesos solo para Confidencial y Reservado (nivel efectivo). */
function proximaRevisionAccesos(a, p = PARAMETROS_DEFECTO) {
  if (!p.NIVELES_CON_REVISION_ACCESOS.includes(nivelEfectivo(a.nivel, p))) return null;
  const base = a.fechaRevisionAccesos || a.fechaUltimaRevision || a.fechaAlta;
  if (!base) return null;
  return sumarMeses(base, p.FREC_REVISION_ACCESOS_MESES);
}

/**
 * F59 / RN-09: alertas. Las bloqueantes impiden pasar a Vigente (y enviar a validación).
 * Códigos estables: se usan en Power BI (página Calidad de datos) y en la app.
 */
function calcularAlertas(a, p = PARAMETROS_DEFECTO, hoy = new Date()) {
  const alertas = [];
  const add = (codigo, mensaje, bloqueante) => alertas.push({ codigo, mensaje, bloqueante });
  const nivel = a.nivel;
  const minimo = nivelMinimo(a, p);

  // --- Bloqueantes (RN-09) ---
  if (vacio(a.duenoCargo)) add('A01', 'Sin Dueño (cargo) asignado', true);
  if (vacio(a.confidencialidad) || vacio(a.integridad) || vacio(a.disponibilidad)) add('A02', 'Valoración C-I-D incompleta', true);
  if (vacio(nivel)) add('A03', 'Sin nivel de clasificación (se trata como Confidencial)', true);
  else if (ordenNivel(nivel, p) < ordenNivel(minimo, p)) add('A04', `Nivel asignado (${nivel}) inferior al mínimo exigido (${minimo})`, true);
  if (a.datosPersonales === 'Sí' && vacio(a.idRAT)) add('A05', 'Datos personales sin actividad del RAT vinculada', true);
  if (['Confidencial', 'Reservado'].includes(nivel) && vacio(a.cargosAutorizados)) add('A06', `Nivel ${nivel} sin lista de cargos autorizados`, true);
  if (nivel === 'Reservado' && !vacio(a.tercero) && vacio(a.tercerosAutorizados)) add('A07', 'Reservado con tercero sin lista de terceros autorizados', true);
  if (vacio(a.periodoRetencion)) add('A08', 'Sin período de retención', true);
  if (vacio(a.entidad)) add('A09', 'Sin entidad', true);
  if (a.entidad === 'Ambas' && vacio(a.gerenciaContraparte)) add('A10', 'Activo compartido sin gerencia contraparte', true);
  if (vacio(a.nombre) || vacio(a.descripcion) || vacio(a.categoria) || vacio(a.proceso) || vacio(a.gerencia) ||
      vacio(a.formato) || vacio(a.ubicacion) || vacio(a.confiadaTerceros) || vacio(a.datosPersonales) ||
      vacio(a.datosSensibles) || vacio(a.reglasUso) || vacio(a.fundamentoRetencion)) {
    add('A11', 'Faltan campos obligatorios de normativa interna', true);
  }
  if (a.datosSensibles === 'Sí' && a.datosPersonales !== 'Sí') add('A12', 'Datos sensibles marcados sin datos personales', true);

  // --- No bloqueantes (gestión de brechas) ---
  if (p.CATEGORIAS_TECNOLOGICAS.includes(a.categoria) && vacio(a.idCMDB)) add('B01', 'Activo tecnológico sin ID de CMDB', false);
  if (p.ALOJAMIENTOS_EXTERNOS.includes(a.tipoAlojamiento) && (vacio(a.tercero) || vacio(a.pais))) add('B02', 'Alojamiento externo sin tercero o país', false);
  if (esCritico(a) && vacio(a.idRiesgo)) add('B03', 'Activo crítico sin ID en matriz de riesgos', false);
  const pr = proximaRevision(a, p);
  if (pr && diasEntre(hoy, pr) < 0) add('B04', 'Revisión integral vencida', false);
  const pra = proximaRevisionAccesos(a, p);
  if (pra && diasEntre(hoy, pra) < 0) add('B05', 'Revisión de accesos vencida', false);
  if (a.transferenciaInternacional === 'Sí') add('B06', 'Transferencia internacional de datos personales (revisión DPO)', false);
  if (a.finSoporte && diasEntre(hoy, a.finSoporte) < 0) add('B07', 'Fuera de soporte del fabricante', false);
  if (a.excepcionFin && diasEntre(hoy, a.excepcionFin) < 0) add('B08', 'Excepción vencida', false);
  return alertas;
}

const tieneBloqueantes = (alertas) => alertas.some((x) => x.bloqueante);

/** RF-07 / RN-01: AI-[ENTIDAD]-[GERENCIA]-[correlativo de 5 dígitos]. */
function generarId(codigoEntidad, codigoGerencia, correlativo) {
  if (vacio(codigoEntidad) || vacio(codigoGerencia)) throw new Error('Entidad y gerencia son obligatorias para generar el ID');
  if (!Number.isInteger(correlativo) || correlativo < 1) throw new Error('Correlativo inválido');
  return `AI-${codigoEntidad.toUpperCase()}-${codigoGerencia.toUpperCase()}-${String(correlativo).padStart(5, '0')}`;
}

const PATRON_ID = /^AI-(RNSG|RNSV|AMBAS)-[A-Z0-9]{2,6}-\d{5}$/;

/** RF-36 / RN-10: vigencia máxima de 12 meses. */
function validarExcepcion({ fechaInicio, fechaFin, fundamento, riesgo, controlesCompensatorios }, p = PARAMETROS_DEFECTO) {
  const errores = [];
  if (vacio(fundamento)) errores.push('Fundamento obligatorio');
  if (vacio(riesgo)) errores.push('Riesgo asociado obligatorio');
  if (vacio(controlesCompensatorios)) errores.push('Controles compensatorios obligatorios');
  if (!fechaInicio || !fechaFin) errores.push('Vigencia obligatoria');
  else {
    if (fechaFin <= fechaInicio) errores.push('La fecha de fin debe ser posterior al inicio');
    if (fechaFin > sumarMeses(fechaInicio, p.EXCEPCION_MAX_MESES)) errores.push(`La vigencia no puede superar ${p.EXCEPCION_MAX_MESES} meses`);
  }
  return errores;
}

/** RF-34 / RN-11: baja. */
function validarBaja({ nivel, metodo, ejecutadaPorProveedor, certificadoAdjunto, autorizadaPorDueno }, p = PARAMETROS_DEFECTO) {
  const errores = [];
  const ne = nivelEfectivo(nivel, p);
  if (!autorizadaPorDueno) errores.push('La baja requiere autorización del Dueño');
  if (metodo !== p.METODO_BAJA_POR_NIVEL[ne]) errores.push(`Método exigido para ${ne}: ${p.METODO_BAJA_POR_NIVEL[ne]}`);
  const exige = ejecutadaPorProveedor || p.CERTIFICADO_OBLIGATORIO_NIVELES.includes(ne);
  if (exige && !certificadoAdjunto) errores.push('Certificado de destrucción obligatorio');
  return errores;
}

/** RF-26: solo el titular del cargo de Dueño o su subrogante registrado puede declarar. */
function puedeDeclarar(upnUsuario, cargo) {
  const u = (upnUsuario || '').toLowerCase();
  return !!u && [cargo.titular, cargo.subrogante].filter(Boolean).map((x) => x.toLowerCase()).includes(u);
}

/** RF-32: reclasificar un activo Vigente exige motivo. */
function validarReclasificacion({ estado, nivelAnterior, nivelNuevo, motivo }) {
  if (nivelAnterior === nivelNuevo) return [];
  if (['Vigente', 'En revisión'].includes(estado) && vacio(motivo)) return ['Motivo de reclasificación obligatorio'];
  return [];
}

/**
 * RF-31: qué aviso corresponde hoy para un vencimiento, sin repetir los ya enviados.
 * Devuelve '30', '15', '0', 'ESC' (escalamiento) o null.
 */
function avisoCorrespondiente(fechaVencimiento, hoy, avisosEnviados = [], p = PARAMETROS_DEFECTO) {
  const dias = diasEntre(hoy, fechaVencimiento);
  if (dias < 0) return avisosEnviados.includes('ESC') ? null : 'ESC';
  const umbrales = [...p.AVISOS_DIAS_ANTES].sort((x, y) => x - y); // [0,15,30]
  const aplicable = umbrales.find((u) => dias <= u);
  if (aplicable === undefined) return null;
  const clave = String(aplicable);
  return avisosEnviados.includes(clave) ? null : clave;
}

module.exports = {
  PARAMETROS_DEFECTO, PATRON_ID,
  ordenNivel, nivelMasAlto, esCritico, nivelEfectivo, nivelMinimo, sumarMeses, sumarDias, diasEntre,
  mesesRevisionIntegral, proximaRevision, proximaRevisionAccesos, calcularAlertas, tieneBloqueantes,
  generarId, validarExcepcion, validarBaja, puedeDeclarar, validarReclasificacion, avisoCorrespondiente,
};

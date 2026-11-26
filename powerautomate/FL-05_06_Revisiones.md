# RN-INV FL-05 / FL-06 Revisión integral y revisión de accesos

| | |
|---|---|
| Requerimientos | RF-28, RF-29, RF-30, RF-31, RN-04, RN-05, CA-04 |
| Disparadores | FL-05 y FL-06: **Periodicidad** diaria 07:10 (America/Santiago). FL-05b / FL-06b: secundarios desde FL-02 |

## FL-05 Recordatorios de revisión integral (programado)
1. *Leer parámetros*. `Hoy = convertFromUtc(utcNow(),'Pacific SA Standard Time','yyyy-MM-dd')`. `Horizonte = addDays(Hoy, max(AVISOS_DIAS_ANTES))`.
2. *Obtener elementos* `Activos` con **consulta OData sobre columnas indexadas** (RNF-09), paginación activada (umbral 100.000):
   `RN_ProximaRevision le '@{outputs('Horizonte')}' and RN_Estado eq 'Vigente'`
3. Por cada activo (concurrencia 5):
   * Buscar la revisión abierta en `Revisiones`: `RN_IdActivoTexto eq '<ID>' and RN_TipoRevision eq 'Integral' and RN_EstadoRevision eq 'Pendiente'`. Si no existe, crearla: `Title = concat('RI ', ID, ' ', ProxRev)`, `RN_FechaVencimiento = RN_ProximaRevision`, `RN_Responsable = RN_DuenoPersona/Email`, `RN_Entidad`, `RN_Campana = concat(Entidad,'-',Gerencia,'-',formatDateTime(ProxRev,'yyyy-MM'))` (RF-30), `RN_AvisosEnviados = ''`.
   * `Dias = div(sub(ticks(ProxRev), ticks(Hoy)), 864000000000)`.
   * Aviso correspondiente (misma regla que `avisoCorrespondiente` de `reglas.js`): el menor umbral de `AVISOS_DIAS_ANTES` ≥ `Dias` que **no** esté en `RN_AvisosEnviados`; si `Dias < 0` y no se escaló → `ESC`.
   * Enviar: umbrales 30/15/0 → correo y Teams al titular del cargo Dueño (y al Delegado) con enlace a *Revisiones*; `ESC` → correo al CISO y a la jefatura del Dueño (`Cargos.RN_Jefatura → RN_Titular`) y `RN_EstadoRevision = Vencida`. Agregar la marca a `RN_AvisosEnviados` (`concat(actual, ',', marca)`).
4. Resumen diario al CISO (una tabla HTML): revisiones vencidas y por vencer por entidad.

**Ejemplo CA-04:** activo crítico con `RN_FechaUltimaRevision = 2027-03-01` → `RN_ProximaRevision = 2027-09-01` (FL-02b, `addToTime(...,6,'Month')`); avisos el 2027-08-02 (30 d), 2027-08-17 (15 d), 2027-09-01 (0 d) y escalamiento el 2027-09-02. Verificado en `tests/reglas/reglas.test.js`.

## FL-05b Registrar revisión integral (secundario, desde FL-02)
Lo dispara el Dueño desde la pantalla *Revisiones* de la app (`RN_SolicitudAccion = Revisión integral`, con `RN_ResultadoRevision` y `RN_RevisionConCambios`). Para la **confirmación en lote** (RF-30) la app aplica `Patch` sobre todos los activos seleccionados de la campaña: cada uno dispara su propia ejecución.
1. Autorización: el editor debe ser titular o subrogante del cargo Dueño (como FL-03 §1.3); si no, revertir.
2. Si `RN_RevisionConCambios = true` y hubo cambios de clasificación → el activo ya pasó a *En revisión* (FL-02 paso 3) y seguirá el flujo de validación; la revisión se cierra como *Completada con cambios*.
3. Si no: cerrar la revisión abierta (`Completada sin cambios`, `RN_Resultado`, `RN_FechaCompletada = utcNow()`), actualizar el activo: `RN_FechaUltimaRevision = Hoy`, `RN_ResponsableUltimaRevision = editor`, `RN_ResultadoRevision = ''`, `RN_SolicitudAccion = Ninguna`, y ejecutar `FL-02b` (nueva `RN_ProximaRevision`).
4. Historial *Revisión integral*.

## FL-06 Revisión de accesos (programado)
Igual a FL-05 con:
* Filtro `RN_ProximaRevisionAccesos le '<Horizonte>' and RN_Estado eq 'Vigente'` (solo Confidencial y Reservado tienen fecha, RN-05).
* Tarea en `Revisiones` con `RN_TipoRevision = Accesos`. El aviso adjunta el vínculo a la evidencia del período anterior y pide, como evidencia, la lista de accesos vigente del sistema (exportada por el Custodio) cargada en `Evidencias` con `RN_TipoEvidencia = Revisión de accesos`.

## FL-06b Registrar revisión de accesos (secundario)
Entradas en el activo: `RN_ResultadoRevision` (hallazgos), `RN_AccesosRetirados` (número). Requisito: existe al menos una evidencia en `Evidencias` con `RN_IdActivo = ID` y `RN_TipoEvidencia = Revisión de accesos` cargada en los últimos 30 días; si no, rechazar con mensaje *"Adjunte la lista de accesos revisada"*.
Cierra la tarea, registra en `Revisiones` el resultado y los accesos retirados, actualiza `RN_FechaRevisionAccesos = Hoy` y ejecuta `FL-02b`. Historial *Revisión de accesos*.

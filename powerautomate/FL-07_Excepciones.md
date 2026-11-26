# RN-INV FL-07 Excepciones del SGSI

| | |
|---|---|
| Requerimientos | RF-36, RF-37, RF-38, RN-10, CA-07 |
| Disparadores | **FL-07a** Power Apps (V2) – *Solicitar excepción*; **FL-07b** Periodicidad diaria 07:20 – vencimientos |

## FL-07a Solicitud y tramitación
Entradas: `idActivo` (Id del elemento), `datosJson` = `{ControlExceptuado, Fundamento, Riesgo, ControlesCompensatorios, FechaInicio, FechaFin, EsRenovacion}`.

1. **Autorización:** `Invocador` (README §4) es titular/subrogante del cargo Dueño del activo, o miembro de CISO.
2. **Validación (RN-10, CA-07)** – se repite en el servidor aunque la app ya la aplica:
   `greater(D?['FechaFin'], addToTime(D?['FechaInicio'], int(outputs('P')?['EXCEPCION_MAX_MESES']), 'Month', 'yyyy-MM-dd'))` → responder `{ok:false, mensaje:"La vigencia no puede superar 12 meses"}`. También: fundamento, riesgo y controles compensatorios obligatorios; fin > inicio.
3. **Crear** en `Excepciones` (cuenta de servicio): `Title = concat('EX-', Entidad, '-', formatDateTime(utcNow(),'yyyy'), '-', formatNumber(<correlativo de Correlativos 'EX-<ENT>-<AAAA>'>,'0000'))` (mismo patrón de concurrencia optimista de FL-01 §4), `RN_EstadoExcepcion = En evaluación CISO`, `RN_Solicitante = Invocador`, `RN_Entidad`.
4. **Permisos del elemento** (RF-38: *CISO, DPO, CSI y Dueño solicitante*): `breakroleinheritance(false)` y asignar: CISO (edición), DPO y CSI (lectura), Auditoría (lectura), solicitante (lectura).
5. **Evaluación CISO** (Approvals, comentario obligatorio). Rechazo → `Rechazada`; fin.
6. **Evaluación DPO** si el activo tiene datos personales (RF-37). Rechazo → `Rechazada`.
7. **Autorización CSI** – aprobación *Todos deben aprobar* o *Primero en responder* según el reglamento del CSI (parámetro `EXCEPCION_TIPO_APROBACION_CSI`, por defecto *primero en responder*), asignada a miembros de `GRUPO_CSI_ENTRAID`. Se registra en `RN_ActaCSI` el N° de acta informado en el comentario.
8. **Vigente:** `RN_EstadoExcepcion = Vigente`; en el activo `RN_ExcepcionVigente = Title` (cuenta de servicio). Historial *Excepción*. Evidencia: el PDF del historial de la aprobación se guarda en `Evidencias/<ENT>/<GER>` con `RN_TipoEvidencia = Acta CSI`.

## FL-07b Vencimientos (programado diario)
* `RN_EstadoExcepcion eq 'Vigente' and RN_FechaFin le '<Hoy + EXCEPCION_AVISO_DIAS>'` → aviso al solicitante y al CISO para reevaluación (renovación = nueva solicitud con `EsRenovacion = true`, que exige nueva autorización del CSI, RN-10).
* `RN_EstadoExcepcion eq 'Vigente' and RN_FechaFin lt '<Hoy>'` → `Vencida`; en el activo `RN_ExcepcionVigente = concat('VENCIDA ', Title)` y ejecutar FL-02b, que agrega la alerta `B08 Excepción vencida` hasta que se renueve o cierre (al cerrar se limpia el campo); aviso al CISO.
* Informe mensual al CSI (primer día hábil): excepciones vigentes, vencidas y por vencer por entidad y nivel (RF-38).

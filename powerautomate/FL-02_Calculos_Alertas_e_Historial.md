# RN-INV FL-02 Procesar cambio de activo (incluye FL-02b, FL-04 y FL-10)

| | |
|---|---|
| Requerimientos | RF-17, RF-18, RF-19, RF-20, RF-27, RF-32, RF-35, RF-41, RF-46, RN-02 a RN-09, RNF-03 (control detectivo), RNF-07 |
| Disparador | SharePoint **Cuando se crea o modifica un elemento** – lista `Activos` |
| Condición de disparador | Editor ≠ cuenta de servicio (README §2) |
| Flujos secundarios | `FL-02b Recalcular activo` (entrada: `idElemento`), `FL-01b Reasignar permisos`, `FL-03`, `FL-05b`, `FL-06b`, `FL-08`, `FL-09` |

La lógica de cálculo replica `tests/reglas/reglas.js` (especificación ejecutable con pruebas). Cualquier cambio de regla se hace primero allí.

## Paso 1 – Contexto
* *Leer parámetros* → `P`.
* `Editor` = `toLower(triggerOutputs()?['body/Editor/Email'])`.
* SharePoint **Obtener cambios de un elemento o archivo (solo propiedades)**: lista `Activos`, id `triggerOutputs()?['body/ID']`, *Desde* = `triggerOutputs()?['body/{TriggerWindowStartToken}']`, *Incluir secundarios* = no → `Cambios`. Expresiones: `body('Cambios')?['ColumnHasChanged']?['RN_Nivel']`.
* `Version` = `triggerOutputs()?['body/{VersionNumber}']`.
* SharePoint HTTP `GET _api/web/lists/getbytitle('Activos')/items(<ID>)/versions?$top=2&$select=VersionLabel,RN_Nivel,RN_Estado,RN_DuenoCargoId,RN_CustodioCargoId,RN_Confidencialidad,RN_Integridad,RN_Disponibilidad,RN_DatosPersonales,RN_DatosSensibles` → `Versiones`; `Anterior` = `body('Versiones')?['value']?[1]` (vacío en la versión 1.0).

## Paso 2 – Control de cambios no autorizados (control detectivo-correctivo)
SharePoint no tiene seguridad por columna: un usuario con edición sobre el elemento podría modificar cualquier columna desde la vista de lista. Este paso revierte lo que no le corresponde.

| Grupo de columnas | Quién puede cambiarlas | Columnas |
|---|---|---|
| **Protegidas** (solo flujos) | Nadie (se revierte siempre) | Title, RN_Correlativo, RN_Estado, RN_Critico, RN_NivelEfectivo, RN_NivelMinimo, RN_EtiquetaPurview, RN_Alertas, RN_AlertasBloqueantes, RN_ProximaRevision, RN_ProximaRevisionAccesos, RN_FechaAlta, RN_FechaUltimaRevision, RN_ResponsableUltimaRevision, RN_FechaRevisionAccesos, RN_ValidacionCISO, RN_ValidacionDPO, RN_DeclaradoPor, RN_FechaDeclaracion, RN_FechaEnvioValidacion, RN_ClavePermisos, RN_Version, RN_HistorialResumen, RN_DuenoPersona, RN_CustodioPersona, RN_ExcepcionVigente, RN_DatosBaja, RN_UltimaReclasificacion, RN_IdRiesgo, RN_ComentarioValidacion |
| **Clasificación** | Miembros del grupo de edición de la gerencia (Dueño / Delegado) o CISO | RN_Entidad, RN_Gerencia, RN_GerenciaContraparte, RN_Proceso, RN_DuenoCargo, RN_CustodioCargo, RN_Confidencialidad, RN_Integridad, RN_Disponibilidad, RN_ConfiadaTerceros, RN_NivelAcordadoTerceros, RN_Nivel, RN_DatosPersonales, RN_DatosSensibles, RN_IdRAT, RN_CargosAutorizados, RN_TercerosAutorizados, RN_PeriodoRetencion, RN_FundamentoRetencion |
| **Técnicas** | Lo anterior + Custodio | RN_IdCMDB, RN_Ubicacion, RN_TipoAlojamiento, RN_PaisProcesamiento, RN_Subtipo, RN_Formato, RN_CifradoReposo, RN_RegistroAccesos, RN_FrecuenciaRespaldo, RN_RTORPO, RN_FinSoporte |

Implementación:
```
Redactar ColsProtegidas = createArray('Title','RN_Correlativo','RN_Estado', … )        // tabla anterior
Filtrar matriz CambiosProtegidos:  Desde outputs('ColsProtegidas')
                                   Condición  equals(body('Cambios')?['ColumnHasChanged']?[item()], true)
EsGestor = Editor ∈ miembros(Ger.RN_GrupoEdicionEntraId) ∪ miembros(GRUPO_CISO_ENTRAID)     (README §4)
Filtrar matriz CambiosClasifNoAut:  si not(EsGestor) → columnas de clasificación cambiadas
Condición  greater(add(length(body('CambiosProtegidos')), length(body('CambiosClasifNoAut'))), 0)
  Sí →  SharePoint HTTP  POST .../items(<ID>)/validateUpdateListItem
         cuerpo { "formValues": [ { "FieldName": "<col>", "FieldValue": "<valor de Anterior>" } … ], "bNewDocumentUpdate": false }
        HistorialClasificacion: RN_TipoEvento = "Cambio no autorizado revertido", RN_ValorNuevo = columnas, RN_Usuario = Editor
        Correo a CORREO_CISO: "Cambio no autorizado revertido en <ID> por <Editor>"
        Terminar (Correcto)
```
Excepción: en la versión 1.0 (creada por FL-01) no se evalúa este paso.

## Paso 3 – Reclasificación y edición de activos vigentes (RF-32)
Si `Anterior.RN_Estado` ∈ {Vigente, En revisión} y cambió alguna columna de **Clasificación**:
* Si cambió `RN_Nivel` y `empty(triggerOutputs()?['body/RN_MotivoCambio'])` → revertir (como paso 2) y notificar al Editor: *"La reclasificación exige motivo (RF-32)"*.
* Si no: actualizar (cuenta de servicio) `RN_Estado = "En revisión"`, `RN_ValidacionCISO = "Pendiente"`, `RN_ValidacionDPO = if(DatosPersonales='Sí','Pendiente','No aplica')`, `RN_UltimaReclasificacion = concat(utcNow('yyyy-MM-dd'), ' | ', Anterior.RN_Nivel, ' → ', RN_Nivel, ' | ', RN_MotivoCambio, ' | ', Editor)`, `RN_MotivoCambio = ''`, `RN_Version = add(RN_Version,1)`. El Dueño debe volver a declarar → FL-03.

## Paso 4 – Acciones solicitadas desde la app
`Switch` sobre `triggerOutputs()?['body/RN_SolicitudAccion/Value']`:

| Valor | Acción |
|---|---|
| `Declarar` | Ejecutar `FL-03` (idElemento, Editor) |
| `Traspasar` | Ejecutar `FL-09` |
| `Dar de baja` | Ejecutar `FL-08` |
| `Revisión integral` | Ejecutar `FL-05b Registrar revisión integral` |
| `Revisión de accesos` | Ejecutar `FL-06b Registrar revisión de accesos` |
| otro | — |

Cada secundario devuelve `RN_SolicitudAccion` a `Ninguna` en su *Finally*.

## Paso 5 – FL-02b Recalcular activo (flujo secundario)
Entrada `idElemento`. *Obtener elemento* → `A`. Redacciones (nombres exactos, se reutilizan):

```
Orden        = json(outputs('P')?['ORDEN_NIVELES'])                     // {"Pública":1,"Uso Interno":2,"Reservado":3,"Confidencial":4}
Nombres      = json('{"1":"Pública","2":"Uso Interno","3":"Reservado","4":"Confidencial"}')
Critico      = if(or(equals(A?['RN_Confidencialidad']?['Value'],'Alta'), equals(A?['RN_Integridad']?['Value'],'Alta'), equals(A?['RN_Disponibilidad']?['Value'],'Alta')), 'Sí', 'No')
OrdMinDP     = if(equals(A?['RN_DatosPersonales']?['Value'],'Sí'), outputs('Orden')?[outputs('P')?['NIVEL_MIN_DATOS_PERSONALES']], 1)
OrdMinDS     = if(equals(A?['RN_DatosSensibles']?['Value'],'Sí'),  outputs('Orden')?[outputs('P')?['NIVEL_MIN_DATOS_SENSIBLES']], 1)
OrdMinTer    = if(and(equals(A?['RN_ConfiadaTerceros']?['Value'],'Sí'), not(empty(A?['RN_NivelAcordadoTerceros']?['Value']))), outputs('Orden')?[A?['RN_NivelAcordadoTerceros']?['Value']], 1)
OrdMinAgr    = (RF-19) max de Orden[RN_NivelEfectivo] de los activos destino de RelacionesActivos con RN_TipoRelacion = "Contiene / agrega a" y origen = A; 1 si no hay
OrdMin       = max(outputs('OrdMinDP'), outputs('OrdMinDS'), outputs('OrdMinTer'))          // nivel mínimo exigido (bloqueante)
NivelMinimo  = outputs('Nombres')?[string(outputs('OrdMin'))]
NivelSugerido= outputs('Nombres')?[string(max(outputs('OrdMin'), outputs('OrdMinAgr')))]   // agregación: sugerencia (RF-19)
NivelEfectivo= if(empty(A?['RN_Nivel']?['Value']), outputs('P')?['NIVEL_POR_DEFECTO'], A?['RN_Nivel']?['Value'])   // RN-06
OrdAsig      = if(empty(A?['RN_Nivel']?['Value']), 0, outputs('Orden')?[A?['RN_Nivel']?['Value']])
MesesRev     = if(or(equals(outputs('Critico'),'Sí'), equals(A?['RN_DatosPersonales']?['Value'],'Sí')), int(outputs('P')?['FREC_REVISION_CRITICO_MESES']), int(outputs('P')?['FREC_REVISION_MESES']))
BaseRev      = coalesce(A?['RN_FechaUltimaRevision'], A?['RN_FechaAlta'])
ProxRev      = if(empty(outputs('BaseRev')), null, addToTime(outputs('BaseRev'), outputs('MesesRev'), 'Month', 'yyyy-MM-dd'))
ConAccesos   = contains(json(outputs('P')?['NIVELES_CON_REVISION_ACCESOS']), outputs('NivelEfectivo'))
BaseAcc      = coalesce(A?['RN_FechaRevisionAccesos'], A?['RN_FechaUltimaRevision'], A?['RN_FechaAlta'])
ProxAcc      = if(and(outputs('ConAccesos'), not(empty(outputs('BaseAcc')))), addToTime(outputs('BaseAcc'), int(outputs('P')?['FREC_REVISION_ACCESOS_MESES']), 'Month', 'yyyy-MM-dd'), null)
Etiqueta     = json(outputs('P')?['MAPEO_ETIQUETAS_PURVIEW'])?[outputs('NivelEfectivo')]       // RF-46
Hoy          = utcNow('yyyy-MM-dd')
```

**Alertas** (mismos códigos que `reglas.js`; `|` separa alertas):
```
AlertasTexto = concat(
 if(empty(A?['RN_DuenoCargo']?['Id']), 'A01 Sin Dueño (cargo) asignado|', ''),
 if(or(empty(A?['RN_Confidencialidad']?['Value']), empty(A?['RN_Integridad']?['Value']), empty(A?['RN_Disponibilidad']?['Value'])), 'A02 Valoración C-I-D incompleta|', ''),
 if(equals(outputs('OrdAsig'),0), 'A03 Sin nivel de clasificación (se trata como Confidencial)|',
    if(less(outputs('OrdAsig'), outputs('OrdMin')), concat('A04 Nivel asignado (', A?['RN_Nivel']?['Value'], ') inferior al mínimo exigido (', outputs('NivelMinimo'), ')|'), '')),
 if(and(equals(A?['RN_DatosPersonales']?['Value'],'Sí'), empty(A?['RN_IdRAT'])), 'A05 Datos personales sin actividad del RAT vinculada|', ''),
 if(and(contains(createArray('Confidencial','Reservado'), coalesce(A?['RN_Nivel']?['Value'],'')), empty(A?['RN_CargosAutorizados'])), concat('A06 Nivel ', A?['RN_Nivel']?['Value'], ' sin lista de cargos autorizados|'), ''),
 if(and(equals(A?['RN_Nivel']?['Value'],'Reservado'), not(empty(A?['RN_Tercero']?['Id'])), empty(A?['RN_TercerosAutorizados'])), 'A07 Reservado con tercero sin lista de terceros autorizados|', ''),
 if(empty(A?['RN_PeriodoRetencion']), 'A08 Sin período de retención|', ''),
 if(empty(A?['RN_Entidad']?['Id']), 'A09 Sin entidad|', ''),
 if(and(equals(A?['RN_Entidad']?['Value'],'Ambas'), empty(A?['RN_GerenciaContraparte']?['Id'])), 'A10 Activo compartido sin gerencia contraparte|', ''),
 if(or(empty(A?['RN_Nombre']), empty(A?['RN_Descripcion']), empty(A?['RN_Categoria']?['Value']), empty(A?['RN_Proceso']?['Id']), empty(A?['RN_Gerencia']?['Id']), empty(A?['RN_Formato']?['Value']), empty(A?['RN_Ubicacion']), empty(A?['RN_ConfiadaTerceros']?['Value']), empty(A?['RN_DatosPersonales']?['Value']), empty(A?['RN_DatosSensibles']?['Value']), empty(A?['RN_ReglasUso']), empty(A?['RN_FundamentoRetencion'])), 'A11 Faltan campos obligatorios de normativa interna|', ''),
 if(and(equals(A?['RN_DatosSensibles']?['Value'],'Sí'), not(equals(A?['RN_DatosPersonales']?['Value'],'Sí'))), 'A12 Datos sensibles marcados sin datos personales|', ''),
 if(and(contains(json(outputs('P')?['CATEGORIAS_TECNOLOGICAS']), coalesce(A?['RN_Categoria']?['Value'],'')), empty(A?['RN_IdCMDB'])), 'B01 Activo tecnológico sin ID de CMDB|', ''),
 if(and(contains(json(outputs('P')?['ALOJAMIENTOS_EXTERNOS']), coalesce(A?['RN_TipoAlojamiento']?['Value'],'')), or(empty(A?['RN_Tercero']?['Id']), empty(A?['RN_PaisProcesamiento']))), 'B02 Alojamiento externo sin tercero o país|', ''),
 if(and(equals(outputs('Critico'),'Sí'), empty(A?['RN_IdRiesgo'])), 'B03 Activo crítico sin ID en matriz de riesgos|', ''),
 if(and(not(empty(outputs('ProxRev'))), less(outputs('ProxRev'), outputs('Hoy'))), 'B04 Revisión integral vencida|', ''),
 if(and(not(empty(outputs('ProxAcc'))), less(outputs('ProxAcc'), outputs('Hoy'))), 'B05 Revisión de accesos vencida|', ''),
 if(equals(A?['RN_TransferenciaInternacional']?['Value'],'Sí'), 'B06 Transferencia internacional de datos personales (revisión DPO)|', ''),
 if(and(not(empty(A?['RN_FinSoporte'])), less(formatDateTime(A?['RN_FinSoporte'],'yyyy-MM-dd'), outputs('Hoy'))), 'B07 Fuera de soporte del fabricante|', ''),
 if(startsWith(coalesce(A?['RN_ExcepcionVigente'],''), 'VENCIDA'), 'B08 Excepción vencida|', '')
)
Bloqueante = or(contains(outputs('AlertasTexto'),'A0'), contains(outputs('AlertasTexto'),'A1'))
```
Las fechas se comparan como texto `yyyy-MM-dd` (orden lexicográfico = cronológico).

**Actualizar elemento** (cuenta de servicio; solo si algún valor difiere del actual, para no generar versiones vacías):
`RN_Critico = Critico`, `RN_NivelMinimo = NivelMinimo`, `RN_NivelEfectivo = NivelEfectivo`, `RN_EtiquetaPurview = Etiqueta`, `RN_ProximaRevision = ProxRev`, `RN_ProximaRevisionAccesos = ProxAcc`, `RN_Alertas = replace(outputs('AlertasTexto'),'|', decodeUriComponent('%0A'))`, `RN_AlertasBloqueantes = Bloqueante`, `RN_ReglasUso` (si vacío) `= json(outputs('P')?['REGLAS_MANEJO'])?[NivelEfectivo]?['referencia']`.

Si `NivelSugerido ≠ RN_Nivel` y la diferencia viene solo de la agregación, se agrega a `RN_Alertas` la línea `S01 Nivel sugerido por agregación: <NivelSugerido>` (no bloqueante).

## Paso 6 – Permisos (RNF-03)
`ClaveNueva = concat(A.RN_Entidad.Value,'|',A.RN_Gerencia.Value,'|',A.RN_GerenciaContraparte.Value,'|',A.RN_CustodioPersona)`. Si `≠ A.RN_ClavePermisos` → `FL-01b Reasignar permisos` (idéntico a FL-01 §6 precedido de `POST …/items(<ID>)/resetroleinheritance` y nuevo `breakroleinheritance(copyRoleAssignments=false,clearSubscopes=true)`; ambos en la misma ejecución para minimizar la ventana). Registrar evento *Cambio de Dueño/Custodio* si corresponde.

## Paso 7 – FL-04 Historial (RF-32, RF-35, RNF-07)
Por cada columna con cambio entre {RN_Nivel, RN_Estado, RN_DuenoCargo, RN_CustodioCargo} (`ColumnHasChanged`), *Crear elemento* en `HistorialClasificacion`:

| Columna | Valor |
|---|---|
| Title | `concat(<TipoEvento>, ' ', A?['Title'])` |
| RN_Activo / RN_IdActivoTexto / RN_Entidad | Id del activo / `A?['Title']` / código de entidad |
| RN_TipoEvento | Nivel → `Reclasificación`; Estado → `Cambio de estado`; Dueño → `Cambio de Dueño`; Custodio → `Cambio de Custodio` |
| RN_ValorAnterior / RN_ValorNuevo | de `Anterior` / de `A` |
| RN_Motivo | `RN_MotivoCambio` (antes de limpiarlo) |
| RN_Usuario | `Editor` (no la cuenta de servicio) |
| RN_FechaEvento | `utcNow()` |
| RN_VersionActivo | `Version` |

Luego actualizar `RN_HistorialResumen` del activo (últimos 20 eventos visibles para el Dueño):
```
join(take(split(concat(utcNow('yyyy-MM-dd HH:mm'), ' · ', <TipoEvento>, ' · ', <Anterior>, ' → ', <Nuevo>, ' · ', Editor, decodeUriComponent('%0A'), coalesce(A?['RN_HistorialResumen'],'')), decodeUriComponent('%0A')), 20), decodeUriComponent('%0A'))
```

## Paso 8 – Avisos DPO y Riesgos (FL-10)
Condiciones evaluadas tras el recálculo:

| Condición | Aviso | Requisito |
|---|---|---|
| `RN_DatosSensibles = Sí` o `RN_TransferenciaInternacional = Sí`, y (es versión 1.0 o cambió alguna de ellas o `RN_Nivel`) | Correo + tarjeta Teams a `CORREO_DPO` con enlace al activo | RF-41 |
| `Critico = Sí` y (versión 1.0 o cambió C-I-D o `RN_Nivel`) | Correo a `CORREO_RIESGOS` solicitando el ID de riesgo; la Gerencia de Riesgos lo registra desde la app con el flujo instantáneo **FL-10b Registrar ID de riesgo** (autoriza grupo `SGSI-INV-RIESGOS`; escribe `RN_IdRiesgo` como cuenta de servicio y registra historial) | RF-27 |

Plantilla del correo DPO (HTML): asunto `[SGSI][Reservado] Activo con datos sensibles / transferencia internacional – <ID>`; cuerpo con Entidad, Gerencia, Nombre, Nivel, Tercero, País, Id RAT y botón "Abrir en la aplicación" (`rnsgsi_UrlApp?activoId=<ID>`). Los correos no incluyen datos de titulares (RN-16).

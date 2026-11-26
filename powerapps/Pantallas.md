# Aplicación canvas "Inventario de Activos" – pantallas y fórmulas

Diseño: formato **tableta** (1366×768) con diseño adaptable (contenedores horizontales/verticales) para operar en navegador, Teams y móvil (RNF-12). Tema corporativo; color por nivel según `ColorNivel()`. Idioma español. Cada campo tiene un icono ⓘ con la ayuda contextual del Catálogo (`config/catalogo-campos.json` → `nota`/`condicion`), almacenada en la colección `colAyuda` (cargada desde una lista o un JSON incrustado).

Orígenes de datos: listas `Activos`, `Entidades`, `Gerencias`, `Procesos`, `Cargos`, `Terceros`, `Parametros`, `Excepciones`, `CatalogoRAT`, `RelacionesActivos`, biblioteca `Evidencias`; conectores Office 365 Users y Office 365 Groups; flujos FL-01, FL-07a, FL-10b, FL-16.

**Reglas de delegación (RNF-09).** Todos los `Filter` sobre `Activos` usan, como primer criterio, columnas indexadas y operadores delegables en SharePoint (`=` sobre `.Id` de búsqueda, `.Value` de elección y `.Email` de persona; `<`/`>` sobre fechas; `StartsWith` sobre texto). Nada de `in`, `Search` ni `Len` sobre `Activos`. Límite de registros de datos de la app: 2.000.

---

## 1. scrInicio – Mis pendientes
| Control | Propiedad | Fórmula |
|---|---|---|
| `galPendValidacion` (CISO/DPO) | Items | `If(gblEsCISO \|\| gblEsDPO, Filter(Activos, RN_Estado.Value = "En validación"), Blank())` y luego en la galería `Filter(Self.AllItems, (gblEsCISO && RN_ValidacionCISO.Value = "Pendiente") \|\| (gblEsDPO && RN_ValidacionDPO.Value = "Pendiente"))` |
| `galObservados` | Items | `Filter(Activos, RN_Estado.Value = "Observado", RN_DuenoPersona.Email = User().Email)` |
| `galRevisionesPorVencer` | Items | `Filter(Activos, RN_ProximaRevision <= DateAdd(Today(), 30), RN_Estado.Value = "Vigente", RN_DuenoPersona.Email = User().Email)` |
| `galAccesosPorVencer` | Items | `Filter(Activos, RN_ProximaRevisionAccesos <= DateAdd(Today(), 30), RN_Estado.Value = "Vigente", RN_DuenoPersona.Email = User().Email)` |
| `galExcepcionesPorVencer` | Items | `Filter(Excepciones, RN_EstadoExcepcion.Value = "Vigente", RN_FechaFin <= DateAdd(Today(), 30))` (solo devuelve las que el usuario puede ver) |
| Contadores | Text | `CountRows(galX.AllItems)` con semáforo: rojo si hay vencidos |

## 2. scrMisActivos
| Control | Propiedad | Fórmula |
|---|---|---|
| `drpEntidad`, `drpGerencia`, `drpNivel`, `drpEstado`, `drpCritico`, `drpDatosPersonales`, `txtBuscar` | — | Filtros (RF-15) |
| `galActivos` | Items | ```Filter(Activos, (IsBlank(drpGerencia.Selected) \|\| RN_Gerencia.Id = drpGerencia.Selected.ID), (IsBlank(drpEstado.Selected) \|\| RN_Estado.Value = drpEstado.Selected.Value), (IsBlank(drpNivel.Selected) \|\| RN_NivelEfectivo.Value = drpNivel.Selected.Value), (IsBlank(drpCritico.Selected) \|\| RN_Critico.Value = drpCritico.Selected.Value), (IsBlank(drpDatosPersonales.Selected) \|\| RN_DatosPersonales.Value = drpDatosPersonales.Selected.Value), StartsWith(RN_Nombre, txtBuscar.Text) \|\| StartsWith(Title, Upper(txtBuscar.Text)))``` – SharePoint ya limita a lo que el usuario puede ver |
| Semáforo en cada fila | Fill | `If(ThisItem.RN_AlertasBloqueantes, Color.Red, !IsBlank(ThisItem.RN_Alertas), Color.Orange, Color.Green)` |
| Etiqueta de nivel | Fill | `ColorNivel(ThisItem.RN_NivelEfectivo.Value)` – los sin clasificar se muestran como Confidencial (RF-20) |
| `btnNuevo` | OnSelect | `Set(varB, Defaults(Activos)); Set(varPaso, 1); Navigate(scrAsistente)` |
| `btnExportar` | OnSelect | ver §8 |

## 3. scrAsistente – Asistente de registro en 5 pasos (RNF-13)
El borrador vive en `varB` (registro con nombres internos + campos auxiliares `RN_EntidadId`, `RN_GerenciaId`, `EntidadCodigo`, etc.). Los controles escriben en `varB` con `OnChange`: `Set(varB, Patch(varB, { RN_Nivel: Self.Selected.Value }))`. Las fórmulas con nombre (`AlertasBorrador`, `BorradorNivelMinimo`, `Mostrar*`) se recalculan solas.

| Paso | Contenido | Visible / validación |
|---|---|---|
| 1. Identificación | Entidad, Gerencia (filtrada: `Filter(colGerencias, RN_Entidad.Id = drpEnt.Selected.ID \|\| RN_EsCorporativa)`), Gerencia contraparte (`Visible = MostrarContraparte`), Proceso (filtrado por gerencia), Dueño (cargo; `Filter(Cargos, RN_Gerencia.Id = varB.RN_GerenciaId, RN_PuedeSerDueno)`), Custodio, Nombre, Descripción, Categoría, Subtipo (`Visible = CamposEIHabilitados`) | Siguiente habilitado si no hay alertas de `Paso = 1`. **Al salir del paso 1 por primera vez** se crea el borrador en el servidor: ver abajo |
| 2. Ubicación | Formato, Ubicación, Tipo de alojamiento, País (`Visible = MostrarTercero`), Tercero, ID CMDB (`Visible = MostrarCMDB`), Función crítica/BIA (EI) | Alertas `Paso = 2` como advertencias |
| 3. Valoración C-I-D | Tres selectores Alta/Media/Baja con ayuda contextual por criterio (NC 4.2, RF-16); ¿confiada por terceros? y nivel acordado; Nivel asignado | Tarjeta resumen: *Crítico: Sí/No* (`BorradorCritico`), *Nivel mínimo: X* (`BorradorNivelMinimo`); el selector de nivel marca en rojo los niveles con `OrdenNivel(n) < OrdenNivel(BorradorNivelMinimo)` (RF-18, CA-01) |
| 4. Datos personales y terceros | ¿Datos personales? ¿Sensibles? Si Sí: Id RAT (combo sobre `CatalogoRAT` filtrado por entidad y `RN_Vigente`, RF-39), categoría de titulares, base de licitud, volumen, transferencia internacional (EI según parámetro); tercero, contrato, ¿externalizado significativo? | Texto fijo: *"No ingrese datos de titulares: solo el tipo de datos y dónde están (RN-16)"* |
| 5. Uso y retención | Reglas de uso (precargado: `Text(ReglasManejo[varB.RN_Nivel].referencia)`), cargos autorizados (`Visible/Required = ExigeCargosAutorizados`), terceros autorizados, período y fundamento de retención, controles (cifrado, logs, respaldo, RTO/RPO, IA – EI) | Panel **Reglas de manejo del nivel** (RF-22): almacenamiento, transmisión, impresión, medios removibles y eliminación desde `ReglasManejo` |

**Crear borrador (fin del paso 1, RF-07, RF-10):**
```
If(IsBlank(varB.ID),
    Set(varResp, 'RN-INVFL-01Altadeactivo'.Run(JSON({
        RN_EntidadId: varB.RN_EntidadId, RN_GerenciaId: varB.RN_GerenciaId, RN_GerenciaContraparteId: varB.RN_GerenciaContraparteId,
        RN_ProcesoId: varB.RN_ProcesoId, RN_DuenoCargoId: varB.RN_DuenoCargoId, RN_CustodioCargoId: varB.RN_CustodioCargoId,
        RN_Nombre: varB.RN_Nombre, RN_Descripcion: varB.RN_Descripcion, RN_Categoria: varB.RN_Categoria }), "Aplicación", ""));
    If(varResp.ok = "true",
        Set(varB, Patch(varB, { ID: Value(varResp.idelemento), Title: varResp.idactivo }));
        Notify("Borrador " & varResp.idactivo & " creado", NotificationType.Success),
        Notify(varResp.mensaje, NotificationType.Error)
    )
);
If(!IsBlank(varB.ID), Set(varPaso, varPaso + 1))
```
**Guardar (pasos 2-5, borrador):** el usuario edita **con sus propios permisos** (la app no usa la cuenta de servicio para editar):
```
Patch(Activos, LookUp(Activos, ID = varB.ID), {
    RN_Formato: { Value: varB.RN_Formato }, RN_Ubicacion: varB.RN_Ubicacion, RN_TipoAlojamiento: { Value: varB.RN_TipoAlojamiento },
    RN_Confidencialidad: { Value: varB.RN_Confidencialidad }, RN_Integridad: { Value: varB.RN_Integridad }, RN_Disponibilidad: { Value: varB.RN_Disponibilidad },
    RN_Nivel: { Value: varB.RN_Nivel }, RN_DatosPersonales: { Value: varB.RN_DatosPersonales }, RN_DatosSensibles: { Value: varB.RN_DatosSensibles },
    RN_IdRAT: varB.RN_IdRAT, RN_CargosAutorizados: varB.RN_CargosAutorizados, RN_PeriodoRetencion: varB.RN_PeriodoRetencion,
    RN_FundamentoRetencion: varB.RN_FundamentoRetencion, RN_ReglasUso: varB.RN_ReglasUso,
    RN_Tercero: If(IsBlank(varB.RN_TerceroId), Blank(), { Id: varB.RN_TerceroId, Value: LookUp(colTerceros, ID = varB.RN_TerceroId).Title })
    /* … resto de columnas del paso … */ });
Notify("Guardado como borrador", NotificationType.Information)
```
**Enviar a validación (RF-10, RF-23, RF-26):**
| Control | Propiedad | Fórmula |
|---|---|---|
| `btnDeclarar` | DisplayMode | `If(!BorradorTieneBloqueantes && PuedeDeclarar(varB.RN_DuenoCargoId), DisplayMode.Edit, DisplayMode.Disabled)` |
| `lblMotivoDeshabilitado` | Text | `If(!PuedeDeclarar(varB.RN_DuenoCargoId), "Solo el titular del cargo Dueño o su subrogante puede declarar. Su trabajo queda guardado como borrador.", Concat(Filter(AlertasBorrador, Bloqueante), Codigo & " " & Mensaje, Char(10)))` |
| `chkDeclaracion` | Text | *"Declaro, como Dueño del activo, que la información registrada es correcta y que la clasificación asignada cumple la Norma de Clasificación de la Información."* (obligatorio) |
| `btnDeclarar` | OnSelect | guardar (Patch anterior) y luego `Patch(Activos, LookUp(Activos, ID = varB.ID), { RN_SolicitudAccion: { Value: "Declarar" } }); Notify("Enviado a validación"); Navigate(scrMisActivos)` |

## 4. scrFicha – Ficha del activo
Pestañas (contenedor con `TabList`) por grupo del Catálogo: Identificación · Responsables · Ubicación · Valoración · Datos personales · Terceros · Controles y uso · Ciclo de vida · Validación. Además:
* **Historial** (RF-35): `Split(gblActivo.RN_HistorialResumen, Char(10))`; los roles transversales ven además `Filter(HistorialClasificacion, RN_Activo.Id = gblActivo.ID)`.
* **Evidencias** (RF-12): galería sobre `Filter(Evidencias, RN_IdActivo = gblActivo.Title)`; control *Datos adjuntos* + flujo de subida, o botón "Abrir carpeta" `Launch(<url de Evidencias/ENT/GER>)`.
* **Relaciones** (RF-11): `Filter(RelacionesActivos, RN_ActivoOrigen.Id = gblActivo.ID)`.
* **Excepciones**: `Filter(Excepciones, RN_Activo.Id = gblActivo.ID)`.
* **Acciones** (visibles según estado y `PuedeDeclarar`): *Editar* (vuelve al asistente con `varB = gblActivo`), *Reclasificar* (exige `RN_MotivoCambio`, RF-32), *Traspasar* (selector de cargo receptor, RF-33), *Dar de baja* (método por nivel desde `MetodoBajaPorNivel`, ¿por proveedor?, N° certificado, RF-34), *Solicitar excepción* (§7), *Duplicar como plantilla* (RF-13: `Set(varB, Patch(gblActivo, { ID: Blank(), Title: Blank(), RN_Nombre: "Copia de " & gblActivo.RN_Nombre }))`), *Registrar ID de riesgo* (solo `gblEsRiesgos`, llama FL-10b).

## 5. scrValidacion – Bandeja CISO / DPO (RF-23, RF-40)
* Lista izquierda: activos en validación pendientes del rol (como `galPendValidacion`).
* **Vista comparativa del cambio**: tabla de dos columnas *Valor validado anterior* vs *Valor declarado*, a partir de la última versión con `RN_Estado = Vigente` (`RN_UltimaReclasificacion` + historial).
* Botones **Validar** / **Observar** abren la tarjeta de Approvals asociada (las decisiones se registran solo vía Approvals para conservar la evidencia). Observar exige comentario.
* **Bandeja DPO** (RF-40), pestaña adicional para `gblEsDPO`:
  `Filter(Activos, RN_DatosPersonales.Value = "Sí", RN_Estado.Value <> "Dado de baja")` y en la galería: `Filter(Self.AllItems, IsBlank(RN_IdRAT) || RN_TransferenciaInternacional.Value = "Sí" || RN_DatosSensibles.Value = "Sí")` con indicador por motivo, ambas entidades.

## 6. scrRevisiones – Campañas (RF-29, RF-30)
* `drpCampana`: `Distinct(Filter(Activos, RN_ProximaRevision <= DateAdd(Today(), 30), RN_DuenoPersona.Email = User().Email), Text(RN_ProximaRevision, "yyyy-mm"))`.
* `galCampana` con casillas; `btnSinCambiosLote` (confirmación en lote "sin cambios"):
```
ForAll(Filter(galCampana.AllItems, chkSel.Value) As a,
    Patch(Activos, LookUp(Activos, ID = a.ID), { RN_ResultadoRevision: "Revisión integral sin cambios (campaña " & drpCampana.Selected.Value & ")",
        RN_RevisionConCambios: false, RN_SolicitudAccion: { Value: "Revisión integral" } }));
Notify(CountRows(Filter(galCampana.AllItems, chkSel.Value)) & " activos confirmados", NotificationType.Success)
```
* Revisión de accesos: por activo, *N° accesos retirados*, *hallazgos* y carga de la evidencia (lista de accesos) antes de confirmar (`RN_SolicitudAccion = "Revisión de accesos"`).

## 7. scrExcepciones (RF-36 a RF-38)
* Formulario: control exceptuado, fundamento, riesgo, controles compensatorios, inicio, fin.
* `dteFin.DisplayMode`/`btnSolicitar.DisplayMode`: deshabilitado si `dteFin.SelectedDate > DateAdd(dteInicio.SelectedDate, MaxMesesExcepcion, TimeUnit.Months)` con mensaje *"La vigencia no puede superar 12 meses (RN-10)"* (CA-07).
* `btnSolicitar.OnSelect`: `'RN-INVFL-07aSolicitarexcepcion'.Run(gblActivo.ID, JSON({ ControlExceptuado: …, FechaInicio: Text(dteInicio.SelectedDate,"yyyy-mm-dd"), FechaFin: Text(dteFin.SelectedDate,"yyyy-mm-dd"), EsRenovacion: chkRenovacion.Value }))`.
* Registro por entidad con estado vigente / vencida / cerrada.

## 8. Exportar a Excel (RF-44)
`btnExportar.OnSelect`:
```
Set(varExp, 'RN-INVFL-16Exportarinventario'.Run(JSON({ gerenciaId: drpGerencia.Selected.ID, estado: drpEstado.Selected.Value, nivel: drpNivel.Selected.Value })));
If(varExp.ok = "true", Launch(varExp.url), Notify(varExp.mensaje, NotificationType.Error))
```
FL-16 se ejecuta **con la conexión del propio usuario** (no con la cuenta de servicio), de modo que solo exporta lo que él puede ver, y genera el archivo a partir de una plantilla con etiqueta **Reservado** (ver `powerautomate/FL-16_Exportar.md`).

## 9. scrAdministracion – solo `gblEsCISO` (RF-48)
* Maestros (formularios sobre Entidades, Gerencias, Procesos, Cargos, Terceros), Parámetros (edición con validación de JSON: `IsError(ParseJSON(txtValor.Text))`).
* **Reasignación masiva de Dueños:** selección de activos por cargo Dueño origen → cargo destino; ejecuta `RN_SolicitudAccion = "Traspasar"` con `RN_CargoReceptor` por cada uno (FL-09; el CISO puede reasignar administrativamente).
* **Reapertura:** devuelve un activo *Vigente* a *En revisión* con motivo (vía flujo, porque `RN_Estado` es columna protegida).
* **Carga masiva:** enlace a `CargaMasiva/Entrada` y a los reportes.
* **Indicadores técnicos:** número de elementos con permisos únicos (último respaldo FL-12) y su relación con el umbral.

## 10. Publicación en Teams (RF-47)
En el canal **SGSI** del equipo correspondiente: *Agregar pestaña → Power Apps → Inventario de Activos*. Los enlaces profundos de los correos usan `rnsgsi_UrlApp`.

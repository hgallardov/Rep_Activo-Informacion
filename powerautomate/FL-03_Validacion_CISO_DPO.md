# RN-INV FL-03 Declaración y validación CISO / DPO

| | |
|---|---|
| Requerimientos | RF-10, RF-23, RF-24, RF-25, RF-26, RN-09, CA-03, CA-05 |
| Disparador | Flujo secundario llamado por FL-02 cuando `RN_SolicitudAccion = Declarar`. Entradas: `idElemento`, `editor` (UPN) |
| Conectores | SharePoint, Approvals, Office 365 Outlook, Microsoft Teams |

## 1. Pre-condiciones de la declaración
1. Ejecutar `FL-02b Recalcular activo` (las alertas deben estar al día).
2. *Obtener elemento* `Activos` → `A`; *Obtener elemento* `Cargos` (id `A.RN_DuenoCargo.Id`) → `C`.
3. **Solo el titular o el subrogante declaran (RF-26):**
   `PuedeDeclarar = or(equals(editor, toLower(C?['RN_Titular']?['Email'])), equals(editor, toLower(C?['RN_Subrogante']?['Email'])))`.
   Si es falso: `RN_SolicitudAccion = Ninguna`; notificar al editor en Teams *"Solo el titular del cargo Dueño (o su subrogante registrado) puede declarar. Su registro quedó guardado como borrador."*; historial *Cambio no autorizado revertido*; terminar.
4. **Sin alertas bloqueantes (RN-09, RF-10, CA-05):** si `A.RN_AlertasBloqueantes = true` → devolver `RN_SolicitudAccion = Ninguna`, notificar al editor con el texto de `RN_Alertas` y terminar (el activo no entra a validación).
5. Actualizar `A`: `RN_Estado = En validación`, `RN_DeclaradoPor = editor`, `RN_FechaDeclaracion = utcNow()`, `RN_FechaEnvioValidacion = utcNow()`, `RN_ValidacionCISO = Pendiente`, `RN_ValidacionDPO = if(DatosPersonales='Sí','Pendiente','No aplica')`, `RN_SolicitudAccion = Ninguna`. Historial: *Declaración* (usuario = editor).

## 2. Validación del CISO (RF-23)
*Iniciar y esperar una aprobación* – tipo **Aprobar/Rechazar: primero en responder**:

| Campo | Valor |
|---|---|
| Título | `concat('Validación de clasificación – ', A?['Title'], ' – ', A?['RN_Nombre'])` |
| Asignado a | miembros de `SGSI-INV-CISO` (lista de UPN separada por `;`, obtenida con *List group members*) **excluyendo** a `editor` (segregación: quien declara no valida) |
| Detalles (Markdown) | Entidad, Gerencia, Dueño (cargo), C-I-D, crítico, nivel asignado / mínimo / efectivo, datos personales y sensibles, RAT, tercero/país, cargos autorizados, `RN_UltimaReclasificacion` si existe, y vínculo a la ficha comparativa |
| Vínculo | `concat(parameters('rnsgsi_UrlApp'), '?activoId=', A?['ID'], '&pantalla=validacion')` |
| Habilitar notificaciones | Sí (Outlook + Teams) |

Plazo y escalamiento (RF-25): la acción de aprobación se coloca en paralelo con una rama *Hacer hasta* que espera `PLAZO_VALIDACION_DIAS` (Retraso) y envía recordatorio; a los `ESCALAR_VALIDACION_DIAS` envía correo de escalamiento al CSI (miembros de `GRUPO_CSI_ENTRAID`). La rama se cancela cuando termina la aprobación (patrón *Terminate* en la rama de espera condicionada a una variable `vResuelto`). La aprobación expira a los 30 días (límite del conector); si expira, se vuelve a crear.

* **Rechazar = Observar (RF-24):** el comentario es obligatorio. Si `empty(first(body('Aprobacion_CISO')?['responses'])?['comments'])`, se crea una nueva aprobación solicitando el comentario (la tarjeta de Approvals no permite exigirlo de forma nativa).
  Actualizar: `RN_Estado = Observado`, `RN_ValidacionCISO = Observado`, `RN_ComentarioValidacion = concat(respondedor, ': ', comentario)`. Historial *Observación*. Notificar al **titular del cargo Dueño y al Delegado** por **Outlook y Teams** (CA-03) con el comentario y el enlace. Terminar.
* **Aprobar:** `RN_ValidacionCISO = Validado`. Historial *Validación CISO* con `RN_Usuario = respondedor` (lo usa el control CAAT C08).

## 3. Validación del DPO (solo si `RN_DatosPersonales = Sí`)
Igual que §2, asignada a miembros de `SGSI-INV-DPO`; detalles adicionales: Id RAT, categoría de titulares, base de licitud, volumen, transferencia internacional, tercero encargado y contrato.
* Observar → `RN_Estado = Observado`, `RN_ValidacionDPO = Observado`, misma notificación; el CISO queda informado.
* Aprobar → `RN_ValidacionDPO = Validado`; historial *Validación DPO*.

## 4. Cierre
Si CISO = Validado y (DPO = Validado o No aplica):
* `FL-02b` (recalcular) y comprobar de nuevo `RN_AlertasBloqueantes = false` (si algo cambió durante la validación, volver a *En validación*).
* Actualizar: `RN_Estado = Vigente`, `RN_FechaUltimaRevision = utcNow('yyyy-MM-dd')` (en el alta), `RN_ResponsableUltimaRevision = editor`, `RN_FechaRevisionAccesos` = hoy si es Confidencial/Reservado y está vacía; recalcular próximas revisiones.
* Historial *Cambio de estado → Vigente*. Notificar al Dueño: *"Su activo <ID> está Vigente"*.
* Si es crítico y es alta o reclasificación → FL-10 (aviso a Riesgos).

# RN-INV FL-01 Alta de activo

| | |
|---|---|
| Requerimientos | RF-07, RF-08, RF-12, RN-01, RN-13, RNF-03, CA-02 |
| Disparador | **Power Apps (V2)** – lo invoca la app al pulsar *Crear borrador* en el paso 1 del asistente. También lo llama FL-11 (carga masiva) como flujo secundario. |
| Ejecuta como | Cuenta de servicio (conexiones *Use this connection*) |
| Respuesta | `{ ok, idElemento, idActivo, mensaje }` |

## Entradas (Power Apps V2)

| Nombre | Tipo | Obligatorio |
|---|---|---|
| `datosJson` | Texto | Sí – JSON con los campos del paso 1 (`RN_Nombre`, `RN_Descripcion`, `RN_Categoria`, `RN_EntidadId`, `RN_GerenciaId`, `RN_GerenciaContraparteId`, `RN_ProcesoId`, `RN_DuenoCargoId`, `RN_CustodioCargoId`) |
| `origen` | Texto | No – `Aplicación` (defecto) o `Carga masiva` |
| `invocadorCarga` | Texto | Solo FL-11: UPN de quien dejó el archivo |

## Pasos

### 1. Contexto
1. *Leer parámetros* (bloque estándar, README §1).
2. `Invocador` = `if(empty(triggerBody()?['text_2']), toLower(triggerOutputs()?['headers']?['x-ms-user-email']), toLower(triggerBody()?['text_2']))` (el segundo caso solo para FL-11, que se ejecuta como cuenta de servicio y pasa el UPN de quien cargó).
3. `D` (Redactar) = `json(triggerBody()?['text'])`.
4. SharePoint *Obtener elemento* `Gerencias` id `outputs('D')?['RN_GerenciaId']` → `Ger`. Ídem `Entidades` → `Ent`; si `RN_GerenciaContraparteId` no está vacío, `Gerencias` → `GerCon`.

### 2. Validaciones de entrada (rechazo inmediato)
| Regla | Expresión de fallo | Mensaje |
|---|---|---|
| Entidad obligatoria (RF-08) | `empty(outputs('D')?['RN_EntidadId'])` | Debe indicar la entidad |
| Gerencia pertenece a la entidad, o es corporativa | `and(not(equals(body('Ger')?['RN_Entidad']?['Id'], outputs('D')?['RN_EntidadId'])), not(body('Ger')?['RN_EsCorporativa']))` | La gerencia no corresponde a la entidad |
| "Ambas" exige contraparte (RF-08, RN-13) | `and(equals(body('Ent')?['RN_Codigo'],'AMBAS'), empty(outputs('D')?['RN_GerenciaContraparteId']))` | Activo compartido: indique la gerencia contraparte |
| Sin datos personales de titulares (RN-16) | Filtrar con `isMatch` no está disponible: se valida en la app; aquí solo longitud máx. 255 en nombre | — |

### 3. Autorización (README §4)
Autorizado si `Invocador` ∈ miembros de `body('Ger')?['RN_GrupoEdicionEntraId']` **o** ∈ `outputs('P')?['GRUPO_CISO_ENTRAID']`. Para FL-11 se evalúa la misma regla con el UPN de quien cargó el archivo.

### 4. Correlativo e ID único (RF-07, RN-01) – control de concurrencia optimista
```
Redactar Clave = concat(body('Ent')?['RN_Codigo'], '-', body('Ger')?['RN_Codigo'])          // p. ej. RNSG-GTG
Inicializar variable  vListo (bool) = false ;  vCorrelativo (int) = 0 ;  vIntentos (int) = 0
Hacer hasta  or(variables('vListo'), greaterOrEquals(variables('vIntentos'), 10))
   Incrementar vIntentos
   SharePoint – Enviar solicitud HTTP   GET
     _api/web/lists/getbytitle('Correlativos')/items?$filter=Title eq '@{outputs('Clave')}'&$select=Id,RN_Ultimo
     Encabezados: Accept: application/json;odata=nometadata
   Condición: empty(body('Leer_correlativo')?['value'])
     Sí  → SharePoint Crear elemento Correlativos { Title: Clave, RN_Ultimo: 1 }  → vCorrelativo = 1 ; vListo = true
           (si falla por carrera, la siguiente vuelta lo leerá)
     No  → SharePoint HTTP  POST  _api/web/lists/getbytitle('Correlativos')/items(@{first(body('Leer_correlativo')?['value'])?['Id']})
           Encabezados:  IF-MATCH: @{first(body('Leer_correlativo')?['value'])?['odata.etag']}   (leer con odata=minimalmetadata para obtener el etag)
                         X-HTTP-Method: MERGE ; Content-Type: application/json;odata=nometadata
           Cuerpo:  { "RN_Ultimo": @{add(first(body('Leer_correlativo')?['value'])?['RN_Ultimo'], 1)} }
           Si statusCode = 204 → vCorrelativo = RN_Ultimo + 1 ; vListo = true
           Si 412 (otro flujo actualizó primero) → Retraso 2 s y repetir
IdActivo = concat('AI-', outputs('Clave'), '-', formatNumber(variables('vCorrelativo'), '00000'))
```
El correlativo nunca disminuye ni se reutiliza tras una baja (RN-01). Si tras 10 intentos no se obtuvo, ir a *Catch*.

### 5. Crear el elemento como cuenta de servicio
SharePoint **Crear elemento** en `Activos`:

| Columna | Valor |
|---|---|
| Title | `outputs('IdActivo')` |
| RN_Correlativo | `variables('vCorrelativo')` |
| RN_Entidad Id | `outputs('D')?['RN_EntidadId']` |
| RN_Gerencia Id / RN_GerenciaContraparte Id / RN_Proceso Id / RN_DuenoCargo Id / RN_CustodioCargo Id | desde `D` |
| RN_Nombre, RN_Descripcion, RN_Categoria | desde `D` |
| RN_Estado | `Borrador` · RN_ValidacionCISO `Pendiente` · RN_ValidacionDPO `No aplica` |
| RN_FechaAlta | `utcNow('yyyy-MM-dd')` |
| RN_DelegadoRegistro Claims | `outputs('Invocador')` |
| RN_DuenoPersona Claims | titular del cargo Dueño (*Obtener elemento* `Cargos` → `RN_Titular/Email`) |
| RN_CustodioPersona | titular del cargo Custodio (texto UPN) |
| RN_OrigenCarga | `triggerBody()?['text_1']` o `Aplicación` |
| RN_Version | 1 |
| RN_SolicitudAccion | `Ninguna` |

### 6. Permisos únicos del elemento (sección 13)
```
POST _api/web/lists/getbytitle('Activos')/items(@{body('Crear_activo')?['ID']})/breakroleinheritance(copyRoleAssignments=false,clearSubscopes=true)
```
La cuenta de servicio queda con Control total (efecto de copiar = false). Luego, por cada asignación (acción *Aplicar a cada uno* sobre una matriz construida con *Redactar*):

```
Redactar Asignaciones =
createArray(
  json(concat('{"p":', string(body('Ger')?['RN_GrupoEdicionSPId']), ',"r":', outputs('P')?['ROL_EDICION_ID'], '}')),
  json(concat('{"p":', outputs('P')?['GRUPO_CISO_SPID'],      ',"r":', outputs('P')?['ROL_EDICION_ID'], '}')),
  json(concat('{"p":', outputs('P')?['GRUPO_DPO_SPID'],       ',"r":', outputs('P')?['ROL_LECTURA_ID'], '}')),
  json(concat('{"p":', outputs('P')?['GRUPO_RIESGOS_SPID'],   ',"r":', outputs('P')?['ROL_LECTURA_ID'], '}')),
  json(concat('{"p":', outputs('P')?['GRUPO_CSI_SPID'],       ',"r":', outputs('P')?['ROL_LECTURA_ID'], '}')),
  json(concat('{"p":', outputs('P')?['GRUPO_AUDITORIA_SPID'], ',"r":', outputs('P')?['ROL_LECTURA_ID'], '}'))
)
+ (si Entidad = AMBAS)  {"p": GerCon.RN_GrupoEdicionSPId, "r": ROL_EDICION_ID}     → union()
+ (si hay Custodio)     {"p": <Id de ensureuser(UPN custodio)>, "r": ROL_EDICION_ID}

Por cada a:  POST _api/web/lists/getbytitle('Activos')/items(<ID>)/roleassignments/addroleassignment(principalid=@{items('Por_cada')?['p']},roledefid=@{items('Por_cada')?['r']})
```
`ensureuser`: `POST _api/web/ensureuser` cuerpo `{ "logonName": "<UPN>" }` → `body(...)?['d']?['Id']` (Accept `application/json;odata=verbose`).

Al terminar, actualizar `RN_ClavePermisos` con `concat(Entidad,'|',Gerencia,'|',Contraparte,'|',CustodioUPN)` (FL-02 la compara para detectar cambios que requieren reasignar).

> **Control clave (CA-02).** Como el elemento lo crea la cuenta de servicio y los usuarios no tienen permiso *Agregar* a nivel de lista, no existe ventana en que el activo herede los permisos de la lista. Si cualquier paso de §6 falla, *Catch* deja el elemento con `RN_Estado = Borrador` y **sin** permisos de usuarios (solo CISO y cuenta de servicio) y alerta al CISO.

### 7. Carpeta de evidencias (RF-12)
* Entidad RNSG/RNSV: las evidencias van a `Evidencias/<ENT>/<GER>` (permisos ya aplicados por `scripts/05`).
* Entidad AMBAS: crear carpeta `Evidencias/AMBAS/<IdActivo>` (*SharePoint – Crear nueva carpeta*), romper herencia con `copyRoleAssignments=true` (hereda CISO + lectura transversal de la biblioteca) y agregar los grupos de edición de ambas gerencias.

### 8. Historial y respuesta
* *Crear elemento* `HistorialClasificacion`: `Title = concat('Alta ', IdActivo)`, `RN_Activo Id`, `RN_IdActivoTexto`, `RN_Entidad = Ent.RN_Codigo`, `RN_TipoEvento = Alta` (o `Carga masiva`), `RN_ValorNuevo = string(outputs('D'))`, `RN_Usuario = Invocador`, `RN_FechaEvento = utcNow()`.
* *Responder a una aplicación de Power Apps*: `ok = true`, `idElemento = body('Crear_activo')?['ID']`, `idActivo = IdActivo`, `mensaje = "Borrador creado"`.

Antes de responder, **ejecutar el flujo secundario `RN-INV FL-02b Recalcular activo`** con `idElemento`: como el elemento lo creó la cuenta de servicio, la condición anti-bucle de FL-02 no lo procesa, y los campos calculados (nivel mínimo, alertas, próximas revisiones) deben quedar completos desde el primer momento.

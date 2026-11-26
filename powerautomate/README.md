# Flujos de Power Automate – especificación de construcción

Esta carpeta especifica los flujos de la solución (sección 14 del ER) con el detalle necesario para construirlos en el entorno **DEV** dentro de la solución `RNInventarioActivos` y luego exportarlos como solución administrada a TEST y PROD (RNF-14).

> **Por qué especificación y no paquete importable.** Un paquete de solución (`.zip`) contiene GUID de entorno, de conexiones y de listas que solo existen en el tenant de Renta Nacional. Generarlo fuera del tenant produciría un artefacto no verificable. Se entrega, en cambio, la lógica exacta (disparadores, condiciones y expresiones) para que el equipo de Power Platform la construya en DEV en una sesión; a partir de ahí la solución exportada es el artefacto versionado (ver `docs/02_Manual_de_Instalacion.md` §6).

| ID | Flujo | Tipo de disparador | Archivo |
|---|---|---|---|
| FL-01 | Alta de activo (ID, permisos, historial) | Instantáneo (Power Apps V2) + secundario | [FL-01_Alta_de_Activo.md](FL-01_Alta_de_Activo.md) |
| FL-02 / FL-04 | Procesar cambio: cálculos, alertas, historial, control de cambios no autorizados | Automatizado (elemento creado o modificado) | [FL-02_Calculos_Alertas_e_Historial.md](FL-02_Calculos_Alertas_e_Historial.md) |
| FL-03 | Declaración y validación CISO / DPO | Secundario (desde FL-02) | [FL-03_Validacion_CISO_DPO.md](FL-03_Validacion_CISO_DPO.md) |
| FL-05 / FL-06 | Recordatorios de revisión integral y revisión de accesos | Programado diario + secundario | [FL-05_06_Revisiones.md](FL-05_06_Revisiones.md) |
| FL-07 | Excepciones | Instantáneo + programado diario | [FL-07_Excepciones.md](FL-07_Excepciones.md) |
| FL-08 / FL-09 | Baja de activo / Traspaso de Dueño o Custodio | Secundario (desde FL-02) | [FL-08_09_Baja_y_Traspaso.md](FL-08_09_Baja_y_Traspaso.md) |
| FL-10 | Avisos DPO y Riesgos | Secundario (desde FL-02) | [FL-02_Calculos_Alertas_e_Historial.md](FL-02_Calculos_Alertas_e_Historial.md#paso-8--avisos-dpo-y-riesgos-fl-10) |
| FL-11 | Carga masiva | Automatizado (archivo en CargaMasiva/Entrada) | [FL-11_Carga_Masiva.md](FL-11_Carga_Masiva.md) |
| FL-16 | Exportar inventario a Excel etiquetado Reservado (RF-44) | Instantáneo (conexión del usuario) | [FL-16_Exportar.md](FL-16_Exportar.md) |
| FL-12 a FL-15 | Respaldo, CMDB, cargos vacantes, pertenencia a grupos | Programados | [FL-12_15_Mantenimiento.md](FL-12_15_Mantenimiento.md) |

## 1. Convenciones

**Nombres.** `RN-INV FL-xx <Nombre>` (ej. `RN-INV FL-01 Alta de activo`). Acciones con nombre descriptivo en español, sin espacios dobles (las expresiones las referencian por nombre: `outputs('Obtener_gerencia')`).

**Cuenta de servicio (RNF-04).** Todas las referencias de conexión pertenecen a `svc-sgsi-inventario@…`. Los flujos instantáneos que llama la app se configuran en *Run only users → Connections Used → "Use this connection"* para que se ejecuten con la cuenta de servicio y **no** con la del usuario. Por eso todo flujo instantáneo **debe validar la autorización del invocador** (ver §4) antes de actuar.

**Variables de entorno** (tipo, valor DEV de ejemplo):

| Variable | Tipo | Uso |
|---|---|---|
| `rnsgsi_SitioInventario` | Data source (sitio SharePoint) | Todas las acciones SharePoint |
| `rnsgsi_ListaActivos`, `rnsgsi_ListaHistorial`, `rnsgsi_ListaRevisiones`, `rnsgsi_ListaExcepciones`, `rnsgsi_ListaParametros`, `rnsgsi_ListaCorrelativos`, `rnsgsi_ListaGerencias`, `rnsgsi_ListaCargos`, `rnsgsi_ListaEntidades` | Data source (lista) | GUID desde `logs/ids-listas-<AMB>.csv` |
| `rnsgsi_CuentaServicio` | Texto | Condiciones anti-bucle |
| `rnsgsi_UrlApp` | Texto | Enlaces profundos en correos y tarjetas (`…/play/<appId>?activoId=`) |

**Referencias de conexión:** `cr_SharePoint`, `cr_Outlook` (Office 365 Outlook), `cr_Teams`, `cr_Approvals`, `cr_Users` (Office 365 Users), `cr_Groups` (Office 365 Groups), `cr_Excel` (Excel Online Business). Todas estándar (sin Premium, §5.2 del ER) y permitidas por la DLP `RN-SGSI-Inventario-Solo-M365`.

**Parámetros de negocio.** Ningún valor de negocio (frecuencias, plazos, niveles mínimos) se escribe en el flujo: cada flujo comienza con el bloque estándar *Leer parámetros* (RNF-17):

```
Acción: SharePoint – Obtener elementos (Parametros)   nombre: Obtener_parametros   Top: 200
Acción: Seleccionar  nombre: Parametros_kv
    Desde: body('Obtener_parametros')?['value']
    Mapa (modo texto):  { "@{item()?['Title']}": "@{item()?['RN_Valor']}" }
Acción: Redactar     nombre: P
    json(replace(replace(replace(string(body('Parametros_kv')),'},{',','),'[{','{'),'}]','}'))
```
Luego: `int(outputs('P')?['FREC_REVISION_MESES'])`, `json(outputs('P')?['ORDEN_NIVELES'])`, etc.

## 2. Prevención de bucles

Los flujos automatizados sobre `Activos` escriben con la cuenta de servicio. Condición de disparador (Settings → Trigger conditions) en FL-02:

```
@not(equals(toLower(triggerOutputs()?['body/Editor/Email']), toLower(parameters('rnsgsi_CuentaServicio (rnsgsi_CuentaServicio)'))))
```
Si el entorno no admite parámetros en condiciones de disparador, reemplace por el UPN literal de la cuenta de servicio.

## 3. Manejo de errores (patrón Try / Catch / Finally)

Cada flujo agrupa su lógica en tres *Ámbitos*:

* `Try` – lógica principal.
* `Catch` – *Configure run after: has failed, has timed out*. Envía correo al buzón del CISO y a `SGSI-INV-ADMIN-TI` con `workflow()?['run']?['name']`, el ID del activo y `result('Try')` filtrado por `status = Failed`; registra en `HistorialClasificacion` un evento con `RN_Motivo = "Error de flujo FL-xx"`.
* `Finally` – devuelve `RN_SolicitudAccion = "Ninguna"` (cuando aplica) para que la app no quede bloqueada.

Reintentos: política exponencial, 4 intentos, en todas las acciones SharePoint (los 429 por limitación son esperables en cargas masivas).

## 4. Autorización en flujos instantáneos

La identidad del invocador se toma **del encabezado del disparador**, no de un parámetro enviado por la app (que podría alterarse):

```
Redactar  Invocador:  toLower(triggerOutputs()?['headers']?['x-ms-user-email'])
```
Pertenencia a grupo (conector Office 365 Groups → *List group members*, `groupId` desde `Gerencias.RN_GrupoEdicionEntraId` o `Parametros.GRUPO_CISO_ENTRAID`):

```
Filtrar matriz  Es_miembro:  Desde body('Miembros_grupo')?['value']   Condición  toLower(item()?['userPrincipalName'])  es igual a  outputs('Invocador')
Condición:  greater(length(body('Es_miembro')), 0)
```
Si no está autorizado: responder a la app `{ "ok": false, "mensaje": "No autorizado" }`, registrar el intento en `HistorialClasificacion` (evento *Cambio no autorizado revertido*) y terminar con estado *Failed*.

## 5. Evidencia y trazabilidad

Todo cambio relevante deja: (a) versión de SharePoint del elemento (versionado 500), (b) registro en `HistorialClasificacion` escrito solo por la cuenta de servicio, (c) registro en la auditoría unificada de Purview. Los flujos registran siempre el **usuario que originó el cambio** (`Editor` del elemento o `Invocador`), no la cuenta de servicio.

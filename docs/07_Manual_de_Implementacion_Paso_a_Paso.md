# 07 · Manual de implementación paso a paso

**Solución:** Inventario y Clasificación de Activos de Información – Microsoft 365 (ER[ZZ].GR_1.0(2026))
**Entidades:** Renta Nacional Seguros Generales (RNSG) y Renta Nacional Seguros de Vida (RNSV)
**Audiencia:** jefe de proyecto, equipo de Power Platform, administradores de Microsoft 365 (Gerencia de TI), CISO y equipo SGSI
**Clasificación:** Uso Interno

Este manual guía la implementación completa, desde la preparación hasta la operación estable. Sigue las fases del plan del ER (sección 17): **F0 Preparación → F1 MVP → F2 Ciclo de vida → F3 Reportería e integraciones → F4 Despliegue**. Cada paso indica **quién** lo ejecuta, **qué** hacer, **cómo verificarlo** y **qué evidencia guardar**. El detalle técnico de cada componente está en los documentos de referencia que se citan; este manual define el orden y los puntos de control.

> **Convenciones.** ☐ = tarea a marcar. 🔍 = punto de verificación (no continuar si falla). 📁 = evidencia a archivar en la carpeta del proyecto. `<AMB>` = DEV, TEST o PROD. Los comandos PowerShell se ejecutan desde la raíz del repositorio.

---

## Índice

| Fase | Pasos | Duración | Hito |
|---|---|---|---|
| F0 Preparación | 1 a 7 | 2 semanas | Diseño aprobado por el CSI |
| F1 MVP | 8 a 22 | 6 semanas | Piloto en producción |
| F2 Ciclo de vida | 23 a 28 | 4 semanas | Ciclo completo operativo |
| F3 Reportería e integraciones | 29 a 33 | 4 semanas | Primer reporte al CSI |
| F4 Despliegue | 34 a 40 | 4 semanas | Inventario completo de ambas entidades |
| Operación | 41 a 43 | Continua | — |

Anexos: A. Solución de problemas · B. Lista de verificación de salida a producción · C. Matriz RACI.

---

# FASE F0 · PREPARACIÓN (semanas 1–2)

## Paso 1 · Constituir el proyecto y obtener aprobaciones

**Quién:** CISO (líder funcional), Gerencia de TI (líder técnico), patrocinador del CSI.

☐ 1.1 Designar: jefe de proyecto, desarrollador principal de Power Platform y **un segundo desarrollador** (mitiga el riesgo "dependencia de un desarrollador", sección 18 del ER).
☐ 1.2 Presentar al CSI el documento de diseño (`docs/01_Diseno_de_la_Solucion.md`), en especial las decisiones DD-01 a DD-08 y los hallazgos D-09 a D-14.
☐ 1.3 Crear la carpeta del proyecto (biblioteca restringida a CISO y TI) para las evidencias 📁 de este manual.

🔍 **Verificación:** acta del CSI que aprueba el diseño y las desviaciones respecto del ER.
📁 Acta del CSI.

## Paso 2 · Cerrar las decisiones pendientes que bloquean la construcción

**Quién:** responsables indicados en cada decisión.

| ☐ | Decisión | Responsable | Qué entregar | Necesaria antes de |
|---|---|---|---|---|
| ☐ | **D-01** Licencias por usuario (E3/E5, Power BI Pro) | TI | Informe del centro de administración M365 → Facturación → Licencias | Paso 6 |
| ☐ | **D-09** Capacidad de Dataverse para entornos TEST y PROD | TI | Captura de *Centro de administración de Power Platform → Recursos → Capacidad* | Paso 7 |
| ☐ | **D-02** Las normas aplican a Seguros de Vida | CSI / Gerencia General | Resolución o normas equivalentes | Paso 40 (salida a producción) |
| ☐ | **D-03** Niveles mínimos para datos personales y sensibles | CISO / DPO | Valores para `NIVEL_MIN_DATOS_PERSONALES` y `NIVEL_MIN_DATOS_SENSIBLES` | Paso 13 |
| ☐ | **D-04** Dónde reside el RAT y su identificador | DPO | Archivo con ID y nombre de cada actividad | Paso 14 |
| ☐ | **D-06** Rol de Delegado de registro en la Norma de Gestión | CISO | Borrador de modificación | Paso 40 |
| ☐ | **D-07** Campo Entidad en el Catálogo | CISO | Catálogo V1.1 | Paso 40 |
| ☐ | **D-11** Textos oficiales de reglas de manejo y métodos de baja (Anexo 1 NC) | CISO | Texto por nivel | Paso 13 |

**Si D-09 resulta negativa** (no hay capacidad de Dataverse): elegir con TI una de estas alternativas y registrarla en el acta:
- (a) adquirir capacidad mínima (1 GB por entorno TEST y PROD);
- (b) DEV como entorno de desarrollador (gratuito) y PROD en el entorno predeterminado, con exportación de paquetes y reconfiguración documentada (CA-12 queda como no cumplido y se informa al CSI).

> El conector **Approvals** (validaciones CISO/DPO y excepciones) también guarda sus datos en Dataverse: en el entorno elegido para PROD debe poder aprovisionarse la base de datos de aprobaciones.

📁 Acta con cada decisión cerrada.

## Paso 3 · Preparar identidades técnicas

**Quién:** TI (administrador de identidades).

☐ 3.1 Crear la cuenta de servicio `svc-sgsi-inventario@rentanacional.cl`:
- Licencia **M365 E3** (necesaria para ejecutar flujos y ser dueña de conexiones).
- MFA según la política de TI para cuentas de servicio; credencial guardada en la bóveda corporativa; sin buzón compartido con personas.
- Excluirla solo de las políticas de acceso condicional que impidan ejecutar flujos en la nube, documentando la excepción.

☐ 3.2 Registrar la aplicación de Entra ID para PnP PowerShell (obligatoria desde septiembre de 2024):

```powershell
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "PnP SGSI Inventario" `
    -Tenant rentanacional.onmicrosoft.com -Interactive
```
Anotar el **Client ID** que devuelve.

☐ 3.3 Asignar roles a los administradores que ejecutarán el despliegue (de preferencia con PIM, activación por el tiempo del despliegue):

| Rol | Para los pasos |
|---|---|
| Administrador de SharePoint | 9 a 12 |
| Administrador de grupos | 8 |
| Administrador de cumplimiento | 7, 10 |
| Administrador de Power Platform | 6, 15 |
| Administrador de acceso condicional | 8.4 |

🔍 **Verificación:** inicio de sesión exitoso con la cuenta de servicio; `Connect-PnPOnline -Url https://rentanacional-admin.sharepoint.com -Interactive -ClientId <ClientId>` funciona.
📁 Ficha de la cuenta de servicio (sin la contraseña) y Client ID.

## Paso 4 · Preparar el equipo de despliegue

**Quién:** TI.

☐ 4.1 Equipo Windows administrado con:
- **PowerShell 7.4 o superior** (`winget install Microsoft.PowerShell`).
- **Windows PowerShell 5.1** (incluido en Windows) para el módulo de administración de Power Platform.
- **Node.js 18+** y **Python 3.10+** con `openpyxl` (solo para pruebas y regenerar la plantilla).
- **Power Platform CLI** (`pac`) – opcional, para empaquetar soluciones.
- **Power BI Desktop** (versión actual).

☐ 4.2 Instalar módulos:

```powershell
# PowerShell 7
Install-Module PnP.PowerShell, Microsoft.Graph.Groups, ExchangeOnlineManagement, ImportExcel, Pester -Scope CurrentUser
# Windows PowerShell 5.1
Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
```

☐ 4.3 Clonar el repositorio y ejecutar las pruebas:

```bash
git clone https://github.com/hgallardov/Rep_Activo-Informacion.git
cd Rep_Activo-Informacion
npm test            # debe indicar: pass 23, fail 0
npm run validar     # debe terminar en: Configuración válida
```
```powershell
Invoke-Pester ./tests/powershell      # todas las pruebas en verde
```

🔍 **Verificación:** las tres ejecuciones sin fallos. **Si Pester falla**, no continuar: el módulo de reglas PowerShell se usa en la validación de cargas y en el CAAT.
📁 Salida de las tres ejecuciones.

## Paso 5 · Preparar los datos maestros

**Quién:** CISO (coordina), Gerencia de Personas (cargos), Riesgos y Compras (terceros), dueños de procesos.

☐ 5.1 Completar en `config/maestros/` (UTF-8, separador `;`):

| Archivo | Fuente | Cuidado especial |
|---|---|---|
| `entidades.csv` | Escrituras / RUT de cada compañía | Completar RUT. No cambiar los códigos RNSG, RNSV, AMBAS |
| `gerencias.csv` | Organigrama vigente de ambas entidades | Código de 2 a 6 letras mayúsculas o dígitos, **único e inmutable** (forma parte del ID del activo). Áreas que sirven a las dos compañías: entidad *Ambas* y `RN_EsCorporativa = true` |
| `procesos.csv` | Mapa de procesos / BIA | El campo Gerencia debe coincidir exactamente con el nombre de la gerencia |
| `cargos.csv` | Gerencia de Personas | Solo cargos de gerente o jefatura pueden ser Dueño (`RN_PuedeSerDueno = true`). Titular y subrogante por UPN |
| `terceros.csv` | Registro de proveedores y registro NCG 573 | Marcar servicios externalizados significativos y encargados de tratamiento |

☐ 5.2 Eliminar las filas de ejemplo que no correspondan (las entregadas son ilustrativas).

☐ 5.3 Validar el formato:
```bash
npm run validar
```

🔍 **Verificación:** revisión cruzada CISO + Personas de la lista de cargos Dueño y sus titulares.
📁 Versión aprobada de los CSV.

## Paso 6 · Preparar los archivos de configuración por ambiente

**Quién:** TI.

☐ 6.1 Por cada ambiente:
```powershell
Copy-Item config/solution.config.json config/solution.config.DEV.json
Copy-Item config/solution.config.json config/solution.config.TEST.json
Copy-Item config/solution.config.json config/solution.config.PROD.json
```
☐ 6.2 Ajustar en cada archivo: `tenant.tenantId`, `tenant.adminUrl`, `pnp.clientId`, `sitio.url` (use una URL distinta por ambiente, p. ej. `…/sites/SGSI-InventarioActivos-DEV`), `sitio.propietarios`, `cuentaServicio`.
☐ 6.3 En `config/parametros.json` ajustar los valores marcados **AJUSTAR**: buzones (`CORREO_CISO`, `CORREO_DPO`, `CORREO_RIESGOS`, `CORREO_PERSONAS`), `CUENTA_SERVICIO_UPN` y, según D-03 y D-11, los niveles mínimos y los textos de `REGLAS_MANEJO` / `METODO_BAJA_POR_NIVEL`.

> Los archivos `solution.config.<AMB>.json` están excluidos de Git (`.gitignore`) porque contienen identificadores del tenant.

## Paso 7 · Crear etiquetas de sensibilidad y retención (una vez por tenant)

**Quién:** Administrador de cumplimiento, con el CISO y el DPO.

☐ 7.1 Revisar en `purview/01-New-SensitivityLabels.ps1` los textos de encabezado y pie de cada etiqueta. Si el tenant **ya tiene** etiquetas corporativas, no crear nuevas: mapear las existentes en el parámetro `MAPEO_ETIQUETAS_PURVIEW` y verificar que *Reservado* tenga alcance "Sitios y grupos".
☐ 7.2 Simular y ejecutar:
```powershell
./purview/01-New-SensitivityLabels.ps1 -Dominio rentanacional.cl -WhatIf
./purview/01-New-SensitivityLabels.ps1 -Dominio rentanacional.cl
```
☐ 7.3 Habilitar el etiquetado de sitios si no lo está (una vez por tenant, con el módulo de SharePoint Online):
```powershell
Set-SPOTenant -EnableAIPIntegration $true
```
☐ 7.4 Copiar el **GUID** de la etiqueta *Reservado* en `sitio.etiquetaSensibilidadId` de los tres archivos de configuración.

🔍 **Verificación (24 h después):** en un documento de Word aparecen las cuatro etiquetas en orden Pública → Uso Interno → Reservado → Confidencial.
📁 Captura del portal de Purview con las etiquetas y la política publicada.

**🏁 Hito F0:** acta del CSI con diseño aprobado y decisiones D-01, D-03, D-09 cerradas.

---

# FASE F1 · MVP (semanas 3–8)

Los pasos 8 a 21 se ejecutan **primero en DEV**. Luego se repiten los pasos 8 a 14 en TEST y PROD (paso 21) y la solución se promueve por exportación (paso 22).

## Paso 8 · Crear los grupos de Entra ID

**Quién:** Administrador de grupos.

☐ 8.1 Simular y ejecutar:
```powershell
./scripts/01-New-EntraGroups.ps1 -Ambiente DEV -WhatIf
./scripts/01-New-EntraGroups.ps1 -Ambiente DEV
```
Se crean 8 grupos transversales y un grupo `SGSI-INV-<ENT>-<GER>-EDIT` por gerencia. El script es idempotente: si se agrega una gerencia, basta volver a ejecutarlo.

☐ 8.2 Revisar `logs/grupos-entra-DEV.csv`: todos los grupos con Id.

> **Grupos por ambiente.** Si se usa el mismo tenant para DEV, TEST y PROD, los grupos son los mismos para los tres ambientes. En DEV y TEST asigne **solo usuarios de prueba**; la membresía real se carga en el paso 37.

☐ 8.3 Asignar miembros en DEV: los usuarios de prueba del plan de pruebas (`docs/05_Plan_de_Pruebas.md` §1).

☐ 8.4 **Acceso condicional (RNF-02):** crear la política *SGSI Inventario – acceso*:
- Usuarios: todos los grupos `SGSI-INV-*`.
- Recursos: Office 365 SharePoint Online y Power Apps (o *Office 365*).
- Condiciones: todas las ubicaciones.
- Conceder: **requerir MFA** y **requerir dispositivo marcado como conforme** o **unido a Entra híbrido**. Alternativa aprobada por el CISO: ubicaciones de confianza.
- Sesión: *Usar restricciones aplicadas por la aplicación* (permite el acceso limitado en dispositivos no administrados configurado en el paso 10).
- Activar primero en modo **Solo informe** durante una semana.

🔍 **Verificación:** en *Registros de inicio de sesión* aparece la política evaluada para un usuario de prueba.
📁 `logs/grupos-entra-DEV.csv`, captura de la política.

## Paso 9 · Crear y endurecer el sitio SharePoint

**Quién:** Administrador de SharePoint.

☐ 9.1 Ejecutar:
```powershell
./scripts/02-New-InventorySite.ps1 -Ambiente DEV
```
☐ 9.2 Si el log muestra la advertencia *"No se pudo aplicar la etiqueta"*, esperar a que se publique la etiqueta del paso 7 y volver a ejecutar el script (es idempotente).

🔍 **Verificación** (Centro de administración de SharePoint → Sitios activos → el sitio):

| Control | Valor esperado |
|---|---|
| Uso compartido externo | Solo personas de la organización |
| Etiqueta de sensibilidad | Reservado |
| Uso compartido por miembros | Solo propietarios |
| Solicitudes de acceso | Desactivadas |
| Acceso desde dispositivos no administrados | Acceso limitado, solo web |
| Scripts personalizados | Bloqueados |

📁 Log del script y captura de la configuración.

## Paso 10 · Aplicar retención y verificar la auditoría

**Quién:** Administrador de cumplimiento.

☐ Ejecutar:
```powershell
./purview/02-New-RetentionPolicy.ps1 -UrlSitio https://rentanacional.sharepoint.com/sites/SGSI-InventarioActivos-DEV
```
🔍 **Verificación:** la política *SGSI-Inventario-5A* aparece en Purview → Administración del ciclo de vida de datos con estado *Activado*, y el script informa *Auditoría unificada: habilitada*.

## Paso 11 · Crear listas, columnas, índices y vistas

**Quién:** Administrador de SharePoint.

☐ 11.1 Ejecutar:
```powershell
./scripts/03-New-InventoryLists.ps1 -Ambiente DEV
```
☐ 11.2 Revisar la línea final del log: `Activos: 15 columnas indexadas (máx. 20); 9 columnas de búsqueda/persona propias (+Autor/Editor, umbral 12)`.
☐ 11.3 Guardar `logs/ids-listas-DEV.csv` (GUID de cada lista): se usa en el paso 16 para las variables de entorno.

🔍 **Verificación:**
- En el sitio existen 15 listas y 3 bibliotecas (*Evidencias*, *CargaMasiva*, *Respaldos*).
- *Activos* → Configuración → Columnas indexadas: 15.
- *Activos* tiene las vistas *Inventario vigente*, *En validación*, *Con alertas bloqueantes*, *Revisión en los próximos 30 días*, *Críticos*, *Con datos personales*.
- Versionado activo en todas las listas; adjuntos desactivados en *Activos*.

## Paso 12 · Cargar maestros y parámetros

**Quién:** Administrador de SharePoint con el CISO.

☐ 12.1 Ejecutar:
```powershell
./scripts/04-Import-MasterData.ps1 -Ambiente DEV
```
☐ 12.2 Revisar que el log no tenga líneas `[ERROR]` (gerencias con entidad inexistente, códigos inválidos, cargos con gerencia inexistente). Corregir los CSV y volver a ejecutar (hace upsert).

🔍 **Verificación:** conteos de las listas *Entidades*, *Gerencias*, *Procesos*, *Cargos*, *Terceros* iguales a las filas de los CSV; *Parametros* con 43 elementos.

## Paso 13 · Aplicar el modelo de permisos

**Quién:** Administrador de SharePoint. **Requisito:** pasos 8 y 12 completados (el script lee los grupos y el maestro de gerencias).

☐ 13.1 Ejecutar:
```powershell
./scripts/05-Set-InventoryPermissions.ps1 -Ambiente DEV
```
☐ 13.2 Verificar en *Parametros* que tienen valor: `GRUPO_CISO_SPID`, `GRUPO_DPO_SPID`, `GRUPO_RIESGOS_SPID`, `GRUPO_CSI_SPID`, `GRUPO_AUDITORIA_SPID`, `GRUPO_CUSTODIOS_SPID`, `GRUPO_*_ENTRAID`, `ROL_EDICION_ID`, `ROL_LECTURA_ID`.
☐ 13.3 Verificar en *Gerencias* que cada fila tiene `RN_GrupoEdicionSPId` y `RN_GrupoEdicionEntraId`.

🔍 **Verificación de permisos** (Configuración de la lista → Permisos):

| Lista | Debe tener | No debe tener |
|---|---|---|
| Activos | Cuenta de servicio (Control total), SGSI-INV-CISO (SGSI Editar sin eliminar) | Grupos de gerencia a nivel de lista, el usuario que ejecutó el script |
| HistorialClasificacion, Revisiones | Cuenta de servicio; CISO, DPO, Riesgos, CSI y Auditoría con *Leer* | Grupos de gerencia |
| Parametros | Todos con *Leer*; CISO con edición | — |
| Cargos | Todos con *Leer*; CISO y PERSONAS con edición | — |
| Evidencias/RNSG/GTG (cada carpeta) | Grupo de la gerencia con edición + CISO + lectura transversal | Grupos de otras gerencias |

📁 Log del script y capturas de permisos de *Activos* y de una carpeta de *Evidencias*.

## Paso 14 · Cargar el catálogo del RAT

**Quién:** DPO (según D-04).

☐ Cargar en la lista *CatalogoRAT* el ID (columna *ID actividad RAT*), nombre, entidad y vigencia de cada actividad de tratamiento, desde el archivo entregado por el DPO (vista *Editar en cuadrícula* → pegar desde Excel).

🔍 **Verificación:** número de actividades igual al del RAT oficial.

## Paso 15 · Crear los entornos de Power Platform y la política DLP

**Quién:** Administrador de Power Platform. **Requisito:** D-09 cerrada.

☐ 15.1 En Windows PowerShell 5.1:
```powershell
.\scripts\09-New-PowerPlatformGovernance.ps1 -Region <región del tenant> -WhatIf
.\scripts\09-New-PowerPlatformGovernance.ps1 -Region <región del tenant>
```
☐ 15.2 Asignar roles de seguridad de los entornos:
- **DEV:** *Creador de entorno* a los desarrolladores.
- **TEST y PROD:** *Administrador del sistema* solo a la cuenta de servicio y al administrador de Power Platform; *Usuario básico* a los grupos `SGSI-INV-*` (necesario para ejecutar la app de una solución).

🔍 **Verificación:** la política DLP *RN-SGSI-Inventario-Solo-M365* se aplica solo a los tres entornos, y un conector no aprobado (p. ej. *HTTP*) aparece como **bloqueado** al intentar usarlo en un flujo de prueba en DEV.
📁 Captura de la política DLP.

## Paso 16 · Crear la solución, variables de entorno y conexiones (DEV)

**Quién:** Desarrollador de Power Platform, con sesión iniciada **como la cuenta de servicio** para las conexiones.

☐ 16.1 make.powerapps.com → entorno *RN-SGSI-Inventario-DEV* → **Soluciones → Nueva solución**:
- Nombre visible: *RN Inventario de Activos*; nombre: `RNInventarioActivos`.
- Publicador nuevo: *SGSI Renta Nacional*, prefijo `rnsgsi`.

☐ 16.2 Dentro de la solución, **Nuevo → Más → Variable de entorno** (una por fila de `powerautomate/README.md` §1):
- `rnsgsi_SitioInventario` (tipo *Origen de datos* → SharePoint → sitio).
- `rnsgsi_ListaActivos`, `rnsgsi_ListaHistorial`, … (tipo *Origen de datos* → lista; valores desde `logs/ids-listas-DEV.csv`).
- `rnsgsi_CuentaServicio` (texto) y `rnsgsi_UrlApp` (texto, se completa en el paso 19).

☐ 16.3 **Nuevo → Más → Referencia de conexión**, una por conector: SharePoint, Office 365 Outlook, Microsoft Teams, Approvals, Office 365 Users, Office 365 Groups, Excel Online (Business), OneDrive para la Empresa. Crear cada conexión con la **cuenta de servicio**.

🔍 **Verificación:** la solución muestra las variables con valor actual y las referencias de conexión en estado *Conectado*.

## Paso 17 · Construir los flujos (DEV)

**Quién:** Desarrolladores de Power Platform. **Referencia:** `powerautomate/` (una especificación por flujo).

### 17.1 Orden de construcción
Construir en este orden: los flujos secundarios primero, porque los principales los invocan.

| Orden | Flujo | Tipo | Especificación |
|---|---|---|---|
| 1 | FL-02b Recalcular activo | Secundario (*Desencadenar manualmente un flujo* con entrada `idElemento`) | FL-02 §Paso 5 |
| 2 | FL-01b Reasignar permisos | Secundario | FL-02 §Paso 6 / FL-01 §6 |
| 3 | FL-01 Alta de activo | Power Apps (V2) | FL-01 |
| 4 | FL-03 Declaración y validación | Secundario | FL-03 |
| 5 | FL-05b / FL-06b Registrar revisión | Secundarios | FL-05_06 |
| 6 | FL-08 Baja / FL-09 Traspaso | Secundarios | FL-08_09 |
| 7 | FL-02 Procesar cambio de activo | Automatizado (SharePoint) | FL-02 |
| 8 | FL-05 / FL-06 Recordatorios | Programados | FL-05_06 |
| 9 | FL-07a / FL-07b Excepciones | Power Apps (V2) / programado | FL-07 |
| 10 | FL-10b Registrar ID de riesgo | Power Apps (V2) | FL-02 §Paso 8 |
| 11 | FL-11 Carga masiva | Automatizado (archivo) | FL-11 |
| 12 | FL-12 a FL-15 | Programados | FL-12_15 |
| 13 | FL-16 Exportar | Power Apps (V2), conexión del usuario | FL-16 |

### 17.2 Procedimiento para cada flujo
☐ a. En la solución: **Nuevo → Automatización → Flujo de nube** del tipo indicado. Nombre: `RN-INV FL-xx <Nombre>`.
☐ b. Usar **solo las referencias de conexión** de la solución (no crear conexiones personales).
☐ c. Agregar al inicio el bloque estándar *Leer parámetros* (`powerautomate/README.md` §1) y, en los flujos instantáneos, la verificación de autorización del invocador (§4).
☐ d. Estructurar la lógica en los ámbitos **Try / Catch / Finally** (§3). En cada acción SharePoint: *Configuración → Directiva de reintento → Exponencial, 4 intentos*.
☐ e. Copiar las expresiones de la especificación **tal como están escritas** (los nombres de las acciones deben coincidir: p. ej. la acción que redacta los parámetros debe llamarse `P`).
☐ f. En FL-02: *Configuración del desencadenador → Condiciones de desencadenador* = condición anti-bucle (§2).
☐ g. En los flujos llamados desde la app (FL-01, FL-07a, FL-10b): *Detalles → Usuarios de solo ejecución → Conexiones usadas* = **Usar esta conexión** (cuenta de servicio). En **FL-16**, al revés: *Proporcionada por el usuario de solo ejecución* para SharePoint, OneDrive y Excel.
☐ h. En los programados, zona horaria *(UTC-04:00) Santiago* y las horas indicadas en cada especificación.
☐ i. Guardar y probar con un caso feliz y un caso de error.

### 17.3 Pruebas mínimas por flujo en DEV

| Flujo | Prueba | Resultado esperado |
|---|---|---|
| FL-01 | Ejecutar desde la app de prueba con `dueno.rnsg` | Elemento con ID `AI-RNSG-<GER>-00001`, permisos únicos correctos, evento *Alta* en el historial |
| FL-01 | Ejecutar con `dueno.rnsv` indicando una gerencia de RNSG | `ok:false`, "No autorizado", sin elemento creado (CP-05) |
| FL-02 | Cambiar C-I-D a *Alta* desde la app | `RN_Critico = Sí`, `RN_ProximaRevision` a 6 meses |
| FL-02 | Cambiar `RN_ValidacionCISO` a mano en la lista | Valor revertido y evento *Cambio no autorizado revertido* (CP-03) |
| FL-03 | Declarar un activo sin bloqueantes | Aprobación llega a `ciso2` (no a `ciso1` si él declaró) |
| FL-05 | Activo con próxima revisión en 30 días; ejecutar el flujo manualmente | Aviso "30" enviado y marcado en `RN_AvisosEnviados` |

🔍 **Verificación:** todas las ejecuciones de prueba en estado *Correcto* (las pruebas de error terminan en el estado esperado y con el correo del bloque *Catch*).
📁 Historial de ejecuciones exportado (o capturas) por flujo.

## Paso 18 · Construir la aplicación canvas (DEV)

**Quién:** Desarrollador de Power Platform. **Referencia:** `powerapps/Pantallas.md`.

☐ 18.1 En la solución: **Nuevo → Aplicación → Aplicación de lienzo**, formato **Tableta**, nombre *Inventario de Activos*.
☐ 18.2 *Configuración → Actualizaciones*: activar **Funciones definidas por el usuario** y **Fórmulas con nombre**. Límite de registros de datos: 2.000.
☐ 18.3 Agregar orígenes de datos (*Datos → Agregar datos*): SharePoint (sitio por variable de entorno) con las listas *Activos, Entidades, Gerencias, Procesos, Cargos, Terceros, Parametros, Excepciones, CatalogoRAT, RelacionesActivos, HistorialClasificacion* y la biblioteca *Evidencias*; **Office 365 Users**; **Office 365 Groups**.
☐ 18.4 Agregar los flujos (*Power Automate → Agregar flujo*): FL-01, FL-07a, FL-10b y FL-16.
☐ 18.5 Pegar el contenido de `powerapps/src/App.Formulas.fx` en **App → Formulas** y el de `powerapps/src/App.OnStart.fx` en **App → OnStart**. Corregir cualquier nombre de flujo que Power Apps haya asignado distinto (p. ej. `'RN-INVFL-01Altadeactivo'`).
☐ 18.6 Construir las pantallas en este orden: `scrInicio`, `scrMisActivos`, `scrAsistente`, `scrFicha`, `scrValidacion`, `scrRevisiones`, `scrExcepciones`, `scrAdministracion`, usando contenedores adaptables y las fórmulas de `Pantallas.md`.
☐ 18.7 Revisar el **Comprobador de aplicaciones**: **cero advertencias de delegación** sobre la lista *Activos*.
☐ 18.8 Guardar y publicar. Copiar la URL de la app (*Detalles → Vínculo web*) en la variable `rnsgsi_UrlApp`.

🔍 **Verificación:** registrar de punta a punta un activo con `dueno.rnsg` en menos de 10 minutos (RNF-13), declararlo y validarlo con `ciso2`.

## Paso 19 · Office Script y plantilla de exportación

**Quién:** Desarrollador (sesión con la cuenta de servicio).

☐ 19.1 En Excel para la Web (OneDrive de la cuenta de servicio) → **Automatizar → Nuevo script**: pegar `powerapps/officescripts/EscribirInventario.ts`, guardar con el nombre `EscribirInventario`. **Compartir → Agregar a un flujo** (FL-16).
☐ 19.2 Crear `Plantilla_Exportacion_Reservado.xlsx` con una hoja *Inventario* vacía, aplicarle **manualmente** la etiqueta *Reservado* y subirla a `CargaMasiva/Plantillas`.

🔍 **Verificación:** CP-07 – exportar con `dueno.rnsv`: el archivo solo contiene sus activos y Office muestra la etiqueta *Reservado*.

## Paso 20 · Pruebas integrales en DEV

**Quién:** Equipo de proyecto + usuarios de prueba. **Referencia:** `docs/05_Plan_de_Pruebas.md`.

☐ 20.1 Ejecutar CA-01 a CA-11 y CP-01 a CP-12 (CA-12 se prueba en el paso 22).
☐ 20.2 Registrar cada caso: fecha, ejecutor, resultado, evidencia.
☐ 20.3 Ejecutar el CAAT:
```powershell
./scripts/08-Test-InventarioControles.ps1 -Ambiente DEV -RevisarPermisos
```

🔍 **Verificación:** todos los casos aprobados; CAAT sin desviaciones de severidad *Alta*.
📁 Planilla de casos de prueba y papel de trabajo `logs/CAAT_Inventario_DEV_*.xlsx`.

## Paso 21 · Preparar TEST y PROD

**Quién:** TI.

☐ Repetir para `-Ambiente TEST` y luego `-Ambiente PROD`, en este orden:

| ☐ | Paso | Comando |
|---|---|---|
| ☐ | 9 | `./scripts/02-New-InventorySite.ps1 -Ambiente <AMB>` |
| ☐ | 10 | `./purview/02-New-RetentionPolicy.ps1 -UrlSitio <url del sitio <AMB>>` |
| ☐ | 11 | `./scripts/03-New-InventoryLists.ps1 -Ambiente <AMB>` |
| ☐ | 12 | `./scripts/04-Import-MasterData.ps1 -Ambiente <AMB>` |
| ☐ | 13 | `./scripts/05-Set-InventoryPermissions.ps1 -Ambiente <AMB>` |
| ☐ | 14 | Cargar *CatalogoRAT* |

En TEST y PROD crear las **conexiones** de la cuenta de servicio (una por conector) en el entorno correspondiente antes de importar.

## Paso 22 · Promover la solución DEV → TEST → PROD

**Quién:** Desarrollador principal + Administrador de Power Platform.

☐ 22.1 En DEV: **Soluciones → RN Inventario de Activos → Exportar → Administrada**, versión `1.0.0.x`. Guardar también la exportación **no administrada** como respaldo.
☐ 22.2 Versionar en Git (opcional, recomendado):
```bash
pac solution unpack --zipfile RNInventarioActivos_managed.zip --folder powerplatform/solution --packagetype Managed
git add powerplatform/solution && git commit -m "Solución 1.0.0.x"
```
☐ 22.3 Generar el archivo de configuración de implementación y completarlo con los valores del ambiente destino (URL de sitio y GUID de listas de `logs/ids-listas-<AMB>.csv`; Id de las conexiones de la cuenta de servicio):
```bash
pac solution create-settings --solution-zip RNInventarioActivos_managed.zip --settings-file settings.TEST.json
```
☐ 22.4 Importar en TEST:
```bash
pac auth create --environment <URL del entorno TEST>
pac solution import --path RNInventarioActivos_managed.zip --settings-file settings.TEST.json --activate-plugins
```
☐ 22.5 Activar los flujos automatizados; dejar **apagados** los programados hasta el *go-live*.
☐ 22.6 Compartir la app con los grupos `SGSI-INV-*` (*Compartir → grupo de seguridad*, rol *Usuario*).
☐ 22.7 Repetir 22.3 a 22.6 para PROD.

🔍 **Verificación CA-12:** en TEST, sin abrir ni editar ningún flujo, un alta desde la app funciona y deja historial.
📁 Registro de importación y archivo de configuración (sin secretos).

## Paso 23 · Piloto en producción

**Quién:** CISO + una gerencia de cada entidad (p. ej. GTG en RNSG y GTV en RNSV).

☐ 23.1 Agregar a los titulares, subrogantes y delegados de las dos gerencias piloto a sus grupos de edición (aprobación del CISO).
☐ 23.2 Publicar la app como pestaña en el canal SGSI de Teams (RF-47): canal → **+** → *Power Apps* → *Inventario de Activos*.
☐ 23.3 Capacitar a los usuarios piloto (1 h, con el manual de usuario `docs/04_Manual_de_Usuario.md`).
☐ 23.4 Registrar entre 10 y 20 activos reales por gerencia, declararlos y validarlos.
☐ 23.5 Prueba de humo de segregación: un usuario piloto de RNSV abre la lista *Activos* directamente en SharePoint y no ve los activos de RNSG (CA-02).
☐ 23.6 Recoger observaciones de usabilidad y ajustar la app (versión 1.0.1 por el mismo procedimiento del paso 22).

**🏁 Hito F1:** piloto en producción con activos *Vigentes* en ambas entidades y CA-02 verificado en PROD.

---

# FASE F2 · CICLO DE VIDA (semanas 9–12)

> Si en F1 se construyeron todos los flujos, esta fase se centra en **activar y probar en PROD** las funciones del ciclo de vida. Si se optó por un MVP reducido, aquí se construyen FL-05 a FL-09 y FL-07 siguiendo el paso 17.

## Paso 24 · Revisiones integrales y de accesos
☐ 24.1 Activar FL-05 y FL-06 en PROD.
☐ 24.2 Verificar con un activo piloto cuya revisión vence en ≤ 30 días que llega el aviso y que la campaña aparece en *Revisiones*.
☐ 24.3 Probar la confirmación en lote "sin cambios" (RF-30) y una revisión de accesos con evidencia (RF-29).

## Paso 25 · Reclasificación, traspaso y baja
☐ 25.1 Reclasificar un activo piloto con motivo (CA-06) y sin motivo (se revierte).
☐ 25.2 Traspasar un activo entre dos cargos piloto (RF-33): el receptor acepta, cambian los permisos.
☐ 25.3 Dar de baja un activo de prueba Confidencial por proveedor: no se cierra sin certificado (CA-08).

## Paso 26 · Excepciones
☐ 26.1 Activar FL-07b.
☐ 26.2 Solicitar una excepción de 18 meses (debe rechazarse, CA-07) y otra de 6 meses que recorra CISO → DPO → CSI.
☐ 26.3 Confirmar que el CSI recibe la aprobación en Teams/Outlook y que el registro queda *Vigente* con su acta.

## Paso 27 · Historial y trazabilidad
☐ Verificar en un activo piloto que el *Historial* de la ficha muestra todos los eventos y que la lista *HistorialClasificacion* tiene el usuario real (no la cuenta de servicio) en cada evento.

## Paso 28 · Respaldo y restauración
☐ 28.1 Activar FL-12 en PROD y verificar el primer respaldo del domingo en `Respaldos/<fecha>/`.
☐ 28.2 Prueba de restauración **en TEST**:
```powershell
./scripts/07-Restore-Inventory.ps1 -Ambiente TEST -Fecha <aaaa-MM-dd> -Lista Activos -Modo Comparar
./scripts/07-Restore-Inventory.ps1 -Ambiente TEST -Fecha <aaaa-MM-dd> -Lista Activos -Modo RestaurarCampos -Autorizacion <ticket>
```
📁 CSV de diferencias y log de la restauración (evidencia de RNF-08).

**🏁 Hito F2:** ciclo completo operativo en PROD (revisión, reclasificación, traspaso, baja, excepción y restauración probados).

---

# FASE F3 · REPORTERÍA E INTEGRACIONES (semanas 13–16)

## Paso 29 · Tablero de Power BI
**Quién:** Desarrollador de BI. **Referencia:** `powerbi/README.md`. **Requisito:** D-01/D-08 (licencias Pro).

☐ 29.1 Activar FL-15 (pertenencia a grupos) y verificar que *PertenenciaGrupos* tiene filas.
☐ 29.2 En Power BI Desktop: crear las consultas de `powerbi/consultas.pq`, las relaciones, la tabla `_Medidas` con `medidas.dax` y el rol **Inventario** con `rls.dax`.
☐ 29.3 Construir las 7 páginas de la sección 15.2 (tabla de páginas en `powerbi/README.md`).
☐ 29.4 Probar **Ver como** con un Dueño de RNSG, uno de RNSV y un usuario transversal.
☐ 29.5 Publicar en el área de trabajo *SGSI – Inventario (PROD)*; aplicar la etiqueta *Reservado* al informe y al modelo; configurar la actualización diaria con la cuenta de servicio; crear la aplicación de Power BI y asignar los grupos al rol *Inventario*.

🔍 **Verificación CA-10:** el Dueño de RNSG solo ve indicadores de su entidad y gerencia.

## Paso 30 · Vínculo con el RAT
☐ Confirmar que el combo del paso 4 del asistente lista las actividades del RAT de la entidad y que el CAAT C15 no encuentra RAT inexistentes.

## Paso 31 · Integración con la CMDB (según D-05)
☐ 31.1 Acordar con TI el extracto semanal (CSV con ID del CI, nombre, tipo y estado) y su entrega en `CargaMasiva/CMDB`.
☐ 31.2 Construir y activar FL-13. Revisar el primer informe de conciliación (CI productivos sin activo y activos con ID de CMDB inexistente).

## Paso 32 · Integración con la matriz de riesgos
☐ Verificar el aviso a Riesgos al validar un activo crítico y que Riesgos registra el ID con *Registrar ID de riesgo* (FL-10b).

## Paso 33 · Primer reporte al CSI
☐ 33.1 Generar la página *Informe CSI / NCG 454* por entidad.
☐ 33.2 Adjuntar el papel de trabajo CAAT del mes:
```powershell
./scripts/08-Test-InventarioControles.ps1 -Ambiente PROD -RevisarPermisos
```

**🏁 Hito F3:** primer reporte presentado al CSI.

---

# FASE F4 · DESPLIEGUE (semanas 17–20)

## Paso 34 · Plan de despliegue por gerencias
**Quién:** CISO + jefe de proyecto.

☐ Definir olas de 3 a 5 gerencias por semana, con fecha de capacitación, carga y meta de activos por gerencia (mitiga "baja adopción", sección 18). Comunicación del patrocinador del CSI a los gerentes antes de cada ola.

## Paso 35 · Preparación de la carga inicial (por ola)
☐ 35.1 Actualizar la hoja *Maestros* de la plantilla con los valores vigentes y regenerar si cambió el catálogo:
```bash
python3 tools/build_plantilla_carga.py
```
☐ 35.2 Entregar a cada gerencia la plantilla `templates/Plantilla_Carga_Inventario_Activos.xlsx` y una sesión de 30 minutos sobre cómo llenarla (hoja *Instrucciones*).
☐ 35.3 Cuando la gerencia la devuelve, validarla:
```powershell
./scripts/06-Test-PlantillaCarga.ps1 -Archivo ./cargas/GTG.xlsx -ConectarSitio -Ambiente PROD
```
☐ 35.4 Devolver el `_reporte.xlsx` a la gerencia y repetir hasta **0 errores** (las advertencias se aceptan: quedarán como alertas del borrador).

## Paso 36 · Carga
☐ 36.1 Subir el archivo validado a `CargaMasiva/Entrada` (solo el CISO tiene permiso).
☐ 36.2 Esperar el correo de FL-11 con los totales y revisar el reporte en `CargaMasiva/Reportes`.
☐ 36.3 Ejecutar el CAAT después de cada ola:
```powershell
./scripts/08-Test-InventarioControles.ps1 -Ambiente PROD -RevisarPermisos
```
🔍 **Verificación:** C01 (IDs únicos), C02/C03 (permisos), C13 (correlativos) sin desviaciones.

## Paso 37 · Habilitar a los usuarios de la ola
☐ 37.1 Personas confirma titulares y subrogantes en *Cargos*.
☐ 37.2 TI agrega a titulares, subrogantes y delegados a su grupo `SGSI-INV-<ENT>-<GER>-EDIT` (aprobación del CISO).
☐ 37.3 Capacitación de 1 hora: registro, declaración, revisiones, excepciones.
☐ 37.4 Cada Dueño completa y **declara** sus activos cargados (quedan en *Borrador*). Meta: 100 % declarados en 2 semanas.

## Paso 38 · Seguimiento de la ola
☐ Tablero → página *Cumplimiento*: % declarados y % validados por gerencia. Escalamiento al gerente si la gerencia no avanza en una semana.

## Paso 39 · Activar el acceso condicional definitivo
☐ Cambiar la política del paso 8.4 de *Solo informe* a **Activada**, después de revisar los inicios de sesión que habría bloqueado.

## Paso 40 · Salida a producción completa
☐ Completar la **lista de verificación del Anexo B** y obtener la aprobación del CSI.

**🏁 Hito F4:** inventario completo de ambas entidades.

---

# OPERACIÓN

## Paso 41 · Soporte post-implementación (4 semanas)
☐ Mesa de ayuda con el equipo SGSI; revisión diaria de ejecuciones fallidas de flujos y de los correos *Cambio no autorizado revertido*; reunión semanal de incidencias.

## Paso 42 · Traspaso a operación
☐ Entregar al CISO y a TI el manual de administración (`docs/03_Manual_de_Administracion.md`) y transferir la propiedad de las conexiones y del área de trabajo de Power BI a sus responsables definitivos. Documentar el procedimiento de cambio de la cuenta de servicio.

## Paso 43 · Calendario de controles recurrentes

| Frecuencia | Control | Responsable |
|---|---|---|
| Diaria | Ejecuciones fallidas de flujos; resumen de revisiones y escalamientos | TI / CISO |
| Semanal | Correo de respaldo FL-12 y conteo de permisos únicos (alerta a los 4.000) | CISO / TI |
| Mensual | CAAT `scripts/08` en PROD; informe de excepciones al CSI | CISO |
| Semestral | Prueba de restauración en TEST; revisión de la hoja de ruta de Microsoft 365 | TI |
| Anual | Informe de estado del inventario al CSI y resumen NCG 454 por entidad; revisión de parámetros; CAAT de Auditoría Interna (sin `-Remediar`) | CISO / Auditoría |

---

# ANEXO A · Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Connect-PnPOnline`: *AADSTS700016 application not found* | Falta registrar la app de PnP o el Client ID es incorrecto | Paso 3.2; revisar `pnp.clientId` |
| `02`: *No se pudo aplicar la etiqueta* | Etiqueta aún no publicada o sin alcance *Sitios y grupos*; integración de etiquetas en SharePoint desactivada | Esperar 24 h; paso 7.3; volver a ejecutar |
| `05`: *Grupo no resuelto* | `logs/grupos-entra-<AMB>.csv` no existe o falta un grupo | Ejecutar el paso 8 con el mismo `-Ambiente` |
| `05`: *Parámetro … no existe* | Se ejecutó 05 antes de 04 | Ejecutar `04-Import-MasterData.ps1` y luego 05 |
| La app muestra advertencias de delegación | Filtro sobre *Activos* con `in`, `Search` o columna no indexada | Reescribir según las reglas de `Pantallas.md` |
| Error *El número de elementos supera el umbral de vista* | Vista o consulta sin filtro indexado | Usar las vistas creadas por `03`; el primer filtro debe ser una columna indexada |
| FL-02 se ejecuta en bucle | Falta la condición anti-bucle o la cuenta de servicio no coincide | `powerautomate/README.md` §2 |
| FL-01 devuelve "No autorizado" a un Dueño legítimo | El usuario no está en el grupo de edición de la gerencia o `RN_GrupoEdicionEntraId` está vacío | Revisar membresía; reejecutar `05` |
| Las aprobaciones no llegan | Approvals sin base de datos aprovisionada en el entorno; notificaciones de Teams bloqueadas | Ver nota del paso 2; revisar la app Aprobaciones en Teams |
| Errores 429 en cargas masivas | Limitación de SharePoint | Normal: la directiva de reintento exponencial lo resuelve; dividir archivos de más de 2.000 filas |
| La exportación trae activos que el usuario no debería ver | FL-16 configurado con la conexión de la cuenta de servicio | Paso 17.2 g: FL-16 debe usar la conexión del usuario |
| El Dueño nuevo no ve sus activos | Cambió el titular en *Cargos* pero no la membresía del grupo | Paso 37.2 (CA-11) |
| CAAT C11 en alerta | Más de 4.000 elementos con permisos únicos | Decisión D-14 (dividir la lista por entidad o escenario C) |

# ANEXO B · Lista de verificación de salida a producción

| ☐ | Ítem | Evidencia |
|---|---|---|
| ☐ | Decisiones D-01, D-02, D-03, D-04, D-06, D-07, D-09, D-11 cerradas | Actas |
| ☐ | Etiquetas de sensibilidad publicadas; sitio etiquetado *Reservado* | Captura |
| ☐ | Retención de 5 años aplicada y auditoría unificada activa | Captura / log |
| ☐ | Acceso condicional activado para los grupos `SGSI-INV-*` | Captura |
| ☐ | Permisos verificados (paso 13) y CA-02 probado en PROD | Capturas, CAAT C02/C03 |
| ☐ | DLP aplicada a los entornos de la solución | Captura |
| ☐ | Solución administrada importada sin reconfiguración (CA-12) | Registro de importación |
| ☐ | Flujos activados (automatizados y programados) y sin fallos en 7 días | Análisis de Power Automate |
| ☐ | CA-01 a CA-12 y CP-01 a CP-12 aprobados | Planilla de pruebas |
| ☐ | Respaldo semanal verificado y prueba de restauración realizada | Logs de FL-12 y `07` |
| ☐ | Tablero publicado con RLS probada (CA-10) | Captura de *Ver como* |
| ☐ | CAAT en PROD sin desviaciones de severidad *Alta* | Papel de trabajo |
| ☐ | Manuales entregados (RNF-15) | `docs/` |
| ☐ | Soporte post-implementación planificado | Plan |

# ANEXO C · Matriz RACI

R = Responsable · A = Aprueba · C = Consultado · I = Informado

| Actividad | CISO | TI | Dev. Power Platform | DPO | Personas | CSI | Auditoría |
|---|---|---|---|---|---|---|---|
| Aprobar diseño y desviaciones (paso 1) | R | C | C | C | — | A | I |
| Decisiones pendientes (paso 2) | R | R | C | R | — | A | I |
| Identidades, grupos y acceso condicional (pasos 3, 8) | A | R | I | — | C | — | I |
| Maestros (paso 5) | A | C | I | C | R | — | — |
| Etiquetas y retención (pasos 7, 10) | A | R | — | C | — | I | I |
| Sitio, listas y permisos (pasos 9, 11–13) | A | R | C | — | — | — | I |
| Entornos y DLP (paso 15) | C | R | C | — | — | — | I |
| Flujos y app (pasos 16–19) | A | C | R | C | — | — | — |
| Pruebas (paso 20) | A | C | R | C | — | — | C |
| Promoción a PROD (paso 22) | A | R | R | — | — | I | I |
| Piloto y despliegue por olas (pasos 23, 34–38) | R | C | C | C | C | I | I |
| Tablero y reporte al CSI (pasos 29, 33) | R | C | R | C | — | I | I |
| Salida a producción (paso 40) | R | R | C | C | — | A | I |
| CAAT recurrente (paso 43) | R | C | — | — | — | I | R (independiente) |

# 02 · Manual de instalación (runbook de despliegue)

Ejecutar en orden en **DEV**, luego **TEST** y finalmente **PROD** (fases F0–F1 del plan, sección 17). Cada paso deja log en `logs/` (excluido de Git): consérvelo como evidencia del despliegue.

## 0. Requisitos previos (F0)

| Requisito | Responsable | Verificación |
|---|---|---|
| Decisiones D-01, D-02, D-03, D-09 resueltas | CSI / TI / CISO / DPO | Acta |
| Cuenta de servicio `svc-sgsi-inventario@…` con licencia E3, MFA según política de TI, excluida de expiración de contraseña solo si la política lo permite y con credencial en bóveda | TI | Ficha de la cuenta |
| App de Entra ID para PnP PowerShell (`Register-PnPEntraIDAppForInteractiveLogin`) | TI | `pnp.clientId` en la configuración |
| Equipo de despliegue: PowerShell 7.4+, módulos `PnP.PowerShell` ≥ 2.4, `Microsoft.Graph.Groups` ≥ 2.0, `ExchangeOnlineManagement` ≥ 3.4, `ImportExcel` ≥ 7.8; Windows PowerShell 5.1 con `Microsoft.PowerApps.Administration.PowerShell` | TI | `Get-Module -ListAvailable` |
| Roles: Administrador de SharePoint, de Grupos, de Cumplimiento, de Power Platform (pueden ser personas distintas) | TI | PIM / asignaciones |
| Node.js 18+ y Python 3.10+ con `openpyxl` (solo para regenerar la plantilla y ejecutar pruebas) | Desarrollo | `npm test` |

```powershell
Install-Module PnP.PowerShell, Microsoft.Graph.Groups, ExchangeOnlineManagement, ImportExcel -Scope CurrentUser
Copy-Item config/solution.config.json config/solution.config.DEV.json   # ajustar tenant, URL, clientId, cuenta de servicio
```

Completar los maestros en `config/maestros/*.csv` con el organigrama vigente (Personas entrega cargos y titulares). Verificar antes de seguir:

```bash
npm test          # 23 pruebas de reglas de negocio
npm run validar   # restricciones de SharePoint y consistencia entre capas
```

## 1. Etiquetas y retención (una vez por tenant)
```powershell
./purview/01-New-SensitivityLabels.ps1 -Dominio rentanacional.cl -WhatIf    # revisar
./purview/01-New-SensitivityLabels.ps1 -Dominio rentanacional.cl
```
Copiar el GUID de **Reservado** en `sitio.etiquetaSensibilidadId`. Esperar la publicación (hasta 24 h) antes del paso 3.

## 2. Grupos de Entra ID
```powershell
./scripts/01-New-EntraGroups.ps1 -Ambiente DEV
```
Genera `logs/grupos-entra-DEV.csv` (lo consume el paso 6). Agregar los grupos a la política de **acceso condicional** del sitio (MFA + dispositivo administrado o ubicación confiable, RNF-02). Asignar miembros: los de edición con aprobación del CISO.

## 3. Sitio
```powershell
./scripts/02-New-InventorySite.ps1 -Ambiente DEV
./purview/02-New-RetentionPolicy.ps1 -UrlSitio <url del sitio>
```

## 4. Listas, columnas, índices y vistas
```powershell
./scripts/03-New-InventoryLists.ps1 -Ambiente DEV
```
Revisar en el log: `Activos: 15 columnas indexadas (máx. 20); 9 columnas de búsqueda/persona propias (+Autor/Editor, umbral 12)`. Los GUID de listas quedan en `logs/ids-listas-DEV.csv`.

## 5. Maestros y parámetros
```powershell
./scripts/04-Import-MasterData.ps1 -Ambiente DEV
```
Reejecutable (upsert). Los parámetros ya existentes no se sobrescriben salvo `-SobrescribirParametros`.

## 6. Permisos
```powershell
./scripts/05-Set-InventoryPermissions.ps1 -Ambiente DEV
```
Escribe en *Parámetros* los Id de grupos y roles (`GRUPO_*_SPID`, `GRUPO_*_ENTRAID`, `ROL_*_ID`) y en *Gerencias* los Id de cada grupo de edición.

## 7. Power Platform: entornos y DLP
```powershell
.\scripts\09-New-PowerPlatformGovernance.ps1 -Region <región del tenant>
```

## 8. Construcción de la solución en DEV
1. Crear la solución **RNInventarioActivos** (publicador `rnsgsi`).
2. Variables de entorno y referencias de conexión según `powerautomate/README.md` §1 (conexiones de la cuenta de servicio).
3. Construir los flujos en este orden, siguiendo cada especificación: FL-02b → FL-01b → FL-01 → FL-03 → FL-05b/FL-06b → FL-08 → FL-09 → FL-02 → FL-05 → FL-06 → FL-07a/b → FL-10b → FL-11 → FL-12 → FL-13 → FL-14 → FL-15 → FL-16.
4. App canvas: pegar `powerapps/src/App.Formulas.fx` en *App.Formulas* y `App.OnStart.fx` en *App.OnStart*; construir las pantallas según `powerapps/Pantallas.md`; agregar como orígenes los flujos FL-01, FL-07a, FL-10b y FL-16. *Configuración → Próximas características*: habilitar **Funciones definidas por el usuario**.
5. Office Script: crear `EscribirInventario` desde `powerapps/officescripts/EscribirInventario.ts` (propiedad de la cuenta de servicio, compartido con el flujo) y subir `Plantilla_Exportacion_Reservado.xlsx` (con hoja *Inventario* y etiqueta **Reservado** aplicada) a `CargaMasiva/Plantillas`.
6. Power BI: según `powerbi/README.md`.
7. Ejecutar el plan de pruebas (`docs/05_Plan_de_Pruebas.md`) en DEV.

## 9. Promoción a TEST y PROD (CA-12)
1. Repetir pasos 1–7 en el ambiente destino con `-Ambiente TEST|PROD` (las listas y los Id de grupos son propios de cada ambiente).
2. Exportar la solución desde DEV como **administrada**; versionar el `.zip` (o desempaquetar con `pac solution unpack` en `powerplatform/solution/` de este repositorio).
3. Importar en el destino con un *archivo de configuración de implementación* (`pac solution create-settings`) que asigne los valores de variables de entorno (URL de sitio y GUID de listas desde `logs/ids-listas-<AMB>.csv`) y las referencias de conexión de la cuenta de servicio del ambiente: **sin reconfiguración manual de conexiones** (CA-12).
4. Activar los flujos (los programados quedan apagados hasta el *go-live*), compartir la app con los grupos `SGSI-INV-*`, publicarla en el canal SGSI de Teams (RF-47).
5. Prueba de humo en PROD con un activo de prueba por entidad, que luego se da de baja.

## 10. Carga inicial (F1/F4)
1. Distribuir `templates/Plantilla_Carga_Inventario_Activos.xlsx` (regenerable con `python3 tools/build_plantilla_carga.py`) con la hoja *Maestros* actualizada.
2. Validar cada archivo: `./scripts/06-Test-PlantillaCarga.ps1 -Archivo <archivo> -ConectarSitio -Ambiente PROD`.
3. Depurar con cada gerencia hasta 0 errores y dejar el archivo en `CargaMasiva/Entrada` (FL-11).
4. Verificar con `./scripts/08-Test-InventarioControles.ps1 -Ambiente PROD -RevisarPermisos`.

## 11. Reversión
* App y flujos: reimportar la versión administrada anterior de la solución.
* Datos: `./scripts/07-Restore-Inventory.ps1 -Fecha <respaldo> -Modo Comparar`, luego `RestaurarCampos` o `RecrearFaltantes` con `-Autorizacion <ticket>`.
* Permisos: `./scripts/08-Test-InventarioControles.ps1 -RevisarPermisos -Remediar`.

# RN-INV FL-12 a FL-15 Flujos de mantenimiento programados

## FL-12 Respaldo semanal (RNF-08)
* Disparador: Periodicidad semanal, domingo 02:15.
* Para cada lista de `createArray('Activos','HistorialClasificacion','Revisiones','Excepciones','Cargos','Gerencias','Procesos','Entidades','Terceros','Parametros','Correlativos','RelacionesActivos')`:
  * SharePoint HTTP `GET _api/web/lists/getbytitle('<Lista>')/items?$top=5000&$select=*,RN_Entidad/Title,RN_Gerencia/Title,...&$expand=...` con bucle *Hacer hasta* sobre `odata.nextLink` (paginación del servidor; respeta el umbral porque no filtra).
  * Unir páginas (`union()`), crear archivo `Respaldos/<aaaa-MM-dd>/<Lista>.json`.
* Contar elementos con permisos únicos: `GET _api/web/lists/getbytitle('Activos')/items?$select=Id,HasUniqueRoleAssignments&$top=5000` + Excepciones; si ≥ `UMBRAL_PERMISOS_UNICOS_ALERTA` → correo al CISO y a TI (RNF-11, decisión de separar listas o migrar al escenario C).
* Conservar 12 respaldos semanales + el último de cada mes por 5 años (eliminar carpetas antiguas según esa regla).
* Correo de confirmación al CISO con número de elementos por lista (evidencia del control de respaldo). Restauración: `scripts/07-Restore-Inventory.ps1`.

## FL-13 Sincronización CMDB (RF-45; depende de D-05)
* Disparador: archivo nuevo en `CargaMasiva/CMDB` (extracto CSV/Excel semanal entregado por TI) o Periodicidad semanal si TI deja el archivo en una ruta fija.
* Upsert en `ReferenciaCMDB` por `Title` (= ID del CI); marcar `RN_EstadoCI = "No presente en extracto"` los que no vengan.
* Conciliación: activos tecnológicos con `RN_IdCMDB` inexistente en la referencia → alerta en el resumen al CISO y a TI; CIs productivos sin activo asociado → lista de brechas (control RN-15: registro antes de producción).

## FL-14 Cargos vacantes y titulares inactivos (RF-50)
* Disparador: Periodicidad semanal, lunes 07:30.
* Por cada `Cargos` con `RN_Titular`: Office 365 Users **Obtener el perfil de usuario (V2)**; si falla (usuario eliminado) o `accountEnabled = false` → `RN_EstadoTitular = Titular inactivo`. Sin titular → `Vacante`.
* Activos cuyo cargo Dueño no está *Vigente*: correo al CISO y a `CORREO_PERSONAS` para reasignar (mientras tanto el Dueño provisorio es el CISO, RN-14).
* Sincroniza `RN_DuenoPersona` de los activos cuando cambió el titular del cargo (sin cambiar el cargo: CA-11).

## FL-15 Pertenencia a grupos para Power BI (sección 13)
* Disparador: Periodicidad diaria 05:00.
* Para cada grupo `SGSI-INV-*`: Office 365 Groups **List group members** (paginado). Reemplazar el contenido de `PertenenciaGrupos` (`RN_UPN`, `RN_Grupo`, `RN_EntidadCodigo`, `RN_GerenciaCodigo` derivados del nombre `SGSI-INV-<ENT>-<GER>-EDIT`, `RN_Transversal = true` para CISO, DPO, RIESGOS, CSI y AUDITORIA).
* Power BI usa esta tabla para la seguridad por filas (`powerbi/`).

# 03 · Manual de administración (CISO / equipo SGSI y Gerencia de TI)

## 1. Responsabilidades

| Tarea | Responsable | Frecuencia | Herramienta |
|---|---|---|---|
| Altas/bajas en grupos `SGSI-INV-<ENT>-<GER>-EDIT` | CISO aprueba; TI ejecuta | Según movimientos informados por Personas | Entra ID (o paquete de acceso de Entra ID Governance si existe) |
| Mantener maestros (Entidades, Gerencias, Procesos, Terceros) | CISO | Ante cambios | App → Administración |
| Titulares y subrogantes de cargos | Gerencia de Personas | Ante cada movimiento | Lista Cargos |
| Delegados de registro | Dueño solicita, CISO registra | Ante cambios | Cargos → `RN_Delegados` |
| Parámetros de negocio | CISO | Ante cambio normativo | App → Administración → Parámetros |
| Revisar resumen diario de revisiones y escalamientos | CISO | Diaria | Correo FL-05/FL-06 |
| Revisar alertas de *Cambio no autorizado revertido* | CISO | Diaria | Correo FL-02 / lista Historial |
| Verificar respaldo semanal y conteo de permisos únicos | CISO + TI | Semanal | Correo FL-12 |
| CAAT de controles del inventario | CISO (2ª línea); Auditoría (3ª línea, sin `-Remediar`) | Mensual / anual | `scripts/08-Test-InventarioControles.ps1` |
| Informe anual al CSI y resumen NCG 454 por entidad | CISO | Anual | Power BI → página *Informe CSI / NCG 454* |
| Monitoreo de ejecuciones fallidas de flujos | TI | Diaria | Centro de administración de Power Platform → Análisis; correo *Catch* |
| Revisión de la hoja de ruta Microsoft (límites, licencias) | TI | Semestral | Centro de mensajes M365 |

## 2. Parámetros (lista *Parametros*)
Todos los valores de negocio están en `Parametros` (semilla: `config/parametros.json`). Cambiar un valor:
1. App → Administración → Parámetros → editar. Para tipo JSON la app valida el formato antes de guardar.
2. El cambio aplica en la siguiente ejecución de cada flujo y al reabrir la app. Las fechas de próxima revisión ya calculadas se recalculan en el siguiente cambio de cada activo; para recalcular todo, ejecutar manualmente **FL-02b** en lote (vista *Inventario vigente* → ejecutar flujo) o esperar a la revisión.
3. Registrar el cambio en el control de cambios del SGSI (el versionado de la lista conserva quién y cuándo).

Parámetros críticos: `NIVEL_MIN_DATOS_PERSONALES` / `NIVEL_MIN_DATOS_SENSIBLES` (decisión D-03), `FREC_*`, `AVISOS_DIAS_ANTES`, `EXCEPCION_MAX_MESES`, `REGLAS_MANEJO`, `METODO_BAJA_POR_NIVEL`, `CAMPOS_EI_HABILITADOS` (habilita los 18 campos de estándares internacionales en la fase 2, RF-06).

## 3. Operaciones frecuentes

**Nuevo colaborador Dueño / Delegado.** Personas actualiza el titular en *Cargos*; TI agrega a la persona al grupo de edición de su gerencia (aprobación CISO). No se tocan los activos: siguen asociados al cargo (RN-12, CA-11). FL-14 sincroniza `RN_DuenoPersona`.

**Nueva gerencia.** Agregar fila en `config/maestros/gerencias.csv` (código de 2–6 caracteres, inmutable) → `scripts/01` (crea el grupo) → `scripts/04` (maestro) → `scripts/05` (permisos de evidencias y Id de grupo). Reejecutables.

**Reasignación masiva de Dueños (reestructuración).** App → Administración → Reasignación: seleccionar cargo origen y destino. Cada activo pasa por FL-09 con aceptación del receptor.

**Activo transversal o de propiedad dudosa (RN-14).** Registrar con Dueño = cargo CISO (Dueño provisorio) y llevar al CSI; luego traspasar al Dueño asignado.

**Reapertura de un activo Vigente.** App → Administración → Reapertura (motivo obligatorio). El activo pasa a *En revisión* y el Dueño debe declarar de nuevo.

**Carga masiva.** Ver manual de instalación §10. Los activos nacen en *Borrador*: comunicar a cada Dueño que debe completar y declarar.

## 4. Monitoreo de la capacidad (RNF-11)
* FL-12 informa semanalmente el número de elementos con permisos únicos (Activos + Excepciones). Alerta a partir de `UMBRAL_PERMISOS_UNICOS_ALERTA` (4.000).
* Al superar 4.500: decidir entre (a) dividir `Activos` en `Activos_RNSG`, `Activos_RNSV` y `Activos_AMBAS` con permisos a nivel de lista para las dos primeras (requiere ajustar la app y flujos para operar sobre tres orígenes) o (b) migrar al escenario C (Dataverse con unidades de negocio).
* Listas cercanas a 5.000 elementos: todas las vistas y consultas usan columnas indexadas como primer filtro; no crear vistas sin filtro indexado.

## 5. Respaldo y restauración (RNF-08)
* FL-12 deja cada domingo `Respaldos/<aaaa-MM-dd>/<Lista>.json` (biblioteca con acceso solo CISO y Admin TI). Retención: 12 semanales + 1 mensual por 5 años.
* Restaurar: `scripts/07-Restore-Inventory.ps1` – primero `-Modo Comparar` (sin cambios, entrega diferencias en `logs/`), luego `RestaurarCampos` o `RecrearFaltantes` con `-Autorizacion`. Toda restauración queda en el Historial.
* Además: papelera de reciclaje de SharePoint (93 días) y versionado (500 versiones por elemento).
* Prueba de restauración: semestral, en TEST, con evidencia (log + CSV de diferencias).

## 6. Gestión de incidentes y continuidad
* Fallo de flujos: el bloque *Catch* notifica al CISO y TI. Los activos quedan en estado seguro (sin permisos de usuario en caso de fallo del alta). Reintentar la ejecución desde el historial de ejecuciones.
* Caída de Power Platform: el inventario sigue consultable en las vistas de SharePoint (solo lectura práctica: las columnas protegidas se revierten al volver el servicio).
* Pérdida de la cuenta de servicio: TI restablece la credencial; si debe reemplazarse, actualizar `CUENTA_SERVICIO_UPN`, las conexiones de la solución y reejecutar `scripts/05` (permisos de lista).
* Incidente de seguridad sobre el inventario (acceso indebido): enlazar con el procedimiento vigente de incidentes (fuera de alcance, sección 2). Evidencias: auditoría unificada (`purview/02` muestra la consulta), Historial y versiones.

## 7. Auditoría y evidencias (RF-49, NG 6.3)
| Evidencia | Dónde | Retención |
|---|---|---|
| Versiones de cada activo (qué, quién, cuándo) | Versionado de `Activos` | 500 versiones |
| Bitácora de eventos (alta, declaración, validación, reclasificación, traspaso, baja, revisión, excepción, cambios revertidos, exportaciones) | `HistorialClasificacion` | 5 años (RNF-07) |
| Aprobaciones CISO/DPO/CSI | Approvals (historial) + Historial | Según Approvals / 5 años |
| Accesos a la información | Auditoría unificada Purview | 180 días (E3) |
| Respaldos | `Respaldos` | 5 años |
| Papeles de trabajo CAAT | `logs/CAAT_*.xlsx` → archivar en el repositorio de auditoría | Según política |

# 05 · Plan de pruebas y criterios de aceptación

## 1. Niveles de prueba

| Nivel | Qué cubre | Cómo | Estado en este repositorio |
|---|---|---|---|
| Reglas PowerShell (Pester) | Mismos casos sobre `RNInventario.Reglas.psm1` | `Invoke-Pester ./tests/powershell` | No ejecutadas aquí (sin PowerShell en el entorno de desarrollo) |
| Reglas de negocio (unitarias) | RN-02 a RN-11, RF-07, RF-17 a RF-21, RF-26, RF-28, RF-31, RF-32, RF-34, RF-36 | `npm test` (`tests/reglas/reglas.test.js`, 23 pruebas) | **Ejecutadas: 23/23 aprobadas** |
| Configuración (estática) | Límites de SharePoint (índices, búsquedas), catálogo completo, parámetros referenciados, coherencia de reglas en app/flujos/PowerShell | `npm run validar` | **Ejecutada: sin errores** |
| Integración en tenant | Scripts PnP, flujos, app, Power BI | Casos §2 en DEV y TEST con usuarios de prueba | Pendiente (requiere el tenant) |
| Aceptación (usuarios) | CA-01 a CA-12 + casos adicionales | Piloto con una gerencia por entidad (F1) | Pendiente |
| Controles (CAAT) | Permisos, segregación, integridad, trazabilidad | `scripts/08-Test-InventarioControles.ps1` tras cada carga y mensualmente | Pendiente |

**Usuarios de prueba (DEV/TEST):** `dueno.rnsg` (titular cargo Gerente Técnico RNSG, grupo `SGSI-INV-RNSG-GTG-EDIT`), `delegado.rnsg` (mismo grupo, delegado), `dueno.rnsv` (grupo `SGSI-INV-RNSV-GTV-EDIT`), `custodio.ti` (titular cargo Jefe de Infraestructura, `SGSI-INV-CUSTODIOS`), `ciso1`, `ciso2` (`SGSI-INV-CISO`), `dpo1`, `riesgos1`, `csi1`, `auditor1`.

## 2. Criterios de aceptación del ER (sección 16)

| ID | Escenario | Pasos | Resultado esperado | Evidencia | Automatizado |
|---|---|---|---|---|---|
| CA-01 | Datos personales clasificado Uso Interno | `dueno.rnsg` registra activo con *Datos personales = Sí*, RAT válido, nivel *Uso Interno* | Botón *Enviar* deshabilitado: "Nivel asignado (Uso Interno) inferior al mínimo exigido (Reservado)". Forzando `RN_SolicitudAccion = Declarar` desde SharePoint, FL-03 lo rechaza por alerta A04 | Captura + historial de ejecución FL-03 | Regla: `reglas.test.js` (CA-01) |
| CA-02 | Usuario RNSV abre la lista directamente | `dueno.rnsv` abre `…/Lists/Activos/AllItems.aspx` | Ve solo activos de su gerencia RNSV y los *Ambas* con su gerencia como dueña o contraparte; ningún activo RNSG. Repetir **durante** la creación de un activo RNSG (no aparece en ningún momento) | Captura; `scripts/08` C02/C03 sin desviaciones | CAAT C02, C03 |
| CA-03 | CISO observa con comentario | `ciso1` rechaza en Approvals con comentario | Estado *Observado*; titular y delegado reciben el comentario en Outlook y Teams. Rechazo sin comentario → nueva solicitud pidiendo el comentario | Correos, chat Teams, historial | — |
| CA-04 | Activo crítico revisado el 1 de marzo | Revisión con `RN_FechaUltimaRevision = 01-03` | `RN_ProximaRevision = 01-09`; avisos el 02-08, 17-08 y 01-09; escalamiento el 02-09 | Campos + correos (ejecutar FL-05 con fecha simulada en DEV) | `reglas.test.js` (CA-04, avisos) |
| CA-05 | Confidencial sin cargos autorizados | Declarar sin `RN_CargosAutorizados` | No pasa a *Vigente* (bloqueante A06) | Captura | `reglas.test.js` (CA-05) |
| CA-06 | Reclasificación Reservado → Confidencial | Dueño reclasifica con motivo | Registro en Historial con nivel anterior, nuevo, motivo, usuario y fecha; activo *En revisión*. Sin motivo → se revierte | Lista Historial | `reglas.test.js` (CA-06) |
| CA-07 | Excepción por 18 meses | Solicitar con fin = inicio + 18 meses | La app rechaza; si se fuerza la llamada al flujo, FL-07a responde "La vigencia no puede superar 12 meses" | Captura + ejecución | `reglas.test.js` (CA-07) |
| CA-08 | Proveedor elimina un Confidencial | Baja con *por proveedor* y sin certificado | Queda *En baja*; no pasa a *Dado de baja* hasta adjuntar certificado y N° | Estado + recordatorio | `reglas.test.js` (CA-08); CAAT C14 |
| CA-09 | Carga de 500 activos | Plantilla con 480 filas válidas y 20 con errores (búsqueda inexistente, nivel bajo mínimo, entidad vacía, duplicado) | 480 creados en *Borrador*; reporte CSV con 20 errores por fila. `scripts/06` previo detecta los mismos 20 | Reporte FL-11 y `_reporte.xlsx` | Validación previa `scripts/06` |
| CA-10 | Dueño RNSG abre el tablero | `dueno.rnsg` abre la app de Power BI | Solo indicadores de su entidad y gerencia | *Ver como* + captura | — |
| CA-11 | Cambia el titular del cargo de un Dueño | Personas cambia `RN_Titular`; TI cambia la membresía del grupo | Los activos siguen asociados al cargo; el nuevo titular los ve y puede declarar; el anterior ya no | Captura + CAAT C09 | — |
| CA-12 | Despliegue TEST → PROD | Importar solución administrada con archivo de configuración | Flujos operativos sin reconfigurar conexiones manualmente | Registro de importación | Depende de D-09 |

## 3. Casos adicionales (controles de seguridad y auditoría)

| ID | Escenario | Resultado esperado | Req. |
|---|---|---|---|
| CP-01 | `delegado.rnsg` intenta declarar | Botón deshabilitado; forzado vía SharePoint → FL-03 rechaza y registra intento | RF-26 |
| CP-02 | `custodio.ti` cambia `RN_Nivel` desde la lista | FL-02 revierte, historial *Cambio no autorizado revertido*, correo al CISO | RNF-03, DD-05 |
| CP-03 | Un Dueño edita `RN_ValidacionCISO = Validado` desde la lista | Revertido y registrado | RF-23 |
| CP-04 | `ciso1` declara (como titular) un activo de su gerencia | No figura entre los aprobadores; aprueba `ciso2` | Segregación |
| CP-05 | Llamar FL-01 con un usuario que no pertenece a la gerencia indicada | `ok:false`, "No autorizado", sin elemento creado | README §4 |
| CP-06 | Activo *Ambas* RNSG-GTI con contraparte RNSV-GTV | Visible y editable por ambos grupos; invisible para el resto | RN-13 |
| CP-07 | Exportación por `dueno.rnsv` | Excel con solo sus activos, etiqueta Reservado visible en Office | RF-44 |
| CP-08 | Fallo simulado de permisos en FL-01 (quitar temporalmente permiso a la cuenta de servicio) | Elemento sin permisos de usuarios + correo de error | DD-01 |
| CP-09 | Respaldo y restauración en TEST | Diferencias detectadas en modo Comparar y restauradas con historial | RNF-08 |
| CP-10 | 2.500 activos en TEST | Pantallas < 3 s; vistas sin error de umbral; galerías completas | RNF-09, RNF-10 |
| CP-11 | Texto con RUT en descripción en la plantilla | `scripts/06` lo advierte | RN-16 |
| CP-12 | Dos cargas concurrentes del mismo ENTIDAD-GERENCIA | IDs sin duplicados ni saltos reutilizados (CAAT C01, C13) | RN-01 |

## 4. Criterio de salida a producción
Todos los CA en *aprobado*, CP-01 a CP-08 aprobados, CAAT sin desviaciones de severidad Alta, decisiones D-02, D-03, D-06, D-07 y D-09 cerradas, manuales entregados (RNF-15).

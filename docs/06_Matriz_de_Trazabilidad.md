# 06 · Matriz de trazabilidad requerimiento → artefacto

Leyenda de estado: **I** = implementado en este repositorio (script, configuración o código probado); **E** = especificado para construir en Power Platform (flujo/app/informe); **D** = depende de una decisión pendiente.

## Requerimientos funcionales

| ID | Prior. | Artefacto(s) | Estado |
|---|---|---|---|
| RF-01 | Debe | `config/listas-soporte.json` (Entidades), `config/maestros/entidades.csv`, `scripts/04` | I |
| RF-02 | Debe | Gerencias, Procesos (`listas-soporte.json`, `gerencias.csv`, `procesos.csv`), `scripts/04` | I |
| RF-03 | Debe | Cargos (titular, subrogante, delegados), FL-14, `Pantallas.md` §9 | I / E |
| RF-04 | Debería | Terceros (contrato, país, NCG 573), `terceros.csv` | I |
| RF-05 | Debe | `config/parametros.json` (43 parámetros), lista Parametros (edición solo CISO, `scripts/05`) | I |
| RF-06 | Debe | `catalogo-campos.json` (61 campos), `CAMPOS_EI_HABILITADOS`, asistente `Pantallas.md` §3 | I / E |
| RF-07 | Debe | FL-01 §4 (correlativo con concurrencia optimista), `generarId` + pruebas, columna Title protegida | I / E |
| RF-08 | Debe | FL-01 §2, alertas A09/A10, `App.Formulas.fx` | I / E |
| RF-09 | Debe | `Mostrar*` en `App.Formulas.fx`; `condicion` en el catálogo | E |
| RF-10 | Debe | Borrador + `BorradorTieneBloqueantes`; FL-03 §1.4 | E |
| RF-11 | Debería | Lista RelacionesActivos, ficha §4 | I / E |
| RF-12 | Debe | Biblioteca Evidencias con carpetas ENT/GER (`scripts/05`), carpeta por activo *Ambas* (FL-01 §7) | I / E |
| RF-13 | Podría | *Duplicar como plantilla* (`Pantallas.md` §4) | E |
| RF-14 | Debe | `templates/Plantilla_Carga_Inventario_Activos.xlsx`, `scripts/06` (validación previa), FL-11 | I / E |
| RF-15 | Debe | `scrMisActivos` con filtros delegables; vistas indexadas `scripts/03` | I / E |
| RF-16 | Debe | Paso 3 del asistente con ayuda contextual | E |
| RF-17 | Debe | `esCritico` (pruebas), `EsCritico()`, FL-02b `Critico` | I / E |
| RF-18 | Debe | `nivelMinimo` + alerta A04 (pruebas CA-01), app, FL-02b, FL-03 | I / E |
| RF-19 | Debería | `nivelesAgregados` (pruebas), FL-02b `OrdMinAgr` / `S01` | I / E |
| RF-20 | Debe | `RN_NivelEfectivo`, `NivelEfectivo()`, Power Query, medida *Sin clasificar* | I / E |
| RF-21 | Debe | Alertas A06/A07 (pruebas CA-05) | I / E |
| RF-22 | Debería | `REGLAS_MANEJO` (D-11), panel en paso 5 | E / D |
| RF-23 | Debe | FL-03 | E |
| RF-24 | Debe | FL-03 §2 (comentario obligatorio, Outlook + Teams) | E |
| RF-25 | Debería | FL-03 §2 (recordatorio y escalamiento, `PLAZO_VALIDACION_DIAS`) | E |
| RF-26 | Debe | `puedeDeclarar` (pruebas), `PuedeDeclarar()`, FL-03 §1.3, CAAT C08 | I / E |
| RF-27 | Debería | FL-10 / FL-10b, alerta B03 | E |
| RF-28 | Debe | `proximaRevision` (pruebas CA-04), FL-02b, FL-05 | I / E |
| RF-29 | Debe | `proximaRevisionAccesos` (pruebas), FL-06 / FL-06b | I / E |
| RF-30 | Debería | `scrRevisiones` (lote), `RN_Campana` | E |
| RF-31 | Debe | `avisoCorrespondiente` (pruebas), FL-05 / FL-06 | I / E |
| RF-32 | Debe | `validarReclasificacion` (pruebas CA-06), FL-02 paso 3, FL-04 | I / E |
| RF-33 | Debe | FL-09 | E |
| RF-34 | Debe | `validarBaja` (pruebas CA-08), FL-08, CAAT C14 | I / E |
| RF-35 | Debe | Versionado, HistorialClasificacion, `RN_HistorialResumen` (DD-03) | I / E |
| RF-36 | Debe | `validarExcepcion` (pruebas CA-07), `scrExcepciones` | I / E |
| RF-37 | Debe | FL-07a | E |
| RF-38 | Debe | Lista Excepciones con permisos por elemento, FL-07b, Power BI página Excepciones | I / E |
| RF-39 | Debe | `CatalogoRAT`, combo RAT en paso 4, CAAT C15 | I / E / D (D-04) |
| RF-40 | Debe | Bandeja DPO (`Pantallas.md` §5) | E |
| RF-41 | Debería | FL-10 (aviso DPO) | E |
| RF-42 | Debe | `powerbi/` (medidas, RLS) | E / D (D-08) |
| RF-43 | Debe | Página *Informe CSI / NCG 454*, `Texto resumen NCG 454` | E |
| RF-44 | Debe | FL-16 + `EscribirInventario.ts` + plantilla Reservado (DD-07) | I / E |
| RF-45 | Debería | `ReferenciaCMDB`, FL-13 | E / D (D-05) |
| RF-46 | Debería | `purview/01` (mismos nombres y orden), `MAPEO_ETIQUETAS_PURVIEW`, `RN_EtiquetaPurview` | I / E |
| RF-47 | Podría | `Pantallas.md` §10 | E |
| RF-48 | Debe | `scrAdministracion` | E |
| RF-49 | Debe | Versionado (`scripts/03`), Historial, `purview/02` (auditoría) | I |
| RF-50 | Debería | FL-14, CAAT C09 | E |

## Reglas de negocio

| ID | Pruebas (`reglas.test.js`) | App | Flujo | CAAT |
|---|---|---|---|---|
| RN-01 | formato del ID | — | FL-01 §4 | C01, C13 |
| RN-02 | CA-01, datos sensibles | `NivelMinimo` | FL-02b | C05 |
| RN-03 | crítico | `EsCritico` | FL-02b | C16 |
| RN-04 | revisión anual/semestral | `MesesRevisionIntegral` | FL-02b, FL-05 | C06, C16 |
| RN-05 | revisión de accesos | — | FL-02b, FL-06 | C06 |
| RN-06 | sin clasificar | `NivelEfectivo` | FL-02b | — |
| RN-07 | agregación | — | FL-02b | — |
| RN-08 | terceros | `NivelMinimo` | FL-02b | C05 |
| RN-09 | bloqueantes A01–A12 | `AlertasBorrador` | FL-02b, FL-03 | C04 |
| RN-10 | CA-07 | `scrExcepciones` | FL-07 | C10 |
| RN-11 | método y certificado | `MetodoBajaPorNivel` | FL-08 | C14 |
| RN-12 | — | `PuedeDeclarar` | FL-09, FL-14 | C09 |
| RN-13 | alerta A10 | `MostrarContraparte` | FL-01 §6 | C03 |
| RN-14 | — | Administración | FL-09 | — |
| RN-15 | — | — | FL-13 (CI sin activo) | — |
| RN-16 | — | aviso en paso 4 | — | `scripts/06` (patrones RUT/correo) |

## Requerimientos no funcionales

| ID | Artefacto(s) | Estado |
|---|---|---|
| RNF-01 | `scripts/02` (sin uso compartido externo, etiqueta Reservado), `purview/01` | I |
| RNF-02 | Acceso condicional (manual de instalación §2), `ConditionalAccessPolicy AllowLimitedAccess` | I / E |
| RNF-03 | `scripts/05`, FL-01 §6 (DD-01), FL-02 paso 2, CAAT C02/C03 | I / E |
| RNF-04 | Cuenta de servicio en `solution.config.json`, `powerautomate/README.md` §1 | I / E |
| RNF-05 | `scripts/09` (DLP solo M365, nuevos conectores bloqueados) | I |
| RNF-06 | Versionado en `scripts/03`, auditoría unificada en `purview/02` | I |
| RNF-07 | HistorialClasificacion (escritura solo cuenta de servicio), retención 5 años `purview/02` | I |
| RNF-08 | FL-12 + `scripts/07` (restauración) | I / E |
| RNF-09 | 15 índices, vistas con filtro indexado (`scripts/03`), reglas de delegación (`Pantallas.md`) | I / E |
| RNF-10 | Colecciones de maestros en `OnStart`, `Concurrent` | E |
| RNF-11 | Monitoreo FL-12, CAAT C11, DD-02, D-14 | I / E |
| RNF-12 | Diseño adaptable, español, Teams/móvil | E |
| RNF-13 | Asistente de 5 pasos | E |
| RNF-14 | `scripts/09` (entornos), manual de instalación §8–9 | E / D (D-09) |
| RNF-15 | `docs/01` a `docs/06`, convenciones de nombres (`powerautomate/README.md`, prefijo `RN_`) | I |
| RNF-16 | Tenant corporativo, `purview/02` (retención del sitio) | I |
| RNF-17 | Lista Parametros; ningún valor de negocio en código (`npm run validar` verifica las claves) | I |

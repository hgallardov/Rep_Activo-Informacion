# Solución de Inventario y Clasificación de Activos de Información – Microsoft 365

Implementación de la especificación **ER[ZZ].GR_1.0(2026)** para Renta Nacional Compañía de Seguros Generales S.A. (RNSG) y Renta Nacional Compañía de Seguros de Vida S.A. (RNSV), sobre Microsoft 365 E3: SharePoint Online + Power Apps + Power Automate + Power BI + Entra ID + Purview (escenario A de licenciamiento).

## Contenido

| Carpeta | Qué hay |
|---|---|
| [`config/`](config) | **Fuente única de verdad**: catálogo de 61 campos + columnas técnicas (`catalogo-campos.json`), listas de soporte, 43 parámetros de negocio, configuración por ambiente y maestros semilla |
| [`scripts/`](scripts) | Aprovisionamiento idempotente en PowerShell 7 / PnP: grupos Entra ID (01), sitio endurecido (02), listas/columnas/índices/vistas (03), maestros (04), permisos por entidad y gerencia (05), validación previa de cargas (06), restauración (07), **CAAT de controles del inventario** (08), entornos y DLP de Power Platform (09) |
| [`purview/`](purview) | Etiquetas de sensibilidad alineadas con los 4 niveles, política de retención de 5 años y verificación de auditoría |
| [`powerautomate/`](powerautomate) | Especificación de construcción de los 16 flujos con expresiones exactas |
| [`powerapps/`](powerapps) | Fórmulas Power Fx (`App.Formulas.fx`, `App.OnStart.fx`), pantallas y Office Script de exportación |
| [`powerbi/`](powerbi) | Power Query, medidas DAX y seguridad por filas |
| [`templates/`](templates) | Plantilla Excel de carga masiva (53 columnas con listas desplegables) |
| [`tests/`](tests) | Especificación ejecutable de las reglas de negocio con 23 pruebas (CA-01, CA-04 a CA-08, RN-01 a RN-11) |
| [`tools/`](tools) | Generador de la plantilla y validador de configuración |
| [`docs/`](docs) | Diseño, instalación, administración, usuario, plan de pruebas y matriz de trazabilidad |

## Inicio rápido

```bash
npm test                              # reglas de negocio (23 pruebas)
npm run validar                       # restricciones de SharePoint y coherencia app/flujos/PowerShell
python3 tools/build_plantilla_carga.py   # regenera la plantilla Excel desde el catálogo
```
Despliegue: seguir [`docs/02_Manual_de_Instalacion.md`](docs/02_Manual_de_Instalacion.md).

## Decisiones de diseño relevantes
Ver [`docs/01_Diseno_de_la_Solucion.md`](docs/01_Diseno_de_la_Solucion.md) §4–5. En resumen: el alta se hace con la cuenta de servicio para que ningún activo sea visible fuera de su gerencia ni por un instante (CA-02); las columnas calculadas y de estado están protegidas por un control detectivo-correctivo; las revisiones no consumen permisos únicos; y se identificó la decisión **D-09** (capacidad de Dataverse para usar soluciones DEV/TEST/PROD con licencias E3).

**Clasificación del repositorio:** Uso Interno. No contiene datos del inventario. Los archivos generados en `logs/` (inventarios de grupos, papeles de trabajo CAAT, diferencias de restauración) pueden contener información **Reservada** y están excluidos de Git.

# Tablero SGSI – Inventario de Activos (Power BI)

Cubre RF-42, RF-43 y la sección 15.2 del ER. Archivos:

| Archivo | Contenido |
|---|---|
| `consultas.pq` | Consultas Power Query (M) sobre las listas SharePoint (conector *SharePoint Online List* v2.0) |
| `medidas.dax` | Medidas por página del tablero |
| `rls.dax` | Seguridad por filas equivalente a los permisos de SharePoint (CA-10) |

## Construcción (Power BI Desktop)
1. *Obtener datos → Consulta en blanco → Editor avanzado*: crear una consulta por cada bloque de `consultas.pq` con el mismo nombre (`pSitio`, `fnLista`, `Activos`, `Entidades`, `Gerencias`, `Excepciones`, `Revisiones`, `Alertas`, `Pertenencia`, `Calendario`). `Entidades` y `Gerencias` se usan como apoyo: desactivar *Cargar* si no se requieren como dimensión.
2. Relaciones: `Activos[IdActivo]` 1→* `Excepciones[IdActivo]`, `Revisiones[IdActivo]`, `Alertas[IdActivo]`; `Calendario[Fecha]` 1→* `Activos[RN_ProximaRevision]`. `Pertenencia` sin relaciones y oculta.
3. Crear la tabla `_Medidas` y pegar `medidas.dax`.
4. *Modelado → Administrar roles*: rol **Inventario** con los filtros de `rls.dax` sobre `Activos` y `Pertenencia`. Probar con *Ver como*.
5. Publicar en el área de trabajo **SGSI – Inventario (PROD)** (acceso: CISO como administrador; nadie más con rol de área de trabajo, para que RLS aplique a todos los consumidores). Compartir la aplicación de Power BI con todos los grupos `SGSI-INV-*` y asignarlos al rol *Inventario*.
6. Actualización programada diaria 06:00 con la cuenta de servicio (credencial OAuth2). Etiqueta de sensibilidad del informe y del modelo semántico: **Reservado** (se hereda a las exportaciones a Excel/PDF).

## Páginas (sección 15.2)
| Página | Visuales | Medidas |
|---|---|---|
| Resumen ejecutivo | Tarjetas; barras apiladas por entidad × nivel; anillo por estado | Activos (total), Activos críticos, % Clasificado, Sin clasificar (reportados como Confidencial), Activos compartidos |
| Cumplimiento | Matriz gerencia × indicador con formato condicional; tendencia mensual | % Con Dueño, % Validados por CISO, Revisiones integrales / de accesos vencidas, Activos con alertas bloqueantes, Críticos sin ID de riesgo |
| Datos personales (DPO) | Tarjetas; tabla de activos sin RAT o con transferencia | Activos con datos personales / sensibles, % Vinculados al RAT, Transferencias internacionales |
| Terceros | Barras por proveedor; mapa por país | Activos en terceros, en servicios externalizados significativos, Países de procesamiento |
| Excepciones | Tabla con semáforo de vencimiento | Excepciones vigentes / vencidas / por vencer 30d |
| Calidad de datos | Matriz gerencia × código de alerta (A01…B08) con detalle | Alertas (total), Alertas bloqueantes, Activos con alguna alerta |
| Informe CSI / NCG 454 | Página paginable por entidad (segmentación Entidad) con el texto narrativo | Texto resumen NCG 454, Índice de madurez del inventario |

## Escenario sin Power BI Pro (D-01 / D-08)
Si no se adquieren licencias Pro, la app Power Apps incluye los mismos contadores en *Inicio* y *Administración* (consultas delegables sobre columnas indexadas), y las vistas de SharePoint de `scripts/03` sirven de reportería operativa. El informe anual al CSI se genera exportando (FL-16) y con el papel de trabajo de `scripts/08-Test-InventarioControles.ps1`.

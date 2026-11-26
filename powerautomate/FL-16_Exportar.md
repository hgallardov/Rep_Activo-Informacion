# RN-INV FL-16 Exportar inventario a Excel (RF-44)

| | |
|---|---|
| Disparador | Power Apps (V2), entrada `filtrosJson` |
| Conexiones | **SharePoint y OneDrive: del usuario que ejecuta** (*Run only users → Provided by run-only user*). Excel Online: del usuario. Es el único flujo que no usa la cuenta de servicio: así la exportación respeta exactamente los permisos del usuario. |
| Office Script | `powerapps/officescripts/EscribirInventario.ts` |

1. SharePoint **Obtener elementos** `Activos` con consulta OData construida desde los filtros (columnas indexadas: `RN_Gerencia/Id`, `RN_Estado`, `RN_NivelEfectivo`), paginación 5.000. Como corre con la identidad del usuario, solo devuelve los elementos que él puede ver.
2. **Seleccionar** las columnas exportables (no se exportan columnas técnicas: `RN_ClavePermisos`, `RN_InstantaneaClasif`, `RN_HistorialResumen`).
3. OneDrive for Business **Copiar archivo**: `Plantillas/Plantilla_Exportacion_Reservado.xlsx` (biblioteca `CargaMasiva`, archivo con **etiqueta de sensibilidad Reservado aplicada manualmente**; la etiqueta se conserva al copiar) → `/Exportaciones SGSI/Inventario_<aaaaMMdd_HHmm>.xlsx` en el OneDrive del usuario.
4. Excel Online (Business) **Ejecutar script** `EscribirInventario` con `filas = string(body('Seleccionar'))` (inserción masiva en una sola llamada).
5. Responder a Power Apps `{ ok: true, url: <webUrl del archivo> }`. Registrar en `HistorialClasificacion` un evento informativo *Exportación* con el usuario y el número de filas (trazabilidad del uso del inventario, NG 6.3).

> Con licencias E5 / E5 Compliance, el paso 3 puede reemplazarse por la acción de etiquetado de archivos de SharePoint o por una directiva de etiquetado predeterminado de la biblioteca.

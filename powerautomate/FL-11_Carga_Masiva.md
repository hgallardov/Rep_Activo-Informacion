# RN-INV FL-11 Carga masiva desde la plantilla Excel

| | |
|---|---|
| Requerimientos | RF-14, CA-09, RN-16 |
| Disparador | SharePoint **Cuando se crea un archivo (solo propiedades)** – biblioteca `CargaMasiva`, carpeta `/Entrada` |
| Entrada | `templates/Plantilla_Carga_Inventario_Activos.xlsx` (tabla `tblActivos`), validada antes con `scripts/06-Test-PlantillaCarga.ps1` |
| Mapeo de columnas | `powerautomate/mapeo-plantilla-carga.json` (generado junto con la plantilla) |

## Pasos
1. `Cargador = triggerOutputs()?['body/Author/Email']`. Solo miembros de CISO pueden dejar archivos en `Entrada` (permisos de la biblioteca, `scripts/05`); se verifica igualmente.
2. Excel Online (Business) **Enumerar filas presentes en una tabla** – tabla `tblActivos`, paginación activada (umbral 5.000), *Formato de fecha y hora* = ISO 8601.
3. Filtrar filas vacías: `not(empty(item()?['F02 Nombre del activo']))`.
4. Cargar en memoria los maestros (Entidades, Gerencias, Procesos, Cargos, Terceros) con *Obtener elementos* y construir diccionarios Title → Id con *Seleccionar* (mismo patrón que *Leer parámetros*).
5. **Por cada fila** (concurrencia 1 para preservar el orden del correlativo; ~2 s por fila → 500 filas ≈ 20 min):
   * Resolver búsquedas por Title (`outputs('DicGerencias')?[item()?['F08 Gerencia responsable']]`); si alguna no existe → error de fila.
   * Validar elecciones contra el catálogo (mismo conjunto de `opciones`), fechas y reglas de integridad mínima (A04, A09, A10, A12 de `reglas.js`). Los faltantes no críticos se aceptan: el activo queda en **Borrador** con sus alertas, para que el Dueño complete y declare.
   * Si la fila es válida: ejecutar **FL-01** como secundario (`origen = Carga masiva`, `invocadorCarga = Cargador`) con los campos del paso 1 y luego **Actualizar elemento** con el resto de columnas mapeadas (cuenta de servicio) y `FL-02b`.
   * Agregar a la matriz `vReporte`: `{Fila, Resultado: "Creado"|"Error", ID, Detalle}`.
6. **Reporte de errores por fila (CA-09):** *Crear tabla CSV* desde `vReporte` → crear archivo `CargaMasiva/Reportes/<nombre>_reporte_<aaaaMMdd_HHmm>.csv`; mover el archivo original a `/Procesados`. Correo al cargador con totales (creados / errores) y vínculo al reporte.
7. Historial: un evento *Carga masiva* por activo creado (lo hace FL-01) y un resumen en el correo.

## Notas
* Archivos con más de 5.000 filas: dividir por gerencia (límite de paginación del conector Excel).
* El archivo de carga es Reservado: la biblioteca `CargaMasiva` hereda la etiqueta del sitio y solo la ve el CISO; los archivos de `Procesados` se eliminan a los 90 días (la evidencia de la carga queda en el historial y en el reporte).

/**
 * Office Script "EscribirInventario" – lo ejecuta FL-16 (Excel Online Business → Ejecutar script).
 * Escribe en la hoja "Inventario" de la plantilla etiquetada como Reservado las filas recibidas en JSON
 * (arreglo de objetos con las mismas claves para todas las filas) en una sola operación.
 */
function main(workbook: ExcelScript.Workbook, filas: string): string {
  const datos: Record<string, string | number | boolean | null>[] = JSON.parse(filas);
  let hoja = workbook.getWorksheet("Inventario");
  if (!hoja) {
    hoja = workbook.addWorksheet("Inventario");
  }
  hoja.getUsedRange()?.clear();
  if (datos.length === 0) {
    hoja.getRange("A1").setValue("Sin registros para los filtros indicados");
    return "0";
  }
  const columnas = Object.keys(datos[0]);
  const matriz: (string | number | boolean)[][] = [columnas];
  for (const fila of datos) {
    matriz.push(columnas.map((c) => {
      const v = fila[c];
      if (v === null || v === undefined) return "";
      if (typeof v === "object") return JSON.stringify(v);
      return v;
    }));
  }
  const rango = hoja.getRangeByIndexes(0, 0, matriz.length, columnas.length);
  rango.setValues(matriz);
  const tabla = hoja.addTable(rango, true);
  tabla.setName("tblInventario");
  tabla.getHeaderRowRange().getFormat().getFont().setBold(true);
  hoja.getRange("A1").getEntireRow().getFormat().setRowHeight(30);
  hoja.getRangeByIndexes(0, 0, matriz.length, columnas.length).getFormat().autofitColumns();
  hoja.freezePanes.freezeRows(1);
  // Pie de clasificación visible además de la etiqueta de Purview
  const pie = hoja.getRangeByIndexes(matriz.length + 1, 0, 1, 1);
  pie.setValue("CLASIFICACIÓN: RESERVADO – Inventario de Activos de Información (Norma de Gestión 4.3). Prohibida su divulgación a terceros.");
  pie.getFormat().getFont().setBold(true);
  pie.getFormat().getFont().setColor("#C00000");
  return String(datos.length);
}

#!/usr/bin/env python3
"""
Genera templates/Plantilla_Carga_Inventario_Activos.xlsx a partir de config/catalogo-campos.json.

La plantilla la usan los Dueños/Delegados para la carga inicial (RF-14) y la procesa el flujo FL-11
(tabla Excel 'tblActivos'). Incluye listas desplegables para todas las columnas de elección, validación de
fechas, hoja de instrucciones y hoja de maestros que el CISO completa con los valores vigentes.

Uso:  python3 tools/build_plantilla_carga.py
"""
import json
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from openpyxl.workbook.defined_name import DefinedName
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.table import Table, TableStyleInfo

RAIZ = Path(__file__).resolve().parent.parent
catalogo = json.loads((RAIZ / "config/catalogo-campos.json").read_text(encoding="utf-8"))

# Campos que escribe el flujo pero que se aceptan en la migración inicial (historia previa a la herramienta)
MIGRACION = {"RN_FechaAlta", "RN_FechaUltimaRevision", "RN_ResponsableUltimaRevision", "RN_FechaRevisionAccesos"}
# Columnas técnicas que no se cargan
EXCLUIR = {"Title"}

campos = [
    c for c in catalogo["campos"]
    if c["interno"] not in EXCLUIR
    and not c["codigo"].startswith("T")
    and (c.get("escribe") != "flujo" or c["interno"] in MIGRACION)
]
MAESTROS = {"Entidades": "lstEntidades", "Gerencias": "lstGerencias", "Procesos": "lstProcesos", "Cargos": "lstCargos", "Terceros": "lstTerceros"}

AZUL = PatternFill("solid", fgColor="1F3864")
GRIS = PatternFill("solid", fgColor="D9E1F2")
AMAR = PatternFill("solid", fgColor="FFF2CC")
blanco = Font(color="FFFFFF", bold=True)

wb = Workbook()

# ---------------- Instrucciones ----------------
ws = wb.active
ws.title = "Instrucciones"
ws["A1"] = "Plantilla de carga – Inventario y Clasificación de Activos de Información (RNSG / RNSV)"
ws["A1"].font = Font(bold=True, size=14, color="1F3864")
ws["A2"] = "Clasificación de este archivo: RESERVADO (el inventario es un activo Reservado – Norma de Gestión 4.3)."
ws["A2"].font = Font(bold=True, color="C00000")
instr = [
    "1. Complete una fila por activo en la hoja 'Activos', dentro de la tabla tblActivos (no cambie los encabezados ni el nombre de la tabla).",
    "2. Las columnas con lista desplegable solo aceptan los valores indicados. Entidad, Gerencia, Proceso, Cargos y Terceros deben coincidir EXACTAMENTE con los maestros (hoja 'Maestros').",
    "3. No ingrese el ID del activo: lo genera el sistema con formato AI-[ENTIDAD]-[GERENCIA]-[correlativo] (RF-07).",
    "4. NO registre datos personales de titulares, credenciales ni configuraciones sensibles: solo describa qué tipo de datos existen y dónde (RN-16).",
    "5. Activos compartidos por ambas compañías: Entidad = 'Ambas', con la gerencia del Dueño principal y la gerencia contraparte (RF-08, RN-13).",
    "6. Si el activo contiene datos personales, el nivel mínimo es Reservado; con datos sensibles, Confidencial (RN-02). Confidencial y Reservado exigen cargos autorizados (RF-21).",
    "7. Fechas en formato dd-mm-aaaa. Las columnas marcadas (migración) solo se usan en la carga inicial para conservar la historia previa.",
    "8. Antes de enviar, el CISO puede validar el archivo con scripts/06-Test-PlantillaCarga.ps1, que entrega un reporte de errores por fila.",
    "9. Para cargar: dejar el archivo en la biblioteca 'CargaMasiva/Entrada' del sitio SGSI – Inventario de Activos. El flujo FL-11 crea los activos válidos en estado Borrador y deja el reporte en 'CargaMasiva/Reportes'.",
    "10. Los activos cargados quedan en Borrador: el Dueño debe revisarlos y declararlos desde la aplicación para iniciar la validación CISO / DPO.",
]
for i, t in enumerate(instr, start=4):
    ws.cell(row=i, column=1, value=t).alignment = Alignment(wrap_text=True)
ws.column_dimensions["A"].width = 150
fila = len(instr) + 6
ws.cell(row=fila, column=1, value="Diccionario de columnas").font = Font(bold=True, size=12)
cab = ["Código", "Columna", "Origen", "Obligatoriedad", "Condición / nota"]
for j, h in enumerate(cab, start=1):
    c = ws.cell(row=fila + 1, column=j, value=h)
    c.fill, c.font = AZUL, blanco
for k, cpo in enumerate(campos, start=fila + 2):
    ws.cell(row=k, column=1, value=cpo["codigo"])
    ws.cell(row=k, column=2, value=cpo["nombre"])
    ws.cell(row=k, column=3, value={"NI": "Normativa interna", "EI": "Estándar internacional", "TEC": "Solución", "CALC": "Cálculo", "VAL": "Validación"}[cpo["origen"]])
    ws.cell(row=k, column=4, value=cpo.get("requerido", ""))
    ws.cell(row=k, column=5, value=cpo.get("condicion", cpo.get("nota", "")))
for col, w in zip("BCDE", (55, 22, 16, 90)):
    ws.column_dimensions[col].width = w if col != "A" else 150

# ---------------- Listas (valores de elección) ----------------
wl = wb.create_sheet("Listas")
col = 1
rangos = {}
for cpo in campos:
    if cpo["tipo"] in ("Choice", "MultiChoice") and cpo.get("opciones"):
        wl.cell(row=1, column=col, value=cpo["interno"]).font = Font(bold=True)
        for i, op in enumerate(cpo["opciones"], start=2):
            wl.cell(row=i, column=col, value=op)
        letra = get_column_letter(col)
        nombre = f"lst_{cpo['interno']}"
        wb.defined_names[nombre] = DefinedName(nombre, attr_text=f"Listas!${letra}$2:${letra}${len(cpo['opciones']) + 1}")
        rangos[cpo["interno"]] = nombre
        col += 1
wl.sheet_state = "hidden"

# ---------------- Maestros (los completa el CISO con los valores vigentes) ----------------
wm = wb.create_sheet("Maestros")
wm["A1"] = "Valores vigentes de los maestros. El CISO los actualiza exportando las listas del sitio antes de distribuir la plantilla."
wm["A1"].font = Font(italic=True)
ejemplos = {
    "Entidades": ["Seguros Generales", "Seguros de Vida", "Ambas"],
    "Gerencias": [l.split(";")[0] for l in (RAIZ / "config/maestros/gerencias.csv").read_text(encoding="utf-8").splitlines()[1:]],
    "Procesos": [l.split(";")[0] for l in (RAIZ / "config/maestros/procesos.csv").read_text(encoding="utf-8").splitlines()[1:]],
    "Cargos": [l.split(";")[0] for l in (RAIZ / "config/maestros/cargos.csv").read_text(encoding="utf-8").splitlines()[1:]],
    "Terceros": [l.split(";")[0] for l in (RAIZ / "config/maestros/terceros.csv").read_text(encoding="utf-8").splitlines()[1:]],
}
for j, (m, vals) in enumerate(ejemplos.items(), start=1):
    c = wm.cell(row=2, column=j, value=m)
    c.fill, c.font = AZUL, blanco
    for i, v in enumerate(vals, start=3):
        wm.cell(row=i, column=j, value=v)
    letra = get_column_letter(j)
    wb.defined_names[MAESTROS[m]] = DefinedName(MAESTROS[m], attr_text=f"Maestros!${letra}$3:${letra}$1000")
    wm.column_dimensions[letra].width = 48

# ---------------- Activos ----------------
wa = wb.create_sheet("Activos", 1)
encabezados = []
for cpo in campos:
    sufijo = " (migración)" if cpo["interno"] in MIGRACION else ""
    encabezados.append(f"{cpo['codigo']} {cpo['nombre']}{sufijo}")
# Encabezados únicos y sin caracteres conflictivos para el conector Excel de Power Automate
encabezados = [h.replace("/", "-").replace("[", "(").replace("]", ")") for h in encabezados]
assert len(set(encabezados)) == len(encabezados)
for j, h in enumerate(encabezados, start=1):
    c = wa.cell(row=1, column=j, value=h)
    cpo = campos[j - 1]
    c.font = Font(bold=True, color="FFFFFF" if cpo.get("requerido") == "Obligatorio" else "000000")
    c.fill = AZUL if cpo.get("requerido") == "Obligatorio" else (GRIS if cpo.get("requerido") != "Condicional" else AMAR)
    c.alignment = Alignment(wrap_text=True, vertical="center")
    wa.column_dimensions[get_column_letter(j)].width = 28
wa.row_dimensions[1].height = 60
FILAS = 2000
ultima = get_column_letter(len(encabezados))
tabla = Table(displayName="tblActivos", ref=f"A1:{ultima}{FILAS + 1}")
tabla.tableStyleInfo = TableStyleInfo(name="TableStyleLight9", showRowStripes=True)
wa.add_table(tabla)
wa.freeze_panes = "C2"

for j, cpo in enumerate(campos, start=1):
    letra = get_column_letter(j)
    rng = f"{letra}2:{letra}{FILAS + 1}"
    dv = None
    if cpo["tipo"] == "Choice" and cpo["interno"] in rangos:
        dv = DataValidation(type="list", formula1=f"={rangos[cpo['interno']]}", allow_blank=True,
                            errorTitle="Valor no permitido", error="Seleccione un valor de la lista.")
    elif cpo["tipo"] == "MultiChoice":
        dv = DataValidation(type="custom", formula1="TRUE", allow_blank=True, showInputMessage=True,
                            promptTitle="Selección múltiple", prompt="Separe los valores con ';'. Valores en hoja Listas (" + cpo["interno"] + ").")
    elif cpo["tipo"] == "Lookup":
        dv = DataValidation(type="list", formula1=f"={MAESTROS[cpo['lookupLista']]}", allow_blank=True,
                            errorTitle="No existe en el maestro", error=f"Seleccione un valor del maestro {cpo['lookupLista']}.")
    elif cpo["tipo"] == "DateTime":
        dv = DataValidation(type="date", operator="greaterThan", formula1="DATE(2000,1,1)", allow_blank=True,
                            errorTitle="Fecha inválida", error="Ingrese una fecha dd-mm-aaaa.")
        for r in range(2, FILAS + 2):
            wa.cell(row=r, column=j).number_format = "DD-MM-YYYY"
    if dv is not None:
        if cpo.get("condicion"):
            dv.showInputMessage = True
            dv.promptTitle = cpo["codigo"]
            dv.prompt = cpo["condicion"][:250]
        wa.add_data_validation(dv)
        dv.add(rng)

# Mapeo encabezado → columna interna para FL-11 (hoja oculta, también exportado a JSON)
wmap = wb.create_sheet("Mapeo")
wmap.append(["Encabezado", "ColumnaInterna", "Tipo", "ListaBusqueda"])
mapeo = []
for h, cpo in zip(encabezados, campos):
    fila_m = [h, cpo["interno"], cpo["tipo"], cpo.get("lookupLista", "")]
    wmap.append(fila_m)
    mapeo.append(dict(zip(["encabezado", "interno", "tipo", "lookupLista"], fila_m)))
wmap.sheet_state = "hidden"

wb.properties.title = "Plantilla de carga – Inventario de Activos"
wb.properties.subject = "Clasificación: Reservado"
wb.properties.keywords = "SGSI; Inventario; Reservado"

salida = RAIZ / "templates/Plantilla_Carga_Inventario_Activos.xlsx"
salida.parent.mkdir(exist_ok=True)
wb.save(salida)
(RAIZ / "powerautomate/mapeo-plantilla-carga.json").write_text(json.dumps({"tabla": "tblActivos", "columnas": mapeo}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Generado {salida.relative_to(RAIZ)} con {len(campos)} columnas y {FILAS} filas habilitadas")

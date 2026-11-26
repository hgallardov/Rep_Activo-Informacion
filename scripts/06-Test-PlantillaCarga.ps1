#Requires -Version 7.2
<#
.SYNOPSIS
  Validación previa (fuera de línea) de la plantilla de carga masiva antes de entregarla a FL-11 (RF-14, CA-09).
.DESCRIPTION
  Lee la tabla tblActivos de la plantilla, valida cada fila contra:
   - valores permitidos de las columnas de elección (config/catalogo-campos.json);
   - existencia en los maestros (CSV de config/maestros o exportación del sitio con -ConectarSitio);
   - reglas de negocio bloqueantes (RN-02, RN-09, RF-08, RF-21) del módulo RNInventario.Reglas;
   - ausencia de patrones de datos personales de titulares (RUT, correo) en textos libres (RN-16);
   - duplicados por Entidad + Gerencia + Nombre.
  Genera <archivo>_reporte.xlsx con una fila por error/advertencia y el estado por fila (Válida / Con errores).
  Requiere el módulo ImportExcel (Install-Module ImportExcel -Scope CurrentUser).
.PARAMETER Archivo        Ruta del .xlsx a validar.
.PARAMETER ConectarSitio  Lee los maestros vigentes desde el sitio en vez de los CSV.
.EXAMPLE
  ./06-Test-PlantillaCarga.ps1 -Archivo ./carga_GTI.xlsx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$Archivo,
    [ValidateSet('DEV', 'TEST', 'PROD')][string]$Ambiente = 'DEV',
    [switch]$ConectarSitio
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/RNInventario.Comun.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/RNInventario.Reglas.psm1') -Force
Initialize-RNLog -NombreScript '06-Test-PlantillaCarga' | Out-Null
Assert-RNModulo -Nombre 'ImportExcel' -VersionMinima '7.8'
$cfg = Get-RNConfiguracion -Ambiente $Ambiente

$mapeo = (Get-Content (Join-Path (Get-RNRutaRepositorio) 'powerautomate/mapeo-plantilla-carga.json') -Raw | ConvertFrom-Json).columnas
$campos = @{}; foreach ($c in $cfg.Catalogo.campos) { $campos[$c.interno] = $c }

# Maestros
$maestros = @{}
if ($ConectarSitio) {
    Connect-RNSitio -Config $cfg
    foreach ($m in 'Entidades', 'Gerencias', 'Procesos', 'Cargos', 'Terceros') { $maestros[$m] = @(Get-PnPListItem -List $m -PageSize 2000 -Fields Title | ForEach-Object { $_['Title'] }) }
} else {
    $arch = @{ Entidades = 'entidades.csv'; Gerencias = 'gerencias.csv'; Procesos = 'procesos.csv'; Cargos = 'cargos.csv'; Terceros = 'terceros.csv' }
    foreach ($m in $arch.Keys) { $maestros[$m] = @(Import-Csv (Join-Path $cfg.DirMaestros $arch[$m]) -Delimiter ';' -Encoding utf8 | ForEach-Object Title) }
}

$filas = Import-Excel -Path $Archivo -WorksheetName 'Activos' -DataOnly
$hallazgos = [System.Collections.Generic.List[object]]::new()
$claves = @{}
$patronRUT = '\b\d{1,2}\.?\d{3}\.?\d{3}-[\dkK]\b'
$patronCorreo = '[\w.+-]+@[\w-]+\.[\w.]+'
$nFila = 1

foreach ($f in $filas) {
    $nFila++
    if (-not ($f.PSObject.Properties.Value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) { continue }  # fila vacía
    $reg = { param($nivel, $col, $msg) $hallazgos.Add([pscustomobject]@{ Fila = $nFila; Nivel = $nivel; Columna = $col; Detalle = $msg }) }
    $a = @{}
    foreach ($m in $mapeo) {
        $v = $f.($m.encabezado)
        $a[$m.interno] = $v
        if ([string]::IsNullOrWhiteSpace([string]$v)) { continue }
        $def = $campos[$m.interno]
        switch ($m.tipo) {
            'Choice' { if ($def.opciones -notcontains [string]$v) { & $reg 'ERROR' $m.encabezado "Valor '$v' no permitido" } }
            'MultiChoice' { foreach ($x in ([string]$v -split ';' | ForEach-Object Trim)) { if ($def.opciones -notcontains $x) { & $reg 'ERROR' $m.encabezado "Valor '$x' no permitido" } } }
            'Lookup' { if ($maestros[$m.lookupLista] -notcontains [string]$v) { & $reg 'ERROR' $m.encabezado "'$v' no existe en el maestro $($m.lookupLista)" } }
            'DateTime' { if ($v -isnot [datetime]) { try { $a[$m.interno] = [datetime]::ParseExact([string]$v, 'dd-MM-yyyy', $null) } catch { & $reg 'ERROR' $m.encabezado "Fecha '$v' inválida (dd-mm-aaaa)" } } }
        }
        if ($m.tipo -in 'Text', 'Note' -and ([string]$v -match $patronRUT -or [string]$v -match $patronCorreo)) {
            & $reg 'ADVERTENCIA' $m.encabezado 'Posible dato personal de titular (RUT o correo) en texto libre: el inventario solo admite metadatos (RN-16)'
        }
    }
    # Normalización a los nombres que usa el módulo de reglas
    $activo = [pscustomobject]@{
        Entidad = $a.RN_Entidad; Nombre = $a.RN_Nombre; Descripcion = $a.RN_Descripcion; Categoria = $a.RN_Categoria; Proceso = $a.RN_Proceso
        Gerencia = $a.RN_Gerencia; GerenciaContraparte = $a.RN_GerenciaContraparte; DuenoCargo = $a.RN_DuenoCargo; Formato = $a.RN_Formato
        Ubicacion = $a.RN_Ubicacion; TipoAlojamiento = $a.RN_TipoAlojamiento; Pais = $a.RN_PaisProcesamiento
        Confidencialidad = $a.RN_Confidencialidad; Integridad = $a.RN_Integridad; Disponibilidad = $a.RN_Disponibilidad
        ConfiadaTerceros = $a.RN_ConfiadaTerceros; NivelAcordadoTerceros = $a.RN_NivelAcordadoTerceros; Nivel = $a.RN_Nivel
        DatosPersonales = $a.RN_DatosPersonales; DatosSensibles = $a.RN_DatosSensibles; IdRAT = $a.RN_IdRAT
        TransferenciaInternacional = $a.RN_TransferenciaInternacional; Tercero = $a.RN_Tercero; ReglasUso = $a.RN_ReglasUso
        CargosAutorizados = $a.RN_CargosAutorizados; TercerosAutorizados = $a.RN_TercerosAutorizados
        PeriodoRetencion = $a.RN_PeriodoRetencion; FundamentoRetencion = $a.RN_FundamentoRetencion; IdCMDB = $a.RN_IdCMDB; IdRiesgo = $a.RN_IdRiesgo
        FechaAlta = $a.RN_FechaAlta; FechaUltimaRevision = $a.RN_FechaUltimaRevision; FechaRevisionAccesos = $a.RN_FechaRevisionAccesos
    }
    foreach ($al in (Get-RNAlertas -A $activo)) {
        # En la carga se admiten borradores incompletos: las bloqueantes se informan como ADVERTENCIA salvo las de integridad mínima
        $critica = $al.Codigo -in 'A04', 'A09', 'A10', 'A12'
        & $reg ($(if ($critica) { 'ERROR' } else { 'ADVERTENCIA' })) $al.Codigo $al.Mensaje
    }
    if ([string]::IsNullOrWhiteSpace($activo.Gerencia)) { & $reg 'ERROR' 'F08' 'Gerencia obligatoria para generar el ID' }
    $clave = "$($activo.Entidad)|$($activo.Gerencia)|$($activo.Nombre)".ToLowerInvariant()
    if ($claves.ContainsKey($clave)) { & $reg 'ERROR' 'F02' "Duplicado de la fila $($claves[$clave]) (misma entidad, gerencia y nombre)" } else { $claves[$clave] = $nFila }
}

$porFila = $hallazgos | Group-Object Fila
$conErrores = @($porFila | Where-Object { $_.Group.Nivel -contains 'ERROR' }).Count
$total = $claves.Count
$resumen = [pscustomobject]@{ Archivo = (Split-Path $Archivo -Leaf); FilasConDatos = $total; FilasConErrores = $conErrores; FilasValidas = $total - $conErrores
    Advertencias = @($hallazgos | Where-Object Nivel -eq 'ADVERTENCIA').Count; Fecha = (Get-Date).ToString('yyyy-MM-dd HH:mm') }

$salida = [IO.Path]::ChangeExtension($Archivo, $null).TrimEnd('.') + '_reporte.xlsx'
$resumen | Export-Excel -Path $salida -WorksheetName 'Resumen' -AutoSize -ClearSheet
$hallazgos | Export-Excel -Path $salida -WorksheetName 'Hallazgos' -AutoSize -AutoFilter -FreezeTopRow -ClearSheet
Write-RNLog ("Filas: {0} | válidas: {1} | con errores: {2} | advertencias: {3}" -f $total, $resumen.FilasValidas, $conErrores, $resumen.Advertencias) $(if ($conErrores) { 'ADVERTENCIA' } else { 'OK' })
Write-RNLog "Reporte: $salida"

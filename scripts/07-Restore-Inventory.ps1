#Requires -Version 7.2
<#
.SYNOPSIS
  Procedimiento de restauración del inventario desde los respaldos semanales de FL-12 (RNF-08).
.DESCRIPTION
  FL-12 deja cada semana en la biblioteca Respaldos/<aaaa-MM-dd>/ un archivo <Lista>.json por lista
  (arreglo de elementos con columnas internas; búsquedas como {Id,Value}; personas como correo).
  Modos:
    Comparar          Informa diferencias entre el respaldo y la lista actual (sin cambios). Úselo siempre primero.
    RestaurarCampos   Devuelve a los valores del respaldo los elementos existentes (por ID del activo = Title) que difieren.
    RecrearFaltantes  Crea los elementos del respaldo que ya no existen y les reaplica permisos por entidad y gerencia.
  Todas las restauraciones quedan registradas en HistorialClasificacion (tipo 'Cambio de estado', motivo 'Restauración').
  Ejecutar con una cuenta del grupo SGSI-INV-CISO o la cuenta de servicio, con autorización documentada del CISO.
.EXAMPLE
  ./07-Restore-Inventory.ps1 -Ambiente PROD -Fecha 2026-11-22 -Lista Activos -Modo Comparar
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('DEV', 'TEST', 'PROD')][string]$Ambiente = 'DEV',
    [Parameter(Mandatory)][ValidatePattern('^\d{4}-\d{2}-\d{2}$')][string]$Fecha,
    [ValidateSet('Activos', 'Excepciones', 'Cargos', 'Gerencias', 'Procesos', 'Terceros', 'Parametros')][string]$Lista = 'Activos',
    [ValidateSet('Comparar', 'RestaurarCampos', 'RecrearFaltantes')][string]$Modo = 'Comparar',
    [string]$Autorizacion = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/RNInventario.Comun.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/RNInventario.Permisos.psm1') -Force
Initialize-RNLog -NombreScript '07-Restore-Inventory' | Out-Null
$cfg = Get-RNConfiguracion -Ambiente $Ambiente
if ($Modo -ne 'Comparar' -and [string]::IsNullOrWhiteSpace($Autorizacion)) { throw 'Indique -Autorizacion (N° de ticket o acta del CISO) para restaurar.' }
Connect-RNSitio -Config $cfg

$tmp = Join-Path ([IO.Path]::GetTempPath()) "rn-restore-$Fecha"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Get-PnPFile -Url "Respaldos/$Fecha/$Lista.json" -Path $tmp -FileName "$Lista.json" -AsFile -Force
$respaldo = Get-Content (Join-Path $tmp "$Lista.json") -Raw -Encoding utf8 | ConvertFrom-Json
Write-RNLog "Respaldo $Fecha/$Lista.json: $($respaldo.Count) elementos"

# Columnas restaurables: las editables por usuario y por flujo (no las del sistema)
$excluir = 'ID', 'Id', 'Created', 'Modified', 'Author', 'Editor', 'GUID', '_UIVersionString', 'Attachments', 'ContentTypeId', '@odata.etag'
$actual = @{}
Get-PnPListItem -List $Lista -PageSize 2000 | ForEach-Object { $actual[$_['Title']] = $_ }

function ConvertTo-RNValor { param($v)
    if ($null -eq $v) { return $null }
    if ($v -is [pscustomobject] -and $v.PSObject.Properties['Id']) { return [int]$v.Id }      # búsqueda
    if ($v -is [pscustomobject] -and $v.PSObject.Properties['Email']) { return $v.Email }     # persona
    if ($v -is [array]) { return @($v | ForEach-Object { ConvertTo-RNValor $_ }) }
    $v }

$diferencias = [System.Collections.Generic.List[object]]::new()
foreach ($r in $respaldo) {
    $id = $r.Title
    if (-not $actual.ContainsKey($id)) { $diferencias.Add([pscustomobject]@{ ID = $id; Tipo = 'Faltante'; Columna = ''; Respaldo = ''; Actual = '' }); continue }
    $it = $actual[$id]
    foreach ($p in $r.PSObject.Properties | Where-Object { $_.Name -notin $excluir }) {
        $vr = ConvertTo-RNValor $p.Value
        $va = $it[$p.Name]
        if ($va -is [Microsoft.SharePoint.Client.FieldLookupValue]) { $va = $va.LookupId }
        if ($va -is [Microsoft.SharePoint.Client.FieldUserValue]) { $va = $va.Email }
        if ("$vr" -ne "$va") { $diferencias.Add([pscustomobject]@{ ID = $id; Tipo = 'Distinto'; Columna = $p.Name; Respaldo = "$vr"; Actual = "$va" }) }
    }
}
$reporte = Join-Path (Get-RNRutaRepositorio) "logs/restauracion-$Lista-$Fecha-$Modo.csv"
$diferencias | Export-Csv $reporte -Delimiter ';' -Encoding utf8 -NoTypeInformation
Write-RNLog "Diferencias: $($diferencias.Count) (faltantes: $(@($diferencias | Where-Object Tipo -eq 'Faltante').Count)). Detalle: $reporte"
if ($Modo -eq 'Comparar') { Write-RNLog 'Modo Comparar: sin cambios.' 'OK'; return }

$historial = { param($idTexto, $detalle)
    Add-PnPListItem -List 'HistorialClasificacion' -Values @{ Title = "Restauración $idTexto"; RN_IdActivoTexto = $idTexto; RN_TipoEvento = 'Cambio de estado'
        RN_Motivo = "Restauración desde respaldo $Fecha. Autorización: $Autorizacion. $detalle"; RN_Usuario = (Get-PnPWeb -Includes CurrentUser).CurrentUser.Email
        RN_FechaEvento = (Get-Date) } | Out-Null }

if ($Modo -eq 'RestaurarCampos') {
    foreach ($g in ($diferencias | Where-Object Tipo -eq 'Distinto' | Group-Object ID)) {
        $r = $respaldo | Where-Object Title -eq $g.Name
        $valores = @{}; foreach ($d in $g.Group) { $valores[$d.Columna] = ConvertTo-RNValor $r.($d.Columna) }
        if ($PSCmdlet.ShouldProcess($g.Name, "Restaurar $($valores.Count) columnas")) {
            Set-PnPListItem -List $Lista -Identity $actual[$g.Name].Id -Values $valores -UpdateType SystemUpdate | Out-Null
            if ($Lista -eq 'Activos') { & $historial $g.Name ("Columnas: " + ($valores.Keys -join ', ')) }
            Write-RNLog "  restaurado $($g.Name)" 'OK'
        }
    }
}
if ($Modo -eq 'RecrearFaltantes') {
    foreach ($d in $diferencias | Where-Object Tipo -eq 'Faltante') {
        $r = $respaldo | Where-Object Title -eq $d.ID
        $valores = @{}; foreach ($p in $r.PSObject.Properties | Where-Object { $_.Name -notin $excluir }) { $valores[$p.Name] = ConvertTo-RNValor $p.Value }
        if ($PSCmdlet.ShouldProcess($d.ID, 'Recrear elemento')) {
            $n = Add-PnPListItem -List $Lista -Values $valores
            if ($Lista -eq 'Activos') { Set-RNPermisosActivo -IdElemento $n.Id; & $historial $d.ID 'Elemento recreado' }
            Write-RNLog "  recreado $($d.ID) (nuevo Id $($n.Id))" 'OK'
        }
    }
}
Write-RNLog 'Fin de la restauración. Ejecute 08-Test-InventarioControles.ps1 para verificar permisos e integridad.' 'OK'

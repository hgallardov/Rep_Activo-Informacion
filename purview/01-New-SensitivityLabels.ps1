#Requires -Version 7.2
<#
.SYNOPSIS
  Crea las etiquetas de sensibilidad alineadas con los 4 niveles de la Norma de Clasificación (RF-46, NC 4.6)
  y la política que las publica. Mismos nombres y mismo orden (prioridad) que en la solución.
.DESCRIPTION
  Orden de Purview: la prioridad 0 es la menos sensible. Resultado:
     0 Pública · 1 Uso Interno · 2 Reservado · 3 Confidencial
  - Reservado y Confidencial: marca de agua/encabezado; Confidencial además cifrado (solo usuarios de la organización).
  - Reservado con alcance "Sitios y grupos" para etiquetar el sitio del inventario (RNF-01): privado, sin invitados,
    acceso limitado en dispositivos no administrados.
  - Etiqueta por defecto en la política: Uso Interno (RN-06 se aplica en la solución, no a todo el tenant).
  En E3 el etiquetado es manual; el etiquetado automático (fase posterior) requiere E5 / E5 Compliance (sección 5.3).
  Requiere ExchangeOnlineManagement 3.x y rol "Administrador de cumplimiento".
  REVISAR con el CISO y el DPO los textos de marcado antes de PROD.
.EXAMPLE
  ./01-New-SensitivityLabels.ps1 -Dominio rentanacional.cl -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Dominio,
    [string]$NombrePolitica = 'RN – Clasificación de la Información',
    [string[]]$AlcancePolitica = @('All')
)
$ErrorActionPreference = 'Stop'
Connect-IPPSSession

$etiquetas = @(
    @{ Name = 'RN-Publica'; DisplayName = 'Pública'; Tooltip = 'Información autorizada para divulgación pública (NC 4.1).'; Marca = $null; Cifrar = $false; Sitios = $false },
    @{ Name = 'RN-UsoInterno'; DisplayName = 'Uso Interno'; Tooltip = 'Uso exclusivo del personal de Renta Nacional (NC 4.1).'; Marca = $null; Cifrar = $false; Sitios = $true },
    @{ Name = 'RN-Reservado'; DisplayName = 'Reservado'; Tooltip = 'Acceso restringido a cargos y terceros autorizados (NC 4.1, 4.4).'; Marca = 'RESERVADO – Renta Nacional'; Cifrar = $false; Sitios = $true },
    @{ Name = 'RN-Confidencial'; DisplayName = 'Confidencial'; Tooltip = 'Máxima sensibilidad. Solo cargos autorizados; cifrado obligatorio (NC 4.1, Anexo 1).'; Marca = 'CONFIDENCIAL – Renta Nacional'; Cifrar = $true; Sitios = $true }
)

$creadas = @()
foreach ($e in $etiquetas) {
    $existe = Get-Label -Identity $e.Name -ErrorAction SilentlyContinue
    $p = @{ DisplayName = $e.DisplayName; Tooltip = $e.Tooltip; Comment = 'ER[ZZ].GR_1.0(2026) – Norma de Clasificación NG[YY].GR_1.0(2026)' }
    $p.ContentType = if ($e.Sitios) { 'File, Email, Site, UnifiedGroup' } else { 'File, Email' }
    if ($e.Marca) {
        $p.ApplyContentMarkingHeaderEnabled = $true; $p.ApplyContentMarkingHeaderText = $e.Marca; $p.ApplyContentMarkingHeaderFontColor = '#C00000'
        $p.ApplyContentMarkingFooterEnabled = $true; $p.ApplyContentMarkingFooterText = "Clasificación: $($e.DisplayName)"
    }
    if ($e.Cifrar) {
        $p.EncryptionEnabled = $true; $p.EncryptionProtectionType = 'Template'
        $p.EncryptionRightsDefinitions = "$($Dominio):VIEW,VIEWRIGHTSDATA,DOCEDIT,EDIT,PRINT,EXTRACT,REPLY,REPLYALL,FORWARD,OBJMODEL"
        $p.EncryptionContentExpiredOnDateInDaysOrNever = 'Never'; $p.EncryptionOfflineAccessDays = 7
    }
    if ($e.Sitios) {
        $p.SiteAndGroupProtectionEnabled = $true
        $p.SiteAndGroupProtectionPrivacy = 'Private'
        $p.SiteAndGroupProtectionAllowAccessToGuestUsers = $false
        $p.SiteAndGroupProtectionAllowEmailFromGuestUsers = $false
        $p.SiteExternalSharingControlType = 'Disabled'
        $p.SiteAndGroupProtectionAllowLimitedAccess = ($e.DisplayName -in 'Reservado', 'Confidencial')
        $p.SiteAndGroupProtectionAllowFullAccess = ($e.DisplayName -eq 'Uso Interno')
        $p.SiteAndGroupProtectionBlockAccess = $false
    }
    if ($PSCmdlet.ShouldProcess($e.DisplayName, $(if ($existe) { 'Actualizar etiqueta' } else { 'Crear etiqueta' }))) {
        if ($existe) { Set-Label -Identity $e.Name @p } else { New-Label -Name $e.Name @p | Out-Null }
        Write-Host "Etiqueta $($e.DisplayName) lista" -ForegroundColor Green
    }
    $creadas += $e.Name
}

# Prioridad = orden de sensibilidad (0 = menor)
for ($i = 0; $i -lt $creadas.Count; $i++) { if ($PSCmdlet.ShouldProcess($creadas[$i], "Prioridad $i")) { Set-Label -Identity $creadas[$i] -Priority $i } }

if (-not (Get-LabelPolicy -Identity $NombrePolitica -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($NombrePolitica, 'Crear política de etiquetas')) {
        New-LabelPolicy -Name $NombrePolitica -Labels $creadas -ExchangeLocation $AlcancePolitica `
            -Settings @{ mandatory = 'false'; requiredowngradejustification = 'true'; siteandgroupmandatory = 'false'; defaultlabelid = (Get-Label -Identity 'RN-UsoInterno').Guid.ToString() } | Out-Null
    }
} else { Set-LabelPolicy -Identity $NombrePolitica -AddLabels $creadas }

Get-Label | Where-Object Name -like 'RN-*' | Select-Object DisplayName, Name, Guid, Priority | Format-Table -AutoSize
Write-Host 'Copie el GUID de "Reservado" en sitio.etiquetaSensibilidadId (config/solution.config.<AMBIENTE>.json).' -ForegroundColor Yellow
Write-Host 'La publicación puede tardar hasta 24 h. Habilite el etiquetado de sitios: Set-SPOTenant -EnableAIPIntegration $true y sincronice con Execute-AzureAdLabelSync.' -ForegroundColor Yellow

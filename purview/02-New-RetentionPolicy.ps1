#Requires -Version 7.2
<#
.SYNOPSIS
  Retención del sitio del inventario (RNF-07, RNF-16) y verificación de la auditoría unificada (RNF-06, RF-49).
.DESCRIPTION
  - Política de retención estática sobre el sitio SGSI – Inventario de Activos: conservar 5 años desde la última
    modificación (cubre HistorialClasificacion, Revisiones, Evidencias y versiones). No elimina al vencer: el CISO
    decide la eliminación según el fundamento de retención (evita pérdida de evidencia regulatoria).
  - Comprueba que el registro de auditoría unificado esté activo. En E3 la retención de auditoría es de 180 días;
    por eso RNF-07 exige la lista Historial propia (independiente de la licencia).
  Requiere ExchangeOnlineManagement 3.x (Connect-IPPSSession y Connect-ExchangeOnline).
.EXAMPLE
  ./02-New-RetentionPolicy.ps1 -UrlSitio https://rentanacional.sharepoint.com/sites/SGSI-InventarioActivos
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$UrlSitio,
    [string]$Nombre = 'SGSI-Inventario-5A',
    [int]$Anios = 5
)
$ErrorActionPreference = 'Stop'
Connect-IPPSSession

if (-not (Get-RetentionCompliancePolicy -Identity $Nombre -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($UrlSitio, "Crear política de retención $Nombre")) {
        New-RetentionCompliancePolicy -Name $Nombre -SharePointLocation $UrlSitio `
            -Comment 'ER[ZZ].GR_1.0(2026) RNF-07/RNF-16: inventario de activos y bitácoras, 5 años.' | Out-Null
        New-RetentionComplianceRule -Name "$Nombre-Regla" -Policy $Nombre -RetentionDuration ($Anios * 365) `
            -RetentionComplianceAction Keep -ExpirationDateOption ModificationAgeInDays | Out-Null
        Write-Host "Política $Nombre creada" -ForegroundColor Green
    }
} else { Write-Host "La política $Nombre ya existe" }

Connect-ExchangeOnline -ShowBanner:$false
$cfgAud = Get-AdminAuditLogConfig
if (-not $cfgAud.UnifiedAuditLogIngestionEnabled) {
    if ($PSCmdlet.ShouldProcess('Tenant', 'Habilitar auditoría unificada')) { Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true; Write-Host 'Auditoría unificada habilitada' -ForegroundColor Green }
} else { Write-Host 'Auditoría unificada: habilitada' -ForegroundColor Green }
Write-Host 'Consulta de evidencias de acceso al inventario (ejemplo):' -ForegroundColor Yellow
Write-Host "  Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) -ObjectIds '$UrlSitio/Lists/Activos*' -RecordType SharePointListItemOperation -ResultSize 5000"

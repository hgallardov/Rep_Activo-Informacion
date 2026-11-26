#Requires -Version 7.2
<#
.SYNOPSIS
  Crea y endurece el sitio SharePoint "SGSI – Inventario de Activos" (RNF-01, RNF-06, RNF-16).
.DESCRIPTION
  1. Crea un sitio de grupo SIN grupo de Microsoft 365 (no expone el contenido vía Teams/Outlook).
  2. Deshabilita el uso compartido externo, las solicitudes de acceso y el uso compartido por miembros.
  3. Aplica la etiqueta de sensibilidad "Reservado" al sitio (requiere etiqueta publicada con alcance Sitios/Grupos, ver purview/).
  4. Restringe la descarga en dispositivos no administrados (acceso condicional controlado por la aplicación, RNF-02).
  5. Registra la cuenta de servicio y el grupo CISO como administradores.
.PARAMETER Ambiente DEV | TEST | PROD
.EXAMPLE
  ./02-New-InventorySite.ps1 -Ambiente DEV
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('DEV', 'TEST', 'PROD')][string]$Ambiente = 'DEV')

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/RNInventario.Comun.psm1') -Force
Initialize-RNLog -NombreScript '02-New-InventorySite' | Out-Null
Assert-RNModulo -Nombre 'PnP.PowerShell' -VersionMinima '2.4'

$cfg = Get-RNConfiguracion -Ambiente $Ambiente
$s = $cfg.Solucion.sitio

Connect-RNSitio -Config $cfg -Url $cfg.Solucion.tenant.adminUrl

$sitio = Get-PnPTenantSite -Identity $s.url -ErrorAction SilentlyContinue
if (-not $sitio) {
    if ($PSCmdlet.ShouldProcess($s.url, 'Crear sitio')) {
        Write-RNLog "Creando sitio $($s.url)"
        New-PnPSite -Type TeamSiteWithoutMicrosoft365Group -Title $s.titulo -Url $s.url -Description $s.descripcion `
            -Lcid $s.lcid -TimeZone $s.zonaHoraria -Owner $s.propietarios[0] -Wait | Out-Null
        Write-RNLog 'Sitio creado' 'OK'
    }
} else { Write-RNLog 'El sitio ya existe; se aplicará solo la configuración' }

if ($PSCmdlet.ShouldProcess($s.url, 'Endurecer configuración del sitio')) {
    # Uso compartido externo deshabilitado y sin vínculos "cualquier persona" (RNF-01)
    Set-PnPTenantSite -Identity $s.url -SharingCapability Disabled -DefaultSharingLinkType Internal -DefaultLinkPermission View
    # Acceso limitado a web en dispositivos no administrados (complementa el acceso condicional, RNF-02)
    Set-PnPTenantSite -Identity $s.url -ConditionalAccessPolicy AllowLimitedAccess
    # Sin scripts personalizados
    Set-PnPTenantSite -Identity $s.url -DenyAddAndCustomizePages:$true
    foreach ($o in $s.propietarios) { Set-PnPTenantSite -Identity $s.url -Owners $o }
    Write-RNLog 'Uso compartido externo deshabilitado, acceso condicional y administradores aplicados' 'OK'
}

Connect-RNSitio -Config $cfg

if ($PSCmdlet.ShouldProcess($s.url, 'Configurar web')) {
    $web = Get-PnPWeb -Includes RequestAccessEmail, MembersCanShare
    # Sin solicitudes de acceso ni uso compartido por miembros: las altas se gestionan por grupos de Entra ID
    Set-PnPRequestAccessEmails -Disabled
    $web.MembersCanShare = $false
    $web.Update()
    Invoke-PnPQuery
    Set-PnPSite -DisableSharingForNonOwners
    # Etiqueta de sensibilidad del sitio (RNF-01). Debe existir y estar publicada con alcance "Sitios y grupos".
    try {
        if (-not $s.etiquetaSensibilidadId) { throw 'sitio.etiquetaSensibilidadId vacío en solution.config (GUID de la etiqueta Reservado)' }
        Set-PnPSite -SensitivityLabel $s.etiquetaSensibilidadId
        Write-RNLog "Etiqueta de sensibilidad '$($s.etiquetaSensibilidad)' aplicada al sitio" 'OK'
    } catch {
        Write-RNLog "No se pudo aplicar la etiqueta '$($s.etiquetaSensibilidad)': $($_.Exception.Message). Ejecute purview/01-New-SensitivityLabels.ps1 y reintente." 'ADVERTENCIA'
    }
    # Desactivar la búsqueda de contenido del sitio fuera del propio sitio no es necesario: la búsqueda respeta permisos.
    # Se excluyen de la navegación las listas técnicas en 03-New-InventoryLists.ps1.
}

Write-RNLog 'Pendiente manual: aplicar la etiqueta de retención al sitio (purview/02-New-RetentionPolicy.ps1) y verificar que la auditoría unificada de Purview esté activa (RNF-06).'
Write-RNLog 'Fin 02-New-InventorySite' 'OK'

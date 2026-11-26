#Requires -Version 5.1
<#
.SYNOPSIS
  Gobierno de Power Platform para la solución (RNF-05, RNF-14): entornos DEV/TEST/PROD y política DLP
  que restringe los entornos de la solución a los conectores de Microsoft 365 aprobados.
.DESCRIPTION
  - Crea (si no existen) los entornos RN-SGSI-Inventario-DEV/TEST/PROD con Dataverse (necesario para soluciones,
    variables de entorno y referencias de conexión; la capacidad de Dataverse de entornos productivos se descuenta
    del tenant, ver docs/01_Diseno_de_la_Solucion.md §Licenciamiento).
  - Crea la política DLP "RN-SGSI-Inventario-Solo-M365" aplicada solo a esos entornos:
      Negocio: SharePoint, Office 365 Users, Office 365 Outlook, Office 365 Groups, Microsoft Teams, Approvals,
               Excel Online (Business), OneDrive for Business, Notifications, Power Apps for Makers / Notification.
      Bloqueado: todo lo demás (incluye HTTP, conectores personalizados y conectores de terceros).
  Requiere Microsoft.PowerApps.Administration.PowerShell (Windows PowerShell 5.1) y rol Administrador de Power Platform.
.EXAMPLE
  .\09-New-PowerPlatformGovernance.ps1 -Region unitedstates -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Region = 'unitedstates',
    [string]$NombrePolitica = 'RN-SGSI-Inventario-Solo-M365',
    [string[]]$Entornos = @('RN-SGSI-Inventario-DEV', 'RN-SGSI-Inventario-TEST', 'RN-SGSI-Inventario-PROD')
)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerApps.Administration.PowerShell
Add-PowerAppsAccount

$ids = @()
foreach ($n in $Entornos) {
    $e = Get-AdminPowerAppEnvironment | Where-Object DisplayName -eq $n
    if (-not $e) {
        $sku = if ($n -like '*PROD') { 'Production' } else { 'Sandbox' }
        if ($PSCmdlet.ShouldProcess($n, "Crear entorno $sku")) {
            $e = New-AdminPowerAppEnvironment -DisplayName $n -LocationName $Region -EnvironmentSku $sku -ProvisionDatabase `
                -CurrencyName CLP -LanguageName 3082 -WaitUntilFinished $true
            Write-Host "Entorno $n creado" -ForegroundColor Green
        }
    }
    $ids += $e.EnvironmentName
}

$negocio = @(
    'shared_sharepointonline', 'shared_office365users', 'shared_office365', 'shared_office365groups', 'shared_teams',
    'shared_approvals', 'shared_excelonlinebusiness', 'shared_onedriveforbusiness', 'shared_flowpush', 'shared_powerappsnotificationv2'
)

if ($PSCmdlet.ShouldProcess($NombrePolitica, 'Crear o actualizar política DLP')) {
    $pol = Get-DlpPolicy | Select-Object -ExpandProperty value | Where-Object displayName -eq $NombrePolitica
    if (-not $pol) {
        $pol = New-DlpPolicy -DisplayName $NombrePolitica -EnvironmentType OnlyEnvironments -Environments ($ids -join ',')
        Write-Host "Política $NombrePolitica creada" -ForegroundColor Green
    }
    # Agrupar conectores: Business = aprobados; Blocked = resto (los conectores bloqueables)
    $conectores = Get-AdminPowerAppConnector -EnvironmentName $ids[0] | Select-Object -Property ConnectorName, DisplayName
    $grupos = @(
        @{ classification = 'Confidential'; connectors = @($negocio | ForEach-Object { @{ id = "/providers/Microsoft.PowerApps/apis/$_"; name = $_; type = 'Microsoft.PowerApps/apis' } }) },
        @{ classification = 'General'; connectors = @() },
        @{ classification = 'Blocked'; connectors = @($conectores | Where-Object { $_.ConnectorName -notin $negocio } |
                ForEach-Object { @{ id = "/providers/Microsoft.PowerApps/apis/$($_.ConnectorName)"; name = $_.DisplayName; type = 'Microsoft.PowerApps/apis' } }) }
    )
    $pol.connectorGroups = $grupos
    $pol.defaultConnectorsClassification = 'Blocked'
    Set-DlpPolicy -PolicyName $pol.name -UpdatedPolicy $pol | Out-Null
    Write-Host "DLP: $($negocio.Count) conectores de negocio; conectores nuevos bloqueados por defecto" -ForegroundColor Green
}
Write-Host 'Pendiente manual: asignar el rol "Creador de entorno" solo al equipo de desarrollo en DEV; en TEST/PROD solo la cuenta de servicio importa soluciones (canalización o importación manual).' -ForegroundColor Yellow

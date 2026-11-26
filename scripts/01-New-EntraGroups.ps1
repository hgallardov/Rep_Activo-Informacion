#Requires -Version 7.2
<#
.SYNOPSIS
  Crea (de forma idempotente) los grupos de seguridad de Microsoft Entra ID de la solución (sección 6 y 13 del ER).
.DESCRIPTION
  - Grupos transversales: SGSI-INV-CISO, -DPO, -RIESGOS, -CSI, -AUDITORIA, -CUSTODIOS, -ADMIN-TI, -PERSONAS.
  - Un grupo de edición por gerencia: SGSI-INV-[ENT]-[GER]-EDIT (Dueños y Delegados de registro).
  Los grupos se crean sin miembros: las altas en grupos de edición las aprueba el CISO (sección 13).
  Requiere Microsoft.Graph.Groups y el permiso delegado Group.ReadWrite.All (administrador de grupos).
.PARAMETER Ambiente  DEV | TEST | PROD (lee config/solution.config.<Ambiente>.json si existe).
.PARAMETER WhatIf    Muestra lo que haría sin crear nada.
.EXAMPLE
  ./01-New-EntraGroups.ps1 -Ambiente PROD -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('DEV', 'TEST', 'PROD')][string]$Ambiente = 'DEV')

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/RNInventario.Comun.psm1') -Force
Initialize-RNLog -NombreScript '01-New-EntraGroups' | Out-Null
Assert-RNModulo -Nombre 'Microsoft.Graph.Groups' -VersionMinima '2.0'

$cfg = Get-RNConfiguracion -Ambiente $Ambiente
Connect-MgGraph -TenantId $cfg.Solucion.tenant.tenantId -Scopes 'Group.ReadWrite.All' -NoWelcome

function New-RNGrupoSeguridad {
    param([string]$Nombre, [string]$Descripcion)
    $existente = Get-MgGroup -Filter "displayName eq '$Nombre'" -ConsistencyLevel eventual -CountVariable n -ErrorAction SilentlyContinue
    if ($existente) { Write-RNLog "Ya existe $Nombre ($($existente.Id))"; return $existente }
    $apodo = ($Nombre -replace '[^A-Za-z0-9-]', '').ToLower()
    if ($PSCmdlet.ShouldProcess($Nombre, 'Crear grupo de seguridad')) {
        $g = New-MgGroup -DisplayName $Nombre -Description $Descripcion -MailEnabled:$false -MailNickname $apodo -SecurityEnabled:$true
        Write-RNLog "Creado $Nombre ($($g.Id))" 'OK'
        return $g
    }
}

$resultado = [System.Collections.Generic.List[object]]::new()

foreach ($g in $cfg.Solucion.grupos.transversales) {
    $r = New-RNGrupoSeguridad -Nombre $g.nombre -Descripcion "SGSI Inventario – $($g.descripcion)"
    $resultado.Add([pscustomobject]@{ Grupo = $g.nombre; Id = $r.Id; Tipo = 'Transversal' })
}

$entidades = Import-Csv (Join-Path $cfg.DirMaestros 'entidades.csv') -Delimiter ';' -Encoding utf8
$gerencias = Import-Csv (Join-Path $cfg.DirMaestros 'gerencias.csv') -Delimiter ';' -Encoding utf8
foreach ($ger in $gerencias) {
    $ent = $entidades | Where-Object Title -eq $ger.Entidad
    if (-not $ent) { Write-RNLog "Gerencia $($ger.Title): entidad '$($ger.Entidad)' no existe en entidades.csv" 'ERROR'; continue }
    $nombre = $cfg.Solucion.grupos.plantillaEdicion.Replace('{ENT}', $ent.RN_Codigo).Replace('{GER}', $ger.RN_Codigo)
    $r = New-RNGrupoSeguridad -Nombre $nombre -Descripcion "SGSI Inventario – Dueños y Delegados de $($ger.Title) ($($ent.RN_Codigo))"
    $resultado.Add([pscustomobject]@{ Grupo = $nombre; Id = $r.Id; Tipo = "Edición $($ger.RN_Codigo)" })
}

$salida = Join-Path (Get-RNRutaRepositorio) "logs/grupos-entra-$Ambiente.csv"
$resultado | Export-Csv -Path $salida -Delimiter ';' -Encoding utf8 -NoTypeInformation
Write-RNLog "Inventario de grupos exportado a $salida" 'OK'
Write-RNLog 'Siguiente paso: incluir los grupos en la política de acceso condicional del sitio (RNF-02) y asignar miembros con aprobación del CISO.'

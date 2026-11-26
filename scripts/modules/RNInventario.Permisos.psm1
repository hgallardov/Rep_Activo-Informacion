#Requires -Version 7.2
<#
.SYNOPSIS
  Cálculo y aplicación de los permisos por elemento de la lista Activos (sección 13 del ER).
.DESCRIPTION
  Implementa en PowerShell la MISMA regla que el flujo FL-01 (powerautomate/FL-01_Alta_de_Activo.md):
    Edición (SGSI Editar sin eliminar): grupo de la gerencia dueña; grupo de la gerencia contraparte si Entidad = Ambas;
                                         grupo CISO; titular del cargo Custodio (si existe).
    Lectura: grupos DPO, RIESGOS, CSI y AUDITORIA.
    Control total: cuenta de servicio.
  La usan 07-Restore-Inventory.ps1 (recrear) y 08-Test-InventarioControles.ps1 (detectar y remediar desvíos).
  Requiere una conexión PnP activa al sitio.
#>
Set-StrictMode -Version Latest

function Get-RNParametrosSitio {
    $h = @{}
    Get-PnPListItem -List 'Parametros' -PageSize 500 | ForEach-Object { $h[$_['Title']] = $_['RN_Valor'] }
    $h
}

function Get-RNPermisosEsperados {
    <# Devuelve una lista de @{ PrincipalId; Rol } esperados para el elemento. #>
    param([Parameter(Mandatory)]$Elemento, [hashtable]$Parametros = (Get-RNParametrosSitio), [hashtable]$CacheGerencias = @{})
    $getGer = {
        param($idGer)
        if (-not $idGer) { return $null }
        if (-not $CacheGerencias.ContainsKey($idGer)) { $CacheGerencias[$idGer] = Get-PnPListItem -List 'Gerencias' -Id $idGer }
        $CacheGerencias[$idGer]
    }
    $esperados = [System.Collections.Generic.List[object]]::new()
    $ed = [int]$Parametros['ROL_EDICION_ID']; $le = [int]$Parametros['ROL_LECTURA_ID']
    $ger = & $getGer $Elemento['RN_Gerencia']?.LookupId
    if ($ger -and $ger['RN_GrupoEdicionSPId']) { $esperados.Add(@{ PrincipalId = [int]$ger['RN_GrupoEdicionSPId']; Rol = $ed; Motivo = "Gerencia $($ger['RN_Codigo'])" }) }
    $con = & $getGer $Elemento['RN_GerenciaContraparte']?.LookupId
    if ($Elemento['RN_Entidad']?.LookupValue -eq 'Ambas' -and $con -and $con['RN_GrupoEdicionSPId']) {
        $esperados.Add(@{ PrincipalId = [int]$con['RN_GrupoEdicionSPId']; Rol = $ed; Motivo = "Contraparte $($con['RN_Codigo'])" })
    }
    $esperados.Add(@{ PrincipalId = [int]$Parametros['GRUPO_CISO_SPID']; Rol = $ed; Motivo = 'CISO' })
    foreach ($k in 'GRUPO_DPO_SPID', 'GRUPO_RIESGOS_SPID', 'GRUPO_CSI_SPID', 'GRUPO_AUDITORIA_SPID') {
        if ($Parametros[$k]) { $esperados.Add(@{ PrincipalId = [int]$Parametros[$k]; Rol = $le; Motivo = $k }) }
    }
    $upnCustodio = $Elemento['RN_CustodioPersona']
    if ($upnCustodio) {
        $u = New-PnPUser -LoginName "i:0#.f|membership|$upnCustodio"
        $esperados.Add(@{ PrincipalId = $u.Id; Rol = $ed; Motivo = 'Custodio' })
    }
    , $esperados
}

function Set-RNPermisosActivo {
    <# Rompe herencia (sin copiar) y deja exactamente los permisos esperados + cuenta de servicio. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][int]$IdElemento, [hashtable]$Parametros = (Get-RNParametrosSitio))
    $it = Get-PnPListItem -List 'Activos' -Id $IdElemento
    $esperados = Get-RNPermisosEsperados -Elemento $it -Parametros $Parametros
    if (-not $PSCmdlet.ShouldProcess($it['Title'], 'Aplicar permisos únicos')) { return }
    $ctx = Get-PnPContext
    $li = (Get-PnPList -Identity 'Activos').GetItemById($IdElemento)
    $li.BreakRoleInheritance($false, $false)
    $ctx.ExecuteQuery()
    $li = (Get-PnPList -Identity 'Activos').GetItemById($IdElemento)
    $ctx.Load($li.RoleAssignments); $ctx.ExecuteQuery()
    $svc = New-PnPUser -LoginName "i:0#.f|membership|$($Parametros['CUENTA_SERVICIO_UPN'])"
    $ids = @($esperados | ForEach-Object { $_.PrincipalId }) + $svc.Id
    foreach ($ra in @($li.RoleAssignments)) { if ($ra.PrincipalId -notin $ids) { $li.RoleAssignments.GetByPrincipalId($ra.PrincipalId).DeleteObject() } }
    $ctx.ExecuteQuery()
    $web = Get-PnPWeb
    foreach ($e in $esperados) {
        $bind = [Microsoft.SharePoint.Client.RoleDefinitionBindingCollection]::new($ctx)
        $bind.Add($web.RoleDefinitions.GetById($e.Rol))
        $li.RoleAssignments.Add($web.SiteUsers.GetById($e.PrincipalId), $bind) | Out-Null
    }
    $bindT = [Microsoft.SharePoint.Client.RoleDefinitionBindingCollection]::new($ctx)
    $bindT.Add($web.RoleDefinitions.GetByType([Microsoft.SharePoint.Client.RoleType]::Administrator))
    $li.RoleAssignments.Add($web.SiteUsers.GetById($svc.Id), $bindT) | Out-Null
    $ctx.ExecuteQuery()
    $clave = (@($esperados | ForEach-Object { "$($_.PrincipalId):$($_.Rol)" }) | Sort-Object) -join ','
    Set-PnPListItem -List 'Activos' -Identity $IdElemento -Values @{ RN_ClavePermisos = $clave } -UpdateType SystemUpdate | Out-Null
}

function Get-RNPermisosReales {
    param([Parameter(Mandatory)][int]$IdElemento)
    $ctx = Get-PnPContext
    $li = (Get-PnPList -Identity 'Activos').GetItemById($IdElemento)
    $ctx.Load($li.RoleAssignments)
    $ctx.ExecuteQuery()
    $hasUnique = Get-PnPProperty -ClientObject $li -Property HasUniqueRoleAssignments
    $r = foreach ($ra in $li.RoleAssignments) {
        $ctx.Load($ra.Member); $ctx.Load($ra.RoleDefinitionBindings); $ctx.ExecuteQuery()
        foreach ($b in $ra.RoleDefinitionBindings) { [pscustomobject]@{ PrincipalId = $ra.PrincipalId; Principal = $ra.Member.Title; Rol = $b.Id; NombreRol = $b.Name } }
    }
    [pscustomobject]@{ Unicos = $hasUnique; Asignaciones = @($r) }
}

Export-ModuleMember -Function Get-RNParametrosSitio, Get-RNPermisosEsperados, Set-RNPermisosActivo, Get-RNPermisosReales

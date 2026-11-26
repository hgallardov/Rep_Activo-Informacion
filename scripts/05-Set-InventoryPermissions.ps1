#Requires -Version 7.2
<#
.SYNOPSIS
  Aplica el modelo de permisos para dos entidades (sección 13 del ER, RNF-03, CA-02).
.DESCRIPTION
  Principios:
   - Las personas reciben acceso SOLO a través de grupos de Entra ID (nunca usuarios individuales), salvo el Custodio
     del activo, que el flujo FL-01/FL-09 agrega a nivel de elemento.
   - La lista Activos rompe herencia y solo conservan acceso a nivel de lista el grupo CISO y la cuenta de servicio.
     Los Dueños/Delegados NO pueden crear elementos directamente: el alta la hace FL-01 (cuenta de servicio) desde la app,
     y el elemento nace ya con permisos únicos. Así ningún activo es visible, ni por segundos, fuera de su gerencia.
   - Bitácoras (HistorialClasificacion, Revisiones, Correlativos, PertenenciaGrupos) solo las escribe la cuenta de servicio.
   - Se crea el nivel de permiso "SGSI Editar sin eliminar" (Colaborar sin DeleteListItems ni DeleteVersions):
     los activos no se borran, se dan de baja (RF-34, RN-01).
  Al final escribe en la lista Parametros los Id de SharePoint de los grupos y roles que usan los flujos.
.PARAMETER Ambiente DEV | TEST | PROD
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('DEV', 'TEST', 'PROD')][string]$Ambiente = 'DEV')

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/RNInventario.Comun.psm1') -Force
Initialize-RNLog -NombreScript '05-Set-InventoryPermissions' | Out-Null
Assert-RNModulo -Nombre 'PnP.PowerShell' -VersionMinima '2.4'

$cfg = Get-RNConfiguracion -Ambiente $Ambiente
$csvGrupos = Join-Path (Get-RNRutaRepositorio) "logs/grupos-entra-$Ambiente.csv"
if (-not (Test-Path $csvGrupos)) { throw "No existe $csvGrupos. Ejecute antes 01-New-EntraGroups.ps1 -Ambiente $Ambiente" }
$grupos = Import-Csv $csvGrupos -Delimiter ';' -Encoding utf8
Connect-RNSitio -Config $cfg

# --- Niveles de permiso -------------------------------------------------------------------------
$roles = Get-PnPRoleDefinition
$rolLeer = $roles | Where-Object RoleTypeKind -eq 'Reader'
$rolColaborar = $roles | Where-Object RoleTypeKind -eq 'Contributor'
$rolTotal = $roles | Where-Object RoleTypeKind -eq 'Administrator'
$nombreRolEdicion = 'SGSI Editar sin eliminar'
$rolEdicion = $roles | Where-Object Name -eq $nombreRolEdicion
if (-not $rolEdicion -and $PSCmdlet.ShouldProcess($nombreRolEdicion, 'Crear nivel de permiso')) {
    $rolEdicion = Add-PnPRoleDefinition -RoleName $nombreRolEdicion -Clone $rolColaborar -Exclude DeleteListItems, DeleteVersions `
        -Description 'Ver, agregar y editar elementos sin eliminarlos ni borrar versiones (SGSI Inventario).'
    Write-RNLog "Creado nivel de permiso '$nombreRolEdicion'" 'OK'
}
$rolEdicion = Get-PnPRoleDefinition -Identity $nombreRolEdicion

# --- Resolver grupos de Entra ID como principales de SharePoint ------------------------------------
$tenantLogin = { param($objectId) "c:0t.c|tenant|$objectId" }
$principal = @{}
foreach ($g in $grupos) {
    if (-not $g.Id) { Write-RNLog "Grupo $($g.Grupo) sin Id en $csvGrupos" 'ADVERTENCIA'; continue }
    $u = New-PnPUser -LoginName (& $tenantLogin $g.Id)       # ensureuser: idempotente
    $principal[$g.Grupo] = $u
    Write-RNLog "  Grupo $($g.Grupo) => principal SharePoint $($u.Id)"
}
$svc = New-PnPUser -LoginName "i:0#.f|membership|$($cfg.Solucion.cuentaServicio)"
$G = { param($n) if (-not $principal.ContainsKey($n)) { throw "Grupo no resuelto: $n" }; $principal[$n].LoginName }

# --- Nivel sitio: lectura de maestros para todos los participantes ----------------------------------
$visitantes = Get-PnPGroup -AssociatedVisitorGroup
$miembros = Get-PnPGroup -AssociatedMemberGroup
foreach ($g in $grupos) {
    if ($g.Grupo -in 'SGSI-INV-ADMIN-TI') { continue }    # TI administra la plataforma, sin acceso a los datos (sección 6)
    if ($g.Grupo -eq 'SGSI-INV-CISO') { Add-PnPGroupMember -Group $miembros -LoginName (& $G $g.Grupo); continue }
    Add-PnPGroupMember -Group $visitantes -LoginName (& $G $g.Grupo)
}
Write-RNLog 'Sitio: CISO en Miembros (edición de maestros); resto de grupos en Visitantes (lectura de maestros)' 'OK'

function Set-RNPermisosLista {
    param([string]$Lista, [hashtable]$Asignaciones)  # LoginName => nombre de rol
    if (-not $PSCmdlet.ShouldProcess($Lista, 'Romper herencia y asignar permisos')) { return }
    # Sin copiar permisos: SharePoint deja solo al usuario que ejecuta, que se retira al final.
    Set-PnPList -Identity $Lista -BreakRoleInheritance -CopyRoleAssignments:$false | Out-Null
    Set-PnPListPermission -Identity $Lista -User $svc.LoginName -AddRole $rolTotal.Name
    foreach ($k in $Asignaciones.Keys) { Set-PnPListPermission -Identity $Lista -User $k -AddRole $Asignaciones[$k] }
    if ($ejecutor -ne $svc.LoginName -and -not $Asignaciones.ContainsKey($ejecutor)) {
        Set-PnPListPermission -Identity $Lista -User $ejecutor -RemoveRole $rolTotal.Name -ErrorAction SilentlyContinue
    }
    Write-RNLog "Permisos de lista aplicados: $Lista ($($Asignaciones.Count) asignaciones + cuenta de servicio)" 'OK'
}

function Join-RNAsignaciones {
    <# Combina tablas LoginName => rol; las posteriores prevalecen. #>
    $r = @{}
    foreach ($h in $args) { foreach ($k in $h.Keys) { $r[$k] = $h[$k] } }
    $r
}

$ejecutor = (Get-PnPWeb -Includes CurrentUser).CurrentUser.LoginName

$lectTransversal = @('SGSI-INV-DPO', 'SGSI-INV-RIESGOS', 'SGSI-INV-CSI', 'SGSI-INV-AUDITORIA')
$hLect = @{}; foreach ($n in $lectTransversal) { $hLect[(& $G $n)] = $rolLeer.Name }

# Activos y Excepciones: solo CISO a nivel de lista; los elementos reciben permisos únicos por FL-01 / FL-07
Set-RNPermisosLista -Lista 'Activos' -Asignaciones @{ (& $G 'SGSI-INV-CISO') = $rolEdicion.Name }
Set-RNPermisosLista -Lista 'Excepciones' -Asignaciones @{ (& $G 'SGSI-INV-CISO') = $rolEdicion.Name }
# Bitácoras de solo escritura por flujo (RNF-07): lectura transversal
foreach ($b in 'HistorialClasificacion', 'Revisiones') {
    Set-RNPermisosLista -Lista $b -Asignaciones (Join-RNAsignaciones $hLect @{ (& $G 'SGSI-INV-CISO') = $rolLeer.Name })
}
Set-RNPermisosLista -Lista 'Correlativos' -Asignaciones @{ (& $G 'SGSI-INV-CISO') = $rolLeer.Name }
Set-RNPermisosLista -Lista 'PertenenciaGrupos' -Asignaciones @{ (& $G 'SGSI-INV-CISO') = $rolLeer.Name }
Set-RNPermisosLista -Lista 'Respaldos' -Asignaciones @{ (& $G 'SGSI-INV-CISO') = $rolLeer.Name; (& $G 'SGSI-INV-ADMIN-TI') = $rolLeer.Name }
Set-RNPermisosLista -Lista 'CargaMasiva' -Asignaciones @{ (& $G 'SGSI-INV-CISO') = $rolEdicion.Name }
# Maestros con edición delegada
$todosLectura = @{}; foreach ($g in $grupos) { if ($g.Grupo -ne 'SGSI-INV-ADMIN-TI') { $todosLectura[(& $G $g.Grupo)] = $rolLeer.Name } }
Set-RNPermisosLista -Lista 'Parametros' -Asignaciones (Join-RNAsignaciones $todosLectura @{ (& $G 'SGSI-INV-CISO') = $rolEdicion.Name })
$a = $todosLectura.Clone(); $a[(& $G 'SGSI-INV-CISO')] = $rolEdicion.Name; $a[(& $G 'SGSI-INV-PERSONAS')] = $rolEdicion.Name
Set-RNPermisosLista -Lista 'Cargos' -Asignaciones $a
$a = $todosLectura.Clone(); $a[(& $G 'SGSI-INV-CISO')] = $rolEdicion.Name; $a[(& $G 'SGSI-INV-RIESGOS')] = $rolEdicion.Name
Set-RNPermisosLista -Lista 'Terceros' -Asignaciones $a
$a = $todosLectura.Clone(); $a[(& $G 'SGSI-INV-DPO')] = $rolEdicion.Name; $a[(& $G 'SGSI-INV-CISO')] = $rolEdicion.Name
Set-RNPermisosLista -Lista 'CatalogoRAT' -Asignaciones $a
# RelacionesActivos: la crea/edita FL-01 (relaciones) con la cuenta de servicio; lectura a participantes
Set-RNPermisosLista -Lista 'RelacionesActivos' -Asignaciones (Join-RNAsignaciones $todosLectura @{ (& $G 'SGSI-INV-CISO') = $rolEdicion.Name })

# --- Biblioteca Evidencias: carpeta por entidad/gerencia ---------------------------------------------
Set-RNPermisosLista -Lista 'Evidencias' -Asignaciones (Join-RNAsignaciones $hLect @{ (& $G 'SGSI-INV-CISO') = $rolEdicion.Name })
$entidades = Get-PnPListItem -List 'Entidades' | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Codigo = $_['RN_Codigo'] } }
$gerencias = Get-PnPListItem -List 'Gerencias' -PageSize 500
foreach ($ger in $gerencias) {
    $ent = $entidades | Where-Object Id -eq $ger['RN_Entidad'].LookupId
    $grupoEd = $cfg.Solucion.grupos.plantillaEdicion.Replace('{ENT}', $ent.Codigo).Replace('{GER}', $ger['RN_Codigo'])
    if (-not $principal.ContainsKey($grupoEd)) { Write-RNLog "Sin grupo $grupoEd para la gerencia $($ger['Title'])" 'ADVERTENCIA'; continue }
    # Registrar en el maestro el Id SharePoint del grupo de edición (lo usa FL-01)
    $idEntra = ($grupos | Where-Object Grupo -eq $grupoEd).Id
    Set-PnPListItem -List 'Gerencias' -Identity $ger.Id -Values @{ RN_GrupoEdicion = $grupoEd; RN_GrupoEdicionSPId = $principal[$grupoEd].Id; RN_GrupoEdicionEntraId = $idEntra } | Out-Null
    $ruta = "Evidencias/$($ent.Codigo)/$($ger['RN_Codigo'])"
    if (-not (Get-PnPFolder -Url $ruta -ErrorAction SilentlyContinue)) { Add-PnPFolder -Name $ger['RN_Codigo'] -Folder "Evidencias/$($ent.Codigo)" | Out-Null }
    $carpeta = Get-PnPFolder -Url $ruta -Includes ListItemAllFields
    # Rompe herencia copiando los permisos de la biblioteca (CISO + lectura transversal) y agrega la gerencia
    Set-PnPListItemPermission -List 'Evidencias' -Identity $carpeta.ListItemAllFields.Id -User (& $G $grupoEd) -AddRole $rolEdicion.Name | Out-Null
    Write-RNLog "  Evidencias: $ruta => $grupoEd" 'OK'
}

# --- Parámetros técnicos para los flujos --------------------------------------------------------------
$parametrosItems = Get-PnPListItem -List 'Parametros' -PageSize 500
function Set-RNParametro { param([string]$Clave, [string]$Valor)
    $it = $parametrosItems | Where-Object { $_['Title'] -eq $Clave }
    if ($it) { Set-PnPListItem -List 'Parametros' -Identity $it.Id -Values @{ RN_Valor = $Valor } | Out-Null }
    else { Write-RNLog "Parámetro $Clave no existe (ejecute 04-Import-MasterData.ps1 primero)" 'ADVERTENCIA' }
}
foreach ($t in $cfg.Solucion.grupos.transversales) {
    if ($t.PSObject.Properties['parametro'] -and $principal.ContainsKey($t.nombre)) { Set-RNParametro $t.parametro ([string]$principal[$t.nombre].Id) }
}
foreach ($par in @{ GRUPO_CISO_ENTRAID = 'SGSI-INV-CISO'; GRUPO_DPO_ENTRAID = 'SGSI-INV-DPO'; GRUPO_CSI_ENTRAID = 'SGSI-INV-CSI'; GRUPO_RIESGOS_ENTRAID = 'SGSI-INV-RIESGOS'; GRUPO_AUDITORIA_ENTRAID = 'SGSI-INV-AUDITORIA' }.GetEnumerator()) {
    Set-RNParametro $par.Key ([string]($grupos | Where-Object Grupo -eq $par.Value).Id)
}
Set-RNParametro 'ROL_EDICION_ID' ([string]$rolEdicion.Id)
Set-RNParametro 'ROL_LECTURA_ID' ([string]$rolLeer.Id)

Write-RNLog 'Fin 05-Set-InventoryPermissions. Verifique CA-02 con un usuario de prueba de RNSV (docs/05_Plan_de_Pruebas.md).' 'OK'

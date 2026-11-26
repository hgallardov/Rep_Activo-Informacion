#Requires -Version 7.2
<#
.SYNOPSIS
  Carga o actualiza (upsert por Title) los maestros y los parámetros de negocio (RF-01 a RF-05).
.DESCRIPTION
  Fuentes: config/maestros/*.csv (separador ';', UTF-8) y config/parametros.json.
  Orden: Entidades → Gerencias → Procesos → Cargos (2 pasadas por la autorreferencia Jefatura) → Terceros → Parametros.
  Los parámetros existentes NO se sobrescriben salvo -SobrescribirParametros (protege los valores ajustados por el CISO).
.PARAMETER Ambiente DEV | TEST | PROD
.PARAMETER SobrescribirParametros  Reemplaza el valor de los parámetros ya existentes.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('DEV', 'TEST', 'PROD')][string]$Ambiente = 'DEV',
    [switch]$SobrescribirParametros
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/RNInventario.Comun.psm1') -Force
Initialize-RNLog -NombreScript '04-Import-MasterData' | Out-Null
Assert-RNModulo -Nombre 'PnP.PowerShell' -VersionMinima '2.4'
$cfg = Get-RNConfiguracion -Ambiente $Ambiente
Connect-RNSitio -Config $cfg

function Get-RNIndicePorTitulo { param([string]$Lista)
    $h = @{}; Get-PnPListItem -List $Lista -PageSize 2000 -Fields 'Title' | ForEach-Object { $h[$_['Title']] = $_.Id }; $h }

function Set-RNElemento {
    param([string]$Lista, [hashtable]$Indice, [string]$Titulo, [hashtable]$Valores)
    $Valores['Title'] = $Titulo
    if ($Indice.ContainsKey($Titulo)) {
        if ($PSCmdlet.ShouldProcess("$Lista/$Titulo", 'Actualizar')) { Set-PnPListItem -List $Lista -Identity $Indice[$Titulo] -Values $Valores | Out-Null }
        Write-RNLog "  ~ $Lista/$Titulo"
    } else {
        if ($PSCmdlet.ShouldProcess("$Lista/$Titulo", 'Crear')) { $n = Add-PnPListItem -List $Lista -Values $Valores; $Indice[$Titulo] = $n.Id }
        Write-RNLog "  + $Lista/$Titulo" 'OK'
    }
}

$bool = { param($v) [bool]::Parse(($v ?? 'false').Trim()) }
$leer = { param($archivo) $r = Join-Path $cfg.DirMaestros $archivo; if (Test-Path $r) { Import-Csv $r -Delimiter ';' -Encoding utf8 } else { Write-RNLog "No existe $archivo; se omite" 'ADVERTENCIA'; @() } }

# Entidades
$ixEnt = Get-RNIndicePorTitulo 'Entidades'
foreach ($e in (& $leer 'entidades.csv')) {
    Set-RNElemento 'Entidades' $ixEnt $e.Title @{ RN_Codigo = $e.RN_Codigo; RN_RazonSocial = $e.RN_RazonSocial; RN_RUT = $e.RN_RUT;
        RN_GrupoLectores = $e.RN_GrupoLectores; RN_EsCompartida = (& $bool $e.RN_EsCompartida); RN_Activa = (& $bool $e.RN_Activa) }
}
# Gerencias
$ixGer = Get-RNIndicePorTitulo 'Gerencias'
foreach ($g in (& $leer 'gerencias.csv')) {
    if (-not $ixEnt.ContainsKey($g.Entidad)) { Write-RNLog "Gerencia $($g.Title): entidad '$($g.Entidad)' inexistente" 'ERROR'; continue }
    if ($g.RN_Codigo -notmatch '^[A-Z0-9]{2,6}$') { Write-RNLog "Gerencia $($g.Title): código '$($g.RN_Codigo)' inválido (2-6 mayúsculas/dígitos)" 'ERROR'; continue }
    Set-RNElemento 'Gerencias' $ixGer $g.Title @{ RN_Codigo = $g.RN_Codigo; RN_Entidad = $ixEnt[$g.Entidad];
        RN_EsCorporativa = (& $bool $g.RN_EsCorporativa); RN_GerenteCargo = $g.RN_GerenteCargo; RN_Activa = (& $bool $g.RN_Activa) }
}
# Procesos
$ixPro = Get-RNIndicePorTitulo 'Procesos'
foreach ($p in (& $leer 'procesos.csv')) {
    if (-not $ixGer.ContainsKey($p.Gerencia)) { Write-RNLog "Proceso $($p.Title): gerencia '$($p.Gerencia)' inexistente" 'ERROR'; continue }
    Set-RNElemento 'Procesos' $ixPro $p.Title @{ RN_Codigo = $p.RN_Codigo; RN_Gerencia = $ixGer[$p.Gerencia]; RN_Entidad = $ixEnt[$p.Entidad];
        RN_EsCritico = (& $bool $p.RN_EsCritico); RN_Activa = (& $bool $p.RN_Activa) }
}
# Cargos (pasada 1: datos; pasada 2: Jefatura)
$ixCar = Get-RNIndicePorTitulo 'Cargos'
$cargos = & $leer 'cargos.csv'
foreach ($c in $cargos) {
    if (-not $ixGer.ContainsKey($c.Gerencia)) { Write-RNLog "Cargo $($c.Title): gerencia '$($c.Gerencia)' inexistente" 'ERROR'; continue }
    $v = @{ RN_Gerencia = $ixGer[$c.Gerencia]; RN_Entidad = $ixEnt[$c.Entidad]; RN_PuedeSerDueno = (& $bool $c.RN_PuedeSerDueno) }
    if ($c.TitularUPN -and $c.TitularUPN -notlike 'AJUSTAR*') { $v.RN_Titular = $c.TitularUPN; $v.RN_EstadoTitular = 'Vigente' } else { $v.RN_EstadoTitular = 'Vacante' }
    if ($c.SubroganteUPN) { $v.RN_Subrogante = $c.SubroganteUPN }
    Set-RNElemento 'Cargos' $ixCar $c.Title $v
}
foreach ($c in $cargos | Where-Object { $_.Jefatura }) {
    if ($ixCar.ContainsKey($c.Jefatura)) { Set-PnPListItem -List 'Cargos' -Identity $ixCar[$c.Title] -Values @{ RN_Jefatura = $ixCar[$c.Jefatura] } | Out-Null }
    else { Write-RNLog "Cargo $($c.Title): jefatura '$($c.Jefatura)' inexistente" 'ADVERTENCIA' }
}
# Terceros
$ixTer = Get-RNIndicePorTitulo 'Terceros'
foreach ($t in (& $leer 'terceros.csv')) {
    Set-RNElemento 'Terceros' $ixTer $t.Title @{ RN_RUT = $t.RN_RUT; RN_NumeroContrato = $t.RN_NumeroContrato; RN_Pais = $t.RN_Pais;
        RN_ExternalizadoSignificativo = $t.RN_ExternalizadoSignificativo; RN_EsEncargadoTratamiento = $t.RN_EsEncargadoTratamiento;
        RN_Entidades = @($t.RN_Entidades -split ',' | ForEach-Object Trim); RN_Activa = (& $bool $t.RN_Activa) }
}
# Parámetros
$ixPar = Get-RNIndicePorTitulo 'Parametros'
foreach ($p in $cfg.Parametros.parametros) {
    if ($ixPar.ContainsKey($p.clave) -and -not $SobrescribirParametros) { Write-RNLog "  = Parametros/$($p.clave) se conserva"; continue }
    Set-RNElemento 'Parametros' $ixPar $p.clave @{ RN_Valor = $p.valor; RN_Tipo = $p.tipo; RN_Descripcion = $p.descripcion; RN_Fuente = $p.fuente }
}
Write-RNLog 'Fin 04-Import-MasterData' 'OK'

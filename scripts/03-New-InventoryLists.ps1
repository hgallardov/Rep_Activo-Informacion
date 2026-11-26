#Requires -Version 7.2
<#
.SYNOPSIS
  Crea las listas, bibliotecas, columnas, índices y vistas de la solución a partir de
  config/catalogo-campos.json (lista Activos, Anexo A) y config/listas-soporte.json (sección 12).
.DESCRIPTION
  Idempotente: crea lo que falta y no borra columnas existentes. Ejecutar en DEV, TEST y PROD.
  - Versionado activado en todas las listas y bibliotecas (RNF-06).
  - Columnas indexadas (Entidad, Gerencia, Estado, Nivel, Dueño, fechas de revisión) para el umbral de 5.000 (RNF-09).
  - Adjuntos deshabilitados en Activos: las evidencias van a la biblioteca Evidencias (RF-12).
  - Vistas cuyo primer filtro usa columnas indexadas.
.PARAMETER Ambiente DEV | TEST | PROD
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('DEV', 'TEST', 'PROD')][string]$Ambiente = 'DEV')

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/RNInventario.Comun.psm1') -Force
Initialize-RNLog -NombreScript '03-New-InventoryLists' | Out-Null
Assert-RNModulo -Nombre 'PnP.PowerShell' -VersionMinima '2.4'

$cfg = Get-RNConfiguracion -Ambiente $Ambiente
Connect-RNSitio -Config $cfg

# Orden de creación: los maestros antes que las listas que los referencian.
$ordenListas = @('Entidades', 'Gerencias', 'Procesos', 'Cargos', 'Terceros', 'Parametros', 'Correlativos',
    'CatalogoRAT', 'ReferenciaCMDB', 'PertenenciaGrupos', 'Activos', 'RelacionesActivos',
    'HistorialClasificacion', 'Revisiones', 'Excepciones')
$listasTecnicas = @('Parametros', 'Correlativos', 'PertenenciaGrupos', 'HistorialClasificacion', 'Revisiones', 'ReferenciaCMDB', 'CatalogoRAT', 'RelacionesActivos')

$definiciones = @{}
foreach ($l in $cfg.Soporte.listas) { $definiciones[$l.nombre] = $l }
$definiciones['Activos'] = [pscustomobject]@{
    nombre = 'Activos'; descripcion = 'Inventario corporativo de activos de información RNSG / RNSV (Anexo A).'
    campos = $cfg.Catalogo.campos
}

function Get-OCrearLista {
    param([string]$Nombre, [string]$Descripcion, [ValidateSet('GenericList', 'DocumentLibrary')][string]$Plantilla = 'GenericList')
    $lista = Get-PnPList -Identity $Nombre -ErrorAction SilentlyContinue
    if (-not $lista) {
        if ($PSCmdlet.ShouldProcess($Nombre, "Crear $Plantilla")) {
            $lista = New-PnPList -Title $Nombre -Template $Plantilla -Url ($(if ($Plantilla -eq 'GenericList') { "Lists/$Nombre" } else { $Nombre })) -OnQuickLaunch:$false
            Write-RNLog "Creada $Plantilla $Nombre" 'OK'
        }
    }
    Set-PnPList -Identity $Nombre -Description $Descripcion -EnableVersioning $true -MajorVersions 500 | Out-Null
    Get-PnPList -Identity $Nombre
}

# 1) Crear todas las listas vacías (permite búsquedas entre ellas y autorreferencias como Cargos.Jefatura)
$idsListas = @{}
foreach ($n in $ordenListas) {
    $l = Get-OCrearLista -Nombre $n -Descripcion $definiciones[$n].descripcion
    $idsListas[$n] = $l.Id
}
foreach ($b in $cfg.Soporte.bibliotecas) {
    $l = Get-OCrearLista -Nombre $b.nombre -Descripcion $b.descripcion -Plantilla DocumentLibrary
    $idsListas[$b.nombre] = $l.Id
}

# 2) Columnas
function Add-RNCampos {
    param([string]$Lista, $Campos)
    $existentes = (Get-PnPField -List $Lista).InternalName
    foreach ($c in $Campos) {
        if ($c.interno -eq 'Title') {
            Set-PnPField -List $Lista -Identity Title -Values @{ Title = $c.nombre; Required = $false; Indexed = $true } | Out-Null
            continue
        }
        if ($existentes -contains $c.interno) { Write-RNLog "  = $Lista.$($c.interno) ya existe"; continue }
        $idLookup = if ($c.tipo -eq 'Lookup') { $idsListas[$c.lookupLista] } else { $null }
        $xml = Get-RNXmlCampo -Campo $c -IdListaLookup $idLookup
        if ($PSCmdlet.ShouldProcess("$Lista.$($c.interno)", 'Agregar columna')) {
            Add-PnPFieldFromXml -List $Lista -FieldXml $xml | Out-Null
            Write-RNLog "  + $Lista.$($c.interno) ($($c.tipo))" 'OK'
        }
    }
}

foreach ($n in $ordenListas) {
    Write-RNLog "Columnas de $n"
    Add-RNCampos -Lista $n -Campos $definiciones[$n].campos
}
foreach ($b in $cfg.Soporte.bibliotecas) {
    if ($b.campos.Count -gt 0) { Add-RNCampos -Lista $b.nombre -Campos $b.campos }
    foreach ($carpeta in $b.carpetas) {
        if (-not (Get-PnPFolder -Url "$($b.nombre)/$carpeta" -ErrorAction SilentlyContinue)) {
            Add-PnPFolder -Name $carpeta -Folder $b.nombre | Out-Null
            Write-RNLog "  + carpeta $($b.nombre)/$carpeta" 'OK'
        }
    }
}

# Título visible de la columna Title en maestros y bitácoras
$titulos = @{ Entidades = 'Nombre'; Gerencias = 'Nombre'; Procesos = 'Nombre'; Cargos = 'Nombre del cargo'; Terceros = 'Razón social';
    Parametros = 'Clave'; Correlativos = 'ENTIDAD-GERENCIA'; HistorialClasificacion = 'Resumen del evento'; Revisiones = 'Revisión';
    Excepciones = 'N° de excepción'; CatalogoRAT = 'ID actividad RAT'; ReferenciaCMDB = 'ID CMDB'; PertenenciaGrupos = 'Clave'; RelacionesActivos = 'Relación' }
foreach ($k in $titulos.Keys) { Set-PnPField -List $k -Identity Title -Values @{ Title = $titulos[$k] } | Out-Null }
Set-PnPField -List 'Excepciones' -Identity Title -Values @{ Required = $false } | Out-Null  # lo genera FL-07

# 3) Ajustes de listas
Set-PnPList -Identity 'Activos' -EnableAttachments $false | Out-Null
foreach ($t in $listasTecnicas) { Set-PnPList -Identity $t -EnableAttachments $false | Out-Null }
Set-PnPList -Identity 'HistorialClasificacion' -EnableVersioning $true -MajorVersions 50 | Out-Null

# 4) Vistas de Activos (primer filtro sobre columnas indexadas, RNF-09)
$colsVista = @('Title', 'RN_Nombre', 'RN_Entidad', 'RN_Gerencia', 'RN_DuenoCargo', 'RN_NivelEfectivo', 'RN_Critico', 'RN_DatosPersonales', 'RN_Estado', 'RN_ProximaRevision', 'RN_AlertasBloqueantes')
$vistas = @(
    @{ Nombre = 'Inventario vigente'; Query = '<Where><Eq><FieldRef Name="RN_Estado"/><Value Type="Choice">Vigente</Value></Eq></Where><OrderBy><FieldRef Name="Title"/></OrderBy>'; Defecto = $true },
    @{ Nombre = 'En validación'; Query = '<Where><Eq><FieldRef Name="RN_Estado"/><Value Type="Choice">En validación</Value></Eq></Where>' },
    @{ Nombre = 'Con alertas bloqueantes'; Query = '<Where><Eq><FieldRef Name="RN_AlertasBloqueantes"/><Value Type="Boolean">1</Value></Eq></Where>' },
    @{ Nombre = 'Revisión en los próximos 30 días'; Query = '<Where><Leq><FieldRef Name="RN_ProximaRevision"/><Value Type="DateTime"><Today OffsetDays="30"/></Value></Leq></Where><OrderBy><FieldRef Name="RN_ProximaRevision"/></OrderBy>' },
    @{ Nombre = 'Críticos'; Query = '<Where><Eq><FieldRef Name="RN_Critico"/><Value Type="Choice">Sí</Value></Eq></Where>' },
    @{ Nombre = 'Con datos personales'; Query = '<Where><Eq><FieldRef Name="RN_DatosPersonales"/><Value Type="Choice">Sí</Value></Eq></Where>' }
)
foreach ($v in $vistas) {
    if (-not (Get-PnPView -List 'Activos' -Identity $v.Nombre -ErrorAction SilentlyContinue)) {
        Add-PnPView -List 'Activos' -Title $v.Nombre -Fields $colsVista -Query $v.Query -RowLimit 100 -Paged -SetAsDefault:([bool]$v.Defecto) | Out-Null
        Write-RNLog "  + vista Activos/$($v.Nombre)" 'OK'
    }
}

# 5) Validación final: número de índices (máx. 20 por lista) y columnas de búsqueda (umbral 12 por consulta)
$camposActivos = Get-PnPField -List 'Activos'
$indexados = ($camposActivos | Where-Object { $_.Indexed }).Count
$busquedas = ($camposActivos | Where-Object { $_.TypeAsString -in 'Lookup', 'LookupMulti', 'User', 'UserMulti' -and -not $_.FromBaseType }).Count
Write-RNLog "Activos: $indexados columnas indexadas (máx. 20); $busquedas columnas de búsqueda/persona propias (+Autor/Editor, umbral 12)"
if ($indexados -gt 20) { Write-RNLog 'Se superó el máximo de 20 índices' 'ERROR' }

$idsListas.GetEnumerator() | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Lista = $_.Name; Id = $_.Value } } |
    Export-Csv -Path (Join-Path (Get-RNRutaRepositorio) "logs/ids-listas-$Ambiente.csv") -Delimiter ';' -Encoding utf8 -NoTypeInformation
Write-RNLog 'Fin 03-New-InventoryLists. Los GUID de listas quedaron en logs/ids-listas-<AMBIENTE>.csv para las variables de entorno de la solución.' 'OK'

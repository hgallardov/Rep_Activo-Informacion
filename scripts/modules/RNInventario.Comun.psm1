#Requires -Version 7.2
<#
.SYNOPSIS
  Funciones comunes de los scripts de despliegue de la Solución de Inventario y Clasificación de Activos (ER[ZZ].GR_1.0(2026)).
.NOTES
  Requiere PnP.PowerShell 2.x o superior (PowerShell 7). No almacena credenciales: la conexión es interactiva
  con la app de Entra ID registrada por TI (parámetro pnp.clientId de solution.config.json).
#>

Set-StrictMode -Version Latest

$script:RaizRepositorio = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ArchivoLog = $null

function Get-RNRutaRepositorio { $script:RaizRepositorio }

function Initialize-RNLog {
    param([Parameter(Mandatory)][string]$NombreScript)
    $dir = Join-Path $script:RaizRepositorio 'logs'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $script:ArchivoLog = Join-Path $dir ("{0}_{1:yyyyMMdd_HHmmss}.log" -f $NombreScript, (Get-Date))
    Write-RNLog "Inicio $NombreScript – usuario $([Environment]::UserName) – equipo $([Environment]::MachineName)"
    $script:ArchivoLog
}

function Write-RNLog {
    param(
        [Parameter(Mandatory)][string]$Mensaje,
        [ValidateSet('INFO', 'OK', 'ADVERTENCIA', 'ERROR')][string]$Nivel = 'INFO'
    )
    $linea = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Nivel, $Mensaje
    $color = @{ INFO = 'Gray'; OK = 'Green'; ADVERTENCIA = 'Yellow'; ERROR = 'Red' }[$Nivel]
    Write-Host $linea -ForegroundColor $color
    if ($script:ArchivoLog) { Add-Content -Path $script:ArchivoLog -Value $linea -Encoding utf8 }
}

function Get-RNConfiguracion {
    <# Lee solution.config[.AMBIENTE].json y los JSON de definición. #>
    param([string]$Ambiente)
    $cfgDir = Join-Path $script:RaizRepositorio 'config'
    $archivo = if ($Ambiente) { Join-Path $cfgDir "solution.config.$Ambiente.json" } else { Join-Path $cfgDir 'solution.config.json' }
    if (-not (Test-Path $archivo)) {
        Write-RNLog "No existe $archivo; se usa solution.config.json" 'ADVERTENCIA'
        $archivo = Join-Path $cfgDir 'solution.config.json'
    }
    [pscustomobject]@{
        Solucion   = Get-Content $archivo -Raw -Encoding utf8 | ConvertFrom-Json
        Catalogo   = Get-Content (Join-Path $cfgDir 'catalogo-campos.json') -Raw -Encoding utf8 | ConvertFrom-Json
        Soporte    = Get-Content (Join-Path $cfgDir 'listas-soporte.json') -Raw -Encoding utf8 | ConvertFrom-Json
        Parametros = Get-Content (Join-Path $cfgDir 'parametros.json') -Raw -Encoding utf8 | ConvertFrom-Json
        DirMaestros = Join-Path $cfgDir 'maestros'
    }
}

function Connect-RNSitio {
    param([Parameter(Mandatory)]$Config, [string]$Url)
    $destino = if ($Url) { $Url } else { $Config.Solucion.sitio.url }
    Write-RNLog "Conectando a $destino"
    Connect-PnPOnline -Url $destino -Interactive -ClientId $Config.Solucion.pnp.clientId -Tenant $Config.Solucion.tenant.tenantId
}

function Assert-RNModulo {
    param([Parameter(Mandatory)][string]$Nombre, [string]$VersionMinima = '0.0')
    $m = Get-Module -ListAvailable -Name $Nombre | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $m -or $m.Version -lt [version]$VersionMinima) {
        throw "Falta el módulo $Nombre (>= $VersionMinima). Instale con: Install-Module $Nombre -Scope CurrentUser"
    }
}

function ConvertTo-RNXmlSeguro {
    param([string]$Texto)
    [System.Security.SecurityElement]::Escape($Texto)
}

function Get-RNXmlCampo {
    <#
    .SYNOPSIS Construye el CAML <Field> de una columna definida en los JSON de configuración.
    .PARAMETER Campo   Objeto campo (interno, nombre, tipo, opciones, lookupLista, default...).
    .PARAMETER IdListaLookup  GUID de la lista de búsqueda, si aplica.
    #>
    param([Parameter(Mandatory)]$Campo, [guid]$IdListaLookup)
    $n = ConvertTo-RNXmlSeguro $Campo.interno
    $d = ConvertTo-RNXmlSeguro $Campo.nombre
    $desc = if ($Campo.PSObject.Properties['nota']) { ConvertTo-RNXmlSeguro $Campo.nota } else { '' }
    $indexado = if ($Campo.PSObject.Properties['indexado'] -and $Campo.indexado) { ' Indexed="TRUE"' } else { '' }
    $comun = "Name=`"$n`" StaticName=`"$n`" DisplayName=`"$d`" Description=`"$desc`" Group=`"SGSI Inventario`"$indexado"
    $default = if ($Campo.PSObject.Properties['default']) { "<Default>$(ConvertTo-RNXmlSeguro $Campo.default)</Default>" } else { '' }
    $opciones = if ($Campo.PSObject.Properties['opciones']) {
        '<CHOICES>' + (($Campo.opciones | ForEach-Object { "<CHOICE>$(ConvertTo-RNXmlSeguro $_)</CHOICE>" }) -join '') + '</CHOICES>'
    } else { '' }
    switch ($Campo.tipo) {
        'Text'        { "<Field Type=`"Text`" $comun MaxLength=`"255`" />" }
        'Note'        { "<Field Type=`"Note`" $comun NumLines=`"6`" RichText=`"FALSE`" UnlimitedLengthInDocumentLibrary=`"TRUE`" />" }
        'Number'      { "<Field Type=`"Number`" $comun Decimals=`"0`" />" }
        'DateTime'    { "<Field Type=`"DateTime`" $comun Format=`"DateOnly`" FriendlyDisplayFormat=`"Disabled`" />" }
        'Boolean'     { "<Field Type=`"Boolean`" $comun><Default>0</Default></Field>" }
        'Choice'      { "<Field Type=`"Choice`" $comun Format=`"Dropdown`" FillInChoice=`"FALSE`">$default$opciones</Field>" }
        'MultiChoice' { "<Field Type=`"MultiChoice`" $comun FillInChoice=`"FALSE`">$opciones</Field>" }
        'User'        { "<Field Type=`"User`" $comun UserSelectionMode=`"PeopleOnly`" UserSelectionScope=`"0`" />" }
        'UserMulti'   { "<Field Type=`"UserMulti`" $comun Mult=`"TRUE`" UserSelectionMode=`"PeopleOnly`" UserSelectionScope=`"0`" />" }
        'Lookup' {
            if (-not $IdListaLookup) { throw "Falta IdListaLookup para $($Campo.interno)" }
            "<Field Type=`"Lookup`" $comun List=`"{$IdListaLookup}`" ShowField=`"$($Campo.lookupCampo)`" RelationshipDeleteBehavior=`"None`" />"
        }
        default { throw "Tipo no soportado: $($Campo.tipo) ($($Campo.interno))" }
    }
}

Export-ModuleMember -Function *-RN*

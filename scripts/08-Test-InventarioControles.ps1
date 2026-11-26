#Requires -Version 7.2
<#
.SYNOPSIS
  Pruebas de auditoría asistidas por computador (CAAT) sobre el inventario: verificación independiente de los controles
  de la solución. Pensado para el CISO (monitoreo de primera/segunda línea) y para Auditoría Interna (tercera línea, solo lectura).
.DESCRIPTION
  Ejecuta, sobre la población completa (no muestras), los siguientes controles y genera un papel de trabajo Excel:
   C01 Unicidad y formato del ID (RN-01, RF-07)
   C02 Activos sin permisos únicos – exposición a toda la lista (RNF-03, CA-02)
   C03 Permisos reales distintos a los esperados por entidad/gerencia (sección 13)       [-RevisarPermisos]
   C04 Activos Vigentes con alertas bloqueantes recalculadas (RN-09)
   C05 Nivel asignado inferior al mínimo por datos personales/sensibles/terceros (RN-02, RN-08)
   C06 Revisiones integrales y de accesos vencidas (RN-04, RN-05)
   C07 Vigentes sin validación CISO, o con datos personales sin validación DPO (RF-23)
   C08 Segregación: declaración por quien no es titular/subrogante; validación CISO por quien declaró (RF-26, NG 5)
   C09 Activos cuyo cargo Dueño está vacante o con titular inactivo (RF-50)
   C10 Excepciones con vigencia > 12 meses o vencidas aún vigentes (RN-10)
   C11 Elementos con permisos únicos vs umbral de 5.000 (RNF-11)
   C12 Activos Vigentes sin evento de validación en HistorialClasificacion (RF-49)
   C13 Correlativos menores al máximo usado (riesgo de reutilización de ID, RN-01)
   C14 Bajas Confidenciales o por proveedor sin N° de certificado (RN-11, RF-34)
   C15 Datos personales con ID de RAT inexistente o no vigente en CatalogoRAT (RF-39)
   C16 Diferencias entre los campos calculados almacenados y el recálculo independiente (integridad de FL-02)
  Con -Remediar corrige C02/C03 reaplicando permisos (requiere rol CISO; Auditoría ejecuta siempre sin -Remediar).
.EXAMPLE
  ./08-Test-InventarioControles.ps1 -Ambiente PROD -RevisarPermisos
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('DEV', 'TEST', 'PROD')][string]$Ambiente = 'PROD',
    [switch]$RevisarPermisos,
    [switch]$Remediar,
    [datetime]$FechaCorte = (Get-Date)
)

$ErrorActionPreference = 'Stop'
foreach ($m in 'Comun', 'Reglas', 'Permisos') { Import-Module (Join-Path $PSScriptRoot "modules/RNInventario.$m.psm1") -Force }
Initialize-RNLog -NombreScript '08-Test-InventarioControles' | Out-Null
Assert-RNModulo -Nombre 'ImportExcel' -VersionMinima '7.8'
$cfg = Get-RNConfiguracion -Ambiente $Ambiente
Connect-RNSitio -Config $cfg

$par = Get-RNParametrosSitio
$P = Get-RNParametrosReglas
$P.FREC_REVISION_MESES = [int]$par['FREC_REVISION_MESES']; $P.FREC_REVISION_CRITICO_MESES = [int]$par['FREC_REVISION_CRITICO_MESES']
$P.FREC_REVISION_ACCESOS_MESES = [int]$par['FREC_REVISION_ACCESOS_MESES']
$P.NIVEL_MIN_DATOS_PERSONALES = $par['NIVEL_MIN_DATOS_PERSONALES']; $P.NIVEL_MIN_DATOS_SENSIBLES = $par['NIVEL_MIN_DATOS_SENSIBLES']

Write-RNLog 'Extrayendo población…'
$activos = @(Get-PnPListItem -List 'Activos' -PageSize 2000)
$cargos = @{}; Get-PnPListItem -List 'Cargos' -PageSize 2000 | ForEach-Object { $cargos[$_.Id] = $_ }
$historial = @(Get-PnPListItem -List 'HistorialClasificacion' -PageSize 2000 -Fields 'RN_IdActivoTexto', 'RN_TipoEvento', 'RN_Usuario', 'RN_FechaEvento')
$excepciones = @(Get-PnPListItem -List 'Excepciones' -PageSize 2000)
$correlativos = @(Get-PnPListItem -List 'Correlativos' -PageSize 2000)
$rat = @{}; Get-PnPListItem -List 'CatalogoRAT' -PageSize 5000 | ForEach-Object { $rat[$_['Title']] = [bool]$_['RN_Vigente'] }
Write-RNLog "Población: $($activos.Count) activos, $($historial.Count) eventos, $($excepciones.Count) excepciones"

$h = [System.Collections.Generic.List[object]]::new()
function Add-H { param($Control, $Id, $Detalle, $Severidad = 'Media') $h.Add([pscustomobject]@{ Control = $Control; ID = $Id; Severidad = $Severidad; Detalle = $Detalle }) }
$lv = { param($v) if ($v -is [Microsoft.SharePoint.Client.FieldLookupValue]) { $v.LookupValue } else { $v } }

function ConvertTo-RNActivo { param($it)
    [pscustomobject]@{
        Entidad = & $lv $it['RN_Entidad']; Nombre = $it['RN_Nombre']; Descripcion = $it['RN_Descripcion']; Categoria = $it['RN_Categoria']
        Proceso = & $lv $it['RN_Proceso']; Gerencia = & $lv $it['RN_Gerencia']; GerenciaContraparte = & $lv $it['RN_GerenciaContraparte']
        DuenoCargo = & $lv $it['RN_DuenoCargo']; Formato = $it['RN_Formato']; Ubicacion = $it['RN_Ubicacion']; TipoAlojamiento = $it['RN_TipoAlojamiento']
        Pais = $it['RN_PaisProcesamiento']; Confidencialidad = $it['RN_Confidencialidad']; Integridad = $it['RN_Integridad']; Disponibilidad = $it['RN_Disponibilidad']
        ConfiadaTerceros = $it['RN_ConfiadaTerceros']; NivelAcordadoTerceros = $it['RN_NivelAcordadoTerceros']; Nivel = $it['RN_Nivel']
        DatosPersonales = $it['RN_DatosPersonales']; DatosSensibles = $it['RN_DatosSensibles']; IdRAT = $it['RN_IdRAT']
        TransferenciaInternacional = $it['RN_TransferenciaInternacional']; Tercero = & $lv $it['RN_Tercero']; ReglasUso = $it['RN_ReglasUso']
        CargosAutorizados = $it['RN_CargosAutorizados']; TercerosAutorizados = $it['RN_TercerosAutorizados']; PeriodoRetencion = $it['RN_PeriodoRetencion']
        FundamentoRetencion = $it['RN_FundamentoRetencion']; IdCMDB = $it['RN_IdCMDB']; IdRiesgo = $it['RN_IdRiesgo']; FechaAlta = $it['RN_FechaAlta']
        FechaUltimaRevision = $it['RN_FechaUltimaRevision']; FechaRevisionAccesos = $it['RN_FechaRevisionAccesos'] }
}

# C01 ------------------------------------------------------------------------------------------------
$activos | Group-Object { $_['Title'] } | Where-Object { $_.Count -gt 1 -and $_.Name } | ForEach-Object { Add-H 'C01' $_.Name "ID duplicado en $($_.Count) elementos" 'Alta' }
$activos | Where-Object { $_['Title'] -notmatch '^AI-(RNSG|RNSV|AMBAS)-[A-Z0-9]{2,6}-\d{5}$' } | ForEach-Object { Add-H 'C01' "Id=$($_.Id)" "ID con formato inválido: '$($_['Title'])'" 'Alta' }

# C02 / C03 / C11 ------------------------------------------------------------------------------------
$listaAct = Get-PnPList -Identity 'Activos'
$unicos = 0
foreach ($it in $activos) {
    $li = $listaAct.GetItemById($it.Id)
    if (Get-PnPProperty -ClientObject $li -Property HasUniqueRoleAssignments) { $unicos++ } else {
        Add-H 'C02' $it['Title'] 'Hereda permisos de la lista (visible para todos los que acceden a la lista)' 'Alta'
        if ($Remediar -and $PSCmdlet.ShouldProcess($it['Title'], 'Reaplicar permisos')) { Set-RNPermisosActivo -IdElemento $it.Id -Parametros $par }
        continue
    }
    if ($RevisarPermisos) {
        $esp = Get-RNPermisosEsperados -Elemento $it -Parametros $par
        $real = Get-RNPermisosReales -IdElemento $it.Id
        $svcLogin = $par['CUENTA_SERVICIO_UPN']
        $kEsp = @($esp | ForEach-Object { "$($_.PrincipalId):$($_.Rol)" })
        $kReal = @($real.Asignaciones | Where-Object { $_.Principal -notlike "*$svcLogin*" -and $_.NombreRol -ne 'Acceso limitado' -and $_.NombreRol -ne 'Limited Access' } | ForEach-Object { "$($_.PrincipalId):$($_.Rol)" })
        $exceso = $kReal | Where-Object { $_ -notin $kEsp }; $falta = $kEsp | Where-Object { $_ -notin $kReal }
        if ($exceso -or $falta) {
            Add-H 'C03' $it['Title'] ("Exceso: [{0}] Falta: [{1}]" -f ($exceso -join ', '), ($falta -join ', ')) $(if ($exceso) { 'Alta' } else { 'Media' })
            if ($Remediar -and $PSCmdlet.ShouldProcess($it['Title'], 'Reaplicar permisos')) { Set-RNPermisosActivo -IdElemento $it.Id -Parametros $par }
        }
    }
}
$umbral = [int]($par['UMBRAL_PERMISOS_UNICOS_ALERTA'] ?? 4000)
$totalUnicos = $unicos + $excepciones.Count
if ($totalUnicos -ge $umbral) { Add-H 'C11' 'Lista Activos + Excepciones' "Elementos con permisos únicos: $totalUnicos (umbral de alerta $umbral; límite recomendado 5.000)" 'Alta' }

# C04-C09, C12, C14-C16 por activo -------------------------------------------------------------------
$eventos = $historial | Group-Object { $_['RN_IdActivoTexto'] } -AsHashTable -AsString
foreach ($it in $activos) {
    $id = $it['Title']; $estado = $it['RN_Estado']; $a = ConvertTo-RNActivo $it
    $alertas = Get-RNAlertas -A $a -P $P -Hoy $FechaCorte
    $bloq = @($alertas | Where-Object Bloqueante)
    if ($estado -eq 'Vigente' -and $bloq) { Add-H 'C04' $id ("Vigente con bloqueantes: " + (($bloq | ForEach-Object Codigo) -join ', ')) 'Alta' }
    if ($bloq | Where-Object Codigo -eq 'A04') { Add-H 'C05' $id ($bloq | Where-Object Codigo -eq 'A04').Mensaje 'Alta' }
    if ($estado -in 'Vigente', 'En revisión') {
        foreach ($b in $alertas | Where-Object Codigo -in 'B04', 'B05') { Add-H 'C06' $id $b.Mensaje 'Media' }
        if ($it['RN_ValidacionCISO'] -ne 'Validado') { Add-H 'C07' $id "Vigente con Validación CISO = '$($it['RN_ValidacionCISO'])'" 'Alta' }
        if ($a.DatosPersonales -eq 'Sí' -and $it['RN_ValidacionDPO'] -ne 'Validado') { Add-H 'C07' $id "Datos personales con Validación DPO = '$($it['RN_ValidacionDPO'])'" 'Alta' }
        $ev = if ($eventos -and $eventos.ContainsKey($id)) { $eventos[$id] } else { @() }
        if (-not ($ev | Where-Object { $_['RN_TipoEvento'] -eq 'Validación CISO' })) { Add-H 'C12' $id 'Sin evento de Validación CISO en el historial' 'Media' }
        $declara = ($ev | Where-Object { $_['RN_TipoEvento'] -eq 'Declaración' } | Sort-Object { $_['RN_FechaEvento'] } | Select-Object -Last 1)
        $valida = ($ev | Where-Object { $_['RN_TipoEvento'] -eq 'Validación CISO' } | Sort-Object { $_['RN_FechaEvento'] } | Select-Object -Last 1)
        if ($declara -and $valida -and $declara['RN_Usuario'] -and $declara['RN_Usuario'] -eq $valida['RN_Usuario']) { Add-H 'C08' $id "Declaró y validó la misma persona ($($declara['RN_Usuario']))" 'Alta' }
    }
    $cargo = if ($it['RN_DuenoCargo']) { $cargos[$it['RN_DuenoCargo'].LookupId] } else { $null }
    if ($cargo) {
        $dec = $it['RN_DeclaradoPor']
        $perm = @($cargo['RN_Titular']?.Email, $cargo['RN_Subrogante']?.Email) | Where-Object { $_ }
        if ($dec -and ($perm -notcontains $dec)) { Add-H 'C08' $id "Declarado por $dec, que no es titular ni subrogante del cargo Dueño" 'Alta' }
        if ($cargo['RN_EstadoTitular'] -ne 'Vigente' -and $estado -ne 'Dado de baja') { Add-H 'C09' $id "Cargo Dueño '$($cargo['Title'])' en estado $($cargo['RN_EstadoTitular'])" 'Media' }
    }
    if ($estado -eq 'Dado de baja') {
        $exigeCert = ((Get-RNNivelEfectivo $a.Nivel) -eq 'Confidencial') -or [bool]$it['RN_BajaPorProveedor']
        if ($exigeCert -and -not $it['RN_BajaNumeroCertificado']) { Add-H 'C14' $id 'Baja sin N° de certificado de destrucción' 'Alta' }
    }
    if ($a.DatosPersonales -eq 'Sí' -and $a.IdRAT -and $rat.Count -gt 0 -and -not $rat[$a.IdRAT]) { Add-H 'C15' $id "RAT '$($a.IdRAT)' inexistente o no vigente en CatalogoRAT" 'Media' }
    # C16: recálculo independiente vs valores almacenados por FL-02
    $critCalc = if (Test-RNCritico $a) { 'Sí' } else { 'No' }
    if ($it['RN_Critico'] -and $it['RN_Critico'] -ne $critCalc) { Add-H 'C16' $id "Crítico almacenado '$($it['RN_Critico'])' ≠ recalculado '$critCalc'" 'Media' }
    $minCalc = Get-RNNivelMinimo $a $P
    if ($it['RN_NivelMinimo'] -and $it['RN_NivelMinimo'] -ne $minCalc) { Add-H 'C16' $id "Nivel mínimo almacenado '$($it['RN_NivelMinimo'])' ≠ recalculado '$minCalc'" 'Media' }
    $prCalc = Get-RNProximaRevision $a $P
    if ($prCalc -and $it['RN_ProximaRevision'] -and ([datetime]$it['RN_ProximaRevision']).Date -ne $prCalc.Date) { Add-H 'C16' $id "Próxima revisión almacenada $(([datetime]$it['RN_ProximaRevision']).ToString('yyyy-MM-dd')) ≠ recalculada $($prCalc.ToString('yyyy-MM-dd'))" 'Media' }
}

# C10 ------------------------------------------------------------------------------------------------
$maxMeses = [int]($par['EXCEPCION_MAX_MESES'] ?? 12)
foreach ($e in $excepciones) {
    $ini = $e['RN_FechaInicio']; $fin = $e['RN_FechaFin']
    if ($ini -and $fin -and ([datetime]$fin) -gt ([datetime]$ini).AddMonths($maxMeses)) { Add-H 'C10' $e['Title'] "Vigencia superior a $maxMeses meses" 'Alta' }
    if ($e['RN_EstadoExcepcion'] -eq 'Vigente' -and $fin -and ([datetime]$fin).Date -lt $FechaCorte.Date) { Add-H 'C10' $e['Title'] 'Excepción vencida que sigue en estado Vigente' 'Alta' }
}

# C13 ------------------------------------------------------------------------------------------------
$maxPorClave = @{}
foreach ($it in $activos) { if ($it['Title'] -match '^AI-([A-Z]+)-([A-Z0-9]+)-(\d{5})$') { $k = "$($Matches[1])-$($Matches[2])"; $n = [int]$Matches[3]; if (-not $maxPorClave[$k] -or $n -gt $maxPorClave[$k]) { $maxPorClave[$k] = $n } } }
foreach ($k in $maxPorClave.Keys) {
    $c = $correlativos | Where-Object { $_['Title'] -eq $k }
    if (-not $c) { Add-H 'C13' $k 'Sin registro en Correlativos' 'Alta' }
    elseif ([int]$c['RN_Ultimo'] -lt $maxPorClave[$k]) { Add-H 'C13' $k "Correlativo $($c['RN_Ultimo']) menor al máximo usado $($maxPorClave[$k])" 'Alta' }
}

# Papel de trabajo -----------------------------------------------------------------------------------
$catalogoControles = [ordered]@{
    C01 = 'Unicidad y formato del ID (RN-01, RF-07)'; C02 = 'Activos sin permisos únicos (RNF-03)'; C03 = 'Permisos distintos a los esperados (sección 13)'
    C04 = 'Vigentes con alertas bloqueantes (RN-09)'; C05 = 'Nivel inferior al mínimo (RN-02, RN-08)'; C06 = 'Revisiones vencidas (RN-04, RN-05)'
    C07 = 'Vigentes sin validación CISO/DPO (RF-23)'; C08 = 'Segregación de funciones en declaración/validación (RF-26)'; C09 = 'Cargo Dueño vacante (RF-50)'
    C10 = 'Excepciones fuera de norma (RN-10)'; C11 = 'Umbral de permisos únicos (RNF-11)'; C12 = 'Trazabilidad de validación (RF-49)'
    C13 = 'Correlativos de ID (RN-01)'; C14 = 'Bajas sin certificado (RN-11)'; C15 = 'Vínculo con RAT (RF-39)'; C16 = 'Integridad de campos calculados (FL-02)'
}
$resumen = foreach ($k in $catalogoControles.Keys) {
    $n = @($h | Where-Object Control -eq $k).Count
    $ejecutado = -not ($k -eq 'C03' -and -not $RevisarPermisos)
    [pscustomobject]@{ Control = $k; Descripcion = $catalogoControles[$k]; Poblacion = $activos.Count; Excepciones = $n
        Resultado = if (-not $ejecutado) { 'No ejecutado (use -RevisarPermisos)' } elseif ($n -eq 0) { 'Sin desviaciones' } else { 'Con desviaciones' } }
}
$salida = Join-Path (Get-RNRutaRepositorio) ("logs/CAAT_Inventario_{0}_{1:yyyyMMdd_HHmm}.xlsx" -f $Ambiente, (Get-Date))
[pscustomobject]@{ Ambiente = $Ambiente; FechaCorte = $FechaCorte.ToString('yyyy-MM-dd'); Ejecutor = (Get-PnPWeb -Includes CurrentUser).CurrentUser.Email
    Activos = $activos.Count; PermisosUnicos = $totalUnicos; Remediacion = [bool]$Remediar; Clasificacion = 'RESERVADO' } |
    Export-Excel -Path $salida -WorksheetName 'Encabezado' -AutoSize
$resumen | Export-Excel -Path $salida -WorksheetName 'Resumen' -AutoSize -AutoFilter -FreezeTopRow
$h | Export-Excel -Path $salida -WorksheetName 'Desviaciones' -AutoSize -AutoFilter -FreezeTopRow
Write-RNLog "Desviaciones: $($h.Count). Papel de trabajo: $salida" $(if ($h.Count) { 'ADVERTENCIA' } else { 'OK' })

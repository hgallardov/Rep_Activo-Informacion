#Requires -Version 7.2
<#
.SYNOPSIS
  Reglas de negocio del inventario (sección 9 del ER) en PowerShell.
.DESCRIPTION
  Réplica fiel de la especificación ejecutable tests/reglas/reglas.js (fuente de verdad, con pruebas automatizadas).
  La usan la validación previa de la plantilla de carga (06-Test-PlantillaCarga.ps1) y los controles de auditoría
  (08-Test-InventarioControles.ps1). Cualquier cambio debe replicarse en reglas.js y en la app/flujos.
#>
Set-StrictMode -Version Latest

$script:ParametrosDefecto = @{
    FREC_REVISION_MESES = 12; FREC_REVISION_CRITICO_MESES = 6; FREC_REVISION_ACCESOS_MESES = 6
    NIVELES_CON_REVISION_ACCESOS = @('Confidencial', 'Reservado')
    NIVEL_MIN_DATOS_PERSONALES = 'Reservado'; NIVEL_MIN_DATOS_SENSIBLES = 'Confidencial'; NIVEL_POR_DEFECTO = 'Confidencial'
    ORDEN_NIVELES = @{ 'Pública' = 1; 'Uso Interno' = 2; 'Reservado' = 3; 'Confidencial' = 4 }
    CATEGORIAS_TECNOLOGICAS = @('Software / aplicación', 'Hardware / equipamiento', 'Infraestructura de comunicaciones', 'Servicio (TI o de tercero)')
    ALOJAMIENTOS_EXTERNOS = @('Nube pública – SaaS', 'Nube pública – IaaS / PaaS', 'Proveedor (hosting / outsourcing)', 'Dependencias físicas de tercero')
    EXCEPCION_MAX_MESES = 12
}

function Get-RNParametrosReglas { $script:ParametrosDefecto.Clone() }

function Test-RNVacio { param($Valor) return ($null -eq $Valor) -or ([string]::IsNullOrWhiteSpace([string]$Valor)) }

function Get-RNOrdenNivel { param([string]$Nivel, [hashtable]$P = $script:ParametrosDefecto)
    if ($Nivel -and $P.ORDEN_NIVELES.ContainsKey($Nivel)) { $P.ORDEN_NIVELES[$Nivel] } else { 0 } }

function Get-RNNivelMasAlto { param([string[]]$Niveles, [hashtable]$P = $script:ParametrosDefecto)
    $max = 'Pública'
    foreach ($n in $Niveles) { if (-not (Test-RNVacio $n) -and (Get-RNOrdenNivel $n $P) -gt (Get-RNOrdenNivel $max $P)) { $max = $n } }
    $max }

function Test-RNCritico { param($A) @($A.Confidencialidad, $A.Integridad, $A.Disponibilidad) -contains 'Alta' }

function Get-RNNivelEfectivo { param([string]$Nivel, [hashtable]$P = $script:ParametrosDefecto)
    if (Test-RNVacio $Nivel) { $P.NIVEL_POR_DEFECTO } else { $Nivel } }

function Get-RNNivelMinimo {
    param($A, [hashtable]$P = $script:ParametrosDefecto)
    $c = [System.Collections.Generic.List[string]]::new(); $c.Add('Pública')
    if ($A.DatosPersonales -eq 'Sí') { $c.Add($P.NIVEL_MIN_DATOS_PERSONALES) }
    if ($A.DatosSensibles -eq 'Sí') { $c.Add($P.NIVEL_MIN_DATOS_SENSIBLES) }
    if ($A.ConfiadaTerceros -eq 'Sí' -and -not (Test-RNVacio $A.NivelAcordadoTerceros)) { $c.Add($A.NivelAcordadoTerceros) }
    Get-RNNivelMasAlto -Niveles $c -P $P
}

function Get-RNMesesRevisionIntegral { param($A, [hashtable]$P = $script:ParametrosDefecto)
    if ((Test-RNCritico $A) -or $A.DatosPersonales -eq 'Sí') { $P.FREC_REVISION_CRITICO_MESES } else { $P.FREC_REVISION_MESES } }

function Get-RNProximaRevision { param($A, [hashtable]$P = $script:ParametrosDefecto)
    $base = if ($A.FechaUltimaRevision) { $A.FechaUltimaRevision } else { $A.FechaAlta }
    if (-not $base) { return $null }
    ([datetime]$base).AddMonths((Get-RNMesesRevisionIntegral $A $P)) }

function Get-RNProximaRevisionAccesos { param($A, [hashtable]$P = $script:ParametrosDefecto)
    if ($P.NIVELES_CON_REVISION_ACCESOS -notcontains (Get-RNNivelEfectivo $A.Nivel $P)) { return $null }
    $base = @($A.FechaRevisionAccesos, $A.FechaUltimaRevision, $A.FechaAlta) | Where-Object { $_ } | Select-Object -First 1
    if (-not $base) { return $null }
    ([datetime]$base).AddMonths($P.FREC_REVISION_ACCESOS_MESES) }

function Get-RNAlertas {
    <# Devuelve objetos @{Codigo; Mensaje; Bloqueante}. Mismos códigos que reglas.js. #>
    param($A, [hashtable]$P = $script:ParametrosDefecto, [datetime]$Hoy = (Get-Date))
    $r = [System.Collections.Generic.List[object]]::new()
    $add = { param($c, $m, $b) $r.Add([pscustomobject]@{ Codigo = $c; Mensaje = $m; Bloqueante = $b }) }
    $nivel = $A.Nivel; $minimo = Get-RNNivelMinimo $A $P
    if (Test-RNVacio $A.DuenoCargo) { & $add 'A01' 'Sin Dueño (cargo) asignado' $true }
    if ((Test-RNVacio $A.Confidencialidad) -or (Test-RNVacio $A.Integridad) -or (Test-RNVacio $A.Disponibilidad)) { & $add 'A02' 'Valoración C-I-D incompleta' $true }
    if (Test-RNVacio $nivel) { & $add 'A03' 'Sin nivel de clasificación (se trata como Confidencial)' $true }
    elseif ((Get-RNOrdenNivel $nivel $P) -lt (Get-RNOrdenNivel $minimo $P)) { & $add 'A04' "Nivel asignado ($nivel) inferior al mínimo exigido ($minimo)" $true }
    if ($A.DatosPersonales -eq 'Sí' -and (Test-RNVacio $A.IdRAT)) { & $add 'A05' 'Datos personales sin actividad del RAT vinculada' $true }
    if ($nivel -in 'Confidencial', 'Reservado' -and (Test-RNVacio $A.CargosAutorizados)) { & $add 'A06' "Nivel $nivel sin lista de cargos autorizados" $true }
    if ($nivel -eq 'Reservado' -and -not (Test-RNVacio $A.Tercero) -and (Test-RNVacio $A.TercerosAutorizados)) { & $add 'A07' 'Reservado con tercero sin lista de terceros autorizados' $true }
    if (Test-RNVacio $A.PeriodoRetencion) { & $add 'A08' 'Sin período de retención' $true }
    if (Test-RNVacio $A.Entidad) { & $add 'A09' 'Sin entidad' $true }
    if ($A.Entidad -eq 'Ambas' -and (Test-RNVacio $A.GerenciaContraparte)) { & $add 'A10' 'Activo compartido sin gerencia contraparte' $true }
    $oblig = 'Nombre', 'Descripcion', 'Categoria', 'Proceso', 'Gerencia', 'Formato', 'Ubicacion', 'ConfiadaTerceros', 'DatosPersonales', 'DatosSensibles', 'ReglasUso', 'FundamentoRetencion'
    $faltan = $oblig | Where-Object { Test-RNVacio $A.$_ }
    if ($faltan) { & $add 'A11' ("Faltan campos obligatorios de normativa interna: " + ($faltan -join ', ')) $true }
    if ($A.DatosSensibles -eq 'Sí' -and $A.DatosPersonales -ne 'Sí') { & $add 'A12' 'Datos sensibles marcados sin datos personales' $true }

    if ($P.CATEGORIAS_TECNOLOGICAS -contains $A.Categoria -and (Test-RNVacio $A.IdCMDB)) { & $add 'B01' 'Activo tecnológico sin ID de CMDB' $false }
    if ($P.ALOJAMIENTOS_EXTERNOS -contains $A.TipoAlojamiento -and ((Test-RNVacio $A.Tercero) -or (Test-RNVacio $A.Pais))) { & $add 'B02' 'Alojamiento externo sin tercero o país' $false }
    if ((Test-RNCritico $A) -and (Test-RNVacio $A.IdRiesgo)) { & $add 'B03' 'Activo crítico sin ID en matriz de riesgos' $false }
    $pr = Get-RNProximaRevision $A $P
    if ($pr -and $pr.Date -lt $Hoy.Date) { & $add 'B04' 'Revisión integral vencida' $false }
    $pra = Get-RNProximaRevisionAccesos $A $P
    if ($pra -and $pra.Date -lt $Hoy.Date) { & $add 'B05' 'Revisión de accesos vencida' $false }
    if ($A.TransferenciaInternacional -eq 'Sí') { & $add 'B06' 'Transferencia internacional de datos personales (revisión DPO)' $false }
    , $r
}

function New-RNIdActivo { param([string]$CodigoEntidad, [string]$CodigoGerencia, [int]$Correlativo)
    if ((Test-RNVacio $CodigoEntidad) -or (Test-RNVacio $CodigoGerencia)) { throw 'Entidad y gerencia son obligatorias para generar el ID' }
    if ($Correlativo -lt 1) { throw 'Correlativo inválido' }
    'AI-{0}-{1}-{2:D5}' -f $CodigoEntidad.ToUpper(), $CodigoGerencia.ToUpper(), $Correlativo }

Export-ModuleMember -Function Get-RN*, Test-RN*, New-RNIdActivo

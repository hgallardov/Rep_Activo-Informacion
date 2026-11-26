#Requires -Modules Pester
# Pruebas Pester del módulo de reglas en PowerShell: mismos casos que tests/reglas/reglas.test.js.
# Ejecutar: Invoke-Pester ./tests/powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/RNInventario.Reglas.psm1') -Force
    function Get-Base {
        [pscustomobject]@{ Entidad = 'RNSG'; Nombre = 'Base de pólizas'; Descripcion = 'Pólizas'; Categoria = 'Información / datos'; Proceso = 'Suscripción'
            Gerencia = 'Gerencia Técnica'; GerenciaContraparte = $null; DuenoCargo = 'Gerente Técnico'; Formato = 'Digital estructurado'; Ubicacion = 'Core'
            TipoAlojamiento = $null; Pais = $null; Confidencialidad = 'Media'; Integridad = 'Media'; Disponibilidad = 'Media'; ConfiadaTerceros = 'No'
            NivelAcordadoTerceros = $null; Nivel = 'Uso Interno'; DatosPersonales = 'No'; DatosSensibles = 'No'; IdRAT = $null; TransferenciaInternacional = $null
            Tercero = $null; ReglasUso = 'NC Anexo 1'; CargosAutorizados = $null; TercerosAutorizados = $null; PeriodoRetencion = '10 años'
            FundamentoRetencion = 'Norma CMF'; IdCMDB = $null; IdRiesgo = $null; FechaAlta = [datetime]'2026-01-10'; FechaUltimaRevision = $null; FechaRevisionAccesos = $null }
    }
}
Describe 'Reglas de clasificación' {
    It 'activo de referencia sin bloqueantes' { (Get-RNAlertas -A (Get-Base) -Hoy ([datetime]'2026-02-01') | Where-Object Bloqueante).Count | Should -Be 0 }
    It 'CA-01: datos personales exige Reservado' {
        $a = Get-Base; $a.DatosPersonales = 'Sí'; $a.IdRAT = 'RAT-1'
        Get-RNNivelMinimo $a | Should -Be 'Reservado'
        (Get-RNAlertas -A $a).Codigo | Should -Contain 'A04'
    }
    It 'RN-02: sensibles exige Confidencial' { $a = Get-Base; $a.DatosPersonales = 'Sí'; $a.DatosSensibles = 'Sí'; Get-RNNivelMinimo $a | Should -Be 'Confidencial' }
    It 'CA-04: crítico revisado 1-mar vence 1-sep' { $a = Get-Base; $a.Integridad = 'Alta'; $a.FechaUltimaRevision = [datetime]'2027-03-01'; (Get-RNProximaRevision $a).ToString('yyyy-MM-dd') | Should -Be '2027-09-01' }
    It 'CA-05: Confidencial sin cargos autorizados bloquea' { $a = Get-Base; $a.Nivel = 'Confidencial'; (Get-RNAlertas -A $a).Codigo | Should -Contain 'A06' }
    It 'RN-06: sin nivel => Confidencial' { Get-RNNivelEfectivo '' | Should -Be 'Confidencial' }
    It 'RF-07: formato del ID' { New-RNIdActivo -CodigoEntidad 'rnsg' -CodigoGerencia 'gti' -Correlativo 7 | Should -Be 'AI-RNSG-GTI-00007' }
}

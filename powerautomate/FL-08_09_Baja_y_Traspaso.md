# RN-INV FL-08 Baja de activo · FL-09 Traspaso de Dueño o Custodio

## FL-08 Baja de activo

| | |
|---|---|
| Requerimientos | RF-34, RN-11, NG 4.6, CA-08 |
| Disparador | Secundario desde FL-02 (`RN_SolicitudAccion = Dar de baja`). La app captura `RN_BajaMetodo`, `RN_BajaPorProveedor`, `RN_BajaNumeroCertificado`, `RN_BajaFechaEjecucion` |

1. **Autorización del Dueño:** editor = titular/subrogante del cargo Dueño (FL-03 §1.3). Si lo solicitó el Delegado, se envía aprobación al titular (Approvals, *Autorizar baja de <ID>*); sin aprobación no continúa.
2. **Método según nivel (RN-11):** `MetodoExigido = json(outputs('P')?['METODO_BAJA_POR_NIVEL'])?[A?['RN_NivelEfectivo']?['Value']]`. Si `RN_BajaMetodo ≠ MetodoExigido` → rechazar con el método exigido.
3. Primera etapa: `RN_Estado = En baja` (el activo sigue en el inventario, sin revisiones programadas). Aviso a TI / Custodio para ejecutar la eliminación.
4. **Cierre con certificado (CA-08):**
   `ExigeCertificado = or(A?['RN_BajaPorProveedor'], contains(json(outputs('P')?['CERTIFICADO_OBLIGATORIO_NIVELES']), A?['RN_NivelEfectivo']?['Value']))`.
   Si `ExigeCertificado`, se requiere: `RN_BajaNumeroCertificado` no vacío **y** un archivo en `Evidencias` con `RN_IdActivo = ID` y `RN_TipoEvidencia = Certificado de destrucción`. Mientras falte, el activo permanece *En baja* y FL-05 envía recordatorio semanal al Dueño y al Custodio.
5. Cumplido: `RN_Estado = Dado de baja`, `RN_DatosBaja = concat(fecha, ' | ', método, ' | Cert. ', número, ' | ', proveedor/TI)`, `RN_ProximaRevision = null`, `RN_ProximaRevisionAccesos = null`. Se conservan los permisos (la evidencia histórica sigue disponible para Auditoría). El ID **no se reutiliza** (RN-01: el correlativo nunca baja).
6. Historial *Baja*. Notificación a la Gerencia de Personas **solo como aviso** cuando el activo es equipamiento asignado a personas (proceso de devolución fuera de alcance, sección 2).

## FL-09 Traspaso de Dueño o Custodio

| | |
|---|---|
| Requerimientos | RF-33, RN-12, RN-14, NG 4.2 y 4.3, CA-11 |
| Disparador | Secundario desde FL-02 (`RN_SolicitudAccion = Traspasar`, `RN_CargoReceptor` = Id del cargo en `Cargos`, y campo `RN_MotivoCambio`) |

> El cambio de **titular** de un cargo NO es un traspaso: los activos se asocian al cargo y el nuevo titular los ve automáticamente al ser incorporado al grupo de edición de la gerencia (RN-12, CA-11). FL-14 sincroniza `RN_DuenoPersona`.

1. Autorización: editor = titular/subrogante del cargo Dueño actual, o CISO (reasignación administrativa, RF-48; transversales RN-14).
2. `RN_Estado = En traspaso`. Aprobación al **titular del cargo receptor** (*Aceptar la titularidad del activo <ID>*), con copia informativa al CISO. Plazo: `PLAZO_VALIDACION_DIAS`, escalamiento al CISO.
3. Rechazo → `RN_Estado` vuelve al anterior; historial con el comentario.
4. Aceptación → actualizar `RN_DuenoCargo = RN_CargoReceptor` (o `RN_CustodioCargo` si el traspaso es de custodia), `RN_Gerencia` = gerencia del cargo receptor (si cambia), `RN_DuenoPersona`, `RN_CargoReceptor = null`, `RN_Estado = En revisión` (el nuevo Dueño debe declarar la clasificación vigente → FL-03). Ejecutar `FL-01b Reasignar permisos` (cambió la clave de permisos) y mover las evidencias si cambió la gerencia (*SharePoint – Mover archivo*).
5. Historial *Cambio de Dueño* / *Cambio de Custodio* con valor anterior y nuevo.

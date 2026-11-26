// =====================================================================================================
//  App.Formulas – Aplicación canvas "Inventario de Activos" (RN SGSI)
//  Pegar en App > Formulas. Requiere Power Fx con fórmulas con nombre (habilitado por defecto).
//  Las reglas replican tests/reglas/reglas.js. La app aplica las reglas para la EXPERIENCIA DE USUARIO;
//  el control efectivo lo ejercen FL-02/FL-03 en el servidor y los permisos por elemento (RNF-03).
// =====================================================================================================

// ---------- Identidad ----------
UsuarioUPN = Lower(User().Email);

// ---------- Parámetros de negocio (lista Parametros, RNF-17) ----------
Par = ForAll(Parametros, { Clave: ThisRecord.Title, Valor: ThisRecord.RN_Valor });
ParTexto(clave: Text): Text = LookUp(Par, Clave = clave).Valor;
ParNumero(clave: Text): Number = Value(LookUp(Par, Clave = clave).Valor);

CamposEIHabilitados = Lower(ParTexto("CAMPOS_EI_HABILITADOS")) = "true";
NivelMinDatosPersonales = Coalesce(ParTexto("NIVEL_MIN_DATOS_PERSONALES"), "Reservado");
NivelMinDatosSensibles = Coalesce(ParTexto("NIVEL_MIN_DATOS_SENSIBLES"), "Confidencial");
NivelPorDefecto = Coalesce(ParTexto("NIVEL_POR_DEFECTO"), "Confidencial");
MesesRevision = Coalesce(ParNumero("FREC_REVISION_MESES"), 12);
MesesRevisionCritico = Coalesce(ParNumero("FREC_REVISION_CRITICO_MESES"), 6);
MesesRevisionAccesos = Coalesce(ParNumero("FREC_REVISION_ACCESOS_MESES"), 6);
MaxMesesExcepcion = Coalesce(ParNumero("EXCEPCION_MAX_MESES"), 12);
CategoriasTecnologicas = ForAll(ParseJSON(ParTexto("CATEGORIAS_TECNOLOGICAS")), Text(ThisRecord));
AlojamientosExternos = ForAll(ParseJSON(ParTexto("ALOJAMIENTOS_EXTERNOS")), Text(ThisRecord));
ReglasManejo = ParseJSON(ParTexto("REGLAS_MANEJO"));
MetodoBajaPorNivel = ParseJSON(ParTexto("METODO_BAJA_POR_NIVEL"));

// ---------- Niveles (NC 4.1) ----------
Niveles = Table(
    { Nivel: "Pública",      Orden: 1, Color: ColorValue("#2E7D32") },
    { Nivel: "Uso Interno",  Orden: 2, Color: ColorValue("#1565C0") },
    { Nivel: "Reservado",    Orden: 3, Color: ColorValue("#EF6C00") },
    { Nivel: "Confidencial", Orden: 4, Color: ColorValue("#C62828") }
);
OrdenNivel(n: Text): Number = Coalesce(LookUp(Niveles, Nivel = n).Orden, 0);
NombreNivel(o: Number): Text = LookUp(Niveles, Orden = o).Nivel;
ColorNivel(n: Text): Color = Coalesce(LookUp(Niveles, Nivel = n).Color, ColorValue("#757575"));
NivelEfectivo(n: Text): Text = If(IsBlank(n), NivelPorDefecto, n);                         // RN-06

// ---------- Reglas (RN-02, RN-03, RN-04, RN-05, RN-08) ----------
EsCritico(c: Text, i: Text, d: Text): Boolean = "Alta" in [c, i, d];
NivelMinimo(dp: Text, ds: Text, confiada: Text, acordado: Text): Text =
    NombreNivel(Max(
        1,
        If(dp = "Sí", OrdenNivel(NivelMinDatosPersonales), 1),
        If(ds = "Sí", OrdenNivel(NivelMinDatosSensibles), 1),
        If(confiada = "Sí" && !IsBlank(acordado), OrdenNivel(acordado), 1)
    ));
MesesRevisionIntegral(critico: Boolean, dp: Text): Number = If(critico || dp = "Sí", MesesRevisionCritico, MesesRevision);

// ---------- Borrador en edición (lo alimenta el asistente con Set(varB, …)) ----------
// varB es un registro con los mismos nombres internos de la lista Activos; ver Pantallas.md §Asistente.
BorradorCritico = EsCritico(varB.RN_Confidencialidad, varB.RN_Integridad, varB.RN_Disponibilidad);
BorradorNivelMinimo = NivelMinimo(varB.RN_DatosPersonales, varB.RN_DatosSensibles, varB.RN_ConfiadaTerceros, varB.RN_NivelAcordadoTerceros);

// Alertas del borrador: mismos códigos y textos que reglas.js / FL-02b
AlertasBorrador = Filter(
    Table(
        { Codigo: "A01", Paso: 1, Bloqueante: true, Activa: IsBlank(varB.RN_DuenoCargoId), Mensaje: "Sin Dueño (cargo) asignado" },
        { Codigo: "A02", Paso: 3, Bloqueante: true, Activa: IsBlank(varB.RN_Confidencialidad) || IsBlank(varB.RN_Integridad) || IsBlank(varB.RN_Disponibilidad), Mensaje: "Valoración C-I-D incompleta" },
        { Codigo: "A03", Paso: 3, Bloqueante: true, Activa: IsBlank(varB.RN_Nivel), Mensaje: "Sin nivel de clasificación (se trata como Confidencial)" },
        { Codigo: "A04", Paso: 3, Bloqueante: true, Activa: !IsBlank(varB.RN_Nivel) && OrdenNivel(varB.RN_Nivel) < OrdenNivel(BorradorNivelMinimo),
          Mensaje: "Nivel asignado (" & varB.RN_Nivel & ") inferior al mínimo exigido (" & BorradorNivelMinimo & ")" },
        { Codigo: "A05", Paso: 4, Bloqueante: true, Activa: varB.RN_DatosPersonales = "Sí" && IsBlank(varB.RN_IdRAT), Mensaje: "Datos personales sin actividad del RAT vinculada" },
        { Codigo: "A06", Paso: 5, Bloqueante: true, Activa: varB.RN_Nivel in ["Confidencial", "Reservado"] && IsBlank(varB.RN_CargosAutorizados), Mensaje: "Nivel " & varB.RN_Nivel & " sin lista de cargos autorizados" },
        { Codigo: "A07", Paso: 5, Bloqueante: true, Activa: varB.RN_Nivel = "Reservado" && !IsBlank(varB.RN_TerceroId) && IsBlank(varB.RN_TercerosAutorizados), Mensaje: "Reservado con tercero sin lista de terceros autorizados" },
        { Codigo: "A08", Paso: 5, Bloqueante: true, Activa: IsBlank(varB.RN_PeriodoRetencion), Mensaje: "Sin período de retención" },
        { Codigo: "A09", Paso: 1, Bloqueante: true, Activa: IsBlank(varB.RN_EntidadId), Mensaje: "Sin entidad" },
        { Codigo: "A10", Paso: 1, Bloqueante: true, Activa: varB.EntidadCodigo = "AMBAS" && IsBlank(varB.RN_GerenciaContraparteId), Mensaje: "Activo compartido sin gerencia contraparte" },
        { Codigo: "A11", Paso: 0, Bloqueante: true,
          Activa: IsBlank(varB.RN_Nombre) || IsBlank(varB.RN_Descripcion) || IsBlank(varB.RN_Categoria) || IsBlank(varB.RN_ProcesoId) || IsBlank(varB.RN_GerenciaId)
               || IsBlank(varB.RN_Formato) || IsBlank(varB.RN_Ubicacion) || IsBlank(varB.RN_ConfiadaTerceros) || IsBlank(varB.RN_DatosPersonales)
               || IsBlank(varB.RN_DatosSensibles) || IsBlank(varB.RN_ReglasUso) || IsBlank(varB.RN_FundamentoRetencion),
          Mensaje: "Faltan campos obligatorios de normativa interna" },
        { Codigo: "A12", Paso: 4, Bloqueante: true, Activa: varB.RN_DatosSensibles = "Sí" && varB.RN_DatosPersonales <> "Sí", Mensaje: "Datos sensibles marcados sin datos personales" },
        { Codigo: "B01", Paso: 2, Bloqueante: false, Activa: varB.RN_Categoria in CategoriasTecnologicas && IsBlank(varB.RN_IdCMDB), Mensaje: "Activo tecnológico sin ID de CMDB" },
        { Codigo: "B02", Paso: 2, Bloqueante: false, Activa: varB.RN_TipoAlojamiento in AlojamientosExternos && (IsBlank(varB.RN_TerceroId) || IsBlank(varB.RN_PaisProcesamiento)), Mensaje: "Alojamiento externo sin tercero o país" },
        { Codigo: "B06", Paso: 4, Bloqueante: false, Activa: varB.RN_TransferenciaInternacional = "Sí", Mensaje: "Transferencia internacional: será revisada por el DPO" }
    ),
    Activa
);
BorradorTieneBloqueantes = CountRows(Filter(AlertasBorrador, Bloqueante)) > 0;

// ---------- Campos condicionales (RF-09) ----------
MostrarDatosPersonales = varB.RN_DatosPersonales = "Sí";
MostrarTercero = varB.RN_TipoAlojamiento in AlojamientosExternos || varB.RN_ConfiadaTerceros = "Sí";
MostrarCMDB = varB.RN_Categoria in CategoriasTecnologicas;
MostrarContraparte = varB.EntidadCodigo = "AMBAS";
ExigeCargosAutorizados = NivelEfectivo(varB.RN_Nivel) in ["Confidencial", "Reservado"];

// ---------- Permisos de interfaz (solo experiencia de usuario, RNF-03) ----------
// gblEsCISO / gblEsDPO / gblEsRiesgos / gblEsCSI / gblEsAuditoria se calculan en App.OnStart.
PuedeDeclarar(cargoId: Number): Boolean =
    With({ c: LookUp(Cargos, ID = cargoId) }, Lower(c.RN_Titular.Email) = UsuarioUPN || Lower(c.RN_Subrogante.Email) = UsuarioUPN);   // RF-26

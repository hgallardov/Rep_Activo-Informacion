// =====================================================================================================
//  Power Query (M) – Modelo "Tablero SGSI Inventario de Activos"
//  Origen: SharePoint Online List v2.0 (conector estándar). Parámetro: pSitio = URL del sitio.
//  Credencial de actualización programada: cuenta de servicio con lectura (OAuth2). La seguridad la aplica RLS.
// =====================================================================================================

// --- Parámetro ---
pSitio = "https://rentanacional.sharepoint.com/sites/SGSI-InventarioActivos" meta [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]

// --- Función auxiliar: lista con vista "Todos los elementos" (columnas internas) ---
fnLista = (nombre as text) as table =>
    let
        Origen = SharePoint.Tables(pSitio, [Implementation = "2.0", ViewMode = "All"]),
        Lista  = Origen{[Title = nombre]}[Items]
    in
        Lista

// --- Activos (hecho principal) ---
Activos =
    let
        Fuente = fnLista("Activos"),
        Cols = Table.SelectColumns(Fuente, {
            "ID", "Title", "RN_Nombre", "RN_Entidad", "RN_Gerencia", "RN_GerenciaContraparte", "RN_Proceso", "RN_DuenoCargo",
            "RN_Categoria", "RN_TipoAlojamiento", "RN_PaisProcesamiento", "RN_Tercero", "RN_Confidencialidad", "RN_Integridad",
            "RN_Disponibilidad", "RN_Critico", "RN_Nivel", "RN_NivelEfectivo", "RN_NivelMinimo", "RN_DatosPersonales",
            "RN_DatosSensibles", "RN_IdRAT", "RN_TransferenciaInternacional", "RN_ExternalizadoSignificativo", "RN_Estado",
            "RN_ValidacionCISO", "RN_ValidacionDPO", "RN_Alertas", "RN_AlertasBloqueantes", "RN_ProximaRevision",
            "RN_ProximaRevisionAccesos", "RN_FechaAlta", "RN_FechaUltimaRevision", "RN_IdRiesgo", "RN_ExcepcionVigente", "Created", "Modified" }, MissingField.UseNull),
        // Búsquedas y elecciones vienen como registros: extraer el texto
        Txt = (t as table, c as text, campo as text) => Table.TransformColumns(t, {{c, each if _ = null then null else Record.FieldOrDefault(_, campo, null), type text}}),
        T1 = List.Accumulate({"RN_Entidad", "RN_Gerencia", "RN_GerenciaContraparte", "RN_Proceso", "RN_DuenoCargo", "RN_Tercero"}, Cols, (s, c) => Txt(s, c, "Title")),
        Elecciones = {"RN_Categoria", "RN_TipoAlojamiento", "RN_Confidencialidad", "RN_Integridad", "RN_Disponibilidad", "RN_Critico", "RN_Nivel",
                      "RN_NivelEfectivo", "RN_NivelMinimo", "RN_DatosPersonales", "RN_DatosSensibles", "RN_TransferenciaInternacional",
                      "RN_ExternalizadoSignificativo", "RN_Estado", "RN_ValidacionCISO", "RN_ValidacionDPO"},
        T2 = List.Accumulate(Elecciones, T1, (s, c) => Table.TransformColumns(s, {{c, each if _ is record then _[Value] else _, type text}})),
        // RN-06 / RF-20: sin clasificar se reporta como Confidencial aunque FL-02b no haya corrido
        T3 = Table.TransformColumns(T2, {{"RN_NivelEfectivo", each if _ = null or _ = "" then "Confidencial" else _, type text}}),
        T4 = Table.TransformColumnTypes(T3, {{"ID", Int64.Type}, {"RN_AlertasBloqueantes", type logical}, {"RN_ProximaRevision", type date},
                {"RN_ProximaRevisionAccesos", type date}, {"RN_FechaAlta", type date}, {"RN_FechaUltimaRevision", type date}, {"Created", type datetime}, {"Modified", type datetime}}),
        // Código de entidad y gerencia para RLS (desde los maestros)
        ConEnt = Table.NestedJoin(T4, {"RN_Entidad"}, Entidades, {"Entidad"}, "E", JoinKind.LeftOuter),
        ConEnt2 = Table.ExpandTableColumn(ConEnt, "E", {"EntidadCodigo"}),
        ConGer = Table.NestedJoin(ConEnt2, {"RN_Gerencia"}, Gerencias, {"Gerencia"}, "G", JoinKind.LeftOuter),
        ConGer2 = Table.ExpandTableColumn(ConGer, "G", {"GerenciaCodigo"}),
        ConCon = Table.NestedJoin(ConGer2, {"RN_GerenciaContraparte"}, Gerencias, {"Gerencia"}, "GC", JoinKind.LeftOuter),
        Final = Table.RenameColumns(Table.ExpandTableColumn(ConCon, "GC", {"GerenciaCodigo"}, {"ContraparteCodigo"}), {{"Title", "IdActivo"}})
    in
        Final

Entidades = Table.SelectColumns(Table.RenameColumns(fnLista("Entidades"), {{"Title", "Entidad"}, {"RN_Codigo", "EntidadCodigo"}}), {"Entidad", "EntidadCodigo"})

Gerencias = Table.SelectColumns(Table.RenameColumns(fnLista("Gerencias"), {{"Title", "Gerencia"}, {"RN_Codigo", "GerenciaCodigo"}}), {"Gerencia", "GerenciaCodigo"})

Excepciones =
    let
        F = fnLista("Excepciones"),
        S = Table.SelectColumns(F, {"Title", "RN_Activo", "RN_Entidad", "RN_FechaInicio", "RN_FechaFin", "RN_EstadoExcepcion", "RN_EsRenovacion"}, MissingField.UseNull),
        T = Table.TransformColumns(S, {{"RN_Activo", each if _ = null then null else _[Title], type text}, {"RN_EstadoExcepcion", each if _ is record then _[Value] else _, type text}}),
        Ty = Table.TransformColumnTypes(T, {{"RN_FechaInicio", type date}, {"RN_FechaFin", type date}})
    in
        Table.RenameColumns(Ty, {{"Title", "NumeroExcepcion"}, {"RN_Activo", "IdActivo"}})

Revisiones =
    let
        F = fnLista("Revisiones"),
        S = Table.SelectColumns(F, {"RN_IdActivoTexto", "RN_Entidad", "RN_TipoRevision", "RN_Campana", "RN_FechaVencimiento", "RN_EstadoRevision", "RN_FechaCompletada", "RN_AccesosRetirados"}, MissingField.UseNull),
        T = Table.TransformColumns(S, {{"RN_TipoRevision", each if _ is record then _[Value] else _, type text}, {"RN_EstadoRevision", each if _ is record then _[Value] else _, type text}})
    in
        Table.TransformColumnTypes(Table.RenameColumns(T, {{"RN_IdActivoTexto", "IdActivo"}}), {{"RN_FechaVencimiento", type date}, {"RN_FechaCompletada", type date}})

// Alertas normalizadas: una fila por (activo, código) – página "Calidad de datos"
Alertas =
    let
        A = Table.SelectColumns(Activos, {"IdActivo", "RN_Alertas"}),
        Filas = Table.ExpandListColumn(Table.TransformColumns(A, {{"RN_Alertas", each if _ = null then {} else List.Select(Text.Split(_, "#(lf)"), each Text.Trim(_) <> "")}}), "RN_Alertas"),
        NoVacias = Table.SelectRows(Filas, each [RN_Alertas] <> null),
        Cod = Table.AddColumn(NoVacias, "Codigo", each Text.Start([RN_Alertas], 3), type text),
        Bloq = Table.AddColumn(Cod, "Bloqueante", each Text.StartsWith([Codigo], "A"), type logical)
    in
        Table.RenameColumns(Bloq, {{"RN_Alertas", "Alerta"}})

// Pertenencia a grupos (FL-15) – base de RLS
Pertenencia =
    let
        F = fnLista("PertenenciaGrupos"),
        S = Table.SelectColumns(F, {"RN_UPN", "RN_Grupo", "RN_EntidadCodigo", "RN_GerenciaCodigo", "RN_Transversal"}, MissingField.UseNull)
    in
        Table.TransformColumns(Table.TransformColumnTypes(S, {{"RN_Transversal", type logical}}), {{"RN_UPN", Text.Lower, type text}})

Calendario =
    let
        Inicio = #date(2026, 1, 1), Fin = Date.AddYears(Date.From(DateTime.LocalNow()), 2),
        Fechas = List.Dates(Inicio, Duration.Days(Fin - Inicio) + 1, #duration(1, 0, 0, 0)),
        T = Table.FromList(Fechas, Splitter.SplitByNothing(), {"Fecha"}, null, ExtraValues.Error),
        Ty = Table.TransformColumnTypes(T, {{"Fecha", type date}}),
        A = Table.AddColumn(Ty, "Año", each Date.Year([Fecha]), Int64.Type),
        M = Table.AddColumn(A, "Mes", each Date.ToText([Fecha], "yyyy-MM", "es-CL"), type text)
    in
        M

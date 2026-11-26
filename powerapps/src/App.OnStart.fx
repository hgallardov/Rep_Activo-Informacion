// =====================================================================================================
//  App.OnStart – solo lo que no puede ser fórmula con nombre (llamadas a conectores y parámetros de URL)
//  Conectores: SharePoint (sitio SGSI – Inventario de Activos), Office 365 Users, Office 365 Groups,
//              Power Automate (FL-01, FL-07a, FL-10b, FL-16). Todos estándar.
// =====================================================================================================
Concurrent(
    Set(gblPerfil, Office365Users.MyProfileV2()),
    Set(gblEsCISO,      !IsBlank(LookUp(Office365Groups.ListGroupMembers(ParTexto("GRUPO_CISO_ENTRAID")).value, Lower(userPrincipalName) = UsuarioUPN))),
    Set(gblEsDPO,       !IsBlank(LookUp(Office365Groups.ListGroupMembers(ParTexto("GRUPO_DPO_ENTRAID")).value,  Lower(userPrincipalName) = UsuarioUPN))),
    Set(gblEsCSI,       !IsBlank(LookUp(Office365Groups.ListGroupMembers(ParTexto("GRUPO_CSI_ENTRAID")).value,  Lower(userPrincipalName) = UsuarioUPN))),
    // Cargos de los que el usuario es titular o subrogante (para "Mis activos" y para declarar)
    ClearCollect(colMisCargos, Filter(Cargos, RN_Titular.Email = User().Email || RN_Subrogante.Email = User().Email)),
    // Maestros pequeños en memoria (< 2.000 filas): mejora tiempos de carga (RNF-10)
    ClearCollect(colEntidades, Filter(Entidades, RN_Activa)),
    ClearCollect(colGerencias, Filter(Gerencias, RN_Activa)),
    ClearCollect(colProcesos,  Filter(Procesos, RN_Activa)),
    ClearCollect(colTerceros,  Filter(Terceros, RN_Activa))
);
// Delegado de registro: cargos en los que el usuario figura como delegado (D-06)
ClearCollect(colCargosDelegados, Filter(Cargos, User().Email in RN_Delegados.Email));   // no delegable: Cargos < 2.000 filas
Concurrent(
    Set(gblEsRiesgos,   !IsBlank(LookUp(Office365Groups.ListGroupMembers(ParTexto("GRUPO_RIESGOS_ENTRAID")).value,   Lower(userPrincipalName) = UsuarioUPN))),
    Set(gblEsAuditoria, !IsBlank(LookUp(Office365Groups.ListGroupMembers(ParTexto("GRUPO_AUDITORIA_ENTRAID")).value, Lower(userPrincipalName) = UsuarioUPN)))
);

// Enlace profundo desde correos y aprobaciones: ?activoId=123&pantalla=validacion
If(!IsBlank(Param("activoId")),
    Set(gblActivo, LookUp(Activos, ID = Value(Param("activoId"))));
    Navigate(If(Param("pantalla") = "validacion", scrValidacion, scrFicha), ScreenTransition.None)
);

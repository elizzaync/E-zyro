import 'package:shared_preferences/shared_preferences.dart';

/// Singleton de sesión — cargado una vez en el splash y después del login.
/// Usar [AppSession.i] para acceder desde cualquier parte.
class AppSession {
  AppSession._();
  static final AppSession i = AppSession._();

  String _rol = '';
  String _cargo = '';
  List<String> _permisos = [];

  // ── Carga desde SharedPreferences ────────────────────────────────────────

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    i._rol      = (prefs.getString('user_rol') ?? '').toLowerCase().trim();
    i._cargo    = prefs.getString('user_cargo') ?? '';
    i._permisos = prefs.getStringList('user_permisos') ?? [];
  }

  static void clear() {
    i._rol      = '';
    i._cargo    = '';
    i._permisos = [];
  }

  // ── Checks de permisos ────────────────────────────────────────────────────

  /// Permiso absoluto (bypass). Modelo híbrido: lo concede el permiso meta
  /// 'sistema:admin_total' (delegable), no el nombre del rol. Se lee la lista de
  /// permisos DIRECTAMENTE (sin pasar por hasPerm) para no recursar. Se mantiene
  /// el reconocimiento de los nombres históricos como red de seguridad.
  bool get isAdmin {
    if (_permisos.any((e) => e.toLowerCase().trim() == 'sistema:admin_total')) {
      return true;
    }
    final r = _rol.replaceAll(' ', '');
    return r == 'superadmin' || r == 'admin' || r == 'administrador';
  }

  /// Solo SuperAdmin (no Admin): habilita la Auditoría General cross-empresa.
  /// Normaliza espacios para reconocer "Super Admin" además de "SuperAdmin".
  bool get esSuperAdmin => _rol.replaceAll(' ', '') == 'superadmin';

  /// Usuario del Portal Cliente (empresas externas): nunca debe ver el
  /// sistema interno — el login/splash lo enruta a '/portal'.
  bool get esClienteExterno => _rol.replaceAll(' ', '') == 'clienteexterno';

  /// Ruta home según el tipo de cuenta. Única fuente para login/splash.
  String get rutaHome => esClienteExterno ? '/portal' : '/';

  /// true si es admin O tiene el permiso específico en su lista.
  /// Comparación insensible a mayúsculas/acentos de formato: el backend emite
  /// los permisos en minúsculas con formato `modulo:accion`.
  bool hasPerm(String permiso) {
    if (isAdmin) return true;
    final p = permiso.toLowerCase().trim();
    return _permisos.any((e) => e.toLowerCase().trim() == p);
  }

  // ── Atajos para cada módulo ───────────────────────────────────────────────

  bool get canVerAuditoria          => hasPerm('auditoria:ver');
  // Gestión de usuarios (roles, alta, activar/desactivar). Admin por bypass;
  // delegable a otros roles vía el permiso 'usuarios:gestionar'.
  bool get canGestionarUsuarios     => hasPerm('usuarios:gestionar');
  bool get canGestionarPrivilegios  => hasPerm('privilegios:gestionar');
  // RBAC: el permiso 'comunicados:enviar' decide quién publica.
  // (hasPerm ya concede acceso a Admin por bypass; el Jefe de Operaciones lo
  //  recibe por la matriz rol→permiso.)
  bool get canEnviarComunicado => hasPerm('comunicados:enviar');
  // Logística: admin (bypass) · rol Logístico · o cualquiera con permiso de inventario.
  // El Jefe de Operaciones queda EXCLUIDO: el backend bloquea todas las secciones
  // operativas de logística (Requerimientos/Compras/Salidas/Ingresos/...) para él,
  // así que el panel le saldría vacío. Él solicita materiales desde el servicio.
  bool get canGestInventario   =>
      !_esJefeOp &&
      (isAdmin || _esLogistica || hasPerm('inventario:ver') || hasPerm('inventario:gestionar'));
  // Personal: visibilidad (ver) separada de gestión (crear/editar).
  bool get canVerPersonal      => isAdmin || hasPerm('empleados:ver');
  bool get canGestPersonal     => isAdmin || hasPerm('empleados:crear') || hasPerm('empleados:editar');
  bool get canVerReportes      => hasPerm('reportes:ver');
  // Dashboards ejecutivos: admin, jefe de operaciones o con permiso de reportes.
  bool get canVerDashboards    => isAdmin || _esJefeOp || hasPerm('reportes:ver');
  // Planos: todos pueden ver; gestionar requiere el permiso 'planos:gestionar'
  // (delegable desde Privilegios). Admin pasa por bypass de hasPerm.
  bool get canGestionarPlanos  => hasPerm('planos:gestionar');
  bool get canGestClientes     => hasPerm('clientes:gestionar');
  bool get canValidarAsistencia=> hasPerm('asistencia:validar');
  // Control de asistencias (supervisión): ver el tablero diario de marcas/horas.
  bool get canVerControlAsistencias => hasPerm('asistencia:ver');
  // Configurar turnos y asignar excepciones de horario (permiso específico).
  bool get canConfigurarTurnos => hasPerm('asistencia:configurar');

  // ── Visibilidad de módulos (pestañas / entradas de menú) ──────────────────
  // hasPerm ya da true para admin, así que el admin ve todos los módulos.
  bool get canVerInventario   => canGestInventario; // ver = mismo gate que logística
  bool get canVerEpp          => hasPerm('epp:ver');
  bool get canVerCalibracion  => hasPerm('calibracion:ver');
  bool get canVerCorrectivo   => hasPerm('correctivo:ver');
  bool get canVerItse         => hasPerm('itse:ver');
  bool get canVerCatalogos    => hasPerm('catalogos:ver');
  bool get canVerGaleria      => hasPerm('galeria:ver');
  bool get canVerEquipoIntervenido    => hasPerm('equipo_intervenido:ver');
  bool get canCrearEquipoIntervenido  => hasPerm('equipo_intervenido:crear');
  bool get canEditarEquipoIntervenido => hasPerm('equipo_intervenido:editar');
  bool get canEliminarEquipoIntervenido => hasPerm('equipo_intervenido:eliminar');
  // Documentos de cumplimiento / SST (homologaciones, ATS, PETAR)
  bool get canVerDocumentosSst      => hasPerm('documentos_sst:ver');
  bool get canCrearDocumentosSst    => hasPerm('documentos_sst:crear');
  bool get canEditarDocumentosSst   => hasPerm('documentos_sst:editar');
  bool get canEliminarDocumentosSst => hasPerm('documentos_sst:eliminar');

  // ── Finanzas / ERP contable ───────────────────────────────────────────────
  // Visibilidad del módulo: cualquier permiso de finanzas concede la entrada.
  bool get canVerFinanzas =>
      isAdmin || canVerContabilidad || canVerCxp || canVerCxc ||
      canVerActivosFijos || canVerPlanilla || canVerTributario ||
      canVerControlling || canVerInventarioValorizado || canVerCajaChica ||
      canVerConciliacionBancaria;
  bool get canVerContabilidad   => hasPerm('contabilidad:ver');
  bool get canCrearAsiento      => hasPerm('contabilidad:crear_asiento');
  bool get canVerCxp            => hasPerm('cxp:ver');
  bool get canRegistrarFacturaCxp => hasPerm('cxp:registrar_factura');
  bool get canRegistrarPagoCxp  => hasPerm('cxp:registrar_pago');
  bool get canAnularFacturaCxp  => hasPerm('cxp:anular_factura');
  bool get canVerCxc            => hasPerm('cxc:ver');
  bool get canEmitirComprobante => hasPerm('cxc:emitir_comprobante');
  bool get canRegistrarCobro    => hasPerm('cxc:registrar_cobro');
  bool get canVerActivosFijos   => hasPerm('activos_fijos:ver');
  bool get canGestionarActivos  => hasPerm('activos_fijos:gestionar');
  bool get canVerPlanilla       => hasPerm('planilla:ver');
  bool get canCalcularPlanilla  => hasPerm('planilla:calcular');
  bool get canAprobarPlanilla   => hasPerm('planilla:aprobar');
  bool get canVerTributario     => hasPerm('tributario:ver');
  bool get canVerInventarioValorizado => hasPerm('inventario_valorizado:ver');
  bool get canRegistrarMovimientoInventarioValorizado => hasPerm('inventario_valorizado:registrar_movimiento');
  bool get canVerControlling   => hasPerm('controlling:ver');
  bool get canGestionarCentrosCosto => hasPerm('controlling:gestionar_centros_costo');
  bool get canVerCajaChica      => hasPerm('caja_chica:ver');
  bool get canGestionarCajaChica => hasPerm('caja_chica:gestionar');
  bool get canRegistrarMovimientoCaja => hasPerm('caja_chica:registrar_movimiento');
  bool get canVerConciliacionBancaria      => hasPerm('conciliacion_bancaria:ver');
  bool get canGestionarConciliacionBancaria => hasPerm('conciliacion_bancaria:gestionar');
  bool get canConciliar                     => hasPerm('conciliacion_bancaria:conciliar');

  // ── Acciones (ocultar/mostrar botones) ────────────────────────────────────
  bool get canGestionarInventario => isAdmin || _esLogistica || hasPerm('inventario:gestionar');
  bool get canAprobarRequerimiento => hasPerm('requerimientos:aprobar');
  // EPP
  bool get canCrearEpp        => hasPerm('epp:crear');
  bool get canEntregarEpp     => hasPerm('epp:entregar');
  bool get canIngresarEpp     => hasPerm('epp:ingresar');
  bool get canEliminarEpp     => hasPerm('epp:eliminar');
  // ITSE
  bool get canCrearItse       => hasPerm('itse:crear');
  bool get canEditarItse      => hasPerm('itse:editar');
  bool get canFinalizarItse   => hasPerm('itse:finalizar');
  bool get canEliminarItse    => hasPerm('itse:eliminar');
  // Calibración
  bool get canCrearCalibracion    => hasPerm('calibracion:crear');
  bool get canEditarCalibracion   => hasPerm('calibracion:editar');
  bool get canEliminarCalibracion => hasPerm('calibracion:eliminar');
  // Evaluación de desempeño (Punto 3.2)
  bool get canVerEvaluacion       => hasPerm('evaluacion:ver');
  bool get canCrearEvaluacion     => hasPerm('evaluacion:crear');
  bool get canEditarEvaluacion    => hasPerm('evaluacion:editar');
  bool get canEnviarEvaluacion    => hasPerm('evaluacion:enviar');
  bool get canCompletarEvaluacion => hasPerm('evaluacion:completar');
  bool get canEliminarEvaluacion  => hasPerm('evaluacion:eliminar');
  // Indicadores de desempeño (Punto 3.4) — alineado con el gate dashboard:ver del backend
  bool get canVerIndicadores       => isAdmin || hasPerm('dashboard:ver');
  // Vacaciones por ley (Punto 3.3)
  bool get canVerVacaciones        => hasPerm('vacaciones:ver');
  bool get canConfigurarVacaciones => hasPerm('vacaciones:configurar');
  bool get canSolicitarVacaciones  => hasPerm('vacaciones:solicitar');
  bool get canAprobarVacaciones    => hasPerm('vacaciones:aprobar');
  bool get canRechazarVacaciones   => hasPerm('vacaciones:rechazar');
  // Correctivo
  bool get canCrearCorrectivo     => hasPerm('correctivo:crear');
  bool get canAprobarCorrectivo   => hasPerm('correctivo:aprobar');
  bool get canFinalizarCorrectivo => hasPerm('correctivo:finalizar');
  // Catálogos
  bool get canCrearCatalogo   => hasPerm('catalogos:crear');
  bool get canEditarCatalogo  => hasPerm('catalogos:editar');
  bool get canEliminarCatalogo=> hasPerm('catalogos:eliminar');
  // Galería
  bool get canSubirGaleria    => hasPerm('galeria:subir');
  bool get canEliminarGaleria => hasPerm('galeria:eliminar');

  // ── Roles específicos ─────────────────────────────────────────────────────

  bool get _esJefeOp    => _rol == 'jefe de operaciones' || _rol == 'jefe_operaciones';
  bool get _esLogistica =>
      _rol == 'logística' || _rol == 'logistica' ||
      _rol == 'logístico' || _rol == 'logistico';
  bool get isTecnico    => _rol == 'técnico de campo' || _rol == 'tecnico de campo';
  bool get isSupervisor => _rol == 'supervisor de campo';

  bool get isJefeOperaciones => _esJefeOp;

  /// Solo Jefatura de Operaciones (o Admin) puede finalizar/cerrar un servicio.
  bool get canFinalizarServicio => isAdmin || _esJefeOp;

  /// Rol RBAC (controla permisos) — NO mostrar como "rol/cargo" del usuario en
  /// la UI, ver [cargo] para el puesto laboral (lo que muestra la web).
  String get rol => _rol;

  /// Cargo (puesto laboral, ficha de empleado en RR.HH.) — mismo dato que la
  /// web muestra en Personal. Solo informativo: no participa en permisos.
  String get cargo => _cargo;
}

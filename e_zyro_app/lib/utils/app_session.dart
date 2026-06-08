import 'package:shared_preferences/shared_preferences.dart';

/// Singleton de sesión — cargado una vez en el splash y después del login.
/// Usar [AppSession.i] para acceder desde cualquier parte.
class AppSession {
  AppSession._();
  static final AppSession i = AppSession._();

  String _rol = '';
  List<String> _permisos = [];

  // ── Carga desde SharedPreferences ────────────────────────────────────────

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    i._rol      = (prefs.getString('user_rol') ?? '').toLowerCase().trim();
    i._permisos = prefs.getStringList('user_permisos') ?? [];
  }

  static void clear() {
    i._rol      = '';
    i._permisos = [];
  }

  // ── Checks de permisos ────────────────────────────────────────────────────

  /// SuperAdmin y Admin siempre tienen permiso absoluto.
  /// Normaliza espacios para reconocer variantes como "Super Admin" (con
  /// espacio), que el backend siembra junto a "SuperAdmin" y "Administrador".
  bool get isAdmin {
    final r = _rol.replaceAll(' ', '');
    return r == 'superadmin' || r == 'admin' || r == 'administrador';
  }

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
  bool get canVerMantenimientoGeneral => isAdmin || _esJefeOp || hasPerm('mantenimiento:ver_general');
  // RBAC: el permiso 'comunicados:enviar' decide quién publica.
  // (hasPerm ya concede acceso a Admin por bypass; el Jefe de Operaciones lo
  //  recibe por la matriz rol→permiso.)
  bool get canEnviarComunicado => hasPerm('comunicados:enviar');
  // Logística: admin (bypass) · rol Logístico · o cualquiera con permiso de inventario.
  bool get canGestInventario   =>
      isAdmin || _esLogistica || hasPerm('inventario:ver') || hasPerm('inventario:gestionar');
  // Personal: visibilidad (ver) separada de gestión (crear/editar).
  bool get canVerPersonal      => isAdmin || hasPerm('empleados:ver');
  bool get canGestPersonal     => isAdmin || hasPerm('empleados:crear') || hasPerm('empleados:editar');
  bool get canVerReportes      => hasPerm('reportes:ver');
  // Dashboards ejecutivos: admin, jefe de operaciones o con permiso de reportes.
  bool get canVerDashboards    => isAdmin || _esJefeOp || hasPerm('reportes:ver');
  // Planos: todos pueden ver; gestionan admin/jefe/supervisor/logística.
  bool get canGestionarPlanos  => isAdmin || _esJefeOp || isSupervisor || _esLogistica;
  bool get canGestClientes     => hasPerm('clientes:gestionar');
  bool get canValidarAsistencia=> hasPerm('asistencia:validar');

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

  // ── Finanzas / ERP contable ───────────────────────────────────────────────
  // Visibilidad del módulo: cualquier permiso de finanzas concede la entrada.
  bool get canVerFinanzas =>
      isAdmin || canVerContabilidad || canVerCxp || canVerCxc ||
      canVerActivosFijos || canVerPlanilla || canVerTributario ||
      canVerControlling || canVerInventarioValorizado;
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
  bool get canCrearCalibracion  => hasPerm('calibracion:crear');
  bool get canEditarCalibracion => hasPerm('calibracion:editar');
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

  String get rol => _rol;
}

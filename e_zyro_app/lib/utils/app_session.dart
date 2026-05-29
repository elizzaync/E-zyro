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
  bool get isAdmin =>
      _rol == 'superadmin'    ||
      _rol == 'admin'         ||
      _rol == 'administrador';

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
  bool get canEnviarComunicado => isAdmin || _esJefeOp;
  // Logística: admin (bypass) · rol Logístico · o cualquiera con permiso de inventario.
  bool get canGestInventario   =>
      isAdmin || _esLogistica || hasPerm('inventario:ver') || hasPerm('inventario:gestionar');
  bool get canGestPersonal     => isAdmin || hasPerm('empleados:gestionar') || hasPerm('personal:gestionar');
  bool get canVerReportes      => hasPerm('reportes:ver');
  bool get canGestClientes     => hasPerm('clientes:gestionar');
  bool get canValidarAsistencia=> hasPerm('asistencia:validar');

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

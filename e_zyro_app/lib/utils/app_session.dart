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
  bool hasPerm(String permiso) => isAdmin || _permisos.contains(permiso);

  // ── Atajos para cada módulo ───────────────────────────────────────────────

  bool get canVerAuditoria     => hasPerm('AUDITORIA:VER');
  bool get canEnviarComunicado => isAdmin || _esJefeOp;
  bool get canGestInventario   => isAdmin || _esLogistica;
  bool get canGestPersonal     => isAdmin || hasPerm('PERSONAL:GESTIONAR');
  bool get canVerReportes      => hasPerm('REPORTES:VER');
  bool get canGestClientes     => hasPerm('CLIENTES:GESTIONAR');
  bool get canValidarAsistencia=> hasPerm('ASISTENCIA:VALIDAR');

  // ── Roles específicos ─────────────────────────────────────────────────────

  bool get _esJefeOp    => _rol == 'jefe de operaciones' || _rol == 'jefe_operaciones';
  bool get _esLogistica => _rol == 'logística' || _rol == 'logistica';
  bool get isTecnico    => _rol == 'técnico de campo' || _rol == 'tecnico de campo';
  bool get isSupervisor => _rol == 'supervisor de campo';

  bool get isJefeOperaciones => _esJefeOp;

  /// Solo Jefatura de Operaciones (o Admin) puede finalizar/cerrar un servicio.
  bool get canFinalizarServicio => isAdmin || _esJefeOp;

  String get rol => _rol;
}

import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/comunicado_service.dart';
import '../services/dashboard_service.dart';
import '../services/asistencia_service.dart';
import '../services/notificacion_service.dart';
import '../services/proyecto_service.dart';
import '../services/requerimiento_service.dart';
import '../services/mantenimiento_service.dart';
import '../services/historial_service.dart';

Future<AuthService> getAuthService() async {
  final prefs = await SharedPreferences.getInstance();
  return AuthService(ApiClient(prefs), prefs);
}

Future<DashboardService> getDashboardService() async {
  final prefs = await SharedPreferences.getInstance();
  return DashboardService(ApiClient(prefs));
}

Future<AsistenciaService> getAsistenciaService() async {
  final prefs = await SharedPreferences.getInstance();
  return AsistenciaService(ApiClient(prefs));
}

Future<BiometricService> getBiometricService() async {
  final prefs = await SharedPreferences.getInstance();
  return BiometricService(prefs);
}

Future<ProyectoService> getProyectoService() async {
  final prefs = await SharedPreferences.getInstance();
  return ProyectoService(ApiClient(prefs));
}

Future<ComunicadoService> getComunicadoService() async {
  final prefs = await SharedPreferences.getInstance();
  return ComunicadoService(ApiClient(prefs));
}

Future<RequerimientoService> getRequerimientoService() async {
  final prefs = await SharedPreferences.getInstance();
  return RequerimientoService(ApiClient(prefs));
}

Future<NotificacionService> getNotificacionService() async {
  final prefs = await SharedPreferences.getInstance();
  return NotificacionService(ApiClient(prefs));
}

Future<MantenimientoService> getMantenimientoService() async {
  final prefs = await SharedPreferences.getInstance();
  return MantenimientoService(ApiClient(prefs));
}

Future<HistorialService> getHistorialService() async {
  final prefs = await SharedPreferences.getInstance();
  return HistorialService(ApiClient(prefs));
}

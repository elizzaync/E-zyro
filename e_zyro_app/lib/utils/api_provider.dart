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
import '../services/compras_service.dart';
import '../services/mantenimiento_service.dart';
import '../services/historial_service.dart';
import '../services/auditoria_service.dart';
import '../services/seguridad_service.dart';
import '../services/prestamo_service.dart';
import '../services/retorno_service.dart';
import '../services/galeria_service.dart';
import '../services/epp_service.dart';
import '../services/calibracion_service.dart';
import '../services/personal_service.dart';
import '../services/usuarios_service.dart';
import '../services/evaluacion_service.dart';
import '../services/vacaciones_service.dart';
import '../services/indicadores_service.dart';
import '../services/correctivo_service.dart';
import '../services/itse_service.dart';
import '../services/informe_servicio_service.dart';
import '../services/catalogo_service.dart';
import '../services/equipo_intervenido_service.dart';
import '../services/equipo_service.dart';
import '../services/intervencion_service.dart';
import '../services/analitica_service.dart';
import '../services/planos_service.dart';
import '../services/drive_service.dart';
import '../services/soporte_service.dart';
import '../services/finanzas_service.dart';
import '../services/ingreso_directo_service.dart';
import '../services/chatbot_service.dart';

Future<IngresoDirectoService> getIngresoDirectoService() async {
  final prefs = await SharedPreferences.getInstance();
  return IngresoDirectoService(ApiClient(prefs));
}

Future<FinanzasService> getFinanzasService() async {
  final prefs = await SharedPreferences.getInstance();
  return FinanzasService(ApiClient(prefs));
}

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

Future<ComprasService> getComprasService() async {
  final prefs = await SharedPreferences.getInstance();
  return ComprasService(ApiClient(prefs));
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

Future<AuditoriaService> getAuditoriaService() async {
  final prefs = await SharedPreferences.getInstance();
  return AuditoriaService(ApiClient(prefs));
}

Future<SeguridadService> getSeguridadService() async {
  final prefs = await SharedPreferences.getInstance();
  return SeguridadService(ApiClient(prefs));
}

Future<PrestamoService> getPrestamoService() async {
  final prefs = await SharedPreferences.getInstance();
  return PrestamoService(ApiClient(prefs));
}

Future<RetornoService> getRetornoService() async {
  final prefs = await SharedPreferences.getInstance();
  return RetornoService(ApiClient(prefs));
}

Future<GaleriaService> getGaleriaService() async {
  final prefs = await SharedPreferences.getInstance();
  return GaleriaService(ApiClient(prefs));
}

Future<EppService> getEppService() async {
  final prefs = await SharedPreferences.getInstance();
  return EppService(ApiClient(prefs));
}

Future<CalibracionService> getCalibracionService() async {
  final prefs = await SharedPreferences.getInstance();
  return CalibracionService(ApiClient(prefs));
}

Future<PersonalService> getPersonalService() async {
  final prefs = await SharedPreferences.getInstance();
  return PersonalService(ApiClient(prefs));
}

Future<EvaluacionService> getEvaluacionService() async {
  final prefs = await SharedPreferences.getInstance();
  return EvaluacionService(ApiClient(prefs));
}

Future<UsuariosService> getUsuariosService() async {
  final prefs = await SharedPreferences.getInstance();
  return UsuariosService(ApiClient(prefs));
}

Future<VacacionesService> getVacacionesService() async {
  final prefs = await SharedPreferences.getInstance();
  return VacacionesService(ApiClient(prefs));
}

Future<IndicadoresService> getIndicadoresService() async {
  final prefs = await SharedPreferences.getInstance();
  return IndicadoresService(ApiClient(prefs));
}

Future<CorrectivoService> getCorrectivoService() async {
  final prefs = await SharedPreferences.getInstance();
  return CorrectivoService(ApiClient(prefs));
}

Future<ItseService> getItseService() async {
  final prefs = await SharedPreferences.getInstance();
  return ItseService(ApiClient(prefs));
}

Future<InformeServicioService> getInformeServicioService() async {
  final prefs = await SharedPreferences.getInstance();
  return InformeServicioService(ApiClient(prefs));
}

Future<CatalogoService> getCatalogoService() async {
  final prefs = await SharedPreferences.getInstance();
  return CatalogoService(ApiClient(prefs));
}

Future<EquipoIntervenidoService> getEquipoIntervenidoService() async {
  final prefs = await SharedPreferences.getInstance();
  return EquipoIntervenidoService(ApiClient(prefs));
}

Future<IntervencionService> getIntervencionService() async {
  final prefs = await SharedPreferences.getInstance();
  return IntervencionService(ApiClient(prefs));
}

Future<EquipoService> getEquipoService() async {
  final prefs = await SharedPreferences.getInstance();
  return EquipoService(ApiClient(prefs));
}

Future<AnaliticaService> getAnaliticaService() async {
  final prefs = await SharedPreferences.getInstance();
  return AnaliticaService(ApiClient(prefs));
}

Future<PlanosService> getPlanosService() async {
  final prefs = await SharedPreferences.getInstance();
  return PlanosService(ApiClient(prefs));
}

Future<DriveService> getDriveService() async {
  final prefs = await SharedPreferences.getInstance();
  return DriveService(ApiClient(prefs));
}

Future<SoporteService> getSoporteService() async {
  final prefs = await SharedPreferences.getInstance();
  return SoporteService(ApiClient(prefs));
}

Future<ChatbotService> getChatbotService() async {
  final prefs = await SharedPreferences.getInstance();
  return ChatbotService(ApiClient(prefs));
}

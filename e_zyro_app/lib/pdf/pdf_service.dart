import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/proyecto_models.dart';
import '../models/asistencia_models.dart';
import '../models/requerimiento_models.dart';
import '../models/calibracion_models.dart';
import '../models/personal_models.dart';
import '../models/finanzas_models.dart';
import 'builders/permiso_builder.dart';
import 'builders/informe_servicio_builder.dart';
import 'builders/asistencia_builder.dart';
import 'builders/salidas_builder.dart';
import 'builders/gantt_builder.dart';
import 'builders/calibracion_builder.dart';
import 'builders/historial_personal_builder.dart';
import 'builders/etiqueta_equipo_builder.dart';
import 'builders/boleta_pago_builder.dart';

/// ╔══════════════════════════════════════════════════════════════════════════╗
/// ║  PdfService — FACHADA ÚNICA de creación de PDFs de la app.                 ║
/// ║                                                                            ║
/// ║  Aquí están listadas TODAS las funciones que generan un PDF. Cada una      ║
/// ║  devuelve los bytes (`Uint8List`) y delega el armado a su builder en       ║
/// ║  `lib/pdf/builders/`. Para previsualizar/compartir/imprimir el resultado   ║
/// ║  usar `PdfPreviewScreen.abrir(context, bytes: ...)`.                       ║
/// ║                                                                            ║
/// ║  Modelo de generación:                                                     ║
/// ║   • Formato fijo (rellena una plantilla de assets/plantillas/) → overlay   ║
/// ║     con `PdfOverlay` (ej. permiso).                                         ║
/// ║   • Dinámico (tablas/figuras que crecen) → código con `PdfTheme` (ej.      ║
/// ║     informe de servicio).                                                  ║
/// ║                                                                            ║
/// ║  ÍNDICE DE DOCUMENTOS:                                                      ║
/// ║   - permiso()              Solicitud de permiso (trámites)                  ║
/// ║   - informeServicio()      Informe técnico de conformidad                  ║
/// ║   - preInformeServicio()   Pre-informe (mismo formato, antes de cerrar)    ║
/// ║   - salidasLogistica()     [P3] Reporte de salidas de equipos              ║
/// ║   - asistenciaUsuario()    [P3] Reporte de asistencia por usuario          ║
/// ║   - historialPersonal()    Ficha/historial laboral de un empleado          ║
/// ║   - boletaPago()           Boleta de pago (motor legal de planilla)       ║
/// ║   - historialCalibracion() Historial de calibraciones de un equipo         ║
/// ║   - etiquetaEquipo()       Etiqueta QR imprimible de un equipo             ║
/// ║   - gantt()                [P3] Cronograma Gantt del proyecto              ║
/// ╚══════════════════════════════════════════════════════════════════════════╝
class PdfService {
  PdfService._();

  // ── Trámites ───────────────────────────────────────────────────────────────

  /// Solicitud de permiso: overlay sobre la plantilla oficial.
  static Future<Uint8List> permiso(
    Map<String, dynamic> data,
    Uint8List? firmaBytes,
  ) =>
      PermisoBuilder.build(data, firmaBytes);

  // ── Servicios ────────────────────────────────────────────────────────────

  /// Informe Técnico de Conformidad de Servicio (documento final).
  static Future<Uint8List> informeServicio(ServicioDetalle detalle) async {
    final tecnico = await _nombreUsuario();
    return InformeServicioBuilder.build(
        detalle: detalle, tecnicoNombre: tecnico);
  }

  /// Pre-informe: mismo formato que el informe final; se abre antes/al cerrar
  /// el servicio para revisión.
  static Future<Uint8List> preInformeServicio(ServicioDetalle detalle) =>
      informeServicio(detalle);

  // ── Logística ──────────────────────────────────────────────────────────────

  /// Reporte de salidas de almacén/equipos (filtra los movimientos `salida`).
  static Future<Uint8List> salidasLogistica(
          List<MovimientoStock> movimientos) =>
      SalidasBuilder.build(movimientos: movimientos);

  // ── RR.HH. / Asistencia ────────────────────────────────────────────────────

  /// Reporte de asistencia de un usuario. Si [usuario] es null, usa el de sesión.
  static Future<Uint8List> asistenciaUsuario(
    List<RegistroAsistencia> registros, {
    String? usuario,
  }) async {
    final nombre = usuario ?? await _nombreUsuario();
    return AsistenciaBuilder.build(usuario: nombre, registros: registros);
  }

  /// Ficha/historial consolidado de un empleado (datos, contratos, asistencia,
  /// solicitudes, EPP y evaluaciones).
  static Future<Uint8List> historialPersonal(HistorialPersonal historial) =>
      HistorialPersonalBuilder.build(h: historial);

  /// Boleta de pago (motor legal de planilla): ingresos, descuentos, neto y
  /// beneficios del empleador, con las mismas citas legales que la web.
  static Future<Uint8List> boletaPago({
    required PlanillaPreviewEmpleado empleado,
    required EmpresaInfo empresa,
    required String labelPeriodo,
    required String regimenEmpresa,
  }) =>
      BoletaPagoBuilder.build(
        e: empleado, empresa: empresa, labelPeriodo: labelPeriodo,
        regimenEmpresa: regimenEmpresa,
      );

  // ── Equipos / Calibraciones ──────────────────────────────────────────────

  /// Historial de calibraciones de un equipo (una fila por calibración).
  static Future<Uint8List> historialCalibracion(
          String equipoNombre, List<CalibracionEvento> eventos) =>
      CalibracionBuilder.build(equipoNombre: equipoNombre, eventos: eventos);

  /// Etiqueta imprimible (tarjeta) con QR del código del equipo + datos.
  static Future<Uint8List> etiquetaEquipo({
    required String codigo,
    required String nombre,
    String? marca,
    String? modelo,
    String? numeroSerie,
  }) =>
      EtiquetaEquipoBuilder.build(
        codigo: codigo, nombre: nombre,
        marca: marca, modelo: modelo, numeroSerie: numeroSerie,
      );

  // ── Proyectos ──────────────────────────────────────────────────────────────

  /// Cronograma Gantt del proyecto.
  static Future<Uint8List> gantt(
          ProyectoItem proyecto, List<ServicioItem> servicios) =>
      GanttBuilder.build(proyecto: proyecto, servicios: servicios);

  // ── Helpers internos ───────────────────────────────────────────────────────

  static Future<String> _nombreUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name') ??
        prefs.getString('user_nombre') ??
        'Técnico';
  }
}

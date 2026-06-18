// Modelos de Solicitudes Laborales (RR.HH.) — justificaciones de tardanza,
// permisos y trámites. Espejo de `solicitud_laboral` + bandeja /rrhh/solicitudes
// y /permisos/mis-solicitudes.

/// Categorías de la bandeja RR.HH. (no incluye vacaciones, que tiene su pantalla).
enum CategoriaSolicitud { justificacion, permiso, tramite }

const _kLabelTipo = <String, String>{
  'justificacion_tardanza': 'Justificación de Tardanza',
  'justificacion_falta': 'Justificación de Falta',
  'permiso': 'Permiso',
  'permiso_personal': 'Permiso Personal',
  'comision_trabajo': 'Comisión de Trabajo',
  'cita_essalud': 'Cita Essalud / Clínica',
  'permanencia_capacitacion': 'Permanencia Capacitación',
  'permanencia_extra': 'Permanencia Extra',
  'recuperacion': 'Recuperación',
  'dias_libres': 'Día(s) Libre(s)',
  'adelanto': 'Adelanto',
  'transferencia': 'Transferencia',
  'vacaciones': 'Vacaciones',
  'otros': 'Otros',
  'otro': 'Otro',
};

const _kPermisoTipos = {
  'permiso', 'permiso_personal', 'comision_trabajo', 'cita_essalud',
  'permanencia_capacitacion', 'permanencia_extra', 'recuperacion',
  'dias_libres', 'adelanto',
};

CategoriaSolicitud categoriaDeTipo(String tipo) {
  if (tipo.startsWith('justificacion')) return CategoriaSolicitud.justificacion;
  if (_kPermisoTipos.contains(tipo)) return CategoriaSolicitud.permiso;
  return CategoriaSolicitud.tramite; // transferencia, otros, otro, …
}

class SolicitudLaboral {
  final String id;
  final String tipo;
  final String estado; // pendiente | aprobada | rechazada
  final String descripcion;
  final String? fechaInicio;
  final String? fechaFin;
  final int? dias;
  final String? observacion; // nota de RR.HH. al evaluar
  final String? urlPdf;
  final String? createdAt;
  final String? fechaAprobacion;
  // Empleado (solo en la bandeja RR.HH.)
  final String? empleadoNombre;
  final String? empleadoCargo;
  final String? empleadoArea;
  final String? empleadoIniciales;
  final String? empleadoFotoUrl;

  const SolicitudLaboral({
    required this.id,
    required this.tipo,
    this.estado = 'pendiente',
    this.descripcion = '',
    this.fechaInicio,
    this.fechaFin,
    this.dias,
    this.observacion,
    this.urlPdf,
    this.createdAt,
    this.fechaAprobacion,
    this.empleadoNombre,
    this.empleadoCargo,
    this.empleadoArea,
    this.empleadoIniciales,
    this.empleadoFotoUrl,
  });

  factory SolicitudLaboral.fromJson(Map<String, dynamic> j) {
    final emp = j['empleado'];
    final empMap = emp is Map ? emp : const {};
    return SolicitudLaboral(
      id: j['id']?.toString() ?? '',
      tipo: j['tipo']?.toString() ?? '',
      estado: j['estado']?.toString() ?? 'pendiente',
      descripcion: j['descripcion']?.toString() ?? '',
      fechaInicio: j['fecha_inicio']?.toString(),
      fechaFin: j['fecha_fin']?.toString(),
      dias: (j['dias'] as num?)?.toInt(),
      observacion: j['observacion']?.toString(),
      urlPdf: j['url_pdf']?.toString(),
      createdAt: j['created_at']?.toString(),
      fechaAprobacion: j['fecha_aprobacion']?.toString(),
      empleadoNombre: empMap['nombreCompleto']?.toString(),
      empleadoCargo: empMap['cargo']?.toString(),
      empleadoArea: empMap['area']?.toString(),
      empleadoIniciales: empMap['iniciales']?.toString(),
      empleadoFotoUrl: empMap['fotoUrl']?.toString(),
    );
  }

  String get tipoLabel => _kLabelTipo[tipo] ?? tipo;
  CategoriaSolicitud get categoria => categoriaDeTipo(tipo);
  bool get esPendiente => estado == 'pendiente';
}

/// Modalidades rápidas sugeridas para justificar una tardanza.
const kModalidadesTardanza = <String>[
  'Tráfico / transporte',
  'Cita médica',
  'Problema de salud',
  'Emergencia familiar',
  'Motivo personal',
  'Falla de servicio (luz/agua)',
];

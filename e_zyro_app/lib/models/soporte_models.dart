// Ticket de soporte interno (equipo de TI). Espejo de TicketSoporteOut del
// backend (/soporte). Claves en snake_case (como las emite el backend).

class TicketSoporte {
  final String id;
  final String codigo;
  final String titulo;
  final String descripcion;
  final String categoria; // app_movil | sistema_web | acceso | datos | otro
  final String prioridad; // baja | media | alta | urgente
  final String estado;    // abierto | en_proceso | resuelto | cerrado
  final String? pantalla;
  final String? dispositivo;
  final String? adjuntoUrl;
  final String? respuestaTi;
  final String reportadoPor;
  final String reportanteNombre;
  final String? atendidoPor;
  final String creadoEn;
  final String? actualizadoEn;

  const TicketSoporte({
    required this.id,
    required this.codigo,
    required this.titulo,
    required this.descripcion,
    required this.categoria,
    required this.prioridad,
    required this.estado,
    this.pantalla,
    this.dispositivo,
    this.adjuntoUrl,
    this.respuestaTi,
    required this.reportadoPor,
    required this.reportanteNombre,
    this.atendidoPor,
    required this.creadoEn,
    this.actualizadoEn,
  });

  factory TicketSoporte.fromJson(Map<String, dynamic> j) => TicketSoporte(
        id: j['id'] as String? ?? '',
        codigo: j['codigo'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        descripcion: j['descripcion'] as String? ?? '',
        categoria: j['categoria'] as String? ?? 'otro',
        prioridad: j['prioridad'] as String? ?? 'media',
        estado: j['estado'] as String? ?? 'abierto',
        pantalla: j['pantalla'] as String?,
        dispositivo: j['dispositivo'] as String?,
        adjuntoUrl: j['adjunto_url'] as String?,
        respuestaTi: j['respuesta_ti'] as String?,
        reportadoPor: j['reportado_por'] as String? ?? '',
        reportanteNombre: j['reportante_nombre'] as String? ?? 'Usuario',
        atendidoPor: j['atendido_por'] as String?,
        creadoEn: j['creado_en'] as String? ?? '',
        actualizadoEn: j['actualizado_en'] as String?,
      );
}

// ── Catálogos de presentación (etiquetas legibles) ──────────────────────────

const Map<String, String> kCategoriasSoporte = {
  'app_movil': 'App móvil',
  'sistema_web': 'Sistema web',
  'acceso': 'Acceso / Login',
  'datos': 'Datos incorrectos',
  'otro': 'Otro',
};

const Map<String, String> kPrioridadesSoporte = {
  'baja': 'Baja',
  'media': 'Media',
  'alta': 'Alta',
  'urgente': 'Urgente',
};

const Map<String, String> kEstadosSoporte = {
  'abierto': 'Abierto',
  'en_proceso': 'En proceso',
  'resuelto': 'Resuelto',
  'cerrado': 'Cerrado',
};

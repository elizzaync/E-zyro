class DashboardResumen {
  final int activos;
  final int pendientes;
  final int completados;
  final int asistenciasMes;
  final int solicitudesPendientes;
  final UsuarioResumen usuario;

  const DashboardResumen({
    required this.activos,
    required this.pendientes,
    required this.completados,
    this.asistenciasMes = 0,
    this.solicitudesPendientes = 0,
    this.usuario = const _EmptyUsuario(),
  });

  factory DashboardResumen.fromJson(Map<String, dynamic> json) =>
      DashboardResumen(
        activos: json['activos'] ?? 0,
        pendientes: json['pendientes'] ?? 0,
        completados: json['completados'] ?? 0,
        asistenciasMes: json['asistencias_mes'] ?? 0,
        solicitudesPendientes: json['solicitudes_pendientes'] ?? 0,
        usuario: json['usuario'] != null
            ? UsuarioResumen.fromJson(json['usuario'] as Map<String, dynamic>)
            : UsuarioResumen.empty(),
      );
}

class UsuarioResumen {
  final String nombre;
  final String apellido;
  final String email;
  final String telefono;
  final String fotoUrl;

  const UsuarioResumen({
    required this.nombre,
    required this.apellido,
    required this.email,
    required this.telefono,
    required this.fotoUrl,
  });

  factory UsuarioResumen.fromJson(Map<String, dynamic> json) => UsuarioResumen(
    nombre: json['nombre'] ?? '',
    apellido: json['apellido'] ?? '',
    email: json['email'] ?? '',
    telefono: json['telefono'] ?? '',
    fotoUrl: json['foto_url'] ?? '',
  );

  factory UsuarioResumen.empty() => const UsuarioResumen(
    nombre: '',
    apellido: '',
    email: '',
    telefono: '',
    fotoUrl: '',
  );
}

class _EmptyUsuario extends UsuarioResumen {
  const _EmptyUsuario() : super(
    nombre: '',
    apellido: '',
    email: '',
    telefono: '',
    fotoUrl: '',
  );
}

class ProximoServicio {
  final String empresa;
  final String tipo;
  final String fecha;
  final String hora;
  final String estado;

  const ProximoServicio({
    required this.empresa,
    required this.tipo,
    required this.fecha,
    required this.hora,
    required this.estado,
  });

  factory ProximoServicio.fromJson(Map<String, dynamic> json) =>
      ProximoServicio(
        empresa: json['empresa'] ?? '',
        tipo: json['tipo'] ?? '',
        fecha: json['fecha'] ?? '',
        hora: json['hora'] ?? '',
        estado: json['estado'] ?? '',
      );
}

/// Alertas y pendientes accionables del dashboard (GET /dashboard/alertas).
/// Cada contador es tolerante: el backend devuelve 0 si su fuente falla.
class DashboardAlertas {
  final int calibracionesPorVencer;
  final int mantenimientosAlerta;
  final int documentosPendientes;
  final int total;
  final List<AlertaItem> items;

  const DashboardAlertas({
    this.calibracionesPorVencer = 0,
    this.mantenimientosAlerta = 0,
    this.documentosPendientes = 0,
    this.total = 0,
    this.items = const [],
  });

  bool get isEmpty => total == 0;

  factory DashboardAlertas.fromJson(Map<String, dynamic> json) =>
      DashboardAlertas(
        calibracionesPorVencer: json['calibraciones_por_vencer'] ?? 0,
        mantenimientosAlerta: json['mantenimientos_alerta'] ?? 0,
        documentosPendientes: json['documentos_pendientes'] ?? 0,
        total: json['total'] ?? 0,
        items: (json['items'] as List? ?? const [])
            .map((e) => AlertaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AlertaItem {
  final String tipo;      // mantenimiento | calibracion | documento
  final String titulo;
  final String severidad; // alta | media | baja
  final String? ruta;     // ruta de navegación opcional
  final int conteo;

  const AlertaItem({
    required this.tipo,
    required this.titulo,
    this.severidad = 'media',
    this.ruta,
    this.conteo = 0,
  });

  factory AlertaItem.fromJson(Map<String, dynamic> json) => AlertaItem(
        tipo: json['tipo'] ?? '',
        titulo: json['titulo'] ?? '',
        severidad: json['severidad'] ?? 'media',
        ruta: json['ruta'] as String?,
        conteo: json['conteo'] ?? 0,
      );
}

class NotificacionDashboard {
  final String id;
  final String titulo;
  final String mensaje;
  final String tiempo;
  final String tipo;

  const NotificacionDashboard({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.tiempo,
    required this.tipo,
  });

  factory NotificacionDashboard.fromJson(Map<String, dynamic> json) =>
      NotificacionDashboard(
        id:      json['id']?.toString() ?? '',
        titulo:  json['titulo'] ?? '',
        mensaje: json['mensaje'] ?? '',
        tiempo:  json['tiempo'] ?? '',
        tipo:    json['tipo'] ?? '',
      );
}

/// Modelo completo para la pantalla de gestión de notificaciones.
/// Usa el endpoint GET /notificaciones que devuelve todos los campos.
class NotificacionItem {
  final String id;
  final String tipo;
  final String? categoria;
  final String titulo;
  final String mensaje;
  final bool leido;
  final String? referenciaTabla;
  final String? referenciaId;
  final DateTime createdAt;

  const NotificacionItem({
    required this.id,
    required this.tipo,
    this.categoria,
    required this.titulo,
    required this.mensaje,
    required this.leido,
    this.referenciaTabla,
    this.referenciaId,
    required this.createdAt,
  });

  factory NotificacionItem.fromJson(Map<String, dynamic> json) =>
      NotificacionItem(
        id:               json['id']?.toString() ?? '',
        tipo:             json['tipo'] ?? 'general',
        categoria:        json['categoria']?.toString(),
        titulo:           json['titulo'] ?? '',
        mensaje:          json['mensaje'] ?? '',
        leido:            json['leido'] as bool? ?? false,
        referenciaTabla:  json['referencia_tabla']?.toString(),
        referenciaId:     json['referencia_id']?.toString(),
        createdAt:        DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      );

  NotificacionItem copyWith({bool? leido}) => NotificacionItem(
    id:              id,
    tipo:            tipo,
    categoria:       categoria,
    titulo:          titulo,
    mensaje:         mensaje,
    leido:           leido ?? this.leido,
    referenciaTabla: referenciaTabla,
    referenciaId:    referenciaId,
    createdAt:       createdAt,
  );

  String get tiempoRelativo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Ahora mismo';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}

// ─── Calendario ───────────────────────────────────────────────────────────────

class CalendarioData {
  final List<EventoProximo> proximosEventos;
  final Map<String, String> notas;
  final List<String> diasConServicio;

  const CalendarioData({
    required this.proximosEventos,
    required this.notas,
    required this.diasConServicio,
  });

  factory CalendarioData.fromJson(Map<String, dynamic> json) => CalendarioData(
    proximosEventos: (json['proximosEventos'] as List? ?? [])
        .map((e) => EventoProximo.fromJson(e as Map<String, dynamic>))
        .toList(),
    notas: (json['notas'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v.toString())),
    diasConServicio: List<String>.from(json['diasConServicio'] ?? []),
  );
}

class EventoProximo {
  final String dia;
  final String mes;
  final String empresa;
  final String tipo;
  final String hora;
  final bool activo;

  const EventoProximo({
    required this.dia,
    required this.mes,
    required this.empresa,
    required this.tipo,
    required this.hora,
    required this.activo,
  });

  factory EventoProximo.fromJson(Map<String, dynamic> json) => EventoProximo(
    dia:     json['dia'] ?? '',
    mes:     json['mes'] ?? '',
    empresa: json['empresa'] ?? '',
    tipo:    json['tipo'] ?? '',
    hora:    json['hora'] ?? '',
    activo:  json['activo'] ?? false,
  );
}

class DetalleServicioDia {
  final String id;
  final String nombre;
  final String ordenTrabajo;
  final String estado;
  final String servicio;
  final String cliente;
  final String fecha;
  final JefeCalendario? jefe;
  final List<MiembroCalendario> equipo;

  const DetalleServicioDia({
    required this.id,
    required this.nombre,
    required this.ordenTrabajo,
    required this.estado,
    required this.servicio,
    required this.cliente,
    required this.fecha,
    this.jefe,
    required this.equipo,
  });

  factory DetalleServicioDia.fromJson(Map<String, dynamic> json) =>
      DetalleServicioDia(
        id:           json['id']?.toString() ?? '',
        nombre:       json['nombre'] ?? '',
        ordenTrabajo: json['orden_trabajo'] ?? '',
        estado:       json['estado'] ?? '',
        servicio:     json['servicio'] ?? '',
        cliente:      json['cliente'] ?? '',
        fecha:        json['fecha'] ?? '',
        jefe: json['jefe_operaciones'] != null
            ? JefeCalendario.fromJson(
                json['jefe_operaciones'] as Map<String, dynamic>)
            : null,
        equipo: (json['equipo'] as List? ?? [])
            .map((e) => MiembroCalendario.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class JefeCalendario {
  final String nombre;
  final String cargo;

  const JefeCalendario({required this.nombre, required this.cargo});

  factory JefeCalendario.fromJson(Map<String, dynamic> json) => JefeCalendario(
    nombre: json['nombre'] ?? '',
    cargo:  json['cargo'] ?? '',
  );
}

class MiembroCalendario {
  final String nombre;
  final String cargo;
  final String rolProyecto;

  const MiembroCalendario({
    required this.nombre,
    required this.cargo,
    required this.rolProyecto,
  });

  factory MiembroCalendario.fromJson(Map<String, dynamic> json) =>
      MiembroCalendario(
        nombre:      json['nombre'] ?? '',
        cargo:       json['cargo'] ?? '',
        rolProyecto: json['rol_proyecto'] ?? 'Técnico',
      );
}

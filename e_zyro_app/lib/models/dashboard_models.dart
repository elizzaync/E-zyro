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

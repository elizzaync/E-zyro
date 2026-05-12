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
  final String titulo;
  final String tiempo;

  const NotificacionDashboard({required this.titulo, required this.tiempo});

  factory NotificacionDashboard.fromJson(Map<String, dynamic> json) =>
      NotificacionDashboard(
        titulo: json['titulo'] ?? '',
        tiempo: json['tiempo'] ?? '',
      );
}

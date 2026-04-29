class DashboardResumen {
  final int activos;
  final int pendientes;
  final int completados;

  const DashboardResumen({
    required this.activos,
    required this.pendientes,
    required this.completados,
  });

  factory DashboardResumen.fromJson(Map<String, dynamic> json) =>
      DashboardResumen(
        activos: json['activos'] ?? 0,
        pendientes: json['pendientes'] ?? 0,
        completados: json['completados'] ?? 0,
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

class SesionConexion {
  final String id;
  final String dispositivo;
  final String ip;
  final String userAgent;
  final bool activa;
  final bool esActual;
  final String fechaInicio;
  final String fechaExpiracion;
  final String? fechaCierre;

  const SesionConexion({
    required this.id,
    required this.dispositivo,
    required this.ip,
    required this.userAgent,
    required this.activa,
    required this.esActual,
    required this.fechaInicio,
    required this.fechaExpiracion,
    this.fechaCierre,
  });

  factory SesionConexion.fromJson(Map<String, dynamic> j) => SesionConexion(
        id:              j['id'] as String? ?? '',
        dispositivo:     j['dispositivo'] as String? ?? '',
        ip:              j['ip'] as String? ?? '',
        userAgent:       j['user_agent'] as String? ?? '',
        activa:          j['activa'] as bool? ?? false,
        esActual:        j['es_actual'] as bool? ?? false,
        fechaInicio:     j['fecha_inicio'] as String? ?? '',
        fechaExpiracion: j['fecha_expiracion'] as String? ?? '',
        fechaCierre:     j['fecha_cierre'] as String?,
      );
}

class PersonalItem {
  final String id;
  final String nombre;
  final String apellido;
  final String email;
  final String rol;
  final String? fotoUrl;
  final bool activo;
  final String? ultimoAcceso;
  final int sesionesActivas;

  const PersonalItem({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.email,
    required this.rol,
    this.fotoUrl,
    required this.activo,
    this.ultimoAcceso,
    required this.sesionesActivas,
  });

  String get nombreCompleto => '$nombre $apellido'.trim();

  factory PersonalItem.fromJson(Map<String, dynamic> j) => PersonalItem(
        id:               j['id'] as String? ?? '',
        nombre:           j['nombre'] as String? ?? '',
        apellido:         j['apellido'] as String? ?? '',
        email:            j['email'] as String? ?? '',
        rol:              j['rol'] as String? ?? 'Sin rol',
        fotoUrl:          j['foto_url'] as String?,
        activo:           j['activo'] as bool? ?? false,
        ultimoAcceso:     j['ultimo_acceso'] as String?,
        sesionesActivas:  (j['sesiones_activas'] as num?)?.toInt() ?? 0,
      );
}

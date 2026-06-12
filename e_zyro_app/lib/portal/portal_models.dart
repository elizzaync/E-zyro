/// Modelos del "Portal Empresa" (clientes externos, rol ClienteExterno).
/// Contratos espejo del backend FastAPI bajo `/portal-cliente/*` (solo
/// lectura). Todas las fechas llegan como string ISO o null y cualquier campo
/// de texto puede venir null, por eso todos los `fromJson` son null-safe.
library;

// ── Helpers de parseo null-safe ───────────────────────────────────────────────

String _s(dynamic v) => v?.toString() ?? '';

String? _sn(dynamic v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

int _i(dynamic v) =>
    v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

int? _iN(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');

List<T> _lista<T>(dynamic v, T Function(Map<String, dynamic>) fromJson) =>
    v is List
        ? v.whereType<Map<String, dynamic>>().map(fromJson).toList()
        : <T>[];

// ── GET /portal-cliente/dashboard ────────────────────────────────────────────

/// Próximo mantenimiento listado en el dashboard del cliente.
class PortalMantenimientoProximo {
  final String id;
  final String nombre;
  final String? fechaProgramada; // ISO | null
  final String estado;
  final String proyecto;

  PortalMantenimientoProximo({
    required this.id,
    required this.nombre,
    this.fechaProgramada,
    this.estado = '',
    this.proyecto = '',
  });

  factory PortalMantenimientoProximo.fromJson(Map<String, dynamic> json) =>
      PortalMantenimientoProximo(
        id: _s(json['id']),
        nombre: _s(json['nombre']),
        fechaProgramada: _sn(json['fecha_programada']),
        estado: _s(json['estado']),
        proyecto: _s(json['proyecto']),
      );
}

/// Respuesta de GET /portal-cliente/dashboard.
class PortalDashboard {
  final int proyectosActivos;
  final int completadosEsteMes;
  final List<PortalMantenimientoProximo> proximosMantenimientos;

  PortalDashboard({
    this.proyectosActivos = 0,
    this.completadosEsteMes = 0,
    this.proximosMantenimientos = const [],
  });

  factory PortalDashboard.fromJson(Map<String, dynamic> json) =>
      PortalDashboard(
        proyectosActivos: _i(json['proyectos_activos']),
        completadosEsteMes: _i(json['completados_este_mes']),
        proximosMantenimientos: _lista(
          json['proximos_mantenimientos'],
          PortalMantenimientoProximo.fromJson,
        ),
      );
}

// ── GET /portal-cliente/dashboard/kpis ───────────────────────────────────────

/// Respuesta de GET /portal-cliente/dashboard/kpis.
class PortalKpis {
  final int totalEquipos;
  final int mantenimientosCompletados;
  final int enProceso;
  final int proximos30Dias;

  PortalKpis({
    this.totalEquipos = 0,
    this.mantenimientosCompletados = 0,
    this.enProceso = 0,
    this.proximos30Dias = 0,
  });

  factory PortalKpis.fromJson(Map<String, dynamic> json) => PortalKpis(
        totalEquipos: _i(json['total_equipos']),
        mantenimientosCompletados: _i(json['mantenimientos_completados']),
        enProceso: _i(json['en_proceso']),
        proximos30Dias: _i(json['proximos_30_dias']),
      );
}

// ── GET /portal-cliente/proyectos ────────────────────────────────────────────

/// Item de GET /portal-cliente/proyectos. También se reutiliza como bloque
/// `proyecto` de GET /portal-cliente/proyecto/{id}/detalles (ahí los
/// contadores de servicios no vienen y quedan en 0).
class PortalProyecto {
  final String id;
  final String nombreProyecto;
  final String estado;
  final String? fechaInicio; // ISO | null
  final String? fechaFinEstimada; // ISO | null
  final int totalServicios;
  final int serviciosCompletados;
  final int avancePct;

  PortalProyecto({
    required this.id,
    required this.nombreProyecto,
    this.estado = '',
    this.fechaInicio,
    this.fechaFinEstimada,
    this.totalServicios = 0,
    this.serviciosCompletados = 0,
    this.avancePct = 0,
  });

  factory PortalProyecto.fromJson(Map<String, dynamic> json) => PortalProyecto(
        id: _s(json['id']),
        nombreProyecto: _s(json['nombre_proyecto']),
        estado: _s(json['estado']),
        fechaInicio: _sn(json['fecha_inicio']),
        fechaFinEstimada: _sn(json['fecha_fin_estimada']),
        totalServicios: _i(json['total_servicios']),
        serviciosCompletados: _i(json['servicios_completados']),
        avancePct: _i(json['avance_pct']),
      );
}

// ── GET /portal-cliente/proyecto/{id}/detalles ───────────────────────────────

/// Persona del proyecto. Cubre dos formas del backend:
/// - `equipo` dentro de un servicio: nombre, apellido, cargo, foto_url,
///   email, telefono, empresa, rol.
/// - `personal` del proyecto: nombre, cargo, rol_proyecto.
class PortalPersona {
  final String id;
  final String nombre;
  final String? apellido;
  final String? cargo;
  final String? fotoUrl;
  final String? email;
  final String? telefono;
  final String? empresa;
  final String? rol;
  final String? rolProyecto;

  PortalPersona({
    required this.id,
    required this.nombre,
    this.apellido,
    this.cargo,
    this.fotoUrl,
    this.email,
    this.telefono,
    this.empresa,
    this.rol,
    this.rolProyecto,
  });

  String get nombreCompleto =>
      [nombre, apellido ?? ''].where((p) => p.isNotEmpty).join(' ');

  factory PortalPersona.fromJson(Map<String, dynamic> json) => PortalPersona(
        id: _s(json['id']),
        nombre: _s(json['nombre']),
        apellido: _sn(json['apellido']),
        cargo: _sn(json['cargo']),
        fotoUrl: _sn(json['foto_url']),
        email: _sn(json['email']),
        telefono: _sn(json['telefono']),
        empresa: _sn(json['empresa']),
        rol: _sn(json['rol']),
        rolProyecto: _sn(json['rol_proyecto']),
      );
}

/// Tarea del cronograma de un servicio.
class PortalTarea {
  final String id;
  final String nombre;
  final String estado;
  final String? fechaInicio; // ISO | null
  final String? fechaFin; // ISO | null
  final String? responsable;

  PortalTarea({
    required this.id,
    required this.nombre,
    this.estado = '',
    this.fechaInicio,
    this.fechaFin,
    this.responsable,
  });

  factory PortalTarea.fromJson(Map<String, dynamic> json) => PortalTarea(
        id: _s(json['id']),
        nombre: _s(json['nombre']),
        estado: _s(json['estado']),
        fechaInicio: _sn(json['fecha_inicio']),
        fechaFin: _sn(json['fecha_fin']),
        responsable: _sn(json['responsable']),
      );
}

/// Paso del checklist de un servicio.
class PortalPaso {
  final String nombre;
  final String estado;
  final int orden;

  PortalPaso({required this.nombre, this.estado = '', this.orden = 0});

  factory PortalPaso.fromJson(Map<String, dynamic> json) => PortalPaso(
        nombre: _s(json['nombre']),
        estado: _s(json['estado']),
        orden: _i(json['orden']),
      );
}

/// Servicio dentro del detalle de un proyecto.
class PortalServicio {
  final String id;
  final String nombre;
  final String? descripcion;
  final String estado;
  final String? fechaProgramada; // ISO | null
  final String? fechaInicio; // ISO | null
  final String? fechaFin; // ISO | null
  final int progreso; // 0..100
  final List<PortalPersona> equipo;
  final List<PortalTarea> cronograma;
  final List<PortalPaso> pasos;

  PortalServicio({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.estado = '',
    this.fechaProgramada,
    this.fechaInicio,
    this.fechaFin,
    this.progreso = 0,
    this.equipo = const [],
    this.cronograma = const [],
    this.pasos = const [],
  });

  factory PortalServicio.fromJson(Map<String, dynamic> json) => PortalServicio(
        id: _s(json['id']),
        nombre: _s(json['nombre']),
        descripcion: _sn(json['descripcion']),
        estado: _s(json['estado']),
        fechaProgramada: _sn(json['fecha_programada']),
        fechaInicio: _sn(json['fecha_inicio']),
        fechaFin: _sn(json['fecha_fin']),
        progreso: _i(json['progreso']),
        equipo: _lista(json['equipo'], PortalPersona.fromJson),
        cronograma: _lista(json['cronograma'], PortalTarea.fromJson),
        pasos: _lista(json['pasos'], PortalPaso.fromJson)
          ..sort((a, b) => a.orden.compareTo(b.orden)),
      );
}

/// Equipo intervenido listado en el detalle del proyecto.
class PortalEquipo {
  final String id;
  final String nombre;
  final String? codigo;
  final String? marca;
  final String? modelo;
  final String estado;

  PortalEquipo({
    required this.id,
    required this.nombre,
    this.codigo,
    this.marca,
    this.modelo,
    this.estado = '',
  });

  factory PortalEquipo.fromJson(Map<String, dynamic> json) => PortalEquipo(
        id: _s(json['id']),
        nombre: _s(json['nombre']),
        codigo: _sn(json['codigo']),
        marca: _sn(json['marca']),
        modelo: _sn(json['modelo']),
        estado: _s(json['estado']),
      );
}

/// Respuesta de GET /portal-cliente/proyecto/{id}/detalles.
class PortalProyectoDetalle {
  final PortalProyecto proyecto;
  final List<PortalServicio> servicios;
  final List<PortalPersona> personal;
  final List<PortalEquipo> equipos;

  PortalProyectoDetalle({
    required this.proyecto,
    this.servicios = const [],
    this.personal = const [],
    this.equipos = const [],
  });

  factory PortalProyectoDetalle.fromJson(Map<String, dynamic> json) =>
      PortalProyectoDetalle(
        proyecto: PortalProyecto.fromJson(
          (json['proyecto'] as Map<String, dynamic>?) ?? const {},
        ),
        servicios: _lista(json['servicios'], PortalServicio.fromJson),
        personal: _lista(json['personal'], PortalPersona.fromJson),
        equipos: _lista(json['equipos'], PortalEquipo.fromJson),
      );
}

// ── GET /portal-cliente/documentos ───────────────────────────────────────────

/// Documento publicado para el cliente (informe, certificado, carta, etc.).
class PortalDocumento {
  final String id;
  final String tipo;
  final String titulo;
  final String url;
  final String? fecha; // ISO | null
  final String? createdAt; // ISO | null
  final String? proyecto;
  final String? servicio;

  PortalDocumento({
    required this.id,
    this.tipo = '',
    this.titulo = '',
    this.url = '',
    this.fecha,
    this.createdAt,
    this.proyecto,
    this.servicio,
  });

  factory PortalDocumento.fromJson(Map<String, dynamic> json) =>
      PortalDocumento(
        id: _s(json['id']),
        tipo: _s(json['tipo']),
        titulo: _s(json['titulo']),
        url: _s(json['url']),
        fecha: _sn(json['fecha']),
        createdAt: _sn(json['created_at']),
        proyecto: _sn(json['proyecto']),
        servicio: _sn(json['servicio']),
      );
}

// ── GET /portal-cliente/equipos/historial ────────────────────────────────────

/// Equipo del cliente con su historial/estado de mantenimiento.
class PortalEquipoHistorial {
  final String id;
  final String nombre;
  final String? codigo;
  final String? marca;
  final String? modelo;
  final String? ubicacion;
  final String estado;
  final String estadoIntervencion;
  final String? ultimoMantenimiento; // ISO | null
  final String? proximoMantenimiento; // ISO | null
  final int? frecuenciaMeses;
  final String? proyecto;
  final String? servicio;
  final String? servicioEstado;

  PortalEquipoHistorial({
    required this.id,
    required this.nombre,
    this.codigo,
    this.marca,
    this.modelo,
    this.ubicacion,
    this.estado = '',
    this.estadoIntervencion = '',
    this.ultimoMantenimiento,
    this.proximoMantenimiento,
    this.frecuenciaMeses,
    this.proyecto,
    this.servicio,
    this.servicioEstado,
  });

  factory PortalEquipoHistorial.fromJson(Map<String, dynamic> json) =>
      PortalEquipoHistorial(
        id: _s(json['id']),
        nombre: _s(json['nombre']),
        codigo: _sn(json['codigo']),
        marca: _sn(json['marca']),
        modelo: _sn(json['modelo']),
        ubicacion: _sn(json['ubicacion']),
        estado: _s(json['estado']),
        estadoIntervencion: _s(json['estado_intervencion']),
        ultimoMantenimiento: _sn(json['ultimo_mantenimiento']),
        proximoMantenimiento: _sn(json['proximo_mantenimiento']),
        frecuenciaMeses: _iN(json['frecuencia_meses']),
        proyecto: _sn(json['proyecto']),
        servicio: _sn(json['servicio']),
        servicioEstado: _sn(json['servicio_estado']),
      );
}

// ── GET /portal-cliente/perfil ───────────────────────────────────────────────

/// Perfil del usuario ClienteExterno (datos personales + empresa).
/// Ojo: este endpoint devuelve las claves en camelCase (fotoUrl,
/// fechaCreacion, empresaEmail), a diferencia del resto del contrato.
class PortalPerfil {
  final String id;
  final String nombre;
  final String? apellido;
  final String? correo;
  final String? telefono;
  final String? fotoUrl;
  final String? fechaCreacion; // ISO | null
  final String empresa;
  final String? ruc;
  final String? rol;
  final String? empresaEmail;

  PortalPerfil({
    required this.id,
    required this.nombre,
    this.apellido,
    this.correo,
    this.telefono,
    this.fotoUrl,
    this.fechaCreacion,
    this.empresa = '',
    this.ruc,
    this.rol,
    this.empresaEmail,
  });

  String get nombreCompleto =>
      [nombre, apellido ?? ''].where((p) => p.isNotEmpty).join(' ');

  factory PortalPerfil.fromJson(Map<String, dynamic> json) => PortalPerfil(
        id: _s(json['id']),
        nombre: _s(json['nombre']),
        apellido: _sn(json['apellido']),
        correo: _sn(json['correo']),
        telefono: _sn(json['telefono']),
        fotoUrl: _sn(json['fotoUrl']),
        fechaCreacion: _sn(json['fechaCreacion']),
        empresa: _s(json['empresa']),
        ruc: _sn(json['ruc']),
        rol: _sn(json['rol']),
        empresaEmail: _sn(json['empresaEmail']),
      );
}

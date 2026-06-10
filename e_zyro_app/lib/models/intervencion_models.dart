/// Modelos del flujo "Equipos Intervenidos por servicio" (inspección de campo,
/// informe general, carta de garantía y certificados). Contratos espejo del
/// frontend Angular (equipos-intervenidos / intervencion-equipo / certificado)
/// contra los endpoints `/operaciones/servicio/{id}/equipos-intervenidos/*`.
///
/// NO confundir con `equipo_intervenido_models.dart`, que cubre el dominio
/// global `/equipos-intervenidos/*` (mantenimiento de equipos por cliente).
library;

/// Item de la lista GET /operaciones/servicio/{id}/equipos-intervenidos.
class EquipoIntervenidoServicio {
  final String id;
  final String nombre;
  final String? codigo;

  /// "Referencia": indicaciones físicas de dónde está el equipo.
  /// Editable inline por el técnico (PATCH ubicacion_referencia).
  String? ubicacionReferencia;
  final String? tipoNombre;
  final String? tipoEquipoId;
  final String? marca;
  final String? modelo;
  final String? numeroSerie;

  /// operativo | inoperativo | mantenimiento | en_revision
  final String estado;
  final String? ubicacion;
  final String? zona;
  final String? ultimoMantenimiento;
  final String? proximoMantenimiento;

  /// sin_inspeccion | en_proceso | completado (última inspección en el servicio)
  String estadoIntervencion;
  final String? observaciones;

  EquipoIntervenidoServicio({
    required this.id,
    required this.nombre,
    this.codigo,
    this.ubicacionReferencia,
    this.tipoNombre,
    this.tipoEquipoId,
    this.marca,
    this.modelo,
    this.numeroSerie,
    this.estado = 'operativo',
    this.ubicacion,
    this.zona,
    this.ultimoMantenimiento,
    this.proximoMantenimiento,
    this.estadoIntervencion = 'sin_inspeccion',
    this.observaciones,
  });

  factory EquipoIntervenidoServicio.fromJson(Map<String, dynamic> json) =>
      EquipoIntervenidoServicio(
        id: json['id']?.toString() ?? '',
        nombre: json['nombre'] as String? ?? '',
        codigo: json['codigo'] as String?,
        ubicacionReferencia: json['ubicacion_referencia'] as String?,
        tipoNombre: json['tipo_nombre'] as String?,
        tipoEquipoId: json['tipo_equipo_id']?.toString(),
        marca: json['marca'] as String?,
        modelo: json['modelo'] as String?,
        numeroSerie: json['numero_serie'] as String?,
        estado: json['estado'] as String? ?? 'operativo',
        ubicacion: json['ubicacion'] as String?,
        zona: json['zona'] as String?,
        ultimoMantenimiento: json['ultimo_mantenimiento'] as String?,
        proximoMantenimiento: json['proximo_mantenimiento'] as String?,
        estadoIntervencion:
            json['estado_intervencion'] as String? ?? 'sin_inspeccion',
        observaciones: json['observaciones'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'codigo': codigo,
        'ubicacion_referencia': ubicacionReferencia,
        'tipo_nombre': tipoNombre,
        'tipo_equipo_id': tipoEquipoId,
        'marca': marca,
        'modelo': modelo,
        'numero_serie': numeroSerie,
        'estado': estado,
        'ubicacion': ubicacion,
        'zona': zona,
        'ultimo_mantenimiento': ultimoMantenimiento,
        'proximo_mantenimiento': proximoMantenimiento,
        'estado_intervencion': estadoIntervencion,
        'observaciones': observaciones,
      };
}

/// Paso del checklist de una sesión de inspección (`resultado` JSONB).
class PasoInspeccion {
  final int orden;
  final String nombre;
  final String descripcion;
  bool completado;
  String? fotoUrl;
  String? fotoPublicId;

  PasoInspeccion({
    required this.orden,
    required this.nombre,
    this.descripcion = '',
    this.completado = false,
    this.fotoUrl,
    this.fotoPublicId,
  });

  factory PasoInspeccion.fromJson(Map<String, dynamic> json) => PasoInspeccion(
        orden: (json['orden'] as num?)?.toInt() ?? 0,
        nombre: json['nombre'] as String? ?? '',
        descripcion: json['descripcion'] as String? ?? '',
        completado: json['completado'] as bool? ?? false,
        fotoUrl: json['foto_url'] as String?,
        fotoPublicId: json['foto_public_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'orden': orden,
        'nombre': nombre,
        'descripcion': descripcion,
        'completado': completado,
        'foto_url': fotoUrl,
        'foto_public_id': fotoPublicId,
      };
}

/// Bloque `equipo` de GET .../inspeccion (datos de cabecera del equipo).
class EquipoInspeccionInfo {
  final String id;
  final String nombre;
  final String? codigo;
  final String? tipoNombre;
  final String? ubicacionReferencia;
  final String? clienteNombre;
  final String? descripcion;
  final int? nMantenimientos;
  final String? ultimoMantenimiento;
  final String? proximoMantenimiento;
  final String estado;
  String estadoIntervencion;

  EquipoInspeccionInfo({
    required this.id,
    required this.nombre,
    this.codigo,
    this.tipoNombre,
    this.ubicacionReferencia,
    this.clienteNombre,
    this.descripcion,
    this.nMantenimientos,
    this.ultimoMantenimiento,
    this.proximoMantenimiento,
    this.estado = 'operativo',
    this.estadoIntervencion = 'en_proceso',
  });

  factory EquipoInspeccionInfo.fromJson(Map<String, dynamic> json) =>
      EquipoInspeccionInfo(
        id: json['id']?.toString() ?? '',
        nombre: json['nombre'] as String? ?? '',
        codigo: json['codigo'] as String?,
        tipoNombre: json['tipo_nombre'] as String?,
        ubicacionReferencia: json['ubicacion_referencia'] as String?,
        clienteNombre: json['cliente_nombre'] as String?,
        descripcion: json['descripcion'] as String?,
        nMantenimientos: (json['n_mantenimientos'] as num?)?.toInt(),
        ultimoMantenimiento: json['ultimo_mantenimiento'] as String?,
        proximoMantenimiento: json['proximo_mantenimiento'] as String?,
        estado: json['estado'] as String? ?? 'operativo',
        estadoIntervencion:
            json['estado_intervencion'] as String? ?? 'en_proceso',
      );
}

/// Respuesta de GET .../equipos-intervenidos/{eiId}/inspeccion.
/// El backend crea la sesión si no existe; si el equipo ya está completado
/// para este servicio devuelve la última sesión en modo solo lectura.
class InspeccionActiva {
  final String inspeccionId;
  final String estado; // en_proceso | completado
  final List<PasoInspeccion> pasos;
  final String? observaciones;
  final String? proximaFecha;
  final EquipoInspeccionInfo equipo;

  InspeccionActiva({
    required this.inspeccionId,
    required this.estado,
    required this.pasos,
    this.observaciones,
    this.proximaFecha,
    required this.equipo,
  });

  factory InspeccionActiva.fromJson(Map<String, dynamic> json) =>
      InspeccionActiva(
        inspeccionId: json['inspeccion_id']?.toString() ?? '',
        estado: json['estado'] as String? ?? 'en_proceso',
        pasos: ((json['resultado'] as List?) ?? [])
            .map((e) => PasoInspeccion.fromJson(e as Map<String, dynamic>))
            .toList(),
        observaciones: json['observaciones'] as String?,
        proximaFecha: json['proxima_fecha'] as String?,
        equipo: EquipoInspeccionInfo.fromJson(
            (json['equipo'] as Map<String, dynamic>?) ?? const {}),
      );
}

/// Registro de GET .../equipos-intervenidos/{eiId}/historial (inspecciones
/// completadas; shape de `_map_hi` del backend).
class HistorialInspeccionItem {
  final String id;
  final String estado;
  final List<PasoInspeccion> resultado;
  final String? observaciones;
  final String? proximaFechaMantenimiento;
  final String? fechaInicio;
  final String? fechaFin;

  HistorialInspeccionItem({
    required this.id,
    required this.estado,
    required this.resultado,
    this.observaciones,
    this.proximaFechaMantenimiento,
    this.fechaInicio,
    this.fechaFin,
  });

  factory HistorialInspeccionItem.fromJson(Map<String, dynamic> json) =>
      HistorialInspeccionItem(
        id: json['id']?.toString() ?? '',
        estado: json['estado'] as String? ?? '',
        resultado: ((json['resultado'] as List?) ?? [])
            .map((e) => PasoInspeccion.fromJson(e as Map<String, dynamic>))
            .toList(),
        observaciones: json['observaciones'] as String?,
        proximaFechaMantenimiento:
            json['proxima_fecha_mantenimiento'] as String?,
        fechaInicio: json['fecha_inicio'] as String?,
        fechaFin: json['fecha_fin'] as String?,
      );
}

/// Item de catálogo GET /logistica/tipos-equipo y GET /epp.
class CatalogoItemSimple {
  final String id;
  final String nombre;

  const CatalogoItemSimple({required this.id, required this.nombre});

  factory CatalogoItemSimple.fromJson(Map<String, dynamic> json) =>
      CatalogoItemSimple(
        id: json['id']?.toString() ?? '',
        nombre: json['nombre'] as String? ?? '',
      );
}

// ─── Informe General de Pozos a Tierra ────────────────────────────────────────

/// Fila de materiales del informe (defaults del tipo + solicitados del servicio).
class MaterialInforme {
  final String nombre;
  final String unidad;
  final String caracteristicas;

  const MaterialInforme({
    required this.nombre,
    required this.unidad,
    this.caracteristicas = '-',
  });

  factory MaterialInforme.fromJson(Map<String, dynamic> json) =>
      MaterialInforme(
        nombre: json['nombre'] as String? ?? '',
        unidad: json['unidad'] as String? ?? 'UND.',
        caracteristicas: json['caracteristicas'] as String? ?? '-',
      );

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'unidad': unidad,
        'caracteristicas': caracteristicas,
      };
}

/// Fila de herramientas del informe.
class HerramientaInforme {
  final String serie;
  final String nombre;
  final String marca;

  const HerramientaInforme({
    this.serie = '-',
    required this.nombre,
    this.marca = '-',
  });

  factory HerramientaInforme.fromJson(Map<String, dynamic> json) =>
      HerramientaInforme(
        serie: json['serie'] as String? ?? '-',
        nombre: json['nombre'] as String? ?? '',
        marca: json['marca'] as String? ?? '-',
      );

  Map<String, dynamic> toJson() => {
        'serie': serie,
        'nombre': nombre,
        'marca': marca,
      };
}

/// Empleado del proyecto disponible para el informe (precarga).
class PersonalInforme {
  final String id;
  final String nombre;
  final String cargo;
  final String rolSugerido;

  const PersonalInforme({
    required this.id,
    required this.nombre,
    this.cargo = '',
    this.rolSugerido = 'Técnico',
  });

  factory PersonalInforme.fromJson(Map<String, dynamic> json) =>
      PersonalInforme(
        id: json['id']?.toString() ?? '',
        nombre: json['nombre'] as String? ?? '',
        cargo: json['cargo'] as String? ?? '',
        rolSugerido: json['rol_sugerido'] as String? ?? 'Técnico',
      );
}

/// Respuesta de GET /operaciones/servicio/{id}/informe/precarga.
class PrecargaInforme {
  final String servicioNombre;
  final String? proyectoNombre;
  final String tipoDocumento;
  final String nroDocumento;
  final String? clienteNombre;
  final List<MaterialInforme> materialesSolicitados;
  final List<HerramientaInforme> herramientasSolicitadas;
  final List<PersonalInforme> personal;

  const PrecargaInforme({
    this.servicioNombre = '',
    this.proyectoNombre,
    this.tipoDocumento = '',
    this.nroDocumento = '',
    this.clienteNombre,
    this.materialesSolicitados = const [],
    this.herramientasSolicitadas = const [],
    this.personal = const [],
  });

  factory PrecargaInforme.fromJson(Map<String, dynamic> json) {
    final srv = (json['servicio'] as Map<String, dynamic>?) ?? const {};
    return PrecargaInforme(
      servicioNombre: srv['nombre'] as String? ?? '',
      proyectoNombre: srv['proyecto_nombre'] as String?,
      tipoDocumento: srv['tipo_documento'] as String? ?? '',
      nroDocumento: srv['nro_documento'] as String? ?? '',
      clienteNombre: srv['cliente_nombre'] as String?,
      materialesSolicitados: ((json['materiales_solicitados'] as List?) ?? [])
          .map((e) => MaterialInforme.fromJson(e as Map<String, dynamic>))
          .toList(),
      herramientasSolicitadas:
          ((json['herramientas_solicitadas'] as List?) ?? [])
              .map((e) => HerramientaInforme.fromJson(e as Map<String, dynamic>))
              .toList(),
      personal: ((json['personal'] as List?) ?? [])
          .map((e) => PersonalInforme.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─── Dashboard de Operaciones (GET /operaciones/dashboard) ───────────────────

class MetricaOperaciones {
  final String id;
  final String titulo;
  final int valor;
  final String colorIcono; // hex "#rrggbb"
  final bool resaltado;

  const MetricaOperaciones({
    required this.id,
    required this.titulo,
    required this.valor,
    this.colorIcono = '#8FD11B',
    this.resaltado = false,
  });

  factory MetricaOperaciones.fromJson(Map<String, dynamic> json) =>
      MetricaOperaciones(
        id: json['id'] as String? ?? '',
        titulo: json['titulo'] as String? ?? '',
        valor: (json['valor'] as num?)?.toInt() ?? 0,
        colorIcono: json['colorIcono'] as String? ?? '#8FD11B',
        resaltado: json['resaltado'] as bool? ?? false,
      );
}

class ServicioDashboard {
  final String id;
  final String cliente;
  final String tipoServicio;
  final String ubicacion;
  final String fechaStr;
  final String horaStr;
  final String estado; // Pendiente | Activo | Completado
  final bool alerta;
  final String estadoColor; // verde | amarillo | rojo

  const ServicioDashboard({
    required this.id,
    required this.cliente,
    required this.tipoServicio,
    this.ubicacion = '',
    this.fechaStr = '',
    this.horaStr = '',
    this.estado = 'Pendiente',
    this.alerta = false,
    this.estadoColor = 'amarillo',
  });

  factory ServicioDashboard.fromJson(Map<String, dynamic> json) =>
      ServicioDashboard(
        id: json['id']?.toString() ?? '',
        cliente: json['cliente'] as String? ?? '',
        tipoServicio: json['tipoServicio'] as String? ?? '',
        ubicacion: json['ubicacion'] as String? ?? '',
        fechaStr: json['fechaStr'] as String? ?? '',
        horaStr: json['horaStr'] as String? ?? '',
        estado: json['estado'] as String? ?? 'Pendiente',
        alerta: json['alerta'] as bool? ?? false,
        estadoColor: json['estadoColor'] as String? ?? 'amarillo',
      );
}

class DashboardOperaciones {
  final List<MetricaOperaciones> metricas;
  final List<ServicioDashboard> servicios;

  const DashboardOperaciones({
    this.metricas = const [],
    this.servicios = const [],
  });

  factory DashboardOperaciones.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map<String, dynamic>?) ?? json;
    return DashboardOperaciones(
      metricas: ((data['metricas'] as List?) ?? [])
          .map((e) => MetricaOperaciones.fromJson(e as Map<String, dynamic>))
          .toList(),
      servicios: ((data['servicios'] as List?) ?? [])
          .map((e) => ServicioDashboard.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

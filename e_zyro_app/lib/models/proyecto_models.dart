// ── KPIs ─────────────────────────────────────────────────────────────────────

class KpisProyectos {
  final int totalProyectos;
  final int serviciosCompletados;
  final int serviciosPendientes;
  final int tasaAvance;

  const KpisProyectos({
    required this.totalProyectos,
    required this.serviciosCompletados,
    required this.serviciosPendientes,
    required this.tasaAvance,
  });

  factory KpisProyectos.fromJson(Map<String, dynamic> j) => KpisProyectos(
        totalProyectos: j['total_proyectos'] as int? ?? 0,
        serviciosCompletados: j['servicios_completados'] as int? ?? 0,
        serviciosPendientes: j['servicios_pendientes'] as int? ?? 0,
        tasaAvance: j['tasa_avance'] as int? ?? 0,
      );
}

// ── Proyecto (ítem de lista) ──────────────────────────────────────────────────

class ProyectoItem {
  final String id;
  final String ordenTrabajo;
  final String nombreProyecto;
  final String estado;
  final String? fechaInicio;
  final String? fechaFinEstimada;
  final String cliente;
  final int totalServicios;
  final int serviciosCompletados;
  final String jefeNombre;

  const ProyectoItem({
    required this.id,
    required this.ordenTrabajo,
    required this.nombreProyecto,
    required this.estado,
    this.fechaInicio,
    this.fechaFinEstimada,
    required this.cliente,
    required this.totalServicios,
    required this.serviciosCompletados,
    required this.jefeNombre,
  });

  double get progreso =>
      totalServicios == 0 ? 0 : serviciosCompletados / totalServicios;

  factory ProyectoItem.fromJson(Map<String, dynamic> j) => ProyectoItem(
        id: j['id'] as String? ?? '',
        ordenTrabajo: j['orden_trabajo'] as String? ?? '',
        nombreProyecto: j['nombre_proyecto'] as String? ?? '',
        estado: j['estado'] as String? ?? 'Pendiente',
        fechaInicio: j['fecha_inicio'] as String?,
        fechaFinEstimada: j['fecha_fin_estimada'] as String?,
        cliente: j['cliente'] as String? ?? 'Sin Cliente',
        totalServicios: j['total_servicios'] as int? ?? 0,
        serviciosCompletados: j['servicios_completados'] as int? ?? 0,
        jefeNombre: j['jefe_nombre'] as String? ?? 'Sin asignar',
      );
}

// ── Respuesta completa de /operaciones/proyectos ──────────────────────────────

class ProyectosConKpis {
  final KpisProyectos kpis;
  final List<ProyectoItem> proyectos;

  const ProyectosConKpis({required this.kpis, required this.proyectos});

  factory ProyectosConKpis.fromJson(Map<String, dynamic> j) => ProyectosConKpis(
        kpis: KpisProyectos.fromJson(j['kpis'] as Map<String, dynamic>),
        proyectos: (j['proyectos'] as List? ?? [])
            .map((e) => ProyectoItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Servicio (ítem de lista por proyecto) ─────────────────────────────────────

class ServicioItem {
  final String id;
  final String nombre;
  final String? descripcion;
  final String estado;
  final int orden;
  final String? fechaProgramada;
  final String? fechaInicio;
  final String? fechaFin;
  final String estadoColor;
  final int totalProcedimientos;
  final int procedimientosCompletados;

  const ServicioItem({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.estado,
    required this.orden,
    this.fechaProgramada,
    this.fechaInicio,
    this.fechaFin,
    required this.estadoColor,
    this.totalProcedimientos = 0,
    this.procedimientosCompletados = 0,
  });

  factory ServicioItem.fromJson(Map<String, dynamic> j) => ServicioItem(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        descripcion: j['descripcion'] as String?,
        estado: j['estado'] as String? ?? 'Pendiente',
        orden: j['orden'] as int? ?? 1,
        fechaProgramada: j['fecha_programada'] as String?,
        fechaInicio: j['fecha_inicio'] as String?,
        fechaFin: j['fecha_fin'] as String?,
        estadoColor: j['estado_color'] as String? ?? 'amarillo',
        totalProcedimientos: j['total_procedimientos'] as int? ?? 0,
        procedimientosCompletados: j['procedimientos_completados'] as int? ?? 0,
      );
}

// ── Evidencia ─────────────────────────────────────────────────────────────────

class EvidenciaDetalle {
  final String id;
  final String urlCloudinary;
  final String descripcion;
  final String fechaCaptura;
  final String etapa; // 'antes' | 'durante' | 'despues' (puede venir vacío)

  const EvidenciaDetalle({
    required this.id,
    required this.urlCloudinary,
    required this.descripcion,
    required this.fechaCaptura,
    this.etapa = '',
  });

  String get etapaLower => etapa.toLowerCase();

  factory EvidenciaDetalle.fromJson(Map<String, dynamic> j) => EvidenciaDetalle(
        id: j['id'] as String? ?? '',
        urlCloudinary: j['url_cloudinary'] as String? ?? '',
        descripcion: j['descripcion'] as String? ?? '',
        fechaCaptura: j['fecha_captura'] as String? ?? '',
        etapa: j['etapa'] as String? ?? '',
      );
}

// ── Procedimiento ─────────────────────────────────────────────────────────────

class ProcedimientoDetalle {
  final String id;
  final String nombre;
  final String descripcion;
  final int orden;
  final String estado;
  final List<EvidenciaDetalle> evidencias;

  const ProcedimientoDetalle({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.orden,
    required this.estado,
    required this.evidencias,
  });

  factory ProcedimientoDetalle.fromJson(Map<String, dynamic> j) =>
      ProcedimientoDetalle(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        descripcion: j['descripcion'] as String? ?? '',
        orden: j['orden'] as int? ?? 0,
        estado: j['estado'] as String? ?? 'pendiente',
        evidencias: (j['evidencias'] as List? ?? [])
            .map((e) => EvidenciaDetalle.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Miembro del equipo ────────────────────────────────────────────────────────

class MiembroEquipo {
  final String id;
  final String nombre;
  final String apellido;
  final String fotoUrl;
  final String cargo;
  final String rolProyecto;

  const MiembroEquipo({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.fotoUrl,
    required this.cargo,
    required this.rolProyecto,
  });

  String get nombreCompleto => '$nombre $apellido'.trim();

  factory MiembroEquipo.fromJson(Map<String, dynamic> j) => MiembroEquipo(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        apellido: j['apellido'] as String? ?? '',
        fotoUrl: j['foto_url'] as String? ?? '',
        cargo: j['cargo'] as String? ?? 'Sin Cargo',
        rolProyecto: j['rol_proyecto'] as String? ?? 'Técnico',
      );
}

// ── Usuario técnico disponible para asignación ───────────────────────────────

class UsuarioTecnico {
  final String id;
  final String nombre;
  final String apellido;
  final String fotoUrl;
  final String cargo;

  const UsuarioTecnico({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.fotoUrl,
    required this.cargo,
  });

  String get nombreCompleto => '$nombre $apellido'.trim();

  factory UsuarioTecnico.fromJson(Map<String, dynamic> j) => UsuarioTecnico(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        apellido: j['apellido'] as String? ?? '',
        fotoUrl: j['foto_url'] as String? ?? '',
        cargo: j['cargo'] as String? ?? 'Técnico de Campo',
      );
}

// ── Item de material ──────────────────────────────────────────────────────────

class ItemMaterial {
  final String id;
  final String requerimientoId;
  final String nombre;
  final String unidad;
  final int cantidad;
  final String estadoReq;

  const ItemMaterial({
    required this.id,
    required this.requerimientoId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    required this.estadoReq,
  });

  factory ItemMaterial.fromJson(Map<String, dynamic> j) => ItemMaterial(
        id: j['id'] as String? ?? '',
        requerimientoId: j['requerimiento_id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        unidad: j['unidad'] as String? ?? 'Und',
        cantidad: j['cantidad'] as int? ?? 0,
        estadoReq: j['estado_req'] as String? ?? 'pendiente',
      );
}

// ── Material del catálogo (búsqueda en almacén) ───────────────────────────────

class MaterialBusqueda {
  final String id;
  final String nombre;
  final String unidad;
  final int stock;

  const MaterialBusqueda({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.stock,
  });

  factory MaterialBusqueda.fromJson(Map<String, dynamic> j) => MaterialBusqueda(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        unidad: j['unidad'] as String? ?? 'Und',
        stock: j['stock'] as int? ?? 0,
      );
}

// ── Item del borrador de materiales (persistente en BD) ───────────────────────

class BorradorItem {
  final String id; // requerimiento_detalle.id
  final String? materialId;
  final String nombre;
  final String unidad;
  final int cantidad;
  final bool esNuevo; // compra externa (material_id == null)
  final String? especificacion;
  final String agregadoPorNombre;
  final String agregadoPorFoto;

  const BorradorItem({
    required this.id,
    this.materialId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    required this.esNuevo,
    this.especificacion,
    this.agregadoPorNombre = '',
    this.agregadoPorFoto = '',
  });

  factory BorradorItem.fromJson(Map<String, dynamic> j) => BorradorItem(
        id: j['id'] as String? ?? '',
        materialId: j['material_id'] as String?,
        nombre: j['nombre'] as String? ?? '',
        unidad: j['unidad'] as String? ?? 'Und',
        cantidad: j['cantidad'] as int? ?? 1,
        esNuevo: j['es_nuevo'] as bool? ?? (j['material_id'] == null),
        especificacion: j['especificacion'] as String?,
        agregadoPorNombre: j['agregado_por_nombre'] as String? ?? '',
        agregadoPorFoto: j['agregado_por_foto'] as String? ?? '',
      );

  BorradorItem copyWith({int? cantidad, String? nombre, String? especificacion}) =>
      BorradorItem(
        id: id,
        materialId: materialId,
        nombre: nombre ?? this.nombre,
        unidad: unidad,
        cantidad: cantidad ?? this.cantidad,
        esNuevo: esNuevo,
        especificacion: especificacion ?? this.especificacion,
        agregadoPorNombre: agregadoPorNombre,
        agregadoPorFoto: agregadoPorFoto,
      );
}

class Borrador {
  final String? requerimientoId;
  final List<BorradorItem> items;

  const Borrador({this.requerimientoId, required this.items});

  factory Borrador.fromJson(Map<String, dynamic> j) => Borrador(
        requerimientoId: j['requerimiento_id'] as String?,
        items: (j['items'] as List? ?? [])
            .map((e) => BorradorItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Nota de seguimiento ───────────────────────────────────────────────────────

class NotaSeguimiento {
  final String id;
  final String fecha;
  final String texto;
  final String autor;

  const NotaSeguimiento({
    required this.id,
    required this.fecha,
    required this.texto,
    required this.autor,
  });

  factory NotaSeguimiento.fromJson(Map<String, dynamic> j) => NotaSeguimiento(
        id: j['id'] as String? ?? '',
        fecha: j['fecha'] as String? ?? '',
        texto: j['texto'] as String? ?? '',
        autor: j['autor'] as String? ?? '',
      );
}

// ── Detalle completo de servicio ──────────────────────────────────────────────

class ServicioDetalle {
  final String id;
  final String proyectoId;
  final String cliente;
  final String tipoServicio;
  final String ubicacion;
  final String fechaStr;
  final String horaStr;
  final String descripcion;
  final String estado;
  final double progreso;
  final List<MiembroEquipo> equipo;
  final List<ProcedimientoDetalle> procedimientos;
  final List<ItemMaterial> materialesAsignados;
  final List<ItemMaterial> materialesSolicitados;
  final List<NotaSeguimiento> notas;

  const ServicioDetalle({
    required this.id,
    required this.proyectoId,
    required this.cliente,
    required this.tipoServicio,
    required this.ubicacion,
    required this.fechaStr,
    required this.horaStr,
    required this.descripcion,
    required this.estado,
    required this.progreso,
    required this.equipo,
    required this.procedimientos,
    required this.materialesAsignados,
    required this.materialesSolicitados,
    required this.notas,
  });

  factory ServicioDetalle.fromJson(Map<String, dynamic> j) => ServicioDetalle(
        id: j['id'] as String? ?? '',
        proyectoId: j['proyecto_id'] as String? ?? '',
        cliente: j['cliente'] as String? ?? '',
        tipoServicio: j['tipo_servicio'] as String? ?? '',
        ubicacion: j['ubicacion'] as String? ?? '',
        fechaStr: j['fecha_str'] as String? ?? '',
        horaStr: j['hora_str'] as String? ?? '',
        descripcion: j['descripcion'] as String? ?? '',
        estado: j['estado'] as String? ?? 'Pendiente',
        progreso: (j['progreso'] as num? ?? 0).toDouble(),
        equipo: (j['equipo'] as List? ?? [])
            .map((e) => MiembroEquipo.fromJson(e as Map<String, dynamic>))
            .toList(),
        procedimientos: (j['procedimientos'] as List? ?? [])
            .map((e) =>
                ProcedimientoDetalle.fromJson(e as Map<String, dynamic>))
            .toList(),
        materialesAsignados: (j['materiales_asignados'] as List? ?? [])
            .map((e) => ItemMaterial.fromJson(e as Map<String, dynamic>))
            .toList(),
        materialesSolicitados: (j['materiales_solicitados'] as List? ?? [])
            .map((e) => ItemMaterial.fromJson(e as Map<String, dynamic>))
            .toList(),
        notas: (j['notas'] as List? ?? [])
            .map((e) => NotaSeguimiento.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Modelo legacy (no eliminar, se usa en dashboard) ─────────────────────────

class ProyectoServicio {
  final String id;
  final String empresa;
  final String tipoServicio;
  final String ubicacion;
  final String estado;
  final String? supervisor;
  final String? fechaInicio;
  final String? fechaFin;
  final String? telefono;
  final bool urgente;

  const ProyectoServicio({
    required this.id,
    required this.empresa,
    required this.tipoServicio,
    required this.ubicacion,
    required this.estado,
    this.supervisor,
    this.fechaInicio,
    this.fechaFin,
    this.telefono,
    this.urgente = false,
  });

  factory ProyectoServicio.fromJson(Map<String, dynamic> j) => ProyectoServicio(
        id: j['id'] as String? ?? '',
        empresa: j['empresa'] as String? ?? '',
        tipoServicio: j['tipo_servicio'] as String? ?? '',
        ubicacion: j['ubicacion'] as String? ?? '',
        estado: _normalizeEstado(j['estado'] as String? ?? ''),
        supervisor: j['supervisor'] as String?,
        fechaInicio: j['fecha_inicio'] as String?,
        fechaFin: j['fecha_fin'] as String?,
        telefono: j['telefono'] as String?,
        urgente: j['urgente'] as bool? ?? false,
      );

  static String _normalizeEstado(String raw) => switch (raw.toLowerCase()) {
        'activo' => 'Activo',
        'completado' => 'Completado',
        _ => 'Pendiente',
      };
}

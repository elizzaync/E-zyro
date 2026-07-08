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
  // Avance por TAREAS del cronograma (el backend ya no envía procedimientos).
  final int totalTareas;
  final int tareasCompletadas;

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
    this.totalTareas = 0,
    this.tareasCompletadas = 0,
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
        totalTareas: j['total_tareas'] as int? ?? 0,
        tareasCompletadas: j['tareas_completadas'] as int? ?? 0,
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

// ── Procedimiento (paso FIJO del servicio: evidencias + avance/informe) ───────

class ProcedimientoDetalle {
  final String id;
  final String nombre;
  final String descripcion;
  final int orden;
  String estado; // mutable: permite toggle optimista con rollback
  final List<EvidenciaDetalle> evidencias;
  // Campos legacy del cronograma: el backend ya NO los envía aquí (viven en
  // Tarea). Se conservan opcionales para compatibilidad; siempre null.
  final String? responsableId;
  final String? fechaInicioTarea;
  final String? fechaLimite;

  ProcedimientoDetalle({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.orden,
    required this.estado,
    required this.evidencias,
    this.responsableId,
    this.fechaInicioTarea,
    this.fechaLimite,
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
        responsableId: j['responsable_id'] as String?,
        fechaInicioTarea: j['fecha_inicio_tarea'] as String?,
        fechaLimite: j['fecha_limite'] as String?,
      );
}

// ── Tarea (cronograma: responsable + fechas, la asigna el jefe) ───────────────

class TareaDetalle {
  final String id;
  final String nombre;
  final String descripcion;
  final int orden;
  String estado; // mutable: toggle optimista con rollback
  final String? responsableId; // empleado.id responsable de la tarea
  final String? fechaInicioTarea; // YYYY-MM-DD
  final String? fechaLimite; // YYYY-MM-DD

  TareaDetalle({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.orden,
    required this.estado,
    this.responsableId,
    this.fechaInicioTarea,
    this.fechaLimite,
  });

  factory TareaDetalle.fromJson(Map<String, dynamic> j) => TareaDetalle(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        descripcion: j['descripcion'] as String? ?? '',
        orden: j['orden'] as int? ?? 0,
        estado: j['estado'] as String? ?? 'pendiente',
        responsableId: j['responsable_id'] as String?,
        fechaInicioTarea: j['fecha_inicio_tarea'] as String?,
        fechaLimite: j['fecha_limite'] as String?,
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

// ── Técnico disponible para asignación (HU-13) ───────────────────────────────

class TecnicoDisponible {
  final String id; // empleado.id
  final String usuarioId;
  final String nombre;
  final String apellido;
  final String cargo;
  final String fotoUrl;

  /// Nombre del grupo de trabajo al que ya pertenece (null si ninguno).
  /// Si no es null, al seleccionarlo se pide confirmación (alerta de grupo).
  final String? grupoActual;

  const TecnicoDisponible({
    required this.id,
    required this.usuarioId,
    required this.nombre,
    required this.apellido,
    required this.cargo,
    required this.fotoUrl,
    this.grupoActual,
  });

  String get nombreCompleto => '$nombre $apellido'.trim();

  String get iniciales {
    final n = nombre.isNotEmpty ? nombre[0] : '';
    final a = apellido.isNotEmpty ? apellido[0] : '';
    final ini = '$n$a'.toUpperCase();
    return ini.isNotEmpty ? ini : '?';
  }

  factory TecnicoDisponible.fromJson(Map<String, dynamic> j) =>
      TecnicoDisponible(
        id: (j['id'] ?? '').toString(),
        usuarioId: (j['usuario_id'] ?? '').toString(),
        nombre: j['nombre'] as String? ?? '',
        apellido: j['apellido'] as String? ?? '',
        cargo: j['cargo'] as String? ?? 'Técnico',
        fotoUrl: j['foto_url'] as String? ?? '',
        grupoActual:
            (j['grupo_actual'] ?? j['grupo_nombre']) as String?,
      );

  /// Construye un técnico a partir de un miembro de equipo del servicio
  /// (usado en modo editar para precargar el equipo ya asignado).
  factory TecnicoDisponible.fromMiembro(MiembroEquipo m) => TecnicoDisponible(
        id: m.id,
        usuarioId: '',
        nombre: m.nombre,
        apellido: m.apellido,
        cargo: m.cargo,
        fotoUrl: m.fotoUrl,
        grupoActual: null,
      );
}

class GrupoDisponible {
  final String id;
  final String nombre;
  final String jefeNombre;
  final List<TecnicoDisponible> miembros;

  const GrupoDisponible({
    required this.id,
    required this.nombre,
    required this.jefeNombre,
    required this.miembros,
  });

  factory GrupoDisponible.fromJson(Map<String, dynamic> j) => GrupoDisponible(
        id: (j['id'] ?? '').toString(),
        nombre: j['nombre'] as String? ?? '',
        jefeNombre: j['jefe_nombre'] as String? ?? '',
        miembros: (j['miembros'] as List? ?? [])
            .map((e) => TecnicoDisponible.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PersonalTecnicos {
  final List<TecnicoDisponible> tecnicos;
  final List<GrupoDisponible> grupos;

  const PersonalTecnicos({required this.tecnicos, required this.grupos});

  factory PersonalTecnicos.fromJson(Map<String, dynamic> j) => PersonalTecnicos(
        tecnicos: (j['tecnicos'] as List? ?? [])
            .map((e) => TecnicoDisponible.fromJson(e as Map<String, dynamic>))
            .toList(),
        grupos: (j['grupos'] as List? ?? [])
            .map((e) => GrupoDisponible.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Detalle de un cruce de horario detectado al asignar un técnico a una tarea.
class ConflictoHorario {
  final String tarea;
  final String servicioNombre;
  final String fechaInicio;
  final String fechaFin;
  final String estado;

  const ConflictoHorario({
    required this.tarea,
    required this.servicioNombre,
    required this.fechaInicio,
    required this.fechaFin,
    required this.estado,
  });

  factory ConflictoHorario.fromJson(Map<String, dynamic> j) => ConflictoHorario(
        tarea: j['tarea'] as String? ?? '',
        servicioNombre: j['servicio_nombre'] as String? ?? '',
        fechaInicio: (j['fecha_inicio'] ?? '').toString(),
        fechaFin: (j['fecha_fin'] ?? '').toString(),
        estado: j['estado'] as String? ?? '',
      );

  String get mensaje =>
      'Ya tiene la tarea "$tarea" en "$servicioNombre" ($fechaInicio → $fechaFin).';
}

// ── Cliente (para crear/editar proyecto) ──────────────────────────────────────

class ClienteBasico {
  final String id;
  final String razonSocial;
  final String? ruc;

  const ClienteBasico({
    required this.id,
    required this.razonSocial,
    this.ruc,
  });

  factory ClienteBasico.fromJson(Map<String, dynamic> j) => ClienteBasico(
        id: (j['id'] ?? '').toString(),
        razonSocial: j['razon_social'] as String? ?? '',
        ruc: j['ruc'] as String?,
      );
}

// ── Servicio del catálogo (para crear/editar servicio) ────────────────────────

class CatalogoServicio {
  final String id;
  final String nombre;
  final String tipoTrabajo;
  final String? descripcion;
  final bool activo;

  const CatalogoServicio({
    required this.id,
    required this.nombre,
    required this.tipoTrabajo,
    this.descripcion,
    this.activo = true,
  });

  factory CatalogoServicio.fromJson(Map<String, dynamic> j) => CatalogoServicio(
        id: (j['id'] ?? '').toString(),
        nombre: j['nombre'] as String? ?? '',
        tipoTrabajo: j['tipo_trabajo'] as String? ?? '',
        descripcion: j['descripcion'] as String?,
        activo: j['activo'] as bool? ?? true,
      );
}

// ── Persona elegible como Líder / Responsable del servicio ────────────────────

class PersonaServicio {
  final String id; // empleado.id
  final String nombre;
  final String apellido;
  final String? cargo;
  final String? fotoUrl;

  const PersonaServicio({
    required this.id,
    required this.nombre,
    required this.apellido,
    this.cargo,
    this.fotoUrl,
  });

  String get nombreCompleto => '$nombre $apellido'.trim();

  factory PersonaServicio.fromJson(Map<String, dynamic> j) => PersonaServicio(
        id: (j['id'] ?? '').toString(),
        nombre: j['nombre'] as String? ?? '',
        apellido: j['apellido'] as String? ?? '',
        cargo: j['cargo'] as String?,
        fotoUrl: j['foto_url'] as String?,
      );
}

// ── Detalle de proyecto (para edición) ────────────────────────────────────────

class ProyectoEdit {
  final String id;
  final String nombreProyecto;
  final String clienteId;
  final String ordenTrabajo;
  final String estado;
  final String? fechaInicio;
  final String? fechaFinEstimada;
  final String? ordenCompraCliente;

  const ProyectoEdit({
    required this.id,
    required this.nombreProyecto,
    required this.clienteId,
    required this.ordenTrabajo,
    required this.estado,
    this.fechaInicio,
    this.fechaFinEstimada,
    this.ordenCompraCliente,
  });

  factory ProyectoEdit.fromJson(Map<String, dynamic> j) => ProyectoEdit(
        id: (j['id'] ?? '').toString(),
        nombreProyecto: j['nombre_proyecto'] as String? ?? '',
        clienteId: (j['cliente_id'] ?? '').toString(),
        ordenTrabajo: j['orden_trabajo'] as String? ?? '',
        estado: j['estado'] as String? ?? 'Pendiente',
        fechaInicio: j['fecha_inicio'] as String?,
        fechaFinEstimada: j['fecha_fin_estimada'] as String?,
        ordenCompraCliente: j['orden_compra_cliente'] as String?,
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
  final String tipo; // material | herramienta

  const ItemMaterial({
    required this.id,
    required this.requerimientoId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    required this.estadoReq,
    this.tipo = 'material',
  });

  factory ItemMaterial.fromJson(Map<String, dynamic> j) => ItemMaterial(
        id: j['id'] as String? ?? '',
        requerimientoId: j['requerimiento_id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        unidad: j['unidad'] as String? ?? 'Und',
        cantidad: j['cantidad'] as int? ?? 0,
        estadoReq: j['estado_req'] as String? ?? 'pendiente',
        tipo: j['tipo'] as String? ?? 'material',
      );
}

// ── Material del catálogo (búsqueda en almacén) ───────────────────────────────

class MaterialBusqueda {
  final String id;
  final String nombre;
  final String unidad;
  final int stock;
  final String tipo; // material | herramienta (del catálogo)

  const MaterialBusqueda({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.stock,
    this.tipo = 'material',
  });

  factory MaterialBusqueda.fromJson(Map<String, dynamic> j) => MaterialBusqueda(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        unidad: j['unidad'] as String? ?? 'Und',
        stock: j['stock'] as int? ?? 0,
        tipo: j['tipo'] as String? ?? 'material',
      );
}

// ── Equipo / Herramienta del inventario (búsqueda para solicitar) ─────────────

class EquipoBusqueda {
  final String id;
  final String nombre;
  final String clase; // equipo | herramienta
  final int cantidad;
  final String estado;

  const EquipoBusqueda({
    required this.id,
    required this.nombre,
    required this.clase,
    required this.cantidad,
    required this.estado,
  });

  bool get esHerramienta => clase == 'herramienta';

  factory EquipoBusqueda.fromJson(Map<String, dynamic> j) => EquipoBusqueda(
        id: (j['id'] ?? '').toString(),
        nombre: j['nombre'] as String? ?? '',
        clase: j['clase'] as String? ?? 'equipo',
        cantidad: (j['cantidad'] as num? ?? 0).toInt(),
        estado: j['estado'] as String? ?? 'operativo',
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
  double progreso; // mutable: refleja el progreso optimista al togglear tareas
  final List<MiembroEquipo> equipo;
  final List<ProcedimientoDetalle> procedimientos; // pasos fijos (avance)
  final List<TareaDetalle> tareas; // cronograma (responsable + fechas)
  final List<ItemMaterial> materialesAsignados;
  final List<ItemMaterial> materialesSolicitados;
  final List<NotaSeguimiento> notas;
  // Metadatos para el modal de edición de servicio
  final String? catalogoServicioId;
  final String? fechaProgramada;
  final String? fechaInicio;
  final String? fechaFin;
  final String? liderId;
  final String? responsableId;
  final String? zonaEjecucion;
  final String? ubicacionId;
  final String? zonaId;
  final String? alcance;
  final String? tipoDocumentoCliente;
  final String? nroDocumento;
  final bool inspeccionEquiposActiva;
  // false = el usuario no está designado: solo cabecera (lectura), sin datos de trabajo.
  final bool accesoCompleto;
  // true = el tipo de servicio no tiene procedimientos estándar definidos, así
  // que este servicio quedó sin ellos (no bloquea, solo alerta — ver Procedimientos Estándar).
  final bool sinProcedimientosEstandar;

  ServicioDetalle({
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
    this.tareas = const [],
    required this.materialesAsignados,
    required this.materialesSolicitados,
    required this.notas,
    this.catalogoServicioId,
    this.fechaProgramada,
    this.fechaInicio,
    this.fechaFin,
    this.liderId,
    this.responsableId,
    this.zonaEjecucion,
    this.ubicacionId,
    this.zonaId,
    this.alcance,
    this.tipoDocumentoCliente,
    this.nroDocumento,
    this.inspeccionEquiposActiva = false,
    this.accesoCompleto = true,
    this.sinProcedimientosEstandar = false,
  });

  /// Estado terminal del servicio: el backend usa 'Completado', pero en
  /// algunos flujos llega 'finalizado'/'terminado'. Comparación case-insensitive.
  bool get esTerminado => const {'completado', 'finalizado', 'terminado'}
      .contains(estado.trim().toLowerCase());

  bool get esCancelado => estado.trim().toLowerCase() == 'cancelado';

  /// Cerrado = terminado o cancelado → solo lectura.
  bool get esCerrado => esTerminado || esCancelado;

  /// En fase de ejecución. El backend usa 'En_Proceso'; se aceptan variantes.
  bool get esEnEjecucion => const {'en_proceso', 'en proceso', 'activo'}
      .contains(estado.trim().toLowerCase());

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
        tareas: (j['tareas'] as List? ?? [])
            .map((e) => TareaDetalle.fromJson(e as Map<String, dynamic>))
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
        catalogoServicioId: j['catalogo_servicio_id'] as String?,
        fechaProgramada: j['fecha_programada'] as String?,
        fechaInicio: j['fecha_inicio'] as String?,
        fechaFin: j['fecha_fin'] as String?,
        liderId: j['lider_id'] as String?,
        responsableId: j['responsable_id'] as String?,
        zonaEjecucion: j['zona_ejecucion'] as String?,
        ubicacionId: j['ubicacion_id'] as String?,
        zonaId: j['zona_id'] as String?,
        alcance: j['alcance'] as String?,
        tipoDocumentoCliente: j['tipo_documento_cliente'] as String?,
        nroDocumento: j['nro_documento'] as String?,
        // El backend desplegado expone `es_mantenimiento`; el campo nuevo
        // `inspeccion_equipos_activa` es su alias. Aceptamos ambos para que el
        // botón aparezca con o sin el último deploy.
        inspeccionEquiposActiva: (j['inspeccion_equipos_activa'] as bool?) ??
            (j['es_mantenimiento'] as bool?) ??
            false,
        accesoCompleto: j['acceso_completo'] as bool? ?? true,
        sinProcedimientosEstandar:
            j['sin_procedimientos_estandar'] as bool? ?? false,
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

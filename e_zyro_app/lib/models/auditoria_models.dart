class AuditoriaItem {
  final String id;
  final String? usuarioId;
  final String? usuarioNombre;
  final String tablaAfectada;
  final String? registroId;
  final String accion;
  final String? modulo;
  final String? descripcion;
  final String? ip;
  final String fecha;
  final Map<String, dynamic>? datosAnteriores;
  final Map<String, dynamic>? datosNuevos;

  const AuditoriaItem({
    required this.id,
    this.usuarioId,
    this.usuarioNombre,
    required this.tablaAfectada,
    this.registroId,
    required this.accion,
    this.modulo,
    this.descripcion,
    this.ip,
    required this.fecha,
    this.datosAnteriores,
    this.datosNuevos,
  });

  factory AuditoriaItem.fromJson(Map<String, dynamic> j) => AuditoriaItem(
        id:               j['id'] as String? ?? '',
        usuarioId:        j['usuario_id'] as String?,
        usuarioNombre:    j['usuario_nombre'] as String?,
        tablaAfectada:    j['tabla_afectada'] as String? ?? '',
        registroId:       j['registro_id'] as String?,
        accion:           j['accion'] as String? ?? '',
        modulo:           j['modulo'] as String?,
        descripcion:      j['descripcion'] as String?,
        ip:               j['ip'] as String?,
        fecha:            j['fecha'] as String? ?? '',
        datosAnteriores:  j['datos_anteriores'] != null
            ? Map<String, dynamic>.from(j['datos_anteriores'] as Map)
            : null,
        datosNuevos:      j['datos_nuevos'] != null
            ? Map<String, dynamic>.from(j['datos_nuevos'] as Map)
            : null,
      );
}

// ── Auditoría General (SuperAdmin) ───────────────────────────────────────────

/// Fila cross-empresa de /auditoria/general (incluye nombre de empresa).
class AuditoriaGeneralItem {
  final String id;
  final String? empresaId;
  final String? empresaNombre;
  final String? usuarioId;
  final String? usuarioNombre;
  final String tablaAfectada;
  final String? registroId;
  final String accion;
  final String? modulo;
  final String? descripcion;
  final String? ip;
  final String fecha;
  final Map<String, dynamic>? datosAnteriores;
  final Map<String, dynamic>? datosNuevos;

  const AuditoriaGeneralItem({
    required this.id,
    this.empresaId,
    this.empresaNombre,
    this.usuarioId,
    this.usuarioNombre,
    required this.tablaAfectada,
    this.registroId,
    required this.accion,
    this.modulo,
    this.descripcion,
    this.ip,
    required this.fecha,
    this.datosAnteriores,
    this.datosNuevos,
  });

  factory AuditoriaGeneralItem.fromJson(Map<String, dynamic> j) =>
      AuditoriaGeneralItem(
        id:            j['id'] as String? ?? '',
        empresaId:     j['empresa_id'] as String?,
        empresaNombre: j['empresa_nombre'] as String?,
        usuarioId:     j['usuario_id'] as String?,
        usuarioNombre: j['usuario_nombre'] as String?,
        tablaAfectada: j['tabla_afectada'] as String? ?? '',
        registroId:    j['registro_id'] as String?,
        accion:        j['accion'] as String? ?? '',
        modulo:        j['modulo'] as String?,
        descripcion:   j['descripcion'] as String?,
        ip:            j['ip'] as String?,
        fecha:         j['fecha'] as String? ?? '',
        datosAnteriores: j['datos_anteriores'] != null
            ? Map<String, dynamic>.from(j['datos_anteriores'] as Map)
            : null,
        datosNuevos: j['datos_nuevos'] != null
            ? Map<String, dynamic>.from(j['datos_nuevos'] as Map)
            : null,
      );
}

/// Evento/error del sistema (tabla log_sistema) — /auditoria/logs.
class LogSistemaItem {
  final String id;
  final String? empresaId;
  final String? usuarioId;
  final String nivel; // info | warning | error
  final String? origen;
  final String mensaje;
  final String? detalle;
  final String? metodo;
  final int? statusCode;
  final String fecha;

  const LogSistemaItem({
    required this.id,
    this.empresaId,
    this.usuarioId,
    required this.nivel,
    this.origen,
    required this.mensaje,
    this.detalle,
    this.metodo,
    this.statusCode,
    required this.fecha,
  });

  factory LogSistemaItem.fromJson(Map<String, dynamic> j) => LogSistemaItem(
        id:         j['id'] as String? ?? '',
        empresaId:  j['empresa_id'] as String?,
        usuarioId:  j['usuario_id'] as String?,
        nivel:      j['nivel'] as String? ?? 'error',
        origen:     j['origen'] as String?,
        mensaje:    j['mensaje'] as String? ?? '',
        detalle:    j['detalle'] as String?,
        metodo:     j['metodo'] as String?,
        statusCode: (j['status_code'] as num?)?.toInt(),
        fecha:      j['fecha'] as String? ?? '',
      );
}

/// Par nombre/cantidad para las estadísticas.
class ConteoStat {
  final String nombre;
  final int cantidad;
  const ConteoStat({required this.nombre, required this.cantidad});

  factory ConteoStat.fromJson(Map<String, dynamic> j, {String campo = 'nombre'}) =>
      ConteoStat(
        nombre:   j[campo] as String? ?? '',
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
      );
}

/// Estadísticas de /auditoria/stats (últimos 30 días).
class AuditoriaStats {
  final int rangoDias;
  final int totalAcciones;
  final int totalErrores;
  final List<ConteoStat> porModulo;
  final List<ConteoStat> porAccion;
  final List<ConteoStat> porDia;        // nombre = fecha (YYYY-MM-DD)
  final List<ConteoStat> erroresPorNivel;

  const AuditoriaStats({
    required this.rangoDias,
    required this.totalAcciones,
    required this.totalErrores,
    required this.porModulo,
    required this.porAccion,
    required this.porDia,
    required this.erroresPorNivel,
  });

  factory AuditoriaStats.fromJson(Map<String, dynamic> j) => AuditoriaStats(
        rangoDias:     (j['rango_dias'] as num?)?.toInt() ?? 30,
        totalAcciones: (j['total_acciones'] as num?)?.toInt() ?? 0,
        totalErrores:  (j['total_errores'] as num?)?.toInt() ?? 0,
        porModulo: (j['por_modulo'] as List? ?? [])
            .map((e) => ConteoStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        porAccion: (j['por_accion'] as List? ?? [])
            .map((e) => ConteoStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        porDia: (j['por_dia'] as List? ?? [])
            .map((e) => ConteoStat.fromJson(e as Map<String, dynamic>, campo: 'fecha'))
            .toList(),
        erroresPorNivel: (j['errores_por_nivel'] as List? ?? [])
            .map((e) => ConteoStat.fromJson(e as Map<String, dynamic>, campo: 'nivel'))
            .toList(),
      );
}

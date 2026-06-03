// DTOs de analítica (dashboards). Cada dominio devuelve `kpis` (mapa) +
// varias series `[{label, value}]`. Modelos tolerantes a campos faltantes.

/// Punto genérico etiqueta→valor para gráficos.
class Punto {
  final String label;
  final num value;
  const Punto(this.label, this.value);
  factory Punto.fromJson(Map<String, dynamic> j) =>
      Punto((j['label'] ?? '—').toString(), (j['value'] as num?) ?? 0);
}

List<Punto> _puntos(dynamic v) =>
    (v as List? ?? []).map((e) => Punto.fromJson(e as Map<String, dynamic>)).toList();

int _i(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

/// ── Operaciones ─────────────────────────────────────────────────────────────
class DashOperaciones {
  final int proyectosActivos, serviciosTotal, serviciosCompletados;
  final int serviciosPendientes, clientes, tasaCumplimiento;
  final List<Punto> porEstado, porCliente;
  final List<({String label, int total, int completados})> tendencia;
  const DashOperaciones({
    required this.proyectosActivos,
    required this.serviciosTotal,
    required this.serviciosCompletados,
    required this.serviciosPendientes,
    required this.clientes,
    required this.tasaCumplimiento,
    required this.porEstado,
    required this.porCliente,
    required this.tendencia,
  });
  factory DashOperaciones.fromJson(Map<String, dynamic> j) {
    final k = (j['kpis'] as Map?)?.cast<String, dynamic>() ?? {};
    return DashOperaciones(
      proyectosActivos: _i(k, 'proyectos_activos'),
      serviciosTotal: _i(k, 'servicios_total'),
      serviciosCompletados: _i(k, 'servicios_completados'),
      serviciosPendientes: _i(k, 'servicios_pendientes'),
      clientes: _i(k, 'clientes'),
      tasaCumplimiento: _i(k, 'tasa_cumplimiento'),
      porEstado: _puntos(j['servicios_por_estado']),
      porCliente: _puntos(j['servicios_por_cliente']),
      tendencia: (j['tendencia_mensual'] as List? ?? [])
          .map((e) => (
                label: (e['label'] ?? '').toString(),
                total: (e['total'] as num?)?.toInt() ?? 0,
                completados: (e['completados'] as num?)?.toInt() ?? 0,
              ))
          .toList(),
    );
  }
}

/// ── Logística ───────────────────────────────────────────────────────────────
class DashLogistica {
  final int items, conStock, agotado, bajo, unidades, equipos;
  final double valor;
  final List<Punto> stockHealth, topCategorias, equiposPorClase, topStock;
  const DashLogistica({
    required this.items,
    required this.conStock,
    required this.agotado,
    required this.bajo,
    required this.unidades,
    required this.equipos,
    required this.valor,
    required this.stockHealth,
    required this.topCategorias,
    required this.equiposPorClase,
    required this.topStock,
  });
  factory DashLogistica.fromJson(Map<String, dynamic> j) {
    final k = (j['kpis'] as Map?)?.cast<String, dynamic>() ?? {};
    return DashLogistica(
      items: _i(k, 'items'),
      conStock: _i(k, 'con_stock'),
      agotado: _i(k, 'agotado'),
      bajo: _i(k, 'bajo'),
      unidades: _i(k, 'unidades'),
      equipos: _i(k, 'equipos'),
      valor: (k['valor'] as num?)?.toDouble() ?? 0,
      stockHealth: _puntos(j['stock_health']),
      topCategorias: _puntos(j['top_categorias']),
      equiposPorClase: _puntos(j['equipos_por_clase']),
      topStock: _puntos(j['top_stock']),
    );
  }
}

/// ── Personal ────────────────────────────────────────────────────────────────
class DashPersonal {
  final int empleados, asistenciasMes, asistenciasTotal, areas;
  final List<Punto> porArea, asistenciaDiaria, topAsistencia;
  const DashPersonal({
    required this.empleados,
    required this.asistenciasMes,
    required this.asistenciasTotal,
    required this.areas,
    required this.porArea,
    required this.asistenciaDiaria,
    required this.topAsistencia,
  });
  factory DashPersonal.fromJson(Map<String, dynamic> j) {
    final k = (j['kpis'] as Map?)?.cast<String, dynamic>() ?? {};
    return DashPersonal(
      empleados: _i(k, 'empleados'),
      asistenciasMes: _i(k, 'asistencias_mes'),
      asistenciasTotal: _i(k, 'asistencias_total'),
      areas: _i(k, 'areas'),
      porArea: _puntos(j['por_area']),
      asistenciaDiaria: _puntos(j['asistencia_diaria']),
      topAsistencia: _puntos(j['top_asistencia']),
    );
  }
}

/// ── Activos ─────────────────────────────────────────────────────────────────
class DashActivos {
  final int equipos, operativos, mantenimiento, fueraServicio, intervenidos, itse, eppEntregas;
  final List<Punto> porEstado, porClase, intervenidosPorTipo, itsePorMes;
  const DashActivos({
    required this.equipos,
    required this.operativos,
    required this.mantenimiento,
    required this.fueraServicio,
    required this.intervenidos,
    required this.itse,
    required this.eppEntregas,
    required this.porEstado,
    required this.porClase,
    required this.intervenidosPorTipo,
    required this.itsePorMes,
  });
  factory DashActivos.fromJson(Map<String, dynamic> j) {
    final k = (j['kpis'] as Map?)?.cast<String, dynamic>() ?? {};
    return DashActivos(
      equipos: _i(k, 'equipos'),
      operativos: _i(k, 'operativos'),
      mantenimiento: _i(k, 'mantenimiento'),
      fueraServicio: _i(k, 'fuera_servicio'),
      intervenidos: _i(k, 'intervenidos'),
      itse: _i(k, 'itse'),
      eppEntregas: _i(k, 'epp_entregas'),
      porEstado: _puntos(j['equipos_por_estado']),
      porClase: _puntos(j['equipos_por_clase']),
      intervenidosPorTipo: _puntos(j['intervenidos_por_tipo']),
      itsePorMes: _puntos(j['itse_por_mes']),
    );
  }
}

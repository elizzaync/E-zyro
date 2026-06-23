// DTOs de Evaluaciones de desempeño (Punto 3.2).

/// Tipos de evaluación (deben coincidir con el backend).
class TipoEvaluacion {
  static const rrhh = 'rrhh';
  static const jefeDirecto = 'jefe_directo';
  static const companero = 'companero';
  static const psicologico = 'psicologico';

  static const todos = [rrhh, jefeDirecto, companero, psicologico];

  static String etiqueta(String tipo) => switch (tipo) {
        rrhh => 'Evaluación RRHH',
        jefeDirecto => 'Evaluación Jefe Directo',
        companero => 'Evaluación Compañero',
        psicologico => 'Evaluación Psicológica',
        _ => 'Evaluación',
      };

  static String etiquetaCorta(String tipo) => switch (tipo) {
        rrhh => 'RRHH',
        jefeDirecto => 'Jefe Directo',
        companero => 'Compañero',
        psicologico => 'Psicológica',
        _ => 'General',
      };
}

/// Estados de una evaluación.
class EstadoEvaluacion {
  static const borrador = 'borrador';
  static const enviada = 'enviada';
  /// Asignada por plantilla — el empleado debe completarla.
  static const asignada = 'asignada';
  static const completada = 'completada';

  static bool esPendiente(String e) => e == asignada || e == enviada;
}

class CriterioEvaluacion {
  final String id;
  final String nombre;
  final String? descripcion;
  final double peso;
  final String tipo;
  final bool activo;

  const CriterioEvaluacion({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.peso = 1.0,
    this.tipo = TipoEvaluacion.rrhh,
    this.activo = true,
  });

  factory CriterioEvaluacion.fromJson(Map<String, dynamic> j) => CriterioEvaluacion(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        descripcion: j['descripcion']?.toString(),
        peso: (j['peso'] as num?)?.toDouble() ?? 1.0,
        tipo: j['tipo']?.toString() ?? TipoEvaluacion.rrhh,
        activo: j['activo'] as bool? ?? true,
      );
}

class DetalleEvaluacion {
  final String? id;
  final String criterioId;
  final String? criterioNombre;
  final double? peso;
  final int puntaje;
  final String? comentario;

  const DetalleEvaluacion({
    this.id,
    required this.criterioId,
    this.criterioNombre,
    this.peso,
    required this.puntaje,
    this.comentario,
  });

  factory DetalleEvaluacion.fromJson(Map<String, dynamic> j) => DetalleEvaluacion(
        id: j['id']?.toString(),
        criterioId: j['criterio_id']?.toString() ?? '',
        criterioNombre: j['criterio_nombre']?.toString(),
        peso: (j['peso'] as num?)?.toDouble(),
        puntaje: (j['puntaje'] as num?)?.toInt() ?? 0,
        comentario: j['comentario']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'criterio_id': criterioId,
        'puntaje': puntaje,
        if (comentario != null && comentario!.isNotEmpty) 'comentario': comentario,
      };
}

// ── Plantillas de evaluación ──────────────────────────────────────────────────

class PlantillaEvaluacionItem {
  final String id;
  final String criterioId;
  final String? criterioNombre;
  final String? criterioDescripcion;
  final double peso;
  final int orden;

  const PlantillaEvaluacionItem({
    required this.id,
    required this.criterioId,
    this.criterioNombre,
    this.criterioDescripcion,
    required this.peso,
    this.orden = 0,
  });

  factory PlantillaEvaluacionItem.fromJson(Map<String, dynamic> j) => PlantillaEvaluacionItem(
        id: j['id']?.toString() ?? '',
        criterioId: j['criterio_id']?.toString() ?? '',
        criterioNombre: j['criterio_nombre']?.toString(),
        criterioDescripcion: j['criterio_descripcion']?.toString(),
        peso: (j['peso'] as num?)?.toDouble() ?? 1.0,
        orden: (j['orden'] as num?)?.toInt() ?? 0,
      );
}

class PlantillaEvaluacion {
  final String id;
  final String nombre;
  final String? descripcion;
  final String tipo;
  final bool activo;
  final List<PlantillaEvaluacionItem> items;
  final String? createdAt;

  const PlantillaEvaluacion({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.tipo = TipoEvaluacion.rrhh,
    this.activo = true,
    this.items = const [],
    this.createdAt,
  });

  factory PlantillaEvaluacion.fromJson(Map<String, dynamic> j) => PlantillaEvaluacion(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        descripcion: j['descripcion']?.toString(),
        tipo: j['tipo']?.toString() ?? TipoEvaluacion.rrhh,
        activo: j['activo'] as bool? ?? true,
        items: ((j['items'] as List?) ?? [])
            .map((e) => PlantillaEvaluacionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: j['created_at']?.toString(),
      );
}

// ── Evaluación ────────────────────────────────────────────────────────────────

class Evaluacion {
  final String id;
  final String empleadoId;
  final String? empleadoNombre;
  final String evaluadorId;
  final String? evaluadorNombre;
  final String tipo;
  final String periodo;
  final String estado; // borrador|asignada|enviada|completada
  final String? fecha;
  final double? promedio;
  final String? plantillaId;
  final String? plantillaNombre;
  final String? notasEvaluador;
  final List<DetalleEvaluacion> detalles;

  const Evaluacion({
    required this.id,
    required this.empleadoId,
    this.empleadoNombre,
    required this.evaluadorId,
    this.evaluadorNombre,
    this.tipo = TipoEvaluacion.rrhh,
    required this.periodo,
    required this.estado,
    this.fecha,
    this.promedio,
    this.plantillaId,
    this.plantillaNombre,
    this.notasEvaluador,
    this.detalles = const [],
  });

  bool get esPendiente => EstadoEvaluacion.esPendiente(estado);
  bool get esAsignada => estado == EstadoEvaluacion.asignada;
  bool get esCompletada => estado == EstadoEvaluacion.completada;

  factory Evaluacion.fromJson(Map<String, dynamic> j) => Evaluacion(
        id: j['id']?.toString() ?? '',
        empleadoId: j['empleado_id']?.toString() ?? '',
        empleadoNombre: j['empleado_nombre']?.toString(),
        evaluadorId: j['evaluador_id']?.toString() ?? '',
        evaluadorNombre: j['evaluador_nombre']?.toString(),
        tipo: j['tipo']?.toString() ?? TipoEvaluacion.rrhh,
        periodo: j['periodo']?.toString() ?? '',
        estado: j['estado']?.toString() ?? 'borrador',
        fecha: j['fecha']?.toString(),
        promedio: (j['promedio'] as num?)?.toDouble(),
        plantillaId: j['plantilla_id']?.toString(),
        plantillaNombre: j['plantilla_nombre']?.toString(),
        notasEvaluador: j['notas_evaluador']?.toString(),
        detalles: ((j['detalles'] as List?) ?? [])
            .map((e) => DetalleEvaluacion.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

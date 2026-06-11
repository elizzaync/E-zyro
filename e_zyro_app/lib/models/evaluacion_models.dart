// DTOs de Evaluaciones de desempeño (Punto 3.2).

/// Tipos de evaluación (deben coincidir con el backend).
class TipoEvaluacion {
  static const rrhh = 'rrhh';
  static const jefeDirecto = 'jefe_directo';
  static const companero = 'companero';

  static const todos = [rrhh, jefeDirecto, companero];

  static String etiqueta(String tipo) => switch (tipo) {
        rrhh => 'Evaluación RRHH',
        jefeDirecto => 'Evaluación Jefe Directo',
        companero => 'Evaluación Compañero',
        _ => 'Evaluación',
      };

  static String etiquetaCorta(String tipo) => switch (tipo) {
        rrhh => 'RRHH',
        jefeDirecto => 'Jefe Directo',
        companero => 'Compañero',
        _ => 'General',
      };
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

class Evaluacion {
  final String id;
  final String empleadoId;
  final String? empleadoNombre;
  final String evaluadorId;
  final String? evaluadorNombre;
  final String tipo;
  final String periodo;
  final String estado; // borrador|enviada|completada
  final String? fecha;
  final double? promedio;
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
    this.detalles = const [],
  });

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
        detalles: ((j['detalles'] as List?) ?? [])
            .map((e) => DetalleEvaluacion.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

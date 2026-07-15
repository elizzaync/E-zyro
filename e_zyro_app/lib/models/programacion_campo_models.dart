// HU-54: cuadrilla diaria por proyecto — separado del fichaje de asistencia.

class ProgramacionEmpleadoItem {
  final String programacionEmpleadoId;
  final String empleadoId;
  final String nombre;
  final bool confirmadoMovil;

  const ProgramacionEmpleadoItem({
    required this.programacionEmpleadoId,
    required this.empleadoId,
    required this.nombre,
    required this.confirmadoMovil,
  });

  factory ProgramacionEmpleadoItem.fromJson(Map<String, dynamic> j) =>
      ProgramacionEmpleadoItem(
        programacionEmpleadoId: j['programacion_empleado_id'] as String? ?? '',
        empleadoId: j['empleado_id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        confirmadoMovil: j['confirmado_movil'] as bool? ?? false,
      );
}

class ProgramacionCampoItem {
  final String id;
  final String proyectoId;
  final String nombreProyecto;
  final String fecha; // ISO yyyy-mm-dd
  final String tipo;
  final String? descripcion;
  final List<ProgramacionEmpleadoItem> empleados;

  const ProgramacionCampoItem({
    required this.id,
    required this.proyectoId,
    required this.nombreProyecto,
    required this.fecha,
    required this.tipo,
    this.descripcion,
    required this.empleados,
  });

  factory ProgramacionCampoItem.fromJson(Map<String, dynamic> j) =>
      ProgramacionCampoItem(
        id: j['id'] as String? ?? '',
        proyectoId: j['proyecto_id'] as String? ?? '',
        nombreProyecto: j['nombre_proyecto'] as String? ?? '',
        fecha: j['fecha'] as String? ?? '',
        tipo: j['tipo'] as String? ?? 'servicio',
        descripcion: j['descripcion'] as String?,
        empleados: (j['empleados'] as List? ?? [])
            .map((e) =>
                ProgramacionEmpleadoItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MiProgramacionItem {
  final String programacionEmpleadoId;
  final String proyectoId;
  final String nombreProyecto;
  final String fecha;
  final String tipo;
  final bool confirmadoMovil;

  const MiProgramacionItem({
    required this.programacionEmpleadoId,
    required this.proyectoId,
    required this.nombreProyecto,
    required this.fecha,
    required this.tipo,
    required this.confirmadoMovil,
  });

  factory MiProgramacionItem.fromJson(Map<String, dynamic> j) =>
      MiProgramacionItem(
        programacionEmpleadoId: j['programacion_empleado_id'] as String? ?? '',
        proyectoId: j['proyecto_id'] as String? ?? '',
        nombreProyecto: j['nombre_proyecto'] as String? ?? '',
        fecha: j['fecha'] as String? ?? '',
        tipo: j['tipo'] as String? ?? 'servicio',
        confirmadoMovil: j['confirmado_movil'] as bool? ?? false,
      );
}

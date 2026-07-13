// HU-19: Historial de equipos y descarga de informes

class FotoEvidencia {
  final String url;
  final String tipo; // 'antes' | 'durante' | 'despues'
  final String? paso;
  final String? fecha;

  const FotoEvidencia({
    required this.url,
    required this.tipo,
    this.paso,
    this.fecha,
  });

  factory FotoEvidencia.fromJson(Map<String, dynamic> j) => FotoEvidencia(
        url: j['url'] as String? ?? '',
        tipo: j['tipo'] as String? ?? '',
        paso: j['paso'] as String?,
        fecha: j['fecha'] as String?,
      );

  String get tipoLabel => switch (tipo.toLowerCase()) {
        'antes' => 'Antes',
        'durante' => 'Durante',
        _ => 'Después',
      };
}

class MantenimientoHistorial {
  final String id;
  final String fecha;
  final String tecnicoNombre;
  final String proyectoNombre;
  final String estado;
  final List<FotoEvidencia> fotos;
  final String? informePdfUrl;
  final String? evidenciasZipUrl;

  const MantenimientoHistorial({
    required this.id,
    required this.fecha,
    required this.tecnicoNombre,
    required this.proyectoNombre,
    required this.estado,
    required this.fotos,
    this.informePdfUrl,
    this.evidenciasZipUrl,
  });

  factory MantenimientoHistorial.fromJson(Map<String, dynamic> j) =>
      MantenimientoHistorial(
        id: j['id'] as String? ?? '',
        fecha: j['fecha'] as String? ?? '',
        tecnicoNombre: j['tecnico_nombre'] as String? ?? '',
        proyectoNombre: j['proyecto_nombre'] as String? ?? '',
        estado: j['estado'] as String? ?? '',
        fotos: (j['fotos'] as List? ?? [])
            .map((e) => FotoEvidencia.fromJson(e as Map<String, dynamic>))
            .toList(),
        informePdfUrl: j['informe_pdf_url'] as String?,
        evidenciasZipUrl: j['evidencias_zip_url'] as String?,
      );
}

// HU-45: Historial de Participación — proyectos cerrados donde el empleado
// logueado fue miembro (perfil > Historial de Proyectos).
class ProyectoHistorial {
  final String proyectoId;
  final String nombreProyecto;
  final String ordenTrabajo;
  final String cliente;
  final String? rolProyecto;
  final String? fechaInicio;
  final String? fechaFinReal;

  const ProyectoHistorial({
    required this.proyectoId,
    required this.nombreProyecto,
    required this.ordenTrabajo,
    required this.cliente,
    this.rolProyecto,
    this.fechaInicio,
    this.fechaFinReal,
  });

  factory ProyectoHistorial.fromJson(Map<String, dynamic> j) =>
      ProyectoHistorial(
        proyectoId: j['proyecto_id'] as String? ?? '',
        nombreProyecto: j['nombre_proyecto'] as String? ?? '',
        ordenTrabajo: j['orden_trabajo'] as String? ?? '',
        cliente: j['cliente'] as String? ?? '',
        rolProyecto: j['rol_proyecto'] as String?,
        fechaInicio: j['fecha_inicio'] as String?,
        fechaFinReal: j['fecha_fin_real'] as String?,
      );
}

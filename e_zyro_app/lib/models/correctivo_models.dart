/// DTOs de Correctivos + Observaciones (Fase 4).
class Correctivo {
  final String id;
  final String servicioId;
  final String? codigo;
  final String? alcance;
  final String estado;
  final String? informeUrl;
  final String? fechaInicio;
  final String? fechaFin;

  const Correctivo({
    required this.id,
    required this.servicioId,
    this.codigo,
    this.alcance,
    required this.estado,
    this.informeUrl,
    this.fechaInicio,
    this.fechaFin,
  });

  factory Correctivo.fromJson(Map<String, dynamic> j) => Correctivo(
        id: j['id']?.toString() ?? '',
        servicioId: j['servicio_id']?.toString() ?? '',
        codigo: j['codigo']?.toString(),
        alcance: j['alcance']?.toString(),
        estado: j['estado']?.toString() ?? 'registrado',
        informeUrl: j['informe_url']?.toString(),
        fechaInicio: j['fecha_inicio']?.toString(),
        fechaFin: j['fecha_fin']?.toString(),
      );
}

class Observacion {
  final String id;
  final String servicioId;
  final String? observaciones;
  final String? recomendaciones;
  final String? fechaDescargo;

  const Observacion({
    required this.id,
    required this.servicioId,
    this.observaciones,
    this.recomendaciones,
    this.fechaDescargo,
  });

  factory Observacion.fromJson(Map<String, dynamic> j) => Observacion(
        id: j['id']?.toString() ?? '',
        servicioId: j['servicio_id']?.toString() ?? '',
        observaciones: j['observaciones']?.toString(),
        recomendaciones: j['recomendaciones']?.toString(),
        fechaDescargo: j['fecha_descargo']?.toString(),
      );
}

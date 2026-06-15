/// Carta de garantía (repositorio central).
class Garantia {
  final String id;
  final String? servicioId;
  final String? servicioNombre;
  final String? proyectoId;
  final String? proyectoNombre;
  final String? clienteId;
  final String? clienteNombre;
  final String? razonSocial;
  final String? lugar;
  final String? fechaOperatividad;
  final String? vigenciaGarantia;
  final String estado; // vigente | por_vencer | vencida | sin_fecha
  final int? diasParaVencer;
  final String? documentoPdfUrl;
  final String? createdAt;

  const Garantia({
    required this.id,
    required this.estado,
    this.servicioId,
    this.servicioNombre,
    this.proyectoId,
    this.proyectoNombre,
    this.clienteId,
    this.clienteNombre,
    this.razonSocial,
    this.lugar,
    this.fechaOperatividad,
    this.vigenciaGarantia,
    this.diasParaVencer,
    this.documentoPdfUrl,
    this.createdAt,
  });

  factory Garantia.fromJson(Map<String, dynamic> j) => Garantia(
        id: (j['id'] ?? '').toString(),
        estado: (j['estado'] ?? 'sin_fecha').toString(),
        servicioId: j['servicio_id']?.toString(),
        servicioNombre: j['servicio_nombre']?.toString(),
        proyectoId: j['proyecto_id']?.toString(),
        proyectoNombre: j['proyecto_nombre']?.toString(),
        clienteId: j['cliente_id']?.toString(),
        clienteNombre: j['cliente_nombre']?.toString(),
        razonSocial: j['razon_social']?.toString(),
        lugar: j['lugar']?.toString(),
        fechaOperatividad: j['fecha_operatividad']?.toString(),
        vigenciaGarantia: j['vigencia_garantia']?.toString(),
        diasParaVencer: j['dias_para_vencer'] is int
            ? j['dias_para_vencer'] as int
            : int.tryParse('${j['dias_para_vencer']}'),
        documentoPdfUrl: j['documento_pdf_url']?.toString(),
        createdAt: j['created_at']?.toString(),
      );

  bool get tienePdf => (documentoPdfUrl ?? '').isNotEmpty;

  /// Nombre del cliente para mostrar (cliente enlazado o la razón social suelta).
  String get nombreCliente =>
      (clienteNombre ?? '').isNotEmpty ? clienteNombre! : (razonSocial ?? 'Sin cliente');
}

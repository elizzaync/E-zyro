/// DTO de un informe de servicio (pre-informe / informe final).
class InformeServicio {
  final String id;
  final String servicioId;
  final String tipo; // pre | final
  final String? titulo;
  final String? url;
  final String? fecha;

  const InformeServicio({
    required this.id,
    required this.servicioId,
    required this.tipo,
    this.titulo,
    this.url,
    this.fecha,
  });

  bool get esFinal => tipo == 'final';

  factory InformeServicio.fromJson(Map<String, dynamic> j) => InformeServicio(
        id: j['id']?.toString() ?? '',
        servicioId: j['servicio_id']?.toString() ?? '',
        tipo: j['tipo']?.toString() ?? 'pre',
        titulo: j['titulo']?.toString(),
        url: j['url']?.toString(),
        fecha: j['fecha']?.toString(),
      );
}

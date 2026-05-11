class Comunicado {
  final String id;
  final String titulo;
  final String contenido;
  final String fecha;
  final bool leido;

  const Comunicado({
    required this.id,
    required this.titulo,
    required this.contenido,
    required this.fecha,
    this.leido = false,
  });

  factory Comunicado.fromJson(Map<String, dynamic> j) => Comunicado(
        id: j['id'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        contenido: j['contenido'] as String? ?? '',
        fecha: j['fecha'] as String? ?? '',
        leido: j['leido'] as bool? ?? false,
      );

  Comunicado markRead() => Comunicado(
        id: id,
        titulo: titulo,
        contenido: contenido,
        fecha: fecha,
        leido: true,
      );
}

class Comunicado {
  final String id;
  final String titulo;
  final String contenido;
  final String fecha;
  final bool leido;
  final String autor;

  const Comunicado({
    required this.id,
    required this.titulo,
    required this.contenido,
    required this.fecha,
    this.leido = false,
    this.autor = '',
  });

  factory Comunicado.fromJson(Map<String, dynamic> j) => Comunicado(
        id: j['id'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        contenido: j['contenido'] as String? ?? '',
        fecha: j['fecha'] as String? ?? '',
        leido: j['leido'] as bool? ?? false,
        autor: j['autor'] as String? ?? '',
      );

  Comunicado markRead() => Comunicado(
        id: id,
        titulo: titulo,
        contenido: contenido,
        fecha: fecha,
        leido: true,
        autor: autor,
      );
}

// HU-13: Comunicados por proyecto (Canal de Difusión)
class ComunicadoProyecto {
  final String id;
  final String proyectoId;
  final String titulo;
  final String mensaje;
  final String autor;
  final String fecha;
  final String? adjuntoUrl;
  final bool leido;

  const ComunicadoProyecto({
    required this.id,
    required this.proyectoId,
    required this.titulo,
    required this.mensaje,
    required this.autor,
    required this.fecha,
    this.adjuntoUrl,
    this.leido = false,
  });

  factory ComunicadoProyecto.fromJson(Map<String, dynamic> j) =>
      ComunicadoProyecto(
        id: j['id'] as String? ?? '',
        proyectoId: j['proyecto_id'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        mensaje: j['mensaje'] as String? ?? '',
        autor: j['autor'] as String? ?? '',
        fecha: j['fecha'] as String? ?? '',
        adjuntoUrl: j['adjunto_url'] as String?,
        leido: j['leido'] as bool? ?? false,
      );

  ComunicadoProyecto markRead() => ComunicadoProyecto(
        id: id,
        proyectoId: proyectoId,
        titulo: titulo,
        mensaje: mensaje,
        autor: autor,
        fecha: fecha,
        adjuntoUrl: adjuntoUrl,
        leido: true,
      );
}

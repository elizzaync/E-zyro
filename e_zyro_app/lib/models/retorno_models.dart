/// Ítem candidato a devolución de un servicio, antes de crear el Retorno.
class RetornoItemPendiente {
  final String detalleId;
  final String nombre;
  final String unidad;
  final String tipoItem; // 'material' | 'herramienta' | 'equipo'
  final int cantidadEntregada;
  final bool esObligatorio;
  int cantidadRetornada;

  RetornoItemPendiente({
    required this.detalleId,
    required this.nombre,
    required this.unidad,
    required this.tipoItem,
    required this.cantidadEntregada,
    required this.esObligatorio,
    int? cantidadRetornada,
  }) : cantidadRetornada = cantidadRetornada ?? (esObligatorio ? cantidadEntregada : 0);

  factory RetornoItemPendiente.fromJson(Map<String, dynamic> j) => RetornoItemPendiente(
        detalleId: j['detalleId'] as String,
        nombre: j['nombre'] as String? ?? 'Ítem',
        unidad: j['unidad'] as String? ?? 'Unidades',
        tipoItem: j['tipoItem'] as String? ?? 'material',
        cantidadEntregada: (j['cantidadEntregada'] as num?)?.toInt() ?? 0,
        esObligatorio: j['esObligatorio'] as bool? ?? false,
      );
}

class CheckRetornoServicio {
  final bool tieneRetorno;
  final String? retornoId;
  final String? estado;

  const CheckRetornoServicio({
    required this.tieneRetorno,
    this.retornoId,
    this.estado,
  });

  factory CheckRetornoServicio.fromJson(Map<String, dynamic> j) => CheckRetornoServicio(
        tieneRetorno: j['tieneRetorno'] as bool? ?? false,
        retornoId: j['retornoId'] as String?,
        estado: j['estado'] as String?,
      );
}

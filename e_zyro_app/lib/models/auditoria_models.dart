class AuditoriaItem {
  final String id;
  final String? usuarioId;
  final String? usuarioNombre;
  final String tablaAfectada;
  final String? registroId;
  final String accion;
  final String? modulo;
  final String? descripcion;
  final String? ip;
  final String fecha;

  const AuditoriaItem({
    required this.id,
    this.usuarioId,
    this.usuarioNombre,
    required this.tablaAfectada,
    this.registroId,
    required this.accion,
    this.modulo,
    this.descripcion,
    this.ip,
    required this.fecha,
  });

  factory AuditoriaItem.fromJson(Map<String, dynamic> j) => AuditoriaItem(
        id:             j['id'] as String? ?? '',
        usuarioId:      j['usuario_id'] as String?,
        usuarioNombre:  j['usuario_nombre'] as String?,
        tablaAfectada:  j['tabla_afectada'] as String? ?? '',
        registroId:     j['registro_id'] as String?,
        accion:         j['accion'] as String? ?? '',
        modulo:         j['modulo'] as String?,
        descripcion:    j['descripcion'] as String?,
        ip:             j['ip'] as String?,
        fecha:          j['fecha'] as String? ?? '',
      );
}

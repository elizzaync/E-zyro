class CatalogoItem {
  final String id;
  final String nombre;
  final String? codigo;
  final String unidad;
  final int stock;
  final String? categoria;

  const CatalogoItem({
    required this.id,
    required this.nombre,
    this.codigo,
    required this.unidad,
    required this.stock,
    this.categoria,
  });

  factory CatalogoItem.fromJson(Map<String, dynamic> json) => CatalogoItem(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        codigo: json['codigo'] as String?,
        unidad: json['unidad'] as String,
        stock: (json['stock'] as num).toInt(),
        categoria: json['categoria'] as String?,
      );
}

class SolicitudDetalle {
  final String id;
  final String materialId;
  final String nombre;
  final String unidad;
  final int cantidad;
  final int? cantidadAprobada;

  const SolicitudDetalle({
    required this.id,
    required this.materialId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    this.cantidadAprobada,
  });

  factory SolicitudDetalle.fromJson(Map<String, dynamic> json) => SolicitudDetalle(
        id: json['id'] as String,
        materialId: json['material_id'] as String,
        nombre: json['nombre'] as String,
        unidad: json['unidad'] as String,
        cantidad: (json['cantidad'] as num).toInt(),
        cantidadAprobada: json['cantidad_aprobada'] != null
            ? (json['cantidad_aprobada'] as num).toInt()
            : null,
      );
}

class MiSolicitud {
  final String id;
  final String estado;
  final String fecha;
  final String? observacion;
  final String proyectoNombre;
  final List<SolicitudDetalle> items;

  const MiSolicitud({
    required this.id,
    required this.estado,
    required this.fecha,
    this.observacion,
    required this.proyectoNombre,
    required this.items,
  });

  factory MiSolicitud.fromJson(Map<String, dynamic> json) => MiSolicitud(
        id: json['id'] as String,
        estado: json['estado'] as String,
        fecha: json['fecha'] as String,
        observacion: json['observacion'] as String?,
        proyectoNombre: json['proyecto_nombre'] as String,
        items: (json['items'] as List? ?? [])
            .map((e) => SolicitudDetalle.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

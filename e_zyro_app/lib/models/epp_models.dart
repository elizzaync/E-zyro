/// DTOs del módulo EPP (espejo de los schemas del backend).
class Epp {
  final String id;
  final String nombre;
  final String? descripcion;
  final int stockActual;
  final int stockMin;
  final double? precio;
  final String? imagenUrl;
  final String? zonaId;
  final String? marcaId;
  final String? unidadId;

  const Epp({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.stockActual,
    required this.stockMin,
    this.precio,
    this.imagenUrl,
    this.zonaId,
    this.marcaId,
    this.unidadId,
  });

  bool get stockBajo => stockActual <= stockMin;

  factory Epp.fromJson(Map<String, dynamic> j) => Epp(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        descripcion: j['descripcion']?.toString(),
        stockActual: (j['stock_actual'] as num?)?.toInt() ?? 0,
        stockMin: (j['stock_min'] as num?)?.toInt() ?? 0,
        precio: (j['precio'] as num?)?.toDouble(),
        imagenUrl: j['imagen_url']?.toString(),
        zonaId: j['zona_id']?.toString(),
        marcaId: j['marca_id']?.toString(),
        unidadId: j['unidad_id']?.toString(),
      );
}

class EppEntregaItem {
  final String eppId;
  final String nombre;
  final int cantidad;
  const EppEntregaItem({required this.eppId, required this.nombre, required this.cantidad});

  factory EppEntregaItem.fromJson(Map<String, dynamic> j) => EppEntregaItem(
        eppId: j['epp_id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
      );
}

class EppEntrega {
  final String id;
  final String empleadoId;
  final String? fecha;
  final String estado;
  final String? firmaUrl;
  final String? observacion;
  final List<EppEntregaItem> items;

  const EppEntrega({
    required this.id,
    required this.empleadoId,
    this.fecha,
    required this.estado,
    this.firmaUrl,
    this.observacion,
    this.items = const [],
  });

  factory EppEntrega.fromJson(Map<String, dynamic> j) => EppEntrega(
        id: j['id']?.toString() ?? '',
        empleadoId: j['empleado_id']?.toString() ?? '',
        fecha: j['fecha']?.toString(),
        estado: j['estado']?.toString() ?? 'registrada',
        firmaUrl: j['firma_url']?.toString(),
        observacion: j['observacion']?.toString(),
        items: ((j['items'] as List?) ?? [])
            .map((e) => EppEntregaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

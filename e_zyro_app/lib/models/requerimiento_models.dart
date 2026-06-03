class CategoriaItem {
  final String id;
  final String nombre;
  const CategoriaItem({required this.id, required this.nombre});
  factory CategoriaItem.fromJson(Map<String, dynamic> j) =>
      CategoriaItem(id: j['id'] as String, nombre: j['nombre'] as String);
}

class AlmacenItem {
  final String id;
  final String nombre;
  final String? ubicacion;
  const AlmacenItem({required this.id, required this.nombre, this.ubicacion});
  factory AlmacenItem.fromJson(Map<String, dynamic> j) => AlmacenItem(
      id: j['id'] as String,
      nombre: j['nombre'] as String,
      ubicacion: j['ubicacion'] as String?);
}

class CatalogoItem {
  final String id;
  final String nombre;
  final String? codigo;
  final String unidad;
  final int stock;
  final int stockMinimo;
  final String? categoria;
  final String? descripcion;
  final String? imagenUrl;
  final String tipo; // consumible | herramienta

  const CatalogoItem({
    required this.id,
    required this.nombre,
    this.codigo,
    required this.unidad,
    required this.stock,
    this.stockMinimo = 0,
    this.categoria,
    this.descripcion,
    this.imagenUrl,
    this.tipo = 'consumible',
  });

  factory CatalogoItem.fromJson(Map<String, dynamic> json) => CatalogoItem(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        codigo: json['codigo'] as String?,
        unidad: json['unidad'] as String,
        stock: (json['stock'] as num).toInt(),
        stockMinimo: (json['stock_minimo'] as num?)?.toInt() ?? 0,
        categoria: json['categoria'] as String?,
        descripcion: json['descripcion'] as String?,
        imagenUrl: json['imagen_url'] as String?,
        tipo: json['tipo'] as String? ?? 'consumible',
      );

  bool get esHerramienta => tipo == 'herramienta';
  bool get agotado    => stock <= 0;
  bool get bajoStock  => stock > 0 && stockMinimo > 0 && stock <= stockMinimo;
}

/// Conteos del catálogo para el header de filtros.
class CatalogoResumen {
  final int total;
  final int conStock;
  final int bajo;
  final int agotado;
  const CatalogoResumen({
    this.total = 0,
    this.conStock = 0,
    this.bajo = 0,
    this.agotado = 0,
  });
  factory CatalogoResumen.fromJson(Map<String, dynamic> j) => CatalogoResumen(
        total: (j['total'] as num?)?.toInt() ?? 0,
        conStock: (j['con_stock'] as num?)?.toInt() ?? 0,
        bajo: (j['bajo'] as num?)?.toInt() ?? 0,
        agotado: (j['agotado'] as num?)?.toInt() ?? 0,
      );
}

// ── Panel del encargado de logística ──────────────────────────────────────────

class MaterialBajoStock {
  final String id;
  final String nombre;
  final String unidad;
  final String? categoria;
  final int stock;
  final int minimo;

  const MaterialBajoStock({
    required this.id,
    required this.nombre,
    required this.unidad,
    this.categoria,
    required this.stock,
    required this.minimo,
  });

  factory MaterialBajoStock.fromJson(Map<String, dynamic> j) => MaterialBajoStock(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        unidad: j['unidad'] as String? ?? 'und',
        categoria: j['categoria'] as String?,
        stock: (j['stock'] as num?)?.toInt() ?? 0,
        minimo: (j['minimo'] as num?)?.toInt() ?? 0,
      );
}

class InventarioResumen {
  final int totalItems;
  final int bajoStock;
  final int sinStock;
  final List<MaterialBajoStock> itemsBajoStock;

  const InventarioResumen({
    this.totalItems = 0,
    this.bajoStock = 0,
    this.sinStock = 0,
    this.itemsBajoStock = const [],
  });

  factory InventarioResumen.fromJson(Map<String, dynamic> j) => InventarioResumen(
        totalItems: (j['total_items'] as num?)?.toInt() ?? 0,
        bajoStock: (j['bajo_stock'] as num?)?.toInt() ?? 0,
        sinStock: (j['sin_stock'] as num?)?.toInt() ?? 0,
        itemsBajoStock: (j['items_bajo_stock'] as List? ?? [])
            .map((e) => MaterialBajoStock.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SolicitudDetalle {
  final String id;
  final String? materialId;
  final String nombre;
  final String unidad;
  final int cantidad;
  final int? cantidadAprobada;

  const SolicitudDetalle({
    required this.id,
    this.materialId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    this.cantidadAprobada,
  });

  factory SolicitudDetalle.fromJson(Map<String, dynamic> json) => SolicitudDetalle(
        id: json['id'] as String,
        materialId: json['material_id'] as String?,
        nombre: json['nombre'] as String? ?? '',
        unidad: json['unidad'] as String? ?? '',
        cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
        cantidadAprobada: json['cantidad_aprobada'] != null
            ? (json['cantidad_aprobada'] as num).toInt()
            : null,
      );
}

// ── Movimiento de inventario (Fase 3) ─────────────────────────────────────────

class MovimientoStock {
  final String id;
  final String materialId;
  final String materialNombre;
  final String unidad;
  final String tipo; // entrada | salida | ajuste | requerimiento | transferencia | compra
  final int cantidad;
  final String? motivo;
  final String? almacenNombre;
  final String? responsableNombre;
  final String fecha;

  const MovimientoStock({
    required this.id,
    required this.materialId,
    required this.materialNombre,
    required this.unidad,
    required this.tipo,
    required this.cantidad,
    this.motivo,
    this.almacenNombre,
    this.responsableNombre,
    required this.fecha,
  });

  factory MovimientoStock.fromJson(Map<String, dynamic> j) => MovimientoStock(
        id: j['id'] as String,
        materialId: j['material_id'] as String? ?? '',
        materialNombre: j['material_nombre'] as String? ?? '',
        unidad: j['unidad'] as String? ?? 'und',
        tipo: j['tipo'] as String? ?? '',
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
        motivo: j['motivo'] as String?,
        almacenNombre: j['almacen_nombre'] as String?,
        responsableNombre: j['responsable_nombre'] as String?,
        fecha: j['fecha'] as String? ?? '',
      );
}

// ── Solicitud para gestión del encargado ──────────────────────────────────────

class SolicitudGestion {
  final String id;
  final String estado;
  final String fecha;
  final String? observacion;
  final String? observacionLogistico;
  final String proyectoNombre;
  final String solicitanteNombre;
  final List<SolicitudDetalle> items;

  const SolicitudGestion({
    required this.id,
    required this.estado,
    required this.fecha,
    this.observacion,
    this.observacionLogistico,
    required this.proyectoNombre,
    required this.solicitanteNombre,
    required this.items,
  });

  factory SolicitudGestion.fromJson(Map<String, dynamic> j) => SolicitudGestion(
        id: j['id'] as String,
        estado: j['estado'] as String? ?? 'pendiente',
        fecha: j['fecha'] as String? ?? '',
        observacion: j['observacion'] as String?,
        observacionLogistico: j['observacion_logistico'] as String?,
        proyectoNombre: j['proyecto_nombre'] as String? ?? 'Proyecto',
        solicitanteNombre: j['solicitante_nombre'] as String? ?? 'Sin nombre',
        items: (j['items'] as List? ?? [])
            .map((e) => SolicitudDetalle.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MiSolicitud {
  final String id;
  final String estado;
  final String fecha;
  final String? observacion;
  final String? observacionLogistico;
  final String proyectoNombre;
  final List<SolicitudDetalle> items;

  const MiSolicitud({
    required this.id,
    required this.estado,
    required this.fecha,
    this.observacion,
    this.observacionLogistico,
    required this.proyectoNombre,
    required this.items,
  });

  factory MiSolicitud.fromJson(Map<String, dynamic> json) => MiSolicitud(
        id: json['id'] as String,
        estado: json['estado'] as String,
        fecha: json['fecha'] as String,
        observacion: json['observacion'] as String?,
        observacionLogistico: json['observacion_logistico'] as String?,
        proyectoNombre: json['proyecto_nombre'] as String,
        items: (json['items'] as List? ?? [])
            .map((e) => SolicitudDetalle.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

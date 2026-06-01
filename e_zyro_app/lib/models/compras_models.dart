// ── Proveedor ─────────────────────────────────────────────────────────────────

class Proveedor {
  final String id;
  final String razonSocial;
  final String? ruc;
  final String? contacto;
  final String? email;
  final String? telefono;
  final String? direccion;

  const Proveedor({
    required this.id,
    required this.razonSocial,
    this.ruc,
    this.contacto,
    this.email,
    this.telefono,
    this.direccion,
  });

  factory Proveedor.fromJson(Map<String, dynamic> j) => Proveedor(
        id: j['id'] as String,
        razonSocial: (j['razon_social'] ?? j['nombre']) as String? ?? '',
        ruc: j['ruc'] as String?,
        contacto: j['contacto'] as String?,
        email: j['email'] as String?,
        telefono: j['telefono'] as String?,
        direccion: j['direccion'] as String?,
      );
}

// ── Detalle de orden de compra ────────────────────────────────────────────────

class DetalleCompra {
  final String id;
  final String materialId;
  final String materialNombre;
  final String unidad;
  final int cantidad;
  final double precioUnitario;

  const DetalleCompra({
    required this.id,
    required this.materialId,
    required this.materialNombre,
    required this.unidad,
    required this.cantidad,
    required this.precioUnitario,
  });

  factory DetalleCompra.fromJson(Map<String, dynamic> j) => DetalleCompra(
        id: j['id'] as String? ?? '',
        materialId: j['material_id'] as String? ?? '',
        materialNombre: j['material_nombre'] as String? ?? '',
        unidad: j['unidad'] as String? ?? 'und',
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
        precioUnitario: (j['precio_unitario'] as num?)?.toDouble() ?? 0.0,
      );
}

// ── Orden de compra ───────────────────────────────────────────────────────────

class OrdenCompra {
  final String id;
  final String proveedorId;
  final String proveedorNombre;
  final String estado; // borrador|enviada|confirmada|en_transito|recibida|cancelada
  final String fechaEmision;
  final String? fechaEntregaEstimada;
  final double totalReferencial;
  final int totalItems;
  final List<DetalleCompra> items;

  const OrdenCompra({
    required this.id,
    required this.proveedorId,
    required this.proveedorNombre,
    required this.estado,
    required this.fechaEmision,
    this.fechaEntregaEstimada,
    required this.totalReferencial,
    required this.totalItems,
    this.items = const [],
  });

  factory OrdenCompra.fromJson(Map<String, dynamic> j) => OrdenCompra(
        id: j['id'] as String,
        proveedorId: j['proveedor_id'] as String? ?? '',
        proveedorNombre: j['proveedor_nombre'] as String? ?? 'Proveedor',
        estado: j['estado'] as String? ?? 'borrador',
        fechaEmision: j['fecha_emision'] as String? ?? '',
        fechaEntregaEstimada: j['fecha_entrega_estimada'] as String?,
        totalReferencial: (j['total_referencial'] as num?)?.toDouble() ?? 0.0,
        totalItems: (j['total_items'] as num?)?.toInt() ?? 0,
        items: (j['items'] as List? ?? [])
            .map((e) => DetalleCompra.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

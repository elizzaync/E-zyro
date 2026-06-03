// ── Proveedor ─────────────────────────────────────────────────────────────────

class Proveedor {
  final String id;
  final String razonSocial;
  final String? ruc;
  final String? contacto;
  final String? email;
  final String? telefono;
  final String? direccion;
  final int rating; // 1-5 (lo usa el modal de proceso de compra)

  const Proveedor({
    required this.id,
    required this.razonSocial,
    this.ruc,
    this.contacto,
    this.email,
    this.telefono,
    this.direccion,
    this.rating = 0,
  });

  /// Nombre mostrado (alias de razonSocial para alinear con el frontend).
  String get nombre => razonSocial;

  factory Proveedor.fromJson(Map<String, dynamic> j) => Proveedor(
        id: j['id'] as String,
        razonSocial: (j['razon_social'] ?? j['nombre']) as String? ?? '',
        ruc: j['ruc'] as String?,
        contacto: j['contacto'] as String?,
        email: j['email'] as String?,
        telefono: j['telefono'] as String?,
        direccion: j['direccion'] as String?,
        rating: (j['rating'] as num?)?.toInt() ?? 0,
      );
}

// ── Ticket de compra (flujo Logística) ─────────────────────────────────────────
// Espejo de TicketCompra/TicketCompraItem del backend (/logistica/compras).
// Claves en camelCase: el backend ya las emite así (TicketCompraOut).

class TicketCompraItem {
  final String id;
  final String ticketId;
  final String? materialId;
  final String nombre;
  final int cantidad;            // cantidad a comprar (editable por logística)
  final int? cantidadSugerida;   // sugerencia automática (solo lectura)
  final int? stockAlAprobar;
  final int? stockMinimoAlAprobar;
  final int? cantidadComprada;
  final String unidad;
  final double? precioUnitario;
  final double? totalItem;
  final String? proveedorId;
  final String? proveedorNombre;
  final String? canalPersonalizado;
  final String? factura;
  final String estadoItem;       // pendiente | comprado | cancelado
  final String? nota;
  final String tipoItem;         // material | equipo | herramienta
  final String? equipoId;

  const TicketCompraItem({
    required this.id,
    required this.ticketId,
    this.materialId,
    required this.nombre,
    required this.cantidad,
    this.cantidadSugerida,
    this.stockAlAprobar,
    this.stockMinimoAlAprobar,
    this.cantidadComprada,
    required this.unidad,
    this.precioUnitario,
    this.totalItem,
    this.proveedorId,
    this.proveedorNombre,
    this.canalPersonalizado,
    this.factura,
    required this.estadoItem,
    this.nota,
    required this.tipoItem,
    this.equipoId,
  });

  /// true si el ítem es nuevo (no existe en inventario): requiere vinculación.
  bool get sinVincular =>
      estadoItem != 'cancelado' && materialId == null && equipoId == null;

  factory TicketCompraItem.fromJson(Map<String, dynamic> j) => TicketCompraItem(
        id: j['id'] as String? ?? '',
        ticketId: j['ticketId'] as String? ?? '',
        materialId: j['materialId'] as String?,
        nombre: j['nombre'] as String? ?? '',
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
        cantidadSugerida: (j['cantidadSugerida'] as num?)?.toInt(),
        stockAlAprobar: (j['stockAlAprobar'] as num?)?.toInt(),
        stockMinimoAlAprobar: (j['stockMinimoAlAprobar'] as num?)?.toInt(),
        cantidadComprada: (j['cantidadComprada'] as num?)?.toInt(),
        unidad: j['unidad'] as String? ?? '',
        precioUnitario: (j['precioUnitario'] as num?)?.toDouble(),
        totalItem: (j['totalItem'] as num?)?.toDouble(),
        proveedorId: j['proveedorId'] as String?,
        proveedorNombre: j['proveedorNombre'] as String?,
        canalPersonalizado: j['canalPersonalizado'] as String?,
        factura: j['factura'] as String?,
        estadoItem: j['estadoItem'] as String? ?? 'pendiente',
        nota: j['nota'] as String?,
        tipoItem: j['tipoItem'] as String? ?? 'material',
        equipoId: j['equipoId'] as String?,
      );
}

class TicketCompra {
  final String id;
  final String codigo;
  final String? requerimientoId;
  final String? proyectoId;
  final String proyectoNombre;
  final String? servicioId;
  final String? servicioNombre;
  final String solicitanteNombre;
  final String estado; // pendiente | en_proceso | completado | cancelado
  final List<TicketCompraItem> items;
  final bool? modoUnificado;
  final String? proveedorUnicoId;
  final String? proveedorUnicoNombre;
  final String? canalUnico;
  final double? totalEstimado;
  final double? totalReal;
  final String? nota;
  final String creadoEn;
  final String? actualizadoEn;
  final bool ingresoRegistrado;

  const TicketCompra({
    required this.id,
    required this.codigo,
    this.requerimientoId,
    this.proyectoId,
    required this.proyectoNombre,
    this.servicioId,
    this.servicioNombre,
    required this.solicitanteNombre,
    required this.estado,
    required this.items,
    this.modoUnificado,
    this.proveedorUnicoId,
    this.proveedorUnicoNombre,
    this.canalUnico,
    this.totalEstimado,
    this.totalReal,
    this.nota,
    required this.creadoEn,
    this.actualizadoEn,
    this.ingresoRegistrado = false,
  });

  int get itemsPendientesCount =>
      items.where((i) => i.estadoItem == 'pendiente').length;

  int get itemsHechosCount => items.length - itemsPendientesCount;

  double get total =>
      totalReal ??
      items.fold(
        0.0,
        (s, i) => s + ((i.cantidadComprada ?? 0) * (i.precioUnitario ?? 0)),
      );

  factory TicketCompra.fromJson(Map<String, dynamic> j) => TicketCompra(
        id: j['id'] as String? ?? '',
        codigo: j['codigo'] as String? ?? '',
        requerimientoId: j['requerimientoId'] as String?,
        proyectoId: j['proyectoId'] as String?,
        proyectoNombre: j['proyectoNombre'] as String? ?? '—',
        servicioId: j['servicioId'] as String?,
        servicioNombre: j['servicioNombre'] as String?,
        solicitanteNombre: j['solicitanteNombre'] as String? ?? '—',
        estado: j['estado'] as String? ?? 'pendiente',
        items: (j['items'] as List? ?? [])
            .map((e) => TicketCompraItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        modoUnificado: j['modoUnificado'] as bool?,
        proveedorUnicoId: j['proveedorUnicoId'] as String?,
        proveedorUnicoNombre: j['proveedorUnicoNombre'] as String?,
        canalUnico: j['canalUnico'] as String?,
        totalEstimado: (j['totalEstimado'] as num?)?.toDouble(),
        totalReal: (j['totalReal'] as num?)?.toDouble(),
        nota: j['nota'] as String?,
        creadoEn: j['creadoEn'] as String? ?? '',
        actualizadoEn: j['actualizadoEn'] as String?,
        ingresoRegistrado: j['ingresoRegistrado'] as bool? ?? false,
      );
}

// ── Resumen de KPIs de compras ──────────────────────────────────────────────

class ComprasResumen {
  final int pendiente;
  final int enProceso;
  final int completado;
  final int cancelado;

  const ComprasResumen({
    this.pendiente = 0,
    this.enProceso = 0,
    this.completado = 0,
    this.cancelado = 0,
  });

  factory ComprasResumen.fromJson(Map<String, dynamic> j) => ComprasResumen(
        pendiente: (j['pendiente'] as num?)?.toInt() ?? 0,
        enProceso: (j['en_proceso'] as num?)?.toInt() ?? 0,
        completado: (j['completado'] as num?)?.toInt() ?? 0,
        cancelado: (j['cancelado'] as num?)?.toInt() ?? 0,
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

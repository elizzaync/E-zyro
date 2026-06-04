/// Equipos/herramientas que el técnico puede solicitar como préstamo.
class EquipoCatalogo {
  final String id;
  final String? codigo;
  final String nombre;
  final String clase; // 'equipo' | 'herramienta'
  final String? tipo;
  final String? marca;
  final String? modelo;
  final String? almacenNombre;
  final int cantidadTotal;
  final int cantidadDisponible;
  final bool requiereMantenimiento;

  const EquipoCatalogo({
    required this.id,
    this.codigo,
    required this.nombre,
    required this.clase,
    this.tipo,
    this.marca,
    this.modelo,
    this.almacenNombre,
    required this.cantidadTotal,
    required this.cantidadDisponible,
    this.requiereMantenimiento = false,
  });

  factory EquipoCatalogo.fromJson(Map<String, dynamic> j) => EquipoCatalogo(
        id: j['id'] as String,
        codigo: j['codigo'] as String?,
        nombre: j['nombre'] as String? ?? '',
        clase: j['clase'] as String? ?? 'equipo',
        tipo: j['tipo'] as String?,
        marca: j['marca'] as String?,
        modelo: j['modelo'] as String?,
        almacenNombre: j['almacen_nombre'] as String?,
        cantidadTotal: (j['cantidad_total'] as num?)?.toInt() ?? 0,
        cantidadDisponible: (j['cantidad_disponible'] as num?)?.toInt() ?? 0,
        requiereMantenimiento: j['requiere_mantenimiento'] as bool? ?? false,
      );
}

class PrestamoItem {
  final String id;
  final String equipoId;
  final String equipoNombre;
  final String? equipoCodigo;
  final String clase;
  final int cantidadSolicitada;
  final int? cantidadEntregada;
  final int? cantidadDevuelta;
  final int cantidadPerdida;
  final String? observacion;

  const PrestamoItem({
    required this.id,
    required this.equipoId,
    required this.equipoNombre,
    this.equipoCodigo,
    required this.clase,
    required this.cantidadSolicitada,
    this.cantidadEntregada,
    this.cantidadDevuelta,
    this.cantidadPerdida = 0,
    this.observacion,
  });

  factory PrestamoItem.fromJson(Map<String, dynamic> j) => PrestamoItem(
        id: j['id'] as String,
        equipoId: j['equipo_id'] as String? ?? '',
        equipoNombre: j['equipo_nombre'] as String? ?? '—',
        equipoCodigo: j['equipo_codigo'] as String?,
        clase: j['clase'] as String? ?? 'equipo',
        cantidadSolicitada: (j['cantidad_solicitada'] as num?)?.toInt() ?? 0,
        cantidadEntregada: (j['cantidad_entregada'] as num?)?.toInt(),
        cantidadDevuelta: (j['cantidad_devuelta'] as num?)?.toInt(),
        cantidadPerdida: (j['cantidad_perdida'] as num?)?.toInt() ?? 0,
        observacion: j['observacion'] as String?,
      );
}

class Prestamo {
  final String id;
  final String servicioId;
  final String? servicioNombre;
  final String? proyectoNombre;
  final String solicitanteId;
  final String solicitanteNombre;
  final String estado; // solicitado | entregado | devuelto | confirmado | rechazado
  final String? observacion;
  final String? observacionLogistico;
  final String? entregadoPorNombre;
  final String? devueltoPorNombre;
  final String? confirmadoPorNombre;
  final String fechaSolicitud;
  final String? fechaEntrega;
  final String? fechaDevolucion;
  final String? fechaConfirmacion;
  final String? firmaReceptorUrl;
  final String? firmaEntregadorUrl;
  final String? firmandoPorNombre;   // cinema-seat: quién firma la recepción ahora
  final List<PrestamoItem> items;

  const Prestamo({
    required this.id,
    required this.servicioId,
    this.servicioNombre,
    this.proyectoNombre,
    required this.solicitanteId,
    required this.solicitanteNombre,
    required this.estado,
    this.observacion,
    this.observacionLogistico,
    this.entregadoPorNombre,
    this.devueltoPorNombre,
    this.confirmadoPorNombre,
    required this.fechaSolicitud,
    this.fechaEntrega,
    this.fechaDevolucion,
    this.fechaConfirmacion,
    this.firmaReceptorUrl,
    this.firmaEntregadorUrl,
    this.firmandoPorNombre,
    required this.items,
  });

  /// Préstamo auto-generado al recibir la compra de un faltante (marca interna).
  bool get esAutoCompra => (observacion ?? '').startsWith('[auto:tc:');

  /// Despachado por logística, pendiente de que el equipo firme la recepción.
  bool get porRecibir => estado == 'por_recibir';

  /// Otro técnico tiene el lock de firma de recepción ahora mismo.
  bool get hayAlguienFirmando =>
      firmandoPorNombre != null && firmandoPorNombre!.isNotEmpty;

  factory Prestamo.fromJson(Map<String, dynamic> j) => Prestamo(
        id: j['id'] as String,
        servicioId: j['servicio_id'] as String? ?? '',
        servicioNombre: j['servicio_nombre'] as String?,
        proyectoNombre: j['proyecto_nombre'] as String?,
        solicitanteId: j['solicitante_id'] as String? ?? '',
        solicitanteNombre: j['solicitante_nombre'] as String? ?? '—',
        estado: j['estado'] as String? ?? 'solicitado',
        observacion: j['observacion'] as String?,
        observacionLogistico: j['observacion_logistico'] as String?,
        entregadoPorNombre: j['entregado_por_nombre'] as String?,
        devueltoPorNombre: j['devuelto_por_nombre'] as String?,
        confirmadoPorNombre: j['confirmado_por_nombre'] as String?,
        fechaSolicitud: j['fecha_solicitud'] as String? ?? '',
        fechaEntrega: j['fecha_entrega'] as String?,
        fechaDevolucion: j['fecha_devolucion'] as String?,
        fechaConfirmacion: j['fecha_confirmacion'] as String?,
        firmaReceptorUrl: j['firma_receptor_url'] as String?,
        firmaEntregadorUrl: j['firma_entregador_url'] as String?,
        firmandoPorNombre: j['firmando_por_nombre'] as String?,
        items: (j['items'] as List? ?? [])
            .map((e) => PrestamoItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Aviso liviano: préstamos del servicio en estado 'devuelto' (esperando confirmación).
class PrestamoAviso {
  final String id;
  final String servicioId;
  final String estado;
  final String? fechaDevolucion;
  final int totalItems;

  const PrestamoAviso({
    required this.id,
    required this.servicioId,
    required this.estado,
    this.fechaDevolucion,
    required this.totalItems,
  });

  factory PrestamoAviso.fromJson(Map<String, dynamic> j) => PrestamoAviso(
        id: j['id'] as String,
        servicioId: j['servicio_id'] as String? ?? '',
        estado: j['estado'] as String? ?? '',
        fechaDevolucion: j['fecha_devolucion'] as String?,
        totalItems: (j['total_items'] as num?)?.toInt() ?? 0,
      );
}

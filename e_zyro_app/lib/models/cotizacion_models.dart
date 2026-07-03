/// Modelos del módulo de cotizaciones (ciclo comercial).
library;

double _toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

class CotizacionItem {
  final String id, descripcion;
  final String? unidad;
  final double cantidad, precioUnitario, total;
  CotizacionItem({
    required this.id, required this.descripcion, this.unidad,
    required this.cantidad, required this.precioUnitario, required this.total,
  });
  factory CotizacionItem.fromJson(Map<String, dynamic> j) => CotizacionItem(
        id: j['id'].toString(),
        descripcion: j['descripcion']?.toString() ?? '',
        unidad: j['unidad']?.toString(),
        cantidad: _toD(j['cantidad']),
        precioUnitario: _toD(j['precio_unitario']),
        total: _toD(j['total']),
      );
}

class Cotizacion {
  final String id, numero, clienteId, cliente, estado, moneda;
  final String? ruc, condicionesPago, notas, proyectoId, resueltoVia;
  final String fechaEmision, vence;
  final int validezDias;
  final double subtotal, igv, total;
  final List<CotizacionItem> items;
  Cotizacion({
    required this.id, required this.numero, required this.clienteId,
    required this.cliente, this.ruc, required this.estado,
    required this.moneda, required this.fechaEmision, required this.vence,
    required this.validezDias, required this.subtotal, required this.igv,
    required this.total, this.condicionesPago, this.notas,
    this.proyectoId, this.resueltoVia, this.items = const [],
  });
  factory Cotizacion.fromJson(Map<String, dynamic> j) => Cotizacion(
        id: j['id'].toString(),
        numero: j['numero']?.toString() ?? '',
        clienteId: j['cliente_id'].toString(),
        cliente: j['cliente']?.toString() ?? '',
        ruc: j['ruc']?.toString(),
        estado: j['estado']?.toString() ?? 'borrador',
        moneda: j['moneda']?.toString() ?? 'PEN',
        fechaEmision: j['fecha_emision']?.toString() ?? '',
        vence: j['vence']?.toString() ?? '',
        validezDias: (j['validez_dias'] as num?)?.toInt() ?? 30,
        subtotal: _toD(j['subtotal']),
        igv: _toD(j['igv']),
        total: _toD(j['total']),
        condicionesPago: j['condiciones_pago']?.toString(),
        notas: j['notas']?.toString(),
        proyectoId: j['proyecto_id']?.toString(),
        resueltoVia: j['resuelto_via']?.toString(),
        items: (j['items'] as List? ?? [])
            .map((e) => CotizacionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Ítem editable del formulario (antes de guardar).
class ItemBorrador {
  String descripcion;
  String? unidad;
  double cantidad;
  double precioUnitario;
  ItemBorrador({
    this.descripcion = '', this.unidad,
    this.cantidad = 1, this.precioUnitario = 0,
  });
  double get total => cantidad * precioUnitario;
  Map<String, dynamic> toJson() => {
        'descripcion': descripcion,
        if (unidad != null && unidad!.isNotEmpty) 'unidad': unidad,
        'cantidad': cantidad,
        'precio_unitario': precioUnitario,
      };
}

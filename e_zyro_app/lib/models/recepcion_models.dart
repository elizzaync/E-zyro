// ─────────────────────────────────────────────────────────────────────────
//  Modelos de la recepción de materiales (HU-16) y notas con permisos.
//
//  Recepción: cuando Logística APRUEBA un requerimiento de un servicio, este
//  aparece "listo para firmar". Un técnico (uno solo, para evitar errores)
//  firma la recepción → el requerimiento pasa a 'listo' y Logística despacha.
//
//  Backend (router logística, prefijo /logistica):
//    GET  /logistica/requerimientos?estado=todos&servicio_id={id}
//    POST /logistica/requerimientos/{id}/firmar  { recibidoPorId, firmaUrl }
//  El payload del backend viene en camelCase (RequerimientoOut).
// ─────────────────────────────────────────────────────────────────────────

class ReqRecepcionItem {
  final String id;
  final String nombre;
  final String unidad;
  final int cantidad;
  final int? cantidadAprobada;
  final String estadoItem; // pendiente | aprobado | para_compra | rechazado
  final bool esCompraExterna;

  const ReqRecepcionItem({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    this.cantidadAprobada,
    required this.estadoItem,
    required this.esCompraExterna,
  });

  /// Cantidad efectiva a recibir (la aprobada si existe, si no la solicitada).
  int get cantidadEfectiva => cantidadAprobada ?? cantidad;

  bool get rechazado => estadoItem == 'rechazado';
  bool get esCompra => estadoItem == 'para_compra' || esCompraExterna;

  factory ReqRecepcionItem.fromJson(Map<String, dynamic> j) => ReqRecepcionItem(
        id: (j['id'] ?? '').toString(),
        nombre: j['nombre'] as String? ?? '—',
        unidad: j['unidad'] as String? ?? '',
        cantidad: (j['cantidad'] as num? ?? 0).toInt(),
        cantidadAprobada: j['cantidadAprobada'] == null
            ? null
            : (j['cantidadAprobada'] as num).toInt(),
        estadoItem: j['estadoItem'] as String? ?? 'pendiente',
        esCompraExterna: j['esCompraExterna'] as bool? ?? false,
      );
}

class ReqRecepcion {
  final String id;
  final String estado; // pendiente | comprando | listo | aprobado | entregado | rechazado
  final String? fecha;
  final String solicitanteNombre;
  final List<ReqRecepcionItem> items;

  /// MODELO HÍBRIDO — quién mantiene el lock de firma (si hay alguien firmando).
  /// Se actualiza en tiempo real vía WS (`requerimiento_actualizado`).
  final String? firmandoPorNombre;
  final String? firmandoDesde;

  const ReqRecepcion({
    required this.id,
    required this.estado,
    this.fecha,
    required this.solicitanteNombre,
    required this.items,
    this.firmandoPorNombre,
    this.firmandoDesde,
  });

  /// 'listo' = materiales disponibles (de stock o compra ya llegada) →
  /// el equipo puede firmar la recepción.
  bool get porFirmar => estado == 'listo';

  /// 'comprando' = sin stock, en proceso de compra (informativo, no firmable).
  bool get enCompra => estado == 'comprando';

  /// MODELO HÍBRIDO — 'aprobado' = el técnico firmó la recepción.
  /// Estado funcional final desde el campo (el equipo ya tiene los materiales),
  /// pero PENDIENTE de cierre administrativo por logística.
  bool get recibido => estado == 'aprobado';

  /// MODELO HÍBRIDO — 'entregado' = logística cerró contablemente con su firma.
  /// Estado final completo (las dos firmas están en `RequerimientoEntrega`).
  bool get cerrado => estado == 'entregado';

  /// True si hay un técnico activamente firmando ahora mismo (cinema-seat).
  /// La UI debe deshabilitar el botón "Firmar" para los demás dispositivos.
  bool get hayAlguienFirmando =>
      firmandoPorNombre != null && firmandoPorNombre!.isNotEmpty;

  /// Ítems que efectivamente llegan (no rechazados).
  List<ReqRecepcionItem> get itemsValidos =>
      items.where((it) => !it.rechazado).toList();

  factory ReqRecepcion.fromJson(Map<String, dynamic> j) => ReqRecepcion(
        id: (j['id'] ?? '').toString(),
        estado: j['estado'] as String? ?? 'pendiente',
        fecha: j['fecha'] as String?,
        solicitanteNombre: j['solicitanteNombre'] as String? ?? 'Equipo',
        items: (j['items'] as List? ?? [])
            .map((e) => ReqRecepcionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        firmandoPorNombre: j['firmandoPorNombre'] as String?,
        firmandoDesde: j['firmandoDesde'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────
//  Nota del servicio con bandera de permiso de edición (CRUD).
//  Backend: GET /operaciones/servicio/{id}/notas → NotaOut[]
// ─────────────────────────────────────────────────────────────────────────

class NotaServicio {
  final String id;
  final String descripcion;
  final String autor;
  final String? autorId;
  final String fecha;
  final bool puedeEditar;

  const NotaServicio({
    required this.id,
    required this.descripcion,
    required this.autor,
    this.autorId,
    required this.fecha,
    required this.puedeEditar,
  });

  factory NotaServicio.fromJson(Map<String, dynamic> j) => NotaServicio(
        id: (j['id'] ?? '').toString(),
        descripcion: j['descripcion'] as String? ?? '',
        autor: j['autor'] as String? ?? 'Usuario',
        autorId: j['autor_id'] as String?,
        fecha: j['fecha'] as String? ?? '—',
        puedeEditar: j['puede_editar'] as bool? ?? false,
      );
}

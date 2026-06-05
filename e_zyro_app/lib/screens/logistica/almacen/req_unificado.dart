// req_unificado.dart — Fase 1: adaptador/view-model que UNIFICA materiales
// (SolicitudGestion) y equipos/herramientas (Prestamo) en un solo modelo para
// la pantalla unificada de requerimientos.
//
// Principio clave: NO se reemplazan los modelos reales. Cada ReqUnificado
// CONSERVA una referencia al objeto original (`solicitud` o `prestamo`) para
// que las acciones (aprobar/entregar/rechazar/devolución/firma) sigan llamando
// su servicio y endpoint reales sin perder lógica.

import '../../../models/requerimiento_models.dart';
import '../../../models/prestamo_models.dart';

enum TipoReq { material, equipo }

/// Ítem normalizado para pintar la tarjeta (nombre + cantidad + stock opcional).
class ReqUnificadoItem {
  final String nombre;
  final String cantidadLabel; // p. ej. "5 u", "400 m", "1 u"
  final bool? enStock;        // null para equipos (y para materiales hasta enriquecer en Fase 2)
  const ReqUnificadoItem({
    required this.nombre,
    required this.cantidadLabel,
    this.enStock,
  });
}

/// View-model unificado de un requerimiento (material o equipo).
class ReqUnificado {
  final String id;
  final TipoReq tipo;
  final String estadoReal;   // estado crudo del backend (para decidir acciones)
  final String estadoNorm;   // normalizado para los tabs: pendiente|aprobado|entregado|devuelto|rechazado
  final String estadoLabel;  // etiqueta para StatusPill (Pendiente|Aprobada|Entregada|En préstamo|Devuelto|Rechazado)
  final String solicitante;
  final String proyecto;
  final String fecha;
  final List<ReqUnificadoItem> items;
  final String? dueText;     // texto de devolución para equipos (si aplica)

  // Referencias al objeto original — fuente de verdad para las acciones.
  final SolicitudGestion? solicitud;
  final Prestamo? prestamo;

  const ReqUnificado({
    required this.id,
    required this.tipo,
    required this.estadoReal,
    required this.estadoNorm,
    required this.estadoLabel,
    required this.solicitante,
    required this.proyecto,
    required this.fecha,
    required this.items,
    this.dueText,
    this.solicitud,
    this.prestamo,
  });

  bool get esMaterial => tipo == TipoReq.material;
  bool get esEquipo => tipo == TipoReq.equipo;

  /// Código corto para mostrar en la tarjeta (REQ-XXXXXX).
  String get codigoCorto {
    final base = id.replaceAll('-', '');
    return 'REQ-${base.substring(0, base.length < 6 ? base.length : 6).toUpperCase()}';
  }

  // ── Adaptador: SolicitudGestion (material) ────────────────────────────────
  // [stockPorMaterial] (materialId → stock disponible) permite mostrar el
  // StockChip "En stock / Req. compra". Si es null o no contiene el material,
  // el ítem queda con enStock=null (sin chip).
  factory ReqUnificado.fromSolicitud(
    SolicitudGestion s, {
    Map<String, int>? stockPorMaterial,
  }) {
    final norm = _normMaterial(s.estado);
    return ReqUnificado(
      id: s.id,
      tipo: TipoReq.material,
      estadoReal: s.estado,
      estadoNorm: norm,
      estadoLabel: _labelMaterial(s.estado),
      solicitante: s.solicitanteNombre,
      proyecto: s.proyectoNombre,
      fecha: s.fecha,
      items: s.items.map((it) {
        bool? enStock;
        final mid = it.materialId;
        if (mid != null && stockPorMaterial != null) {
          final stock = stockPorMaterial[mid];
          if (stock != null) enStock = stock >= it.cantidad;
        }
        return ReqUnificadoItem(
          nombre: it.nombre,
          cantidadLabel: '${it.cantidad} ${it.unidad}'.trim(),
          enStock: enStock,
        );
      }).toList(),
      solicitud: s,
    );
  }

  // ── Adaptador: Prestamo (equipo/herramienta) ──────────────────────────────
  factory ReqUnificado.fromPrestamo(Prestamo p) {
    final norm = _normPrestamo(p.estado);
    return ReqUnificado(
      id: p.id,
      tipo: TipoReq.equipo,
      estadoReal: p.estado,
      estadoNorm: norm,
      estadoLabel: _labelPrestamo(p.estado),
      solicitante: p.solicitanteNombre,
      proyecto: p.proyectoNombre ?? p.servicioNombre ?? 'Servicio',
      fecha: p.fechaSolicitud,
      items: p.items
          .map((it) => ReqUnificadoItem(
                nombre: it.equipoNombre,
                cantidadLabel: '${it.cantidadSolicitada} u',
                enStock: null, // equipos no usan stock chip
              ))
          .toList(),
      dueText: _duePrestamo(p),
      prestamo: p,
    );
  }
}

// ── Normalización de estados a dominio común (para los tabs) ─────────────────
// Tabs comunes: pendiente | aprobado | entregado | devuelto | rechazado

String _normMaterial(String e) {
  switch (e) {
    case 'pendiente':
    case 'listo':
    case 'comprando':
      return 'pendiente';
    case 'aprobado':
      return 'aprobado';
    case 'entregado':
      return 'entregado';
    case 'rechazado':
      return 'rechazado';
    default:
      return 'pendiente';
  }
}

String _normPrestamo(String e) {
  switch (e) {
    case 'solicitado':
      return 'pendiente';
    case 'por_recibir':
    case 'entregado':
      return 'entregado'; // en poder del técnico (préstamo activo)
    case 'devuelto':
    case 'confirmado':
      return 'devuelto';
    case 'rechazado':
      return 'rechazado';
    default:
      return 'pendiente';
  }
}

// ── Etiquetas para StatusPill (deben existir en esStatusColors) ──────────────

String _labelMaterial(String e) {
  switch (e) {
    case 'pendiente':
    case 'listo':
    case 'comprando':
      return 'Pendiente';
    case 'aprobado':
      return 'Aprobada';
    case 'entregado':
      return 'Entregada';
    case 'rechazado':
      return 'Rechazado';
    default:
      return 'Pendiente';
  }
}

String _labelPrestamo(String e) {
  switch (e) {
    case 'solicitado':
      return 'Pendiente';
    case 'por_recibir':
      return 'Aprobada'; // despachado, espera firma de recepción
    case 'entregado':
      return 'En préstamo';
    case 'devuelto':
    case 'confirmado':
      return 'Devuelto';
    case 'rechazado':
      return 'Rechazado';
    default:
      return 'Pendiente';
  }
}

// Texto de devolución para préstamos. El backend aún NO modela una fecha límite,
// así que por ahora se deriva del estado/fechas disponibles (mejora futura:
// añadir fecha_limite al préstamo para mostrar "Vencido/Devolver en X días").
String? _duePrestamo(Prestamo p) {
  switch (p.estado) {
    case 'entregado':
      return 'En préstamo';
    case 'por_recibir':
      return 'Espera firma de recepción';
    case 'devuelto':
      return p.fechaDevolucion != null ? 'Devuelto ${p.fechaDevolucion}' : 'Devuelto';
    case 'confirmado':
      return 'Devolución confirmada';
    default:
      return null;
  }
}

import 'dart:convert';
import '../core/api_client.dart';
import '../utils/json_async.dart';
import '../core/api_result.dart';
import '../models/compras_models.dart';
import '../models/requerimiento_models.dart' show AlmacenItem;

class ComprasService {
  final ApiClient _client;
  ComprasService(this._client);

  /// Almacenes activos de la empresa (para elegir destino del ingreso).
  Future<List<AlmacenItem>> getAlmacenes() async {
    try {
      final r = await _client.get('/logistica/almacenes');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => AlmacenItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TICKETS DE COMPRA (flujo Logística — /logistica/compras)
  // ══════════════════════════════════════════════════════════════════════════

  /// KPIs por estado para la cabecera.
  Future<ComprasResumen> getComprasResumen() async {
    try {
      final r = await _client.get('/logistica/compras/resumen');
      if (r.statusCode == 200) {
        return ComprasResumen.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const ComprasResumen();
  }

  /// Lista de tickets de un estado. estado: pendiente|en_proceso|completado|cancelado|todos
  Future<List<TicketCompra>> getTicketsCompra({
    String estado = 'pendiente',
    String q = '',
  }) async {
    try {
      final params = <String, String>{
        'estado': estado,
        'page': '1',
        'page_size': '200',
      };
      if (q.trim().isNotEmpty) params['q'] = q.trim();
      final query = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final r = await _client.get('/logistica/compras?$query');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        final list = body is Map ? (body['items'] as List? ?? []) : (body as List? ?? []);
        return list
            .map((e) => TicketCompra.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Detalle fresco de un ticket (con ítems).
  Future<TicketCompra?> getTicketCompra(String id) async {
    try {
      final r = await _client.get('/logistica/compras/$id');
      if (r.statusCode == 200) {
        return TicketCompra.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// Registra detalles de compra. completado=false guarda progreso (en_proceso);
  /// completado=true completa el ticket y dispara el auto-ingreso al inventario.
  Future<ApiResult<TicketCompra>> procesarCompra(
    String id, {
    required bool modoUnificado,
    String? proveedorUnicoId,
    String? proveedorUnicoNombre,
    String? canalUnico,
    String? nota,
    required bool completado,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final r = await _client.patch('/logistica/compras/$id/procesar', {
        'modoUnificado': modoUnificado,
        'proveedorUnicoId': proveedorUnicoId,
        'proveedorUnicoNombre': proveedorUnicoNombre,
        'canalUnico': canalUnico,
        'nota': nota,
        'completado': completado,
        'items': items,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(
            TicketCompra.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Cancela un ticket con motivo opcional.
  Future<ApiResult<TicketCompra>> cancelarCompra(String id, {String? motivo}) async {
    try {
      final r = await _client.post('/logistica/compras/$id/cancelar', {
        'motivo': motivo,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(
            TicketCompra.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Registro manual de ingreso (override). items: [{itemId, cantidad}].
  Future<ApiResult<TicketCompra>> registrarIngreso(
    String ticketId, {
    String? almacenId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final r = await _client.post('/logistica/compras/$ticketId/registrar-ingreso', {
        'almacenId': almacenId,
        'items': items,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(
            TicketCompra.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Crea/enlaza un ítem nuevo a inventario (material o equipo/herramienta).
  Future<ApiResult<TicketCompraItem>> vincularInventario(
    String ticketId,
    String itemId,
    Map<String, dynamic> body,
  ) async {
    try {
      final r = await _client.post(
        '/logistica/compras/$ticketId/items/$itemId/vincular-inventario',
        body,
      );
      if (r.statusCode == 200) {
        return ApiResult.ok(
            TicketCompraItem.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Proveedores ─────────────────────────────────────────────────────────────

  Future<List<Proveedor>> getProveedores() async {
    try {
      final r = await _client.get('/logistica/proveedores');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => Proveedor.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> crearProveedor(Map<String, dynamic> body) async {
    try {
      final r = await _client.post('/logistica/proveedores', body);
      return r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> editarProveedor(String id, Map<String, dynamic> body) async {
    try {
      final r = await _client.patch('/logistica/proveedores/$id', body);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> eliminarProveedor(String id) async {
    try {
      final r = await _client.delete('/logistica/proveedores/$id');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Órdenes de compra ─────────────────────────────────────────────────────────

  Future<List<OrdenCompra>> getOrdenes({String? estado}) async {
    try {
      final query = (estado != null && estado.isNotEmpty)
          ? '?estado=${Uri.encodeComponent(estado)}'
          : '';
      final r = await _client.get('/compras/ordenes$query');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => OrdenCompra.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<OrdenCompra?> getOrden(String id) async {
    try {
      final r = await _client.get('/compras/ordenes/$id');
      if (r.statusCode == 200) {
        return OrdenCompra.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> crearOrden({
    required String proveedorId,
    String? fechaEntregaEstimada,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final r = await _client.post('/compras/ordenes', {
        'proveedor_id': proveedorId,
        'fecha_entrega_estimada': ?fechaEntregaEstimada,
        'items': items,
      });
      return r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cambiarEstadoOrden(String id, String estado) async {
    try {
      final r = await _client.patch('/compras/ordenes/$id/estado', {
        'estado': estado,
      });
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Recepción de mercadería ───────────────────────────────────────────────────

  Future<bool> recibirOrden(
    String id, {
    String? almacenId,
    String? notas,
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      final r = await _client.post('/compras/ordenes/$id/recibir', {
        'almacen_id': ?almacenId,
        if (notas != null && notas.isNotEmpty) 'notas': notas,
        'items': ?items,
      });
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}

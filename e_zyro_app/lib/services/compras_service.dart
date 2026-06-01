import 'dart:convert';
import '../core/api_client.dart';
import '../models/compras_models.dart';

class ComprasService {
  final ApiClient _client;
  ComprasService(this._client);

  // ── Proveedores ─────────────────────────────────────────────────────────────

  Future<List<Proveedor>> getProveedores() async {
    try {
      final r = await _client.get('/logistica/proveedores');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
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
        final list = jsonDecode(r.body) as List? ?? [];
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

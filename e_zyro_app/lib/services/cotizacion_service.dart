import 'dart:convert';
import 'dart:typed_data';

import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/cotizacion_models.dart';

/// Cliente del módulo de cotizaciones (/cotizaciones).
class CotizacionService {
  final ApiClient _client;
  CotizacionService(this._client);

  Future<ApiResult<List<Cotizacion>>> listar({String? estado}) async {
    try {
      final qs = estado == null ? '' : '?estado=$estado';
      final r = await _client.get('/cotizaciones$qs');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list
            .map((e) => Cotizacion.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Cotizacion>> _obj(Future<dynamic> Function() call) async {
    try {
      final r = await call();
      if (r.statusCode == 200 || r.statusCode == 201) {
        return ApiResult.ok(
            Cotizacion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Cotizacion>> obtener(String id) =>
      _obj(() => _client.get('/cotizaciones/$id'));

  Future<ApiResult<Cotizacion>> crear({
    String? clienteId,
    String? clienteNuevoRazon,
    String? clienteNuevoRuc,
    required List<ItemBorrador> items,
    int validezDias = 30,
    String? condicionesPago,
    String? notas,
  }) =>
      _obj(() => _client.post('/cotizaciones', {
            'cliente_id': ?clienteId,
            if (clienteId == null)
              'cliente_nuevo': {
                'razon_social': clienteNuevoRazon,
                if (clienteNuevoRuc != null && clienteNuevoRuc.isNotEmpty)
                  'ruc': clienteNuevoRuc,
              },
            'validez_dias': validezDias,
            if (condicionesPago != null && condicionesPago.isNotEmpty)
              'condiciones_pago': condicionesPago,
            if (notas != null && notas.isNotEmpty) 'notas': notas,
            'items': items.map((i) => i.toJson()).toList(),
          }));

  Future<ApiResult<Cotizacion>> editar(String id,
          {List<ItemBorrador>? items,
          int? validezDias,
          String? condicionesPago,
          String? notas}) =>
      _obj(() => _client.put('/cotizaciones/$id', {
            'validez_dias': ?validezDias,
            'condiciones_pago': ?condicionesPago,
            'notas': ?notas,
            'items': ?items?.map((i) => i.toJson()).toList(),
          }));

  Future<bool> eliminarBorrador(String id) async {
    try {
      final r = await _client.delete('/cotizaciones/$id');
      return r.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<ApiResult<Cotizacion>> enviar(String id) =>
      _obj(() => _client.post('/cotizaciones/$id/enviar', {}));

  Future<ApiResult<Cotizacion>> resolver(String id, String estado) =>
      _obj(() => _client.post('/cotizaciones/$id/resolver', {'estado': estado}));

  Future<ApiResult<Cotizacion>> convertir(String id,
          {required String jefeOperacionesId, String? nombreProyecto}) =>
      _obj(() => _client.post('/cotizaciones/$id/convertir', {
            'jefe_operaciones_id': jefeOperacionesId,
            if (nombreProyecto != null && nombreProyecto.isNotEmpty)
              'nombre_proyecto': nombreProyecto,
          }));

  /// Bytes del PDF (el endpoint requiere token — no sirve url_launcher).
  Future<Uint8List?> pdf(String id) async {
    try {
      final r = await _client.get('/cotizaciones/$id/pdf');
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  /// Jefes elegibles para convertir a proyecto (reusa operaciones).
  Future<List<Map<String, String>>> lideres() async {
    try {
      final r = await _client.get('/operaciones/lideres-servicio');
      if (r.statusCode != 200) return [];
      return (jsonDecode(r.body) as List)
          .map((e) => {
                'id': e['id'].toString(),
                'nombre':
                    '${e['nombre'] ?? ''} ${e['apellido'] ?? ''}'.trim(),
              })
          .toList();
    } catch (_) {
      return [];
    }
  }
}

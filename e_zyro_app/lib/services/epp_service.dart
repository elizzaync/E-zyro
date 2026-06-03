import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/epp_models.dart';

/// Cliente del módulo EPP (`/epp`).
class EppService {
  final ApiClient _client;
  EppService(this._client);

  Future<ApiResult<List<Epp>>> listar({String? q, bool stockBajo = false}) async {
    try {
      final params = <String, String>{
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (stockBajo) 'stock_bajo': 'true',
      };
      final qs = Uri(queryParameters: params).query;
      final r = await _client.get('/epp${qs.isEmpty ? '' : '?$qs'}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => Epp.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Epp>> crear({
    required String nombre,
    String? descripcion,
    int stockMin = 0,
    double? precio,
    String? zonaId,
    String? marcaId,
    String? unidadId,
  }) async {
    try {
      final r = await _client.post('/epp', {
        'nombre': nombre,
        if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
        'stock_min': stockMin,
        'precio': ?precio,
        'zona_id': ?zonaId,
        'marca_id': ?marcaId,
        'unidad_id': ?unidadId,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(Epp.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Genera la constancia PDF de una entrega; devuelve la URL del PDF.
  Future<ApiResult<String>> generarConstancia(String entregaId) async {
    try {
      final r = await _client.post('/epp/entregas/$entregaId/constancia', {},
          timeout: const Duration(seconds: 90));
      if (r.statusCode == 200 || r.statusCode == 201) {
        final url = (jsonDecode(r.body) as Map)['pdf_url']?.toString() ?? '';
        return ApiResult.ok(url);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Genera el reporte PDF consolidado de todo el EPP entregado a un técnico;
  /// devuelve la URL del PDF.
  Future<ApiResult<String>> reporteEmpleado(String empleadoId) async {
    try {
      final r = await _client.get('/epp/empleado/$empleadoId/reporte',
          timeout: const Duration(seconds: 90));
      if (r.statusCode == 200) {
        final url = (jsonDecode(r.body) as Map)['pdf_url']?.toString() ?? '';
        return ApiResult.ok(url);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<EppEntrega>>> listarEntregas({String? empleadoId}) async {
    try {
      final qs = (empleadoId != null && empleadoId.isNotEmpty) ? '?empleado_id=$empleadoId' : '';
      final r = await _client.get('/epp/entregas$qs');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => EppEntrega.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// items: lista de {epp_id, cantidad}. firmaBase64 opcional.
  Future<ApiResult<EppEntrega>> crearEntrega({
    required String empleadoId,
    required List<Map<String, dynamic>> items,
    String? firmaBase64,
    String? observacion,
  }) async {
    try {
      final r = await _client.post('/epp/entregas', {
        'empleado_id': empleadoId,
        'items': items,
        'firma_base64': ?firmaBase64,
        if (observacion != null && observacion.isNotEmpty) 'observacion': observacion,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(EppEntrega.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

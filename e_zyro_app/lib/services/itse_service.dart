import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/itse_models.dart';

/// Cliente de Inspección ITSE (`/itse`).
class ItseService {
  final ApiClient _client;
  ItseService(this._client);

  Future<ApiResult<List<InspeccionItse>>> listar({String? estado, String? modo}) async {
    try {
      final params = <String, String>{
        if (estado != null && estado.isNotEmpty) 'estado': estado,
        if (modo != null && modo.isNotEmpty) 'modo': modo,
      };
      final qs = Uri(queryParameters: params).query;
      final r = await _client.get('/itse${qs.isEmpty ? '' : '?$qs'}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => InspeccionItse.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<InspeccionItse>> crear({
    required String modo,
    String? clienteId,
    String? ubicacionId,
    String? zonaId,
    String? observaciones,
  }) async {
    try {
      final r = await _client.post('/itse', {
        'modo': modo,
        'cliente_id': ?clienteId,
        'ubicacion_id': ?ubicacionId,
        'zona_id': ?zonaId,
        if (observaciones != null && observaciones.isNotEmpty) 'observaciones': observaciones,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(InspeccionItse.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Genera el informe PDF de la inspección; devuelve la URL.
  Future<ApiResult<String>> generarInforme(String id) async {
    try {
      final r = await _client.post('/itse/$id/informe', {}, timeout: const Duration(seconds: 90));
      if (r.statusCode == 200) {
        final url = (jsonDecode(r.body) as Map)['pdf_url']?.toString() ?? '';
        return ApiResult.ok(url);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<InspeccionItse>> finalizar(String id) async {
    try {
      final r = await _client.post('/itse/$id/finalizar', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(InspeccionItse.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Tableros ──────────────────────────────────────────────────────────────
  Future<ApiResult<List<InspeccionTablero>>> listarTableros(String id) async {
    try {
      final r = await _client.get('/itse/$id/tableros');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => InspeccionTablero.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<InspeccionTablero>> crearTablero(String id, String nombre, String? ambiente, String? descripcion) async {
    try {
      final r = await _client.post('/itse/$id/tableros', {
        'nombre': nombre, 'ambiente': ?ambiente, 'descripcion': ?descripcion,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(InspeccionTablero.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminarTablero(String tableroId) async {
    try {
      final r = await _client.delete('/itse/tableros/$tableroId');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Ítems ─────────────────────────────────────────────────────────────────
  Future<ApiResult<List<InspeccionItem>>> listarItems(String id) async {
    try {
      final r = await _client.get('/itse/$id/items');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => InspeccionItem.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<InspeccionItem>> crearItem(String id, String descripcion, String resultado, String? observacion, String? tableroId) async {
    try {
      final r = await _client.post('/itse/$id/items', {
        'descripcion': descripcion, 'resultado': resultado,
        'observacion': ?observacion, 'tablero_id': ?tableroId,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(InspeccionItem.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminarItem(String itemId) async {
    try {
      final r = await _client.delete('/itse/items/$itemId');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Fotos ─────────────────────────────────────────────────────────────────
  Future<ApiResult<String>> subirFoto(String id, String imagenBase64, {String? tableroId, String? descripcion}) async {
    try {
      final r = await _client.post('/itse/$id/fotos', {
        'imagen_base64': imagenBase64, 'tablero_id': ?tableroId, 'descripcion': ?descripcion,
      }, timeout: const Duration(seconds: 60));
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok((jsonDecode(r.body) as Map)['secure_url']?.toString() ?? '');
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

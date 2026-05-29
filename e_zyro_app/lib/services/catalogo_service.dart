import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/catalogo_models.dart';

/// Cliente de catálogos base (`/catalogos`): ubicaciones, zonas, áreas.
class CatalogoService {
  final ApiClient _client;
  CatalogoService(this._client);

  Future<ApiResult<List<Ubicacion>>> ubicaciones() async {
    return _list('/catalogos/ubicaciones', (j) => Ubicacion.fromJson(j));
  }

  Future<ApiResult<List<Zona>>> zonas({String? ubicacionId}) async {
    final qs = (ubicacionId != null && ubicacionId.isNotEmpty) ? '?ubicacion_id=$ubicacionId' : '';
    return _list('/catalogos/zonas$qs', (j) => Zona.fromJson(j));
  }

  Future<ApiResult<List<Area>>> areas() async {
    return _list('/catalogos/areas', (j) => Area.fromJson(j));
  }

  Future<ApiResult<List<T>>> _list<T>(String path, T Function(Map<String, dynamic>) fromJson) async {
    try {
      final r = await _client.get(path);
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> crearUbicacion(String nombre, String? region) =>
      _post('/catalogos/ubicaciones', {'nombre': nombre, 'region': ?region});

  Future<ApiResult<void>> crearZona(String nombre, String? tipo, String? ubicacionId) =>
      _post('/catalogos/zonas', {'nombre': nombre, 'tipo': ?tipo, 'ubicacion_id': ?ubicacionId});

  Future<ApiResult<void>> crearArea(String nombre) =>
      _post('/catalogos/areas', {'nombre': nombre});

  Future<ApiResult<void>> _post(String path, Map<String, dynamic> body) async {
    try {
      final r = await _client.post(path, body);
      if (r.statusCode == 201 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminar(String tipo, String id) async {
    try {
      final r = await _client.delete('/catalogos/$tipo/$id');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

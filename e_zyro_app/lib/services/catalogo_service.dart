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

  Future<ApiResult<List<Area>>> areas({String? zonaId, String? ubicacionId}) async {
    final params = <String>[
      if (zonaId != null && zonaId.isNotEmpty) 'zona_id=$zonaId',
      if (ubicacionId != null && ubicacionId.isNotEmpty) 'ubicacion_id=$ubicacionId',
    ];
    final qs = params.isEmpty ? '' : '?${params.join('&')}';
    return _list('/catalogos/areas$qs', (j) => Area.fromJson(j));
  }

  /// Árbol jerárquico ubicacion → zona → area. Si [proyectoId] se indica, se
  /// limita a las ubicaciones usadas por los servicios de ese proyecto.
  Future<ApiResult<List<UbicacionArbol>>> arbol({String? proyectoId}) async {
    final qs = (proyectoId != null && proyectoId.isNotEmpty) ? '?proyecto_id=$proyectoId' : '';
    return _list('/catalogos/arbol$qs', (j) => UbicacionArbol.fromJson(j));
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

  Future<ApiResult<void>> crearArea(String nombre, {String? zonaId, String? ubicacionId}) =>
      _post('/catalogos/areas', {
        'nombre': nombre,
        'zona_id': ?zonaId,
        'ubicacion_id': ?ubicacionId,
      });

  // ── Creación que devuelve la entidad creada (para "+ nuevo" inline) ────────
  Future<ApiResult<Ubicacion>> crearUbicacionRet(String nombre, String? region) =>
      _postRet('/catalogos/ubicaciones', {'nombre': nombre, 'region': ?region},
          (j) => Ubicacion.fromJson(j));

  Future<ApiResult<Zona>> crearZonaRet(String nombre, String? tipo, String? ubicacionId) =>
      _postRet('/catalogos/zonas', {'nombre': nombre, 'tipo': ?tipo, 'ubicacion_id': ?ubicacionId},
          (j) => Zona.fromJson(j));

  Future<ApiResult<Area>> crearAreaRet(String nombre, {String? zonaId, String? ubicacionId}) =>
      _postRet('/catalogos/areas',
          {'nombre': nombre, 'zona_id': ?zonaId, 'ubicacion_id': ?ubicacionId},
          (j) => Area.fromJson(j));

  Future<ApiResult<void>> _post(String path, Map<String, dynamic> body) async {
    try {
      final r = await _client.post(path, body);
      if (r.statusCode == 201 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<T>> _postRet<T>(
      String path, Map<String, dynamic> body, T Function(Map<String, dynamic>) fromJson) async {
    try {
      final r = await _client.post(path, body);
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
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

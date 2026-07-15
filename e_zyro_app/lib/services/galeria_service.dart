import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/galeria_models.dart';

/// Cliente de la Galería Global (`/galeria`).
class GaleriaService {
  final ApiClient _client;
  GaleriaService(this._client);

  /// Lista recursos con filtros opcionales. Filtra siempre por la empresa del token.
  Future<ApiResult<List<RecursoCloudinary>>> listar({
    String? entidadTipo,
    String? entidadId,
    String? recursoTipo,
    String? q,
    String? fechaDesde,
    String? fechaHasta,
    int limit = 60,
    int offset = 0,
  }) async {
    try {
      final params = <String, String>{
        'limit': '$limit',
        'offset': '$offset',
        if (entidadTipo != null && entidadTipo.isNotEmpty) 'entidad_tipo': entidadTipo,
        if (entidadId != null && entidadId.isNotEmpty) 'entidad_id': entidadId,
        if (recursoTipo != null && recursoTipo.isNotEmpty) 'recurso_tipo': recursoTipo,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (fechaDesde != null && fechaDesde.isNotEmpty) 'fecha_desde': fechaDesde,
        if (fechaHasta != null && fechaHasta.isNotEmpty) 'fecha_hasta': fechaHasta,
      };
      final qs = Uri(queryParameters: params).query;
      final r = await _client.get('/galeria?$qs');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(
          list.map((e) => RecursoCloudinary.fromJson(e as Map<String, dynamic>)).toList(),
        );
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Sube una imagen (base64) a la galería. `entidadTipo/entidadId` opcionales.
  Future<ApiResult<RecursoCloudinary>> subir({
    required String imagenBase64,
    String? descripcion,
    String? entidadTipo,
    String? entidadId,
  }) async {
    try {
      final r = await _client.post('/galeria', {
        'imagen_base64': imagenBase64,
        if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
        if (entidadTipo != null && entidadTipo.isNotEmpty) 'entidad_tipo': entidadTipo,
        if (entidadId != null && entidadId.isNotEmpty) 'entidad_id': entidadId,
      }, timeout: const Duration(seconds: 60));
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(
          RecursoCloudinary.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
        );
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Elimina un recurso (también lo borra de Cloudinary en el backend).
  Future<ApiResult<void>> eliminar(String id) async {
    try {
      final r = await _client.delete('/galeria/$id');
      if (r.statusCode == 204 || r.statusCode == 200) {
        return const ApiResult.ok();
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

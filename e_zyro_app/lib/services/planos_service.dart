import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/planos_models.dart';

/// Cliente del módulo de planos (`/planos`): carpetas, planos y versiones.
class PlanosService {
  final ApiClient _client;
  PlanosService(this._client);

  // ── Carpetas ───────────────────────────────────────────────────────────────
  Future<List<Carpeta>> carpetas({String? padreId, String? proyectoId}) async {
    try {
      final p = <String, String>{
        'padre_id': ?padreId,
        'proyecto_id': ?proyectoId,
      };
      final qs = p.isEmpty ? '' : '?${_qs(p)}';
      final r = await _client.get('/planos/carpetas$qs');
      if (r.statusCode == 200) {
        return (jsonDecode(r.body) as List)
            .map((e) => Carpeta.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<ApiResult<Carpeta>> crearCarpeta(String nombre,
      {String? padreId, String? proyectoId}) async {
    return _postObj('/planos/carpetas', {
      'nombre': nombre,
      'padre_id': ?padreId,
      'proyecto_id': ?proyectoId,
    }, (j) => Carpeta.fromJson(j));
  }

  Future<ApiResult<void>> renombrarCarpeta(String id, String nombre) async {
    try {
      final r = await _client.patch('/planos/carpetas/$id', {'nombre': nombre});
      if (r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminarCarpeta(String id) =>
      _delete('/planos/carpetas/$id');

  // ── Planos ───────────────────────────────────────────────────────────────────
  Future<List<PlanoItem>> planos(
      {String? carpetaId, String? proyectoId, String q = ''}) async {
    try {
      final p = <String, String>{
        'carpeta_id': ?carpetaId,
        'proyecto_id': ?proyectoId,
        if (q.trim().isNotEmpty) 'q': q.trim(),
      };
      final qs = p.isEmpty ? '' : '?${_qs(p)}';
      final r = await _client.get('/planos$qs');
      if (r.statusCode == 200) {
        return (jsonDecode(r.body) as List)
            .map((e) => PlanoItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<ApiResult<PlanoItem>> crearPlano({
    required String nombre,
    required String archivoBase64,
    required String filename,
    String? disciplina,
    String? descripcion,
    String? carpetaId,
    String? proyectoId,
  }) async {
    return _postObj('/planos', {
      'nombre': nombre,
      'archivo_base64': archivoBase64,
      'filename': filename,
      'disciplina': ?disciplina,
      'descripcion': ?descripcion,
      'carpeta_id': ?carpetaId,
      'proyecto_id': ?proyectoId,
    }, (j) => PlanoItem.fromJson(j), timeout: const Duration(seconds: 120));
  }

  Future<ApiResult<PlanoItem>> subirVersion(
      String planoId, String archivoBase64, String filename) async {
    return _postObj('/planos/$planoId/versiones', {
      'archivo_base64': archivoBase64,
      'filename': filename,
    }, (j) => PlanoItem.fromJson(j), timeout: const Duration(seconds: 120));
  }

  Future<ApiResult<PlanoItem>> detalle(String planoId) async {
    try {
      final r = await _client.get('/planos/$planoId');
      if (r.statusCode == 200) {
        return ApiResult.ok(
            PlanoItem.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminarPlano(String id) => _delete('/planos/$id');

  // ── Helpers ──────────────────────────────────────────────────────────────────
  String _qs(Map<String, String> p) =>
      p.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

  Future<ApiResult<T>> _postObj<T>(
      String path, Map<String, dynamic> body, T Function(Map<String, dynamic>) fromJson,
      {Duration? timeout}) async {
    try {
      final r = await _client.post(path, body, timeout: timeout);
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> _delete(String path) async {
    try {
      final r = await _client.delete(path);
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

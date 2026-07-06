import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/drive_models.dart';

/// Cliente del Drive de empresa (`/drive`). Lectura y subida abiertas a todos
/// los usuarios; borrar/renombrar lo valida el backend (dueño o gestión/admin).
class DriveService {
  final ApiClient _client;
  DriveService(this._client);

  // ── Carpetas ───────────────────────────────────────────────────────────
  Future<ApiResult<List<DriveCarpeta>>> listarCarpetas({
    required String ambito,
    String? padreId,
  }) async {
    try {
      final qp = 'ambito=$ambito&padre_id=${Uri.encodeComponent(padreId ?? '')}';
      final r = await _client.get('/drive/carpetas?$qp');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(
            list.map((e) => DriveCarpeta.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<DriveCarpeta>> crearCarpeta({
    required String nombre,
    required String ambito,
    String? padreId,
  }) async {
    try {
      final r = await _client.post('/drive/carpetas', {
        'nombre': nombre,
        'ambito': ambito,
        'padre_id': ?padreId,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(DriveCarpeta.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<DriveCarpeta>> renombrarCarpeta(String id, String nombre) async {
    try {
      final r = await _client.put('/drive/carpetas/$id', {'nombre': nombre});
      if (r.statusCode == 200) {
        return ApiResult.ok(DriveCarpeta.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminarCarpeta(String id) async {
    try {
      final r = await _client.delete('/drive/carpetas/$id');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Archivos ───────────────────────────────────────────────────────────
  Future<ApiResult<List<DriveArchivo>>> listarArchivos({
    required String ambito,
    String? carpetaId,
    String? q,
  }) async {
    try {
      final qp = 'ambito=$ambito&carpeta_id=${Uri.encodeComponent(carpetaId ?? '')}'
          '&q=${Uri.encodeComponent(q ?? '')}';
      final r = await _client.get('/drive/archivos?$qp');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(
            list.map((e) => DriveArchivo.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<DriveArchivo>> subirArchivo({
    required String nombre,
    required String filename,
    required String archivoBase64,
    required String ambito,
    String? carpetaId,
    String? descripcion,
  }) async {
    try {
      final r = await _client.post(
        '/drive/archivos',
        {
          'nombre': nombre,
          'filename': filename,
          'archivo_base64': archivoBase64,
          'ambito': ambito,
          'carpeta_id': ?carpetaId,
          'descripcion': ?descripcion,
        },
        // hasta 30 MB en base64: el timeout por defecto (30 s) corta la subida
        timeout: const Duration(minutes: 3),
      );
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(DriveArchivo.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminarArchivo(String id) async {
    try {
      final r = await _client.delete('/drive/archivos/$id');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

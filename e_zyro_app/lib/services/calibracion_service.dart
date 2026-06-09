import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/calibracion_models.dart';

/// Cliente de Calibraciones (`/calibraciones`) y estado de equipos (`/equipos`).
class CalibracionService {
  final ApiClient _client;
  CalibracionService(this._client);

  Future<ApiResult<List<Calibracion>>> listar({bool porVencer = false}) async {
    try {
      final r = await _client.get('/calibraciones${porVencer ? '?por_vencer=true' : ''}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => Calibracion.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Calibracion>> crear({
    required String equipoId,
    String? fechaUltima,
    String? fechaProxima,
    String? empresaResponsable,
    String? observacion,
  }) async {
    try {
      final r = await _client.post('/calibraciones', {
        'equipo_id': equipoId,
        'fecha_ultima': ?fechaUltima,
        'fecha_proxima': ?fechaProxima,
        'empresa_responsable': ?empresaResponsable,
        'observacion': ?observacion,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(Calibracion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Historial de calibraciones (eventos) ──────────────────────────────────

  /// Lista el historial de calibraciones de un equipo (más reciente primero).
  Future<ApiResult<List<CalibracionEvento>>> listarEventos(String equipoId) async {
    try {
      final r = await _client.get('/calibraciones/eventos?equipo_id=$equipoId');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => CalibracionEvento.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Registra una calibración realizada. Si se envía [periodicidadMeses] el
  /// backend calcula la próxima fecha y actualiza el snapshot del equipo.
  Future<ApiResult<CalibracionEvento>> crearEvento({
    required String equipoId,
    required String fechaRealizada,
    int? periodicidadMeses,
    String? fechaProxima,
    String? realizadaPor,
    String? empresaResponsable,
    String? numeroCertificado,
    String? resultado,
    String? observacion,
  }) async {
    try {
      final r = await _client.post('/calibraciones/eventos', {
        'equipo_id': equipoId,
        'fecha_realizada': fechaRealizada,
        'periodicidad_meses': ?periodicidadMeses,
        'fecha_proxima': ?fechaProxima,
        'realizada_por': ?realizadaPor,
        'empresa_responsable': ?empresaResponsable,
        'numero_certificado': ?numeroCertificado,
        'resultado': ?resultado,
        'observacion': ?observacion,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(CalibracionEvento.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Adjunta el certificado (PDF o imagen) a un evento. [extension] = pdf|jpg|png…
  Future<ApiResult<String>> subirCertificadoEvento(
      String eventoId, String archivoBase64, {String extension = 'pdf'}) async {
    try {
      final r = await _client.post('/calibraciones/eventos/$eventoId/certificado',
          {'archivo_base64': archivoBase64, 'extension': extension},
          timeout: const Duration(seconds: 60));
      if (r.statusCode == 200) {
        final url = (jsonDecode(r.body) as Map)['certificado_url']?.toString() ?? '';
        return ApiResult.ok(url);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Elimina un evento del historial (recalcula el snapshot del equipo).
  Future<ApiResult<void>> eliminarEvento(String eventoId) async {
    try {
      final r = await _client.delete('/calibraciones/eventos/$eventoId');
      if (r.statusCode == 204 || r.statusCode == 200) {
        return const ApiResult.ok(null);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Sube el certificado (imagen base64) de una calibración; devuelve la URL.
  Future<ApiResult<String>> subirCertificado(String calId, String archivoBase64) async {
    try {
      final r = await _client.post('/calibraciones/$calId/certificado',
          {'archivo_base64': archivoBase64}, timeout: const Duration(seconds: 60));
      if (r.statusCode == 200) {
        final url = (jsonDecode(r.body) as Map)['certificado_url']?.toString() ?? '';
        return ApiResult.ok(url);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<EquipoEstado>>> listarEstado({String? solo}) async {
    try {
      final r = await _client.get('/equipos/estado${solo != null ? '?solo=$solo' : ''}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => EquipoEstado.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EquipoEstado>> marcarInoperativo(String equipoId, int cantidad, String? motivo) async {
    return _estadoMov('/equipos/$equipoId/inoperativo', cantidad, motivo);
  }

  Future<ApiResult<EquipoEstado>> reactivar(String equipoId, int cantidad, String? motivo) async {
    return _estadoMov('/equipos/$equipoId/reactivar', cantidad, motivo);
  }

  Future<ApiResult<EquipoEstado>> _estadoMov(String path, int cantidad, String? motivo) async {
    try {
      final r = await _client.post(path, {'cantidad': cantidad, 'motivo': ?motivo});
      if (r.statusCode == 200 || r.statusCode == 201) {
        return ApiResult.ok(EquipoEstado.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

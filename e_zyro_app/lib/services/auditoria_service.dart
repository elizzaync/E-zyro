import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/auditoria_models.dart';

class AuditoriaService {
  final ApiClient _client;
  AuditoriaService(this._client);

  Future<List<AuditoriaItem>> getAuditoria({
    String? modulo,
    String? accion,
    String? tablaAfectada,
    String? q,
    String? fechaDesde,
    String? fechaHasta,
    String? usuarioId,
    String? buscarUsuario,
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String>[];
    params.add('page=$page');
    params.add('page_size=$pageSize');
    if (modulo != null && modulo.isNotEmpty) params.add('modulo=$modulo');
    if (accion != null && accion.isNotEmpty) params.add('accion=$accion');
    if (tablaAfectada != null && tablaAfectada.isNotEmpty) params.add('tabla_afectada=$tablaAfectada');
    if (q != null && q.isNotEmpty) params.add('q=${Uri.encodeComponent(q)}');
    if (fechaDesde != null) params.add('fecha_desde=$fechaDesde');
    if (fechaHasta != null) params.add('fecha_hasta=$fechaHasta');
    if (usuarioId != null) params.add('usuario_id=$usuarioId');
    if (buscarUsuario != null && buscarUsuario.isNotEmpty) {
      params.add('buscar_usuario=${Uri.encodeComponent(buscarUsuario)}');
    }

    final path = '/auditoria${params.isEmpty ? '' : '?${params.join('&')}'}';
    // Deja que la excepción de sesión expirada se propague al caller
    final r = await _client.get(path);
    if (r.statusCode == 200) {
      final list = jsonDecode(r.body) as List;
      return list.map((e) => AuditoriaItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (r.statusCode == 403) throw Exception('Sin permiso para ver auditoría');
    return [];
  }

  // ── Auditoría General (solo SuperAdmin) ────────────────────────────────────

  /// Acciones cross-empresa con filtros opcionales.
  Future<ApiResult<List<AuditoriaGeneralItem>>> getAuditoriaGeneral({
    String? empresaId,
    String? usuarioId,
    String? modulo,
    String? accion,
    String? desde,
    String? hasta,
    String? q,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final params = <String>['limit=$limit', 'offset=$offset'];
      if (empresaId != null && empresaId.isNotEmpty) params.add('empresa_id=$empresaId');
      if (usuarioId != null && usuarioId.isNotEmpty) params.add('usuario_id=$usuarioId');
      if (modulo != null && modulo.isNotEmpty) params.add('modulo=${Uri.encodeComponent(modulo)}');
      if (accion != null && accion.isNotEmpty) params.add('accion=${Uri.encodeComponent(accion)}');
      if (desde != null && desde.isNotEmpty) params.add('desde=$desde');
      if (hasta != null && hasta.isNotEmpty) params.add('hasta=$hasta');
      if (q != null && q.isNotEmpty) params.add('q=${Uri.encodeComponent(q)}');

      final r = await _client.get('/auditoria/general?${params.join('&')}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list
            .map((e) => AuditoriaGeneralItem.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Errores/eventos del sistema (tabla log_sistema).
  Future<ApiResult<List<LogSistemaItem>>> getLogsSistema({
    String? nivel,
    String? desde,
    String? hasta,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final params = <String>['limit=$limit', 'offset=$offset'];
      if (nivel != null && nivel.isNotEmpty) params.add('nivel=$nivel');
      if (desde != null && desde.isNotEmpty) params.add('desde=$desde');
      if (hasta != null && hasta.isNotEmpty) params.add('hasta=$hasta');

      final r = await _client.get('/auditoria/logs?${params.join('&')}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list
            .map((e) => LogSistemaItem.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Estadísticas de actividad y errores de los últimos 30 días.
  Future<ApiResult<AuditoriaStats>> getStats() async {
    try {
      final r = await _client.get('/auditoria/stats');
      if (r.statusCode == 200) {
        return ApiResult.ok(
            AuditoriaStats.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

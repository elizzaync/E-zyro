import 'dart:convert';
import 'dart:typed_data';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/equipo_intervenido_models.dart';
import '../models/intervencion_models.dart' show AntecedenteProcedimiento;

class EquipoIntervenidoService {
  final ApiClient _client;
  EquipoIntervenidoService(this._client);

  Future<ApiResult<List<EquipoIntervenido>>> listar({
    String? clienteId,
    String? proyectoId,
    String? estado,
    String? ubicacionId,
    String? zonaId,
    String? areaId,
  }) async {
    try {
      final params = <String>[];
      if (clienteId != null) params.add('cliente_id=$clienteId');
      if (proyectoId != null) params.add('proyecto_id=$proyectoId');
      if (estado != null) params.add('estado=$estado');
      if (ubicacionId != null) params.add('ubicacion_id=$ubicacionId');
      if (zonaId != null) params.add('zona_id=$zonaId');
      if (areaId != null) params.add('area_id=$areaId');
      final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
      final r = await _client.get('/equipos-intervenidos$qs');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list
            .map((e) => EquipoIntervenido.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EquipoIntervenido>> obtener(String id) async {
    try {
      final r = await _client.get('/equipos-intervenidos/$id');
      if (r.statusCode == 200) {
        return ApiResult.ok(
            EquipoIntervenido.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EquipoIntervenido>> crear(Map<String, dynamic> body) async {
    try {
      final r = await _client.post('/equipos-intervenidos', body);
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(
            EquipoIntervenido.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EquipoIntervenido>> actualizar(
      String id, Map<String, dynamic> body) async {
    try {
      final r = await _client.patch('/equipos-intervenidos/$id', body);
      if (r.statusCode == 200) {
        return ApiResult.ok(
            EquipoIntervenido.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Historial de mantenimientos del equipo (más reciente primero).
  Future<ApiResult<List<MantenimientoEquipo>>> listarMantenimientos(String id) async {
    try {
      final r = await _client.get('/equipos-intervenidos/$id/mantenimientos');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list
            .map((e) => MantenimientoEquipo.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }


  Future<ApiResult<void>> eliminar(String id) async {
    try {
      final r = await _client.delete('/equipos-intervenidos/$id');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Directorio de circuitos de tablero ──────────────────────────────────────

  Future<ApiResult<List<TableroCircuito>>> listarCircuitos(String equipoId) async {
    try {
      final r = await _client.get('/equipos-intervenidos/$equipoId/circuitos');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list
            .map((e) => TableroCircuito.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<TableroCircuito>> crearCircuito(
      String equipoId, Map<String, dynamic> body) async {
    try {
      final r = await _client.post('/equipos-intervenidos/$equipoId/circuitos', body);
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(
            TableroCircuito.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<TableroCircuito>> actualizarCircuito(
      String circuitoId, Map<String, dynamic> body) async {
    try {
      final r = await _client.patch('/equipos-intervenidos/circuitos/$circuitoId', body);
      if (r.statusCode == 200) {
        return ApiResult.ok(
            TableroCircuito.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminarCircuito(String circuitoId) async {
    try {
      final r = await _client.delete('/equipos-intervenidos/circuitos/$circuitoId');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Historial de observación/recomendación de un paso puntual del checklist,
  /// a través de sesiones de inspección anteriores del mismo equipo.
  Future<ApiResult<List<AntecedenteProcedimiento>>> antecedenteProcedimiento(
      String equipoId, int orden) async {
    try {
      final r = await _client.get('/equipos-intervenidos/$equipoId/procedimientos/$orden/antecedente');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list
            .map((e) => AntecedenteProcedimiento.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Genera el PDF del directorio de circuitos (blob binario).
  Future<ApiResult<Uint8List>> generarDirectorioPdf(String equipoId) async {
    try {
      final r = await _client.post(
        '/equipos-intervenidos/$equipoId/circuitos/pdf',
        const {},
        timeout: const Duration(seconds: 60),
      );
      if (r.statusCode == 200) return ApiResult.ok(r.bodyBytes);
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

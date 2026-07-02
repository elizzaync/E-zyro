import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/retorno_models.dart';

/// Cliente del flujo "Declarar Devolución": al finalizar un servicio, el
/// técnico indica qué materiales/equipos/herramientas retornan al almacén.
/// Espejo de la lógica de retorno del frontend Angular
/// (operaciones-detalle.component.ts) y de los endpoints de
/// `app/routers/logistica.py` (`/retornos/*`).
class RetornoService {
  final ApiClient _client;
  RetornoService(this._client);

  Future<ApiResult<T>> _run<T>(
    Future<http.Response> Function() send,
    T Function(http.Response r) onOk,
  ) async {
    try {
      final r = await send();
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return ApiResult.ok(onOk(r));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } on TimeoutException {
      return const ApiResult.fail(
          ApiError(ApiErrorKind.network, 'La conexión tardó demasiado.'));
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Sesión') || msg.contains('login')) {
        return const ApiResult.fail(ApiError(ApiErrorKind.auth));
      }
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // GET /retornos/check-servicio/{servicioId}
  Future<ApiResult<CheckRetornoServicio>> checkRetornoServicio(String servicioId) => _run(
        () => _client.get('/retornos/check-servicio/$servicioId'),
        (r) => CheckRetornoServicio.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
      );

  // GET /retornos/servicio/{servicioId}/items-pendientes
  Future<ApiResult<List<RetornoItemPendiente>>> getItemsPendientes(String servicioId) => _run(
        () => _client.get('/retornos/servicio/$servicioId/items-pendientes'),
        (r) {
          final m = jsonDecode(r.body) as Map<String, dynamic>;
          final list = (m['items'] as List?) ?? const [];
          return list
              .map((e) => RetornoItemPendiente.fromJson(e as Map<String, dynamic>))
              .toList();
        },
      );

  // POST /retornos/desde-servicio
  Future<ApiResult<void>> crearDesdeServicio({
    required String proyectoServicioId,
    required List<RetornoItemPendiente> items,
    String? notaTecnico,
  }) =>
      _run(
        () => _client.post('/retornos/desde-servicio', {
          'proyectoServicioId': proyectoServicioId,
          'items': items
              .map((it) => {
                    'detalleId': it.detalleId,
                    'cantidadRetornada': it.cantidadRetornada,
                  })
              .toList(),
          if (notaTecnico != null && notaTecnico.trim().isNotEmpty)
            'notaTecnico': notaTecnico.trim(),
        }),
        (r) {},
      );
}

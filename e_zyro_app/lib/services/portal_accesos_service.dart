import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/portal_acceso_models.dart';

/// Cliente del módulo "Accesos Portal Cliente" (`/portal-accesos`).
/// Solo Admin/SuperAdmin: el backend ya valida el rol; la app únicamente
/// decide la visibilidad del menú.
class PortalAccesosService {
  final ApiClient _client;
  PortalAccesosService(this._client);

  /// Ejecuta una petición y la traduce a [ApiResult], clasificando la causa
  /// del fallo (mismo criterio que IntervencionService._run).
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

  // GET /portal-accesos — todos los clientes activos, tengan o no acceso.
  Future<ApiResult<List<AccesoPortalCliente>>> getAccesos() => _run(
        () => _client.get('/portal-accesos'),
        (r) => ((jsonDecode(r.body) as List?) ?? [])
            .map((e) => AccesoPortalCliente.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // POST /portal-accesos — crea la cuenta de portal (409 si ya tiene acceso).
  Future<ApiResult<CredencialesPortal>> crearAcceso(String clienteId) => _run(
        () => _client.post('/portal-accesos', {'cliente_id': clienteId}),
        (r) => CredencialesPortal.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>),
      );

  // POST /portal-accesos/{clienteId}/reset-password — nueva contraseña
  // temporal; si el usuario estaba revocado, el backend lo reactiva.
  Future<ApiResult<CredencialesPortal>> resetPassword(String clienteId) => _run(
        () => _client.post('/portal-accesos/$clienteId/reset-password',
            const <String, dynamic>{}),
        (r) => CredencialesPortal.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>),
      );

  // DELETE /portal-accesos/{clienteId} — revoca el acceso (404 si no tiene).
  Future<ApiResult<String>> revocarAcceso(String clienteId) => _run(
        () => _client.delete('/portal-accesos/$clienteId'),
        (r) {
          try {
            final body = jsonDecode(r.body);
            if (body is Map) return body['username']?.toString() ?? '';
          } catch (_) {}
          return '';
        },
      );
}

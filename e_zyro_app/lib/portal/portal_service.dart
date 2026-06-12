import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/api_client.dart';
import '../core/api_result.dart';
import 'portal_models.dart';

/// Cliente del "Portal Empresa" (rol ClienteExterno): consume los endpoints
/// de solo lectura del backend bajo `/portal-cliente/*`. Mismo estilo que
/// IntervencionService (_run + ApiResult).
class PortalService {
  final ApiClient _client;
  PortalService(this._client);

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

  // GET /portal-cliente/dashboard → resumen (proyectos activos, completados
  // del mes y próximos mantenimientos).
  Future<ApiResult<PortalDashboard>> getDashboard() => _run(
        () => _client.get('/portal-cliente/dashboard'),
        (r) =>
            PortalDashboard.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
      );

  // GET /portal-cliente/dashboard/kpis → 4 indicadores numéricos.
  Future<ApiResult<PortalKpis>> getKpis() => _run(
        () => _client.get('/portal-cliente/dashboard/kpis'),
        (r) => PortalKpis.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
      );

  // GET /portal-cliente/proyectos → proyectos del cliente con avance.
  Future<ApiResult<List<PortalProyecto>>> getProyectos() => _run(
        () => _client.get('/portal-cliente/proyectos'),
        (r) => ((jsonDecode(r.body) as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PortalProyecto.fromJson)
            .toList(),
      );

  // GET /portal-cliente/proyecto/{id}/detalles → detalle completo
  // (servicios + cronograma + equipo + personal + equipos intervenidos).
  Future<ApiResult<PortalProyectoDetalle>> getProyectoDetalles(
          String proyectoId) =>
      _run(
        () => _client.get('/portal-cliente/proyecto/$proyectoId/detalles'),
        (r) => PortalProyectoDetalle.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>),
      );

  // GET /portal-cliente/documentos → documentos publicados al cliente.
  Future<ApiResult<List<PortalDocumento>>> getDocumentos() => _run(
        () => _client.get('/portal-cliente/documentos'),
        (r) => ((jsonDecode(r.body) as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PortalDocumento.fromJson)
            .toList(),
      );

  // GET /portal-cliente/equipos/historial → equipos del cliente con su
  // estado de intervención y próximos mantenimientos.
  Future<ApiResult<List<PortalEquipoHistorial>>> getEquiposHistorial() => _run(
        () => _client.get('/portal-cliente/equipos/historial'),
        (r) => ((jsonDecode(r.body) as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PortalEquipoHistorial.fromJson)
            .toList(),
      );

  // GET /portal-cliente/perfil → datos del usuario y su empresa.
  Future<ApiResult<PortalPerfil>> getPerfil() => _run(
        () => _client.get('/portal-cliente/perfil'),
        (r) =>
            PortalPerfil.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
      );
}

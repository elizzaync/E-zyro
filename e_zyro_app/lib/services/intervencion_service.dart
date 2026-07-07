import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/intervencion_models.dart';

/// Cliente del flujo "Equipos Intervenidos por servicio":
/// `/operaciones/servicio/{id}/equipos-intervenidos/*`, inspecciones
/// (`/operaciones/inspeccion/*`), informe general, carta de garantía y
/// certificados. Espejo del OperacionesService del frontend Angular.
///
/// NO confundir con EquipoIntervenidoService (dominio global
/// `/equipos-intervenidos/*` de mantenimiento por cliente).
class IntervencionService {
  final ApiClient _client;
  IntervencionService(this._client);

  /// Ejecuta una petición y la traduce a [ApiResult], clasificando la causa
  /// del fallo (mismo criterio que ProyectoService._run).
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

  // ── Equipos intervenidos del servicio ───────────────────────────────────────

  // GET /operaciones/servicio/{id}/equipos-intervenidos?ubicacion_id=&zona_id=
  Future<ApiResult<List<EquipoIntervenidoServicio>>> getEquiposIntervenidos(
    String servicioId, {
    String? ubicacionId,
    String? zonaId,
  }) {
    final params = <String, String>{};
    if (ubicacionId != null && ubicacionId.isNotEmpty) params['ubicacion_id'] = ubicacionId;
    if (zonaId != null && zonaId.isNotEmpty) params['zona_id'] = zonaId;
    final query = params.isEmpty ? '' : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    return _run(
      () => _client.get('/operaciones/servicio/$servicioId/equipos-intervenidos$query'),
      (r) => ((jsonDecode(r.body) as List?) ?? [])
          .map((e) => EquipoIntervenidoServicio.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // POST /operaciones/servicio/{id}/equipos-intervenidos
  // Crea un activo nuevo en el catálogo. Ubicación/zona/cliente NO se envían:
  // el backend las hereda de la sede del servicio (igual que el frontend).
  Future<ApiResult<EquipoIntervenidoServicio>> crearEquipo(
    String servicioId, {
    required String nombre,
    String? tipoEquipoId,
    String? ubicacionReferencia,
    String estado = 'operativo',
    String? descripcion,
    int frecuenciaMeses = 6,
  }) =>
      _run(
        () => _client.post(
            '/operaciones/servicio/$servicioId/equipos-intervenidos', {
          'nombre': nombre,
          'tipo_equipo_id':
              (tipoEquipoId?.isEmpty ?? true) ? null : tipoEquipoId,
          'ubicacion_referencia':
              (ubicacionReferencia?.isEmpty ?? true) ? null : ubicacionReferencia,
          'estado': estado,
          'descripcion': (descripcion?.isEmpty ?? true) ? null : descripcion,
          'frecuencia_meses': frecuenciaMeses,
        }),
        (r) => EquipoIntervenidoServicio.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>),
      );

  // PATCH /operaciones/servicio/{id}/equipos-intervenidos/{eiId}
  // Edición de la "Referencia" (vista del técnico) y campos libres.
  Future<ApiResult<Map<String, dynamic>>> actualizarEquipo(
          String servicioId, String eiId, Map<String, dynamic> body) =>
      _run(
        () => _client.patch(
            '/operaciones/servicio/$servicioId/equipos-intervenidos/$eiId',
            body),
        (r) => jsonDecode(r.body) as Map<String, dynamic>,
      );

  // GET /operaciones/servicio/{id}/equipos-intervenidos/{eiId}/detalle
  Future<ApiResult<EquipoInspeccionInfo>> getDetalleEquipo(
          String servicioId, String eiId) =>
      _run(
        () => _client.get(
            '/operaciones/servicio/$servicioId/equipos-intervenidos/$eiId/detalle'),
        (r) => EquipoInspeccionInfo.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>),
      );

  // GET /operaciones/servicio/{id}/equipos-intervenidos/{eiId}/historial
  Future<ApiResult<List<HistorialInspeccionItem>>> getHistorialEquipo(
          String servicioId, String eiId) =>
      _run(
        () => _client.get(
            '/operaciones/servicio/$servicioId/equipos-intervenidos/$eiId/historial'),
        (r) => ((jsonDecode(r.body) as List?) ?? [])
            .map((e) =>
                HistorialInspeccionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // POST /operaciones/servicio/{id}/equipos-intervenidos/{eiId}/completar
  Future<ApiResult<bool>> completarEquipo(String servicioId, String eiId) =>
      _run(
        () => _client.post(
            '/operaciones/servicio/$servicioId/equipos-intervenidos/$eiId/completar',
            const <String, dynamic>{}),
        (_) => true,
      );

  // ── Catálogos de apoyo ──────────────────────────────────────────────────────

  // GET /logistica/tipos-equipo (catálogo tipo_equipo, igual que el frontend)
  Future<List<CatalogoItemSimple>> getTiposEquipo() async {
    try {
      final r = await _client.get('/logistica/tipos-equipo');
      if (r.statusCode == 200) {
        final list = ((jsonDecode(r.body) as List?) ?? [])
            .map((e) => CatalogoItemSimple.fromJson(e as Map<String, dynamic>))
            .where((t) => t.id.isNotEmpty && t.nombre.isNotEmpty)
            .toList()
          ..sort((a, b) => a.nombre.compareTo(b.nombre));
        return list;
      }
    } catch (_) {}
    return [];
  }

  // GET /logistica/tipos-equipo/{id}/procedimientos — plantilla del checklist
  Future<ApiResult<List<Map<String, dynamic>>>> getProcedimientosTipoEquipo(
          String tipoId) =>
      _run(
        () => _client.get('/logistica/tipos-equipo/$tipoId/procedimientos'),
        (r) => ((jsonDecode(r.body) as Map<String, dynamic>)['procedimientos']
                    as List? ??
                [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

  // PATCH /logistica/tipos-equipo/{id}/procedimientos — reemplaza la plantilla
  Future<ApiResult<bool>> guardarProcedimientosTipoEquipo(
          String tipoId, List<Map<String, dynamic>> pasos) =>
      _run(
        () => _client.patch(
            '/logistica/tipos-equipo/$tipoId/procedimientos',
            {'procedimientos': pasos}),
        (_) => true,
      );

  // POST /logistica/tipos-equipo — crea (o devuelve) un tipo por nombre
  Future<ApiResult<CatalogoItemSimple>> crearTipoEquipo(String nombre) => _run(
        () => _client.post('/logistica/tipos-equipo', {'nombre': nombre}),
        (r) => CatalogoItemSimple.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>),
      );

  // GET /epp — catálogo de EPPs para el selector del informe
  Future<List<CatalogoItemSimple>> getEppCatalogo() async {
    try {
      final r = await _client.get('/epp');
      if (r.statusCode == 200) {
        return ((jsonDecode(r.body) as List?) ?? [])
            .map((e) => CatalogoItemSimple.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Inspección (sesión activa del equipo en el servicio) ────────────────────

  // GET /operaciones/servicio/{id}/equipos-intervenidos/{eiId}/inspeccion
  // El backend crea la sesión si no existe; si el equipo ya fue completado
  // bajo este servicio devuelve la última sesión en modo solo lectura.
  Future<ApiResult<InspeccionActiva>> getInspeccionActiva(
          String servicioId, String eiId) =>
      _run(
        () => _client.get(
            '/operaciones/servicio/$servicioId/equipos-intervenidos/$eiId/inspeccion'),
        (r) =>
            InspeccionActiva.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
      );

  // POST /operaciones/inspeccion/{id}/guardar
  // data = todos_completados (el backend lo calcula tras persistir).
  Future<ApiResult<bool>> guardarInspeccion(
    String inspeccionId, {
    required List<PasoInspeccion> pasos,
    String? observaciones,
  }) =>
      _run(
        () => _client.post('/operaciones/inspeccion/$inspeccionId/guardar', {
          'resultado': [
            for (final p in pasos) {'orden': p.orden, 'completado': p.completado},
          ],
          'observaciones':
              (observaciones?.trim().isEmpty ?? true) ? null : observaciones!.trim(),
        }),
        (r) =>
            (jsonDecode(r.body) as Map<String, dynamic>)['todos_completados'] ==
            true,
      );

  // POST /operaciones/inspeccion/{id}/finalizar
  Future<ApiResult<bool>> finalizarInspeccion(
    String inspeccionId, {
    required List<PasoInspeccion> pasos,
    String? observaciones,
    String? proximaFechaMantenimiento, // ISO YYYY-MM-DD
  }) =>
      _run(
        () => _client.post('/operaciones/inspeccion/$inspeccionId/finalizar', {
          'resultado': [
            for (final p in pasos) {'orden': p.orden, 'completado': p.completado},
          ],
          'observaciones':
              (observaciones?.trim().isEmpty ?? true) ? null : observaciones!.trim(),
          'proxima_fecha_mantenimiento':
              (proximaFechaMantenimiento?.isEmpty ?? true)
                  ? null
                  : proximaFechaMantenimiento,
        }),
        (_) => true,
      );

  // GET /operaciones/servicio/{id}/equipos-intervenidos/{eiId}/intervenciones-previas
  // Lista de intervenciones completadas del equipo para elegir el vínculo.
  Future<ApiResult<List<VinculoInspeccion>>> getIntervencionesPrevias(
          String servicioId, String eiId) =>
      _run(
        () => _client.get(
            '/operaciones/servicio/$servicioId/equipos-intervenidos/$eiId/intervenciones-previas'),
        (r) => (jsonDecode(r.body) as List)
            .map((e) => VinculoInspeccion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // POST /operaciones/inspeccion/{id}/vincular
  // Encadena (o desvincula) la inspección con una anterior del mismo equipo.
  // padreId == null → desvincula.
  Future<ApiResult<bool>> vincularInspeccion(
    String inspeccionId, {
    String? padreId,
  }) =>
      _run(
        () => _client.post('/operaciones/inspeccion/$inspeccionId/vincular', {
          'inspeccion_padre_id': padreId,
        }),
        (_) => true,
      );

  // POST /operaciones/inspeccion/{id}/foto/{orden}  (multipart, campo 'archivo')
  // Devuelve {url, public_id}; misma sesión + mismo paso = reemplaza la foto.
  Future<ApiResult<({String url, String? publicId})>> subirFotoInspeccion(
          String inspeccionId, int orden, String filePath) =>
      _run(
        () => _client.postMultipart(
          '/operaciones/inspeccion/$inspeccionId/foto/$orden',
          const {},
          'archivo',
          filePath,
        ),
        (r) {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          return (
            url: body['url'] as String? ?? '',
            publicId: body['public_id'] as String?,
          );
        },
      );

  // DELETE /operaciones/inspeccion/{id}/foto/{orden}
  Future<ApiResult<bool>> quitarFotoInspeccion(
          String inspeccionId, int orden) =>
      _run(
        () =>
            _client.delete('/operaciones/inspeccion/$inspeccionId/foto/$orden'),
        (_) => true,
      );

  // ── Documentos (blobs binarios) ─────────────────────────────────────────────

  // GET /operaciones/servicio/{id}/informe/precarga
  Future<ApiResult<PrecargaInforme>> getPrecargaInforme(String servicioId) =>
      _run(
        () => _client.get('/operaciones/servicio/$servicioId/informe/precarga'),
        (r) =>
            PrecargaInforme.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
      );

  // POST /operaciones/servicio/{id}/informe/generar → .docx (bytes)
  Future<ApiResult<Uint8List>> generarInformeGeneral(
          String servicioId, Map<String, dynamic> payload) =>
      _run(
        () => _client.post(
          '/operaciones/servicio/$servicioId/informe/generar',
          payload,
          timeout: const Duration(seconds: 120),
        ),
        (r) => r.bodyBytes,
      );

  // POST /operaciones/servicio/{id}/carta-garantia/generar → .docx (bytes)
  Future<ApiResult<Uint8List>> generarCartaGarantia(
          String servicioId, Map<String, dynamic> payload) =>
      _run(
        () => _client.post(
          '/operaciones/servicio/$servicioId/carta-garantia/generar',
          payload,
          timeout: const Duration(seconds: 120),
        ),
        (r) => r.bodyBytes,
      );

  // POST .../equipos-intervenidos/{eiId}/certificado/pozo → PDF (bytes)
  Future<ApiResult<Uint8List>> generarCertificadoPozo(
          String servicioId, String eiId, Map<String, dynamic> payload) =>
      _run(
        () => _client.post(
          '/operaciones/servicio/$servicioId/equipos-intervenidos/$eiId/certificado/pozo',
          payload,
          timeout: const Duration(seconds: 120),
        ),
        (r) => r.bodyBytes,
      );

  // POST .../equipos-intervenidos/{eiId}/certificado/operatividad → PDF (bytes)
  Future<ApiResult<Uint8List>> generarCertificadoOperatividad(
          String servicioId, String eiId, Map<String, dynamic> payload) =>
      _run(
        () => _client.post(
          '/operaciones/servicio/$servicioId/equipos-intervenidos/$eiId/certificado/operatividad',
          payload,
          timeout: const Duration(seconds: 120),
        ),
        (r) => r.bodyBytes,
      );

  // ── Dashboard de Operaciones ────────────────────────────────────────────────

  // GET /operaciones/dashboard → métricas + servicios del técnico
  Future<ApiResult<DashboardOperaciones>> getDashboard() => _run(
        () => _client.get('/operaciones/dashboard'),
        (r) => DashboardOperaciones.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>),
      );
}

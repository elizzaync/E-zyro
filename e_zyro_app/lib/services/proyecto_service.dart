import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../utils/json_async.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/accion_pendiente.dart';
import '../models/evidencia_pendiente.dart';
import '../models/proyecto_models.dart';
import '../models/recepcion_models.dart';
import '../repositories/accion_local_repo.dart';
import '../repositories/cache_repo.dart';
import '../repositories/evidencia_local_repo.dart';
import '../utils/app_notifiers.dart';

class ProyectoService {
  final ApiClient _client;
  final _cache = CacheRepo();
  final _evidenciaRepo = EvidenciaLocalRepo();
  final _accionRepo = AccionLocalRepo();
  ProyectoService(this._client);

  // ── Cola offline de acciones (toggle, firma, notas) ─────────────────────────

  /// Encola una acción para reintentarla al reconectar y actualiza el badge.
  Future<void> _enqueueAccion(
      String tipo, Map<String, dynamic> payload, String? servicioId) async {
    await _accionRepo.insertar(AccionPendiente(
      uuid: const Uuid().v4(),
      tipo: tipo,
      payload: payload,
      servicioId: servicioId,
    ));
    pendientesAccionNotifier.value = await _accionRepo.contarPendientes();
  }

  /// Ejecuta online; si falla por **red**, encola la acción y devuelve
  /// `enqueued` (se reintentará). Si falla por otra causa (403/409/…) NO
  /// encola y propaga el error real.
  Future<ApiResult<bool>> _runOrEnqueue(
    Future<http.Response> Function() send,
    String tipo,
    Map<String, dynamic> payload,
    String? servicioId,
  ) async {
    final res = await _run<bool>(send, (_) => true);
    if (res.ok) return res;
    if (res.error?.kind == ApiErrorKind.network) {
      await _enqueueAccion(tipo, payload, servicioId);
      return const ApiResult<bool>.enqueued();
    }
    return res;
  }

  Future<int> contarAccionesPendientes() => _accionRepo.contarPendientes();

  /// Drena la cola de acciones (FIFO). Éxito → elimina; fallo de red →
  /// reintentar luego; error permanente (4xx) → descarta para no atascar.
  Future<int> sincronizarAcciones() async {
    final pendientes = await _accionRepo.obtenerPendientes();
    int enviadas = 0;
    for (final a in pendientes) {
      await _accionRepo.marcarEnviando(a.uuid);
      final res = await _replayAccion(a);
      if (res.ok) {
        await _accionRepo.eliminar(a.uuid);
        enviadas++;
      } else if (res.error?.kind == ApiErrorKind.network) {
        await _accionRepo.registrarFallo(a.uuid);
      } else {
        await _accionRepo.eliminar(a.uuid); // permanente → descartar
      }
    }
    pendientesAccionNotifier.value = await _accionRepo.contarPendientes();
    return enviadas;
  }

  Future<ApiResult<bool>> _replayAccion(AccionPendiente a) {
    final p = a.payload;
    switch (a.tipo) {
      case TipoAccion.toggleProc:
        return _run(
            () => _client.patch('/operaciones/procedimiento/${p['procId']}/estado',
                {'estado': p['estado']}),
            (_) => true);
      case TipoAccion.firmarReq:
        return _run(
            () => _client.post('/logistica/requerimientos/${p['reqId']}/firmar',
                {'recibidoPorId': '', 'firmaUrl': p['firmaUrl']}),
            (_) => true);
      case TipoAccion.notaAdd:
        return _run(
            () => _client.post('/operaciones/servicio/${p['servicioId']}/nota',
                {'descripcion': p['descripcion']}),
            (_) => true);
      case TipoAccion.notaUpdate:
        return _run(
            () => _client
                .put('/operaciones/nota/${p['notaId']}', {'descripcion': p['descripcion']}),
            (_) => true);
      case TipoAccion.notaDelete:
        return _run(
            () => _client.delete('/operaciones/nota/${p['notaId']}'), (_) => true);
      default:
        return Future.value(
            const ApiResult<bool>.fail(ApiError(ApiErrorKind.unknown)));
    }
  }

  /// Ejecuta una petición y la traduce a [ApiResult], clasificando la causa del
  /// fallo (red, sesión, permiso, conflicto, servidor) en vez de tragar el error.
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
      // ApiClient lanza Exception('Sesión expirada…') en 401/sin token.
      final msg = e.toString();
      if (msg.contains('Sesión') || msg.contains('login')) {
        return const ApiResult.fail(ApiError(ApiErrorKind.auth));
      }
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // Claves de caché read-through (offline-first) para lecturas de operaciones.
  static const _kProyectos = 'op_proyectos';
  static String _kServicios(String pid) => 'op_servicios_$pid';
  static String _kDetalle(String sid) => 'op_detalle_$sid';

  // GET /operaciones/proyectos
  Future<ProyectosConKpis?> getProyectos() async {
    try {
      final r = await _client.get('/operaciones/proyectos');
      if (r.statusCode == 200) {
        await _cache.put(_kProyectos, r.body);
        return ProyectosConKpis.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    // Offline / error → caché.
    final cached = await _cache.get(_kProyectos);
    if (cached != null) {
      try {
        return ProyectosConKpis.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return null;
  }

  // GET /operaciones/proyecto/{proyecto_id}/servicios
  Future<List<ServicioItem>> getServiciosProyecto(String proyectoId) async {
    try {
      final r = await _client.get(
        '/operaciones/proyecto/$proyectoId/servicios',
      );
      if (r.statusCode == 200) {
        await _cache.put(_kServicios(proyectoId), r.body);
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => ServicioItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    final cached = await _cache.get(_kServicios(proyectoId));
    if (cached != null) {
      try {
        final list = jsonDecode(cached) as List? ?? [];
        return list
            .map((e) => ServicioItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  // GET /operaciones/servicio/{servicio_id}
  Future<ServicioDetalle?> getDetalleServicio(String servicioId) async {
    try {
      final r = await _client.get('/operaciones/servicio/$servicioId');
      if (r.statusCode == 200) {
        await _cache.put(_kDetalle(servicioId), r.body);
        return ServicioDetalle.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    final cached = await _cache.get(_kDetalle(servicioId));
    if (cached != null) {
      try {
        return ServicioDetalle.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return null;
  }

  // ── Mutaciones de operaciones ───────────────────────────────────────────────

  // PATCH /operaciones/servicio/{id}/estado
  // Surface del motivo (detail del backend): 403 (rol) o 409 (checklist).
  Future<ApiResult<bool>> cambiarEstadoServicio(
    String servicioId,
    String estado,
  ) =>
      _run(
        () => _client.patch(
            '/operaciones/servicio/$servicioId/estado', {'estado': estado}),
        (_) => true,
      );

  // PATCH /operaciones/procedimiento/{id}/estado  (encolable offline)
  Future<ApiResult<bool>> toggleProcedimiento(String procId, String estado,
          {String? servicioId}) =>
      _runOrEnqueue(
        () => _client.patch(
            '/operaciones/procedimiento/$procId/estado', {'estado': estado}),
        TipoAccion.toggleProc,
        {'procId': procId, 'estado': estado},
        servicioId,
      );

  // PATCH /operaciones/tarea/{id}/estado  (estado del cronograma; online)
  // No mueve el avance del servicio (eso lo controlan los procedimientos).
  Future<ApiResult<bool>> toggleTarea(String tareaId, String estado) => _run(
        () => _client.patch(
            '/operaciones/tarea/$tareaId/estado', {'estado': estado}),
        (_) => true,
      );

  // ── Plantillas de procedimientos (estándar por tipo de trabajo) ─────────────

  // GET /operaciones/plantillas-procedimiento
  Future<List<Map<String, dynamic>>> getPlantillas() async {
    try {
      final r = await _client.get('/operaciones/plantillas-procedimiento');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/plantillas-procedimiento/{tipo_trabajo}
  Future<Map<String, dynamic>?> getPlantilla(String tipoTrabajo) async {
    try {
      final r = await _client
          .get('/operaciones/plantillas-procedimiento/$tipoTrabajo');
      if (r.statusCode == 200) {
        return jsonDecode(r.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // PUT /operaciones/plantillas-procedimiento  (upsert por tipo_trabajo)
  // body: { tipo_trabajo, nombre, procesos: [{orden, nombre, descripcion}], activo }
  Future<bool> guardarPlantilla(Map<String, dynamic> body) async {
    try {
      final r =
          await _client.put('/operaciones/plantillas-procedimiento', body);
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // POST /operaciones/procedimiento/{id}/evidencia  (multipart)
  // etapa: 'antes' | 'durante' | 'despues'. Devuelve la URL subida o null.
  Future<String?> subirEvidencia(
    String procId,
    String etapa,
    String filePath, {
    String descripcion = '',
  }) async {
    try {
      final r = await _client.postMultipart(
        '/operaciones/procedimiento/$procId/evidencia',
        {
          'etapa': etapa,
          if (descripcion.isNotEmpty) 'descripcion': descripcion,
        },
        'archivo',
        filePath,
      );
      if (r.statusCode == 200 || r.statusCode == 201) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['url'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // ── Evidencias offline-first (cola local + subida diferida) ─────────────────

  static bool _isSyncingEvidencias = false;

  Future<int> contarEvidenciasPendientes() => _evidenciaRepo.contarPendientes();

  Future<int> contarEvidenciasAbandonadas() =>
      _evidenciaRepo.contarAbandonadas();

  /// Reinicia las evidencias abandonadas (5 reintentos) para reenviarlas.
  Future<int> resetEvidenciasParaReintentar() =>
      _evidenciaRepo.resetParaReintentar();

  /// Descarta (borra fila + archivo) las evidencias abandonadas irrecuperables.
  Future<int> descartarEvidenciasAbandonadas() async {
    final abandonadas = await _evidenciaRepo.obtenerAbandonadas();
    for (final e in abandonadas) {
      _borrarArchivo(e.fotoPath);
      await _evidenciaRepo.eliminar(e.uuid);
    }
    await _actualizarNotifierEvidencias();
    return abandonadas.length;
  }

  Future<void> _actualizarNotifierEvidencias() async {
    pendientesEvidenciaNotifier.value = await _evidenciaRepo.contarPendientes();
  }

  void _borrarArchivo(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Guarda la evidencia localmente y la intenta subir de inmediato.
  /// Devuelve true si se subió ya; false si quedó en cola para reenviar.
  Future<bool> encolarEvidencia({
    required String procedimientoId,
    String? servicioId,
    required String etapa,
    required String fotoPath,
    String descripcion = '',
  }) async {
    final uuid = const Uuid().v4();

    // Copiar la foto a un directorio estable (la de ImagePicker es temporal).
    String stablePath = fotoPath;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/evidence_photos');
      await dir.create(recursive: true);
      stablePath = '${dir.path}/$uuid.jpg';
      await File(fotoPath).copy(stablePath);
    } catch (_) {
      stablePath = fotoPath;
    }

    await _evidenciaRepo.insertarPendiente(
      EvidenciaPendiente(
        uuid: uuid,
        procedimientoId: procedimientoId,
        servicioId: servicioId,
        etapa: etapa,
        descripcion: descripcion.isEmpty ? null : descripcion,
        fotoPath: stablePath,
        createdAt: DateTime.now(),
      ),
    );
    await _actualizarNotifierEvidencias();

    // Intento inmediato de subida.
    final url = await subirEvidencia(
      procedimientoId,
      etapa,
      stablePath,
      descripcion: descripcion,
    );
    if (url != null) {
      await _evidenciaRepo.eliminar(uuid);
      _borrarArchivo(stablePath);
      await _actualizarNotifierEvidencias();
      return true;
    }
    return false;
  }

  /// Drena la cola de evidencias pendientes. Reintenta hasta 5 veces por
  /// evidencia; al subir borra la fila y su archivo local.
  Future<int> sincronizarEvidencias() async {
    if (_isSyncingEvidencias) return 0;
    _isSyncingEvidencias = true;
    try {
      final pendientes = await _evidenciaRepo.obtenerPendientes();
      int enviadas = 0;
      for (final e in pendientes) {
        if (e.retryCount >= 5) continue; // abandonada tras 5 intentos
        await _evidenciaRepo.marcarEnviando(e.uuid);

        // Si la foto ya no existe en disco, descartar para no reintentar infinito.
        if (!File(e.fotoPath).existsSync()) {
          debugPrint(
            '[ProyectoService] evidencia ${e.uuid} → foto perdida, descartada',
          );
          await _evidenciaRepo.eliminar(e.uuid);
          continue;
        }

        final url = await subirEvidencia(
          e.procedimientoId,
          e.etapa,
          e.fotoPath,
          descripcion: e.descripcion ?? '',
        );
        if (url != null) {
          await _evidenciaRepo.eliminar(e.uuid);
          _borrarArchivo(e.fotoPath);
          enviadas++;
        } else {
          await _evidenciaRepo.registrarFallo(e.uuid);
        }
      }
      await _actualizarNotifierEvidencias();
      return enviadas;
    } finally {
      _isSyncingEvidencias = false;
    }
  }

  // GET /operaciones/materiales/buscar?q=
  Future<List<MaterialBusqueda>> buscarMateriales(String q) async {
    if (q.trim().length < 2) return [];
    try {
      final r = await _client.get(
        '/operaciones/materiales/buscar?q=${Uri.encodeComponent(q.trim())}',
      );
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => MaterialBusqueda.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /logistica/equipos?q=&clase=todas&estado=operativo
  // Busca equipos/herramientas operativos del inventario para solicitarlos.
  Future<List<EquipoBusqueda>> buscarEquipos(String q) async {
    if (q.trim().length < 2) return [];
    try {
      final r = await _client.get(
        '/logistica/equipos?q=${Uri.encodeComponent(q.trim())}&estado=operativo&page_size=20',
      );
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        final list = body is Map ? (body['items'] as List? ?? []) : (body as List? ?? []);
        return list
            .map((e) => EquipoBusqueda.fromJson(e as Map<String, dynamic>))
            .where((e) => e.estado == 'operativo')
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/servicio/{id}/borrador
  Future<Borrador> getBorrador(String servicioId) async {
    try {
      final r = await _client.get('/operaciones/servicio/$servicioId/borrador');
      if (r.statusCode == 200) {
        return Borrador.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const Borrador(items: []);
  }

  // POST /operaciones/servicio/{id}/borrador/item → {detalle_id, requerimiento_id}
  // data = detalle_id del ítem creado.
  Future<ApiResult<String?>> agregarItemBorrador(
    String servicioId, {
    String? materialId,
    required String nombre,
    required String unidad,
    required int cantidad,
    String? especificacion,
    String tipo = 'material', // material | herramienta (texto libre)
  }) =>
      _run(
        () => _client.post('/operaciones/servicio/$servicioId/borrador/item', {
          'material_id': materialId,
          'nombre': nombre,
          'unidad': unidad,
          'cantidad': cantidad,
          'tipo': tipo,
          if (especificacion != null && especificacion.isNotEmpty)
            'especificacion': especificacion,
        }),
        (r) => (jsonDecode(r.body) as Map<String, dynamic>)['detalle_id']
            as String?,
      );

  // PATCH /operaciones/requerimiento-detalle/{id}
  Future<ApiResult<bool>> actualizarReqDetalle(
    String rdId, {
    int? cantidad,
    String? nombre,
    String? especificacion,
  }) =>
      _run(
        () => _client.patch('/operaciones/requerimiento-detalle/$rdId', {
          'cantidad': ?cantidad,
          'nombre': ?nombre,
          'especificacion': ?especificacion,
        }),
        (_) => true,
      );

  // DELETE /operaciones/borrador-detalle/{id}
  Future<ApiResult<bool>> removerItemBorrador(String rdId) => _run(
        () => _client.delete('/operaciones/borrador-detalle/$rdId'),
        (_) => true,
      );

  // POST /operaciones/servicio/{id}/borrador/enviar
  // [firmaSolicitanteUrl]: firma del solicitante al enviar el lote (data-url o URL nube).
  Future<ApiResult<bool>> enviarBorrador(String servicioId,
          {String? firmaSolicitanteUrl}) =>
      _run(
        () => _client.post('/operaciones/servicio/$servicioId/borrador/enviar', {
          'firma_solicitante_url': ?firmaSolicitanteUrl,
        }),
        (_) => true,
      );

  // ── Recepción de materiales (HU-16) — firma del técnico ─────────────────────

  /// Requerimientos del servicio que ya fueron aprobados/firmados por Logística.
  /// Se filtran a estado 'aprobado' (por firmar) o 'listo' (firmado) para
  /// mostrar el bloque de recepción en el detalle del servicio.
  // GET /logistica/requerimientos?estado=todos&servicio_id={id}
  Future<List<ReqRecepcion>> getRequerimientosServicio(String servicioId) async {
    try {
      final r = await _client.get(
        '/logistica/requerimientos?estado=todos&servicio_id=$servicioId',
      );
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        final list = body is Map ? (body['items'] as List? ?? []) : (body as List? ?? []);
        return list
            .map((e) => ReqRecepcion.fromJson(e as Map<String, dynamic>))
            .where((req) =>
                req.estado == 'comprando' ||
                req.estado == 'listo' ||
                req.estado == 'aprobado' ||
                req.estado == 'entregado')   // híbrido: mostrar el ciclo completo
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Firma la recepción de un requerimiento aprobado. [firmaUrl] puede ser una
  /// URL en la nube (firma guardada) o un data-url base64 de la firma dibujada.
  /// recibidoPorId vacío → el backend usa el empleado del usuario logueado.
  // POST /logistica/requerimientos/{id}/firmar  (encolable offline)
  Future<ApiResult<bool>> firmarRequerimiento(String reqId, String firmaUrl,
          {String? servicioId}) =>
      _runOrEnqueue(
        () => _client.post('/logistica/requerimientos/$reqId/firmar',
            {'recibidoPorId': '', 'firmaUrl': firmaUrl}),
        TipoAccion.firmarReq,
        {'reqId': reqId, 'firmaUrl': firmaUrl},
        servicioId,
      );

  /// Cinema-seat lock para firma — toma el "asiento" antes de abrir la sheet.
  /// Devuelve `(ok: true)` si pude bloquear; `(ok: false, error: 'firmando_por:Juan')`
  /// si otro técnico ya está firmando (con su nombre en el detail). El WS del
  /// servicio emite `requerimiento_actualizado` para que los demás dispositivos
  /// vean en vivo quién tomó el lock.
  // POST /logistica/requerimientos/{id}/bloquear-firma
  Future<({bool ok, String? error})> bloquearFirmaRequerimiento(String reqId) async {
    try {
      final r = await _client.post(
        '/logistica/requerimientos/$reqId/bloquear-firma',
        const <String, dynamic>{},
      );
      if (r.statusCode == 200) return (ok: true, error: null);
      try {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return (ok: false, error: body['detail'] as String?);
      } catch (_) {
        return (ok: false, error: null);
      }
    } catch (_) {
      return (ok: false, error: null);
    }
  }

  /// Libera el cinema-seat lock (cuando el técnico cancela la sheet o falla
  /// la firma). Best-effort: si falla la red, el timeout de 2 min del backend
  /// lo libera automáticamente.
  // DELETE /logistica/requerimientos/{id}/bloquear-firma
  Future<void> liberarFirmaRequerimiento(String reqId) async {
    try {
      await _client.delete('/logistica/requerimientos/$reqId/bloquear-firma');
    } catch (_) {
      // best-effort: el timeout de 2 min cubre el caso
    }
  }

  // ── Notas del servicio (CRUD) ───────────────────────────────────────────────

  // GET /operaciones/servicio/{id}/notas
  Future<List<NotaServicio>> getNotasServicio(String servicioId) async {
    try {
      final r = await _client.get('/operaciones/servicio/$servicioId/notas');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => NotaServicio.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // POST /operaciones/servicio/{id}/nota  (encolable offline)
  Future<ApiResult<bool>> agregarNota(String servicioId, String descripcion) =>
      _runOrEnqueue(
        () => _client.post(
            '/operaciones/servicio/$servicioId/nota', {'descripcion': descripcion}),
        TipoAccion.notaAdd,
        {'servicioId': servicioId, 'descripcion': descripcion},
        servicioId,
      );

  // PUT /operaciones/nota/{id}  (encolable offline)
  Future<ApiResult<bool>> actualizarNota(String notaId, String descripcion) =>
      _runOrEnqueue(
        () => _client.put('/operaciones/nota/$notaId', {'descripcion': descripcion}),
        TipoAccion.notaUpdate,
        {'notaId': notaId, 'descripcion': descripcion},
        null,
      );

  // DELETE /operaciones/nota/{id}  (encolable offline)
  Future<ApiResult<bool>> eliminarNota(String notaId) => _runOrEnqueue(
        () => _client.delete('/operaciones/nota/$notaId'),
        TipoAccion.notaDelete,
        {'notaId': notaId},
        null,
      );

  // ── Asignación de equipo + cronograma (HU-13) ───────────────────────────────

  // GET /operaciones/personal/tecnicos → { tecnicos:[...], grupos:[...] }
  Future<PersonalTecnicos> getPersonalTecnicos() async {
    try {
      final r = await _client.get('/operaciones/personal/tecnicos');
      if (r.statusCode == 200) {
        return PersonalTecnicos.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return const PersonalTecnicos(tecnicos: [], grupos: []);
  }

  // POST /operaciones/personal/validar-horario
  // Devuelve null si no hay conflicto (o error de red); un mensaje si lo hay.
  Future<ConflictoHorario?> validarHorario({
    required String empleadoId,
    required String fechaInicio,
    required String fechaFin,
    String? excluirServicioId,
  }) async {
    try {
      final r = await _client.post('/operaciones/personal/validar-horario', {
        'empleado_id': empleadoId,
        'fecha_inicio': fechaInicio,
        'fecha_fin': fechaFin,
        'excluir_servicio_id': ?excluirServicioId,
      });
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (body['conflicto'] == true && body['detalle'] != null) {
          return ConflictoHorario.fromJson(
            body['detalle'] as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  // POST /operaciones/servicio/{id}/configurar
  // procedimientos: [{ id?, nombre, responsable_id, fecha_inicio, fecha_fin }]
  // lider_id se omite a propósito: el backend lo deriva del usuario autenticado.
  Future<bool> configurarServicio(
    String servicioId, {
    required List<String> equipo,
    required List<Map<String, dynamic>> procedimientos,
  }) async {
    try {
      final r = await _client.post(
        '/operaciones/servicio/$servicioId/configurar',
        {'equipo': equipo, 'procedimientos': procedimientos},
      );
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ── Catálogos de soporte (crear/editar) ─────────────────────────────────────

  // GET /operaciones/clientes
  Future<List<ClienteBasico>> getClientes() async {
    try {
      final r = await _client.get('/operaciones/clientes');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => ClienteBasico.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/catalogo-servicios
  Future<List<CatalogoServicio>> getCatalogoServicios() async {
    try {
      final r = await _client.get('/operaciones/catalogo-servicios');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => CatalogoServicio.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/lideres-servicio
  Future<List<PersonaServicio>> getLideresServicio() async {
    return _getPersonas('/operaciones/lideres-servicio');
  }

  // GET /operaciones/responsables-servicio
  Future<List<PersonaServicio>> getResponsablesServicio() async {
    return _getPersonas('/operaciones/responsables-servicio');
  }

  Future<List<PersonaServicio>> _getPersonas(String path) async {
    try {
      final r = await _client.get(path);
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => PersonaServicio.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/proyectos/siguiente-orden → { orden_trabajo }
  Future<String?> getSiguienteOrden() async {
    try {
      final r = await _client.get('/operaciones/proyectos/siguiente-orden');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['orden_trabajo'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // GET /operaciones/proyecto/{id}  (datos para editar)
  Future<ProyectoEdit?> getDetalleProyecto(String proyectoId) async {
    try {
      final r = await _client.get('/operaciones/proyecto/$proyectoId');
      if (r.statusCode == 200) {
        return ProyectoEdit.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return null;
  }

  // ── CRUD Proyecto ───────────────────────────────────────────────────────────

  // POST /operaciones/proyectos → { ok, id, orden_trabajo }
  Future<String?> crearProyecto(Map<String, dynamic> payload) async {
    try {
      final r = await _client.post('/operaciones/proyectos', payload);
      if (r.statusCode == 200 || r.statusCode == 201) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // PATCH /operaciones/proyecto/{id}
  Future<bool> actualizarProyecto(
    String proyectoId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final r = await _client.patch(
        '/operaciones/proyecto/$proyectoId',
        payload,
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── CRUD Servicio ─────────────────────────────────────────────────────────

  // POST /operaciones/proyecto/{id}/servicios → { ok, id }
  Future<String?> crearServicio(
    String proyectoId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final r = await _client.post(
        '/operaciones/proyecto/$proyectoId/servicios',
        payload,
      );
      if (r.statusCode == 200 || r.statusCode == 201) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // PATCH /operaciones/servicio/{id}
  Future<bool> actualizarServicio(
    String servicioId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final r = await _client.patch(
        '/operaciones/servicio/$servicioId',
        payload,
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Legacy: usado por el dashboard
  Future<List<ProyectoServicio>> getMisServicios() async {
    try {
      final r = await _client.get('/proyectos/mis-servicios');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final list = data is Map
            ? (data['servicios'] as List? ?? [])
            : (data as List? ?? []);
        return list
            .map((e) => ProyectoServicio.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/api_client.dart';
import '../models/evidencia_pendiente.dart';
import '../models/proyecto_models.dart';
import '../repositories/cache_repo.dart';
import '../repositories/evidencia_local_repo.dart';
import '../utils/app_notifiers.dart';

class ProyectoService {
  final ApiClient _client;
  final _cache = CacheRepo();
  final _evidenciaRepo = EvidenciaLocalRepo();
  ProyectoService(this._client);

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
            jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    // Offline / error → caché.
    final cached = await _cache.get(_kProyectos);
    if (cached != null) {
      try {
        return ProyectosConKpis.fromJson(
            jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {}
    }
    return null;
  }

  // GET /operaciones/proyecto/{proyecto_id}/servicios
  Future<List<ServicioItem>> getServiciosProyecto(String proyectoId) async {
    try {
      final r = await _client.get('/operaciones/proyecto/$proyectoId/servicios');
      if (r.statusCode == 200) {
        await _cache.put(_kServicios(proyectoId), r.body);
        final list = jsonDecode(r.body) as List? ?? [];
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
            jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    final cached = await _cache.get(_kDetalle(servicioId));
    if (cached != null) {
      try {
        return ServicioDetalle.fromJson(
            jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {}
    }
    return null;
  }

  // ── Mutaciones de operaciones ───────────────────────────────────────────────

  // PATCH /operaciones/servicio/{id}/estado
  Future<bool> cambiarEstadoServicio(String servicioId, String estado) async {
    try {
      final r = await _client
          .patch('/operaciones/servicio/$servicioId/estado', {'estado': estado});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // PATCH /operaciones/procedimiento/{id}/estado
  Future<bool> toggleProcedimiento(String procId, String estado) async {
    try {
      final r = await _client
          .patch('/operaciones/procedimiento/$procId/estado', {'estado': estado});
      return r.statusCode == 200;
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
        {'etapa': etapa, if (descripcion.isNotEmpty) 'descripcion': descripcion},
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

  Future<int> contarEvidenciasPendientes() =>
      _evidenciaRepo.contarPendientes();

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

    await _evidenciaRepo.insertarPendiente(EvidenciaPendiente(
      uuid: uuid,
      procedimientoId: procedimientoId,
      servicioId: servicioId,
      etapa: etapa,
      descripcion: descripcion.isEmpty ? null : descripcion,
      fotoPath: stablePath,
      createdAt: DateTime.now(),
    ));
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
          debugPrint('[ProyectoService] evidencia ${e.uuid} → foto perdida, descartada');
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
      final r = await _client
          .get('/operaciones/materiales/buscar?q=${Uri.encodeComponent(q.trim())}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => MaterialBusqueda.fromJson(e as Map<String, dynamic>))
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
  Future<String?> agregarItemBorrador(
    String servicioId, {
    String? materialId,
    required String nombre,
    required String unidad,
    required int cantidad,
    String? especificacion,
  }) async {
    try {
      final r = await _client.post(
        '/operaciones/servicio/$servicioId/borrador/item',
        {
          'material_id': materialId,
          'nombre': nombre,
          'unidad': unidad,
          'cantidad': cantidad,
          if (especificacion != null && especificacion.isNotEmpty)
            'especificacion': especificacion,
        },
      );
      if (r.statusCode == 200 || r.statusCode == 201) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['detalle_id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // PATCH /operaciones/requerimiento-detalle/{id}
  Future<bool> actualizarReqDetalle(
    String rdId, {
    int? cantidad,
    String? nombre,
    String? especificacion,
  }) async {
    try {
      final body = <String, dynamic>{
        if (cantidad != null) 'cantidad': cantidad,
        if (nombre != null) 'nombre': nombre,
        if (especificacion != null) 'especificacion': especificacion,
      };
      final r =
          await _client.patch('/operaciones/requerimiento-detalle/$rdId', body);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // DELETE /operaciones/borrador-detalle/{id}
  Future<bool> removerItemBorrador(String rdId) async {
    try {
      final r = await _client.delete('/operaciones/borrador-detalle/$rdId');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // POST /operaciones/servicio/{id}/borrador/enviar
  Future<bool> enviarBorrador(String servicioId) async {
    try {
      final r =
          await _client.post('/operaciones/servicio/$servicioId/borrador/enviar', {});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Asignación de equipo + cronograma (HU-13) ───────────────────────────────

  // GET /operaciones/personal/tecnicos → { tecnicos:[...], grupos:[...] }
  Future<PersonalTecnicos> getPersonalTecnicos() async {
    try {
      final r = await _client.get('/operaciones/personal/tecnicos');
      if (r.statusCode == 200) {
        return PersonalTecnicos.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
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
        if (excluirServicioId != null) 'excluir_servicio_id': excluirServicioId,
      });
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (body['conflicto'] == true && body['detalle'] != null) {
          return ConflictoHorario.fromJson(
              body['detalle'] as Map<String, dynamic>);
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
        final list = jsonDecode(r.body) as List? ?? [];
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
        final list = jsonDecode(r.body) as List? ?? [];
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
        final list = jsonDecode(r.body) as List? ?? [];
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
            jsonDecode(r.body) as Map<String, dynamic>);
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
      String proyectoId, Map<String, dynamic> payload) async {
    try {
      final r =
          await _client.patch('/operaciones/proyecto/$proyectoId', payload);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── CRUD Servicio ─────────────────────────────────────────────────────────

  // POST /operaciones/proyecto/{id}/servicios → { ok, id }
  Future<String?> crearServicio(
      String proyectoId, Map<String, dynamic> payload) async {
    try {
      final r = await _client.post(
          '/operaciones/proyecto/$proyectoId/servicios', payload);
      if (r.statusCode == 200 || r.statusCode == 201) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // PATCH /operaciones/servicio/{id}
  Future<bool> actualizarServicio(
      String servicioId, Map<String, dynamic> payload) async {
    try {
      final r =
          await _client.patch('/operaciones/servicio/$servicioId', payload);
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

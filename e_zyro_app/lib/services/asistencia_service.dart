import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/api_client.dart';
import '../core/app_constants.dart';
import '../core/sync_logger.dart';
import '../core/trusted_clock.dart';
import '../models/asistencia_models.dart';
import '../models/control_asistencia_models.dart';
import '../models/registro_asistencia_local.dart';
import '../repositories/asistencia_local_repo.dart';
import '../utils/app_notifiers.dart';

String _fileToBase64(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  return base64Encode(bytes);
}

class AsistenciaService {
  final ApiClient _client;
  final _repo = AsistenciaLocalRepo();

  AsistenciaService(this._client);

  /// Guard global: evita que dos llamadas concurrentes a sincronizarPendientes
  /// procesen el mismo registro dos veces.
  static bool _isSyncing = false;

  // Claves de caché local (offline-first) para el estado de asistencia.
  static const _estadoCacheKey   = 'asistencia_estado_cache';
  static const _fotoBaseCacheKey = 'asistencia_foto_base_cache';

  // Claves de caché que deben limpiarse al cerrar sesión.
  static const List<String> cacheKeys = [_estadoCacheKey, _fotoBaseCacheKey];

  // ── Conectividad al servidor ──────────────────────────────────────────────

  /// Verifica que el servidor de Railway es alcanzable usando HTTP crudo
  /// SIN token de autenticación. Cualquier respuesta HTTP (incluyendo 401)
  /// indica que el servidor está UP — solo las excepciones de red indican DOWN.
  ///
  /// IMPORTANTE: NO usa ApiClient para evitar que una sesión vencida sea
  /// interpretada erróneamente como "servidor caído".
  Future<bool> canReachServer() async {
    final client = http.Client();
    try {
      // GET a la raíz del servidor sin Authorization header.
      // Respuestas esperadas: 404 / 422 / 200 (según qué tenga el backend en /).
      // Todas son válidas — significan que el servidor responde.
      await client
          .get(Uri.parse(AppConstants.baseUrl))
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      // Solo falla si no hay ruta de red, timeout TCP, o DNS falla.
      debugPrint('[AsistenciaService] canReachServer → sin respuesta: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Actualiza el notifier global con el conteo real de pendientes.
  Future<void> _actualizarNotifier() async {
    pendientesAsistenciaNotifier.value = await _repo.contarPendientes();
  }

  // ── Foto biométrica base ──────────────────────────────────────────────────

  Future<bool> tieneFotoBase() async {
    try {
      final r = await _client.get('/asistencia/tiene-foto-base');
      if (r.statusCode == 200) {
        final v = (jsonDecode(r.body)['tiene_foto_base'] as bool?) ?? false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_fotoBaseCacheKey, v);
        return v;
      }
    } catch (_) {}
    // Offline / error → último valor conocido (la foto base persiste).
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_fotoBaseCacheKey) ?? false;
  }

  Future<void> subirFotoBase(File foto) async {
    final b64 = await compute(_fileToBase64, foto.path);
    final r = await _client.post('/asistencia/foto-base', {
      'imagen_base': b64,
    }, timeout: AppConstants.uploadTimeout);
    _client.checkResponse(r, fallback: 'Error al subir foto biométrica');
  }

  // ── Marcar asistencia (offline-first) ─────────────────────────────────────

  Future<MarcarResponse> marcar({
    required File selfieFile,
    required String tipo,
    double? latitud,
    double? longitud,
    double? precisionM,
    double? altitud,
  }) async {
    final clientUuid = const Uuid().v4();

    // Intentar sincronizar NTP antes de capturar la hora (si hay red).
    await TrustedClock.sync().timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );

    final trustedTs = TrustedClock.now();
    final ahora = trustedTs.time;

    // 1a. Copiar selfie a directorio estable
    String? stablePath;
    try {
      final appDir   = await getApplicationDocumentsDirectory();
      final selfieDir = Directory('${appDir.path}/attendance_selfies');
      await selfieDir.create(recursive: true);
      stablePath = '${selfieDir.path}/$clientUuid.jpg';
      await selfieFile.copy(stablePath);
    } catch (_) {
      stablePath = selfieFile.path;
    }

    // 1b. Guardar localmente PRIMERO antes de intentar la red
    await _repo.insertarPendiente(RegistroAsistenciaLocal(
      uuid: clientUuid,
      timestampDispositivo: ahora,
      latitud: latitud ?? 0,
      longitud: longitud ?? 0,
      tipoMarcacion: tipo.toLowerCase(),
      evidenciaPath: stablePath,
      fuenteTiempo: trustedTs.etiqueta,
    ));
    await _actualizarNotifier();
    await _aplicarMarcaLocalAlCache(tipo, ahora);

    // 2. Intentar enviar de inmediato
    late http.Response resp;
    try {
      final b64 = await compute(_fileToBase64, selfieFile.path);

      final body = <String, dynamic>{
        'imagen_selfie': b64,
        'tipo':          tipo.toLowerCase(),
        'uuid_cliente':  clientUuid,
        'timestamp':     ahora.toIso8601String(),
        'fuente_tiempo': trustedTs.etiqueta,
      };
      if (latitud    != null) body['latitud']     = latitud;
      if (longitud   != null) body['longitud']    = longitud;
      if (precisionM != null) body['precision_m'] = precisionM;
      if (altitud    != null) body['altitud']     = altitud;

      resp = await _client.post(
        '/asistencia/marcar',
        body,
        timeout: AppConstants.uploadTimeout,
      );
    } catch (e) {
      // Error de red / timeout / sesión → dejar en cola para reintento
      final isSession = _isSessionError(e.toString());
      await SyncLogger.log(SyncLogEntry(
        id:            SyncLogger.newId(),
        timestamp:     DateTime.now(),
        uuid:          clientUuid,
        tipoMarcacion: tipo.toLowerCase(),
        status:        isSession ? SyncLogStatus.sesionVencida : SyncLogStatus.falloRed,
        errorMessage:  _cleanError(e.toString()),
      ));
      if (isSession) sessionExpiredSyncNotifier.value++;
      return MarcarResponse(
        registroId:  clientUuid,
        status:      'PENDIENTE_SYNC',
        score:       0,
        motivo:      'Asistencia guardada localmente. Se enviará al servidor cuando recuperes conexión.',
        timestamp:   ahora,
        gpsGuardado: latitud != null,
        fotoUrl:     null,
        resultadoIa: 'pendiente',
      );
    }

    // Obtuvimos respuesta HTTP — manejar por código de estado
    if (resp.statusCode == 200) {
      // 3. Éxito — marcar como enviado
      await _repo.marcarEnviado(clientUuid);
      await _actualizarNotifier();
      await SyncLogger.log(SyncLogEntry(
        id:            SyncLogger.newId(),
        timestamp:     DateTime.now(),
        uuid:          clientUuid,
        tipoMarcacion: tipo.toLowerCase(),
        status:        SyncLogStatus.enviado,
        httpCode:      200,
      ));
      return MarcarResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }

    final serverMsg = _extractServerMessage(resp.body);

    if (resp.statusCode >= 400 && resp.statusCode < 500) {
      // Rechazo permanente del servidor (ej. 422 sin rostro detectado).
      // No tiene sentido reintentar — marcar y lanzar para que la UI lo informe.
      await _repo.marcarErrorPermanente(clientUuid);
      await _actualizarNotifier();
      await SyncLogger.log(SyncLogEntry(
        id:            SyncLogger.newId(),
        timestamp:     DateTime.now(),
        uuid:          clientUuid,
        tipoMarcacion: tipo.toLowerCase(),
        status:        SyncLogStatus.falloServidor,
        httpCode:      resp.statusCode,
        errorMessage:  '⛔ ${serverMsg.isNotEmpty ? serverMsg : "HTTP ${resp.statusCode}"}',
      ));
      throw Exception(serverMsg.isNotEmpty
          ? serverMsg
          : 'Registro rechazado por el servidor (${resp.statusCode})');
    }

    // 5xx — error transitorio del servidor, dejar en cola para reintento
    debugPrint('[AsistenciaService] uuid=${clientUuid.substring(0, 8)} → HTTP ${resp.statusCode}, dejando pendiente');
    await SyncLogger.log(SyncLogEntry(
      id:            SyncLogger.newId(),
      timestamp:     DateTime.now(),
      uuid:          clientUuid,
      tipoMarcacion: tipo.toLowerCase(),
      status:        SyncLogStatus.falloServidor,
      httpCode:      resp.statusCode,
      errorMessage:  serverMsg.isNotEmpty ? serverMsg : 'Error del servidor (${resp.statusCode})',
    ));
    return MarcarResponse(
      registroId:  clientUuid,
      status:      'ERROR_SERVIDOR',
      score:       0,
      motivo:      'El servidor tuvo un error interno. Tu asistencia está guardada y se reenviará automáticamente.',
      timestamp:   ahora,
      gpsGuardado: latitud != null,
      fotoUrl:     null,
      resultadoIa: 'pendiente',
    );
  }

  // ── Marcar almuerzo (offline-first, SIN selfie — v1 PYME) ─────────────────

  /// Marca inicio/fin de almuerzo con solo GPS + hora (sin biometría).
  /// `tipo` debe ser 'entrada_almuerzo' o 'salida_almuerzo'.
  /// Reutiliza la misma cola offline e idempotencia que [marcar].
  Future<MarcarResponse> marcarAlmuerzo({
    required String tipo,
    double? latitud,
    double? longitud,
    double? precisionM,
    double? altitud,
  }) async {
    final clientUuid = const Uuid().v4();
    await TrustedClock.sync().timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
    final trustedTs = TrustedClock.now();
    final ahora = trustedTs.time;
    final t = tipo.toLowerCase();

    // 1. Guardar localmente PRIMERO (evidenciaPath null: el almuerzo no usa selfie).
    await _repo.insertarPendiente(RegistroAsistenciaLocal(
      uuid: clientUuid,
      timestampDispositivo: ahora,
      latitud: latitud ?? 0,
      longitud: longitud ?? 0,
      tipoMarcacion: t,
      evidenciaPath: null,
      fuenteTiempo: trustedTs.etiqueta,
    ));
    await _actualizarNotifier();
    await _aplicarMarcaLocalAlCache(t, ahora);

    // 2. Intentar enviar de inmediato (sin imagen_selfie).
    late http.Response resp;
    try {
      final body = <String, dynamic>{
        'tipo':          t,
        'uuid_cliente':  clientUuid,
        'timestamp':     ahora.toIso8601String(),
        'fuente_tiempo': trustedTs.etiqueta,
      };
      if (latitud    != null) body['latitud']     = latitud;
      if (longitud   != null) body['longitud']    = longitud;
      if (precisionM != null) body['precision_m'] = precisionM;
      if (altitud    != null) body['altitud']     = altitud;

      resp = await _client.post('/asistencia/marcar', body,
          timeout: AppConstants.uploadTimeout);
    } catch (e) {
      final isSession = _isSessionError(e.toString());
      if (isSession) sessionExpiredSyncNotifier.value++;
      return MarcarResponse(
        registroId: clientUuid,
        status: 'PENDIENTE_SYNC',
        score: 0,
        motivo: 'Almuerzo guardado localmente. Se enviará al reconectar.',
        timestamp: ahora,
        gpsGuardado: latitud != null,
        fotoUrl: null,
        resultadoIa: 'pendiente',
      );
    }

    if (resp.statusCode == 200) {
      await _repo.marcarEnviado(clientUuid);
      await _actualizarNotifier();
      return MarcarResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }

    final serverMsg = _extractServerMessage(resp.body);
    if (resp.statusCode >= 400 && resp.statusCode < 500) {
      // Rechazo permanente (ej. regla de negocio: "ya almorzaste hoy").
      // Revertir el cache local optimista y descartar el registro pendiente.
      await _repo.marcarErrorPermanente(clientUuid);
      await _revertirMarcaAlmuerzoCache(t);
      await _actualizarNotifier();
      throw Exception(serverMsg.isNotEmpty
          ? serverMsg
          : 'Registro de almuerzo rechazado (${resp.statusCode})');
    }

    // 5xx — queda en cola para reintento.
    return MarcarResponse(
      registroId: clientUuid,
      status: 'ERROR_SERVIDOR',
      score: 0,
      motivo: 'El servidor tuvo un error. Tu almuerzo se reenviará automáticamente.',
      timestamp: ahora,
      gpsGuardado: latitud != null,
      fotoUrl: null,
      resultadoIa: 'pendiente',
    );
  }

  // ── Sincronización manual de pendientes ───────────────────────────────────

  Future<int> sincronizarPendientes() async {
    if (_isSyncing) {
      debugPrint('[AsistenciaService] sincronizarPendientes → ya en progreso, omitiendo');
      return 0;
    }
    _isSyncing = true;
    try {
      return await _sincronizarInterno();
    } finally {
      _isSyncing = false;
    }
  }

  Future<int> _sincronizarInterno() async {
    final pendientes = await _repo.obtenerPendientes();
    if (pendientes.isEmpty) {
      debugPrint('[AsistenciaService] _sincronizarInterno → sin pendientes');
      return 0;
    }

    debugPrint('[AsistenciaService] _sincronizarInterno → procesando ${pendientes.length} registros');
    int enviados = 0;

    for (final r in pendientes) {
      if (r.retryCount >= 5) {
        debugPrint('[AsistenciaService] uuid=${r.uuid.substring(0, 8)} → abandonado (5 reintentos)');
        continue;
      }

      debugPrint(
        '[AsistenciaService] Intentando enviar ${r.tipoMarcacion.toUpperCase()} '
        'uuid=${r.uuid.substring(0, 8)} retry=${r.retryCount}',
      );

      await _repo.marcarEnviando(r.uuid);

      // Log de inicio del intento
      await SyncLogger.log(SyncLogEntry(
        id:            SyncLogger.newId(),
        timestamp:     DateTime.now(),
        uuid:          r.uuid,
        tipoMarcacion: r.tipoMarcacion,
        status:        SyncLogStatus.iniciando,
        errorMessage:  'retry #${r.retryCount + 1}',
      ));

      try {
        final evidenciaExiste = r.evidenciaPath != null &&
            File(r.evidenciaPath!).existsSync();

        final body = <String, dynamic>{
          'tipo':          r.tipoMarcacion,
          'uuid_cliente':  r.uuid,
          'timestamp':     r.timestampDispositivo.toIso8601String(),
          'fuente_tiempo': r.fuenteTiempo,
          if (r.latitud  != 0) 'latitud':  r.latitud,
          if (r.longitud != 0) 'longitud': r.longitud,
        };

        // El almuerzo (v1 PYME) se marca sin selfie por diseño: se envía solo
        // GPS + hora y el backend lo aprueba por JWT+GPS. Para entrada/salida,
        // la ausencia de selfie sí es evidencia perdida → error permanente.
        final esAlmuerzo = r.tipoMarcacion == 'entrada_almuerzo' ||
            r.tipoMarcacion == 'salida_almuerzo';

        if (evidenciaExiste) {
          // Comprimir antes de codificar para reducir payload (fix 500 por imagen grande).
          final tmpDir  = await getTemporaryDirectory();
          final tmpPath = '${tmpDir.path}/sync_${r.uuid.substring(0, 8)}.jpg';
          final compressed = await FlutterImageCompress.compressAndGetFile(
            r.evidenciaPath!, tmpPath,
            quality: 85, minWidth: 800, minHeight: 600,
          );
          final encPath = compressed?.path ?? r.evidenciaPath!;
          body['imagen_selfie'] = await compute(_fileToBase64, encPath);
          try { if (compressed != null) File(tmpPath).deleteSync(); } catch (_) {}
        } else if (esAlmuerzo) {
          // Sin selfie por diseño: no agregar imagen_selfie (el backend lo aprueba
          // por JWT+GPS). No descartar.
          debugPrint('[AsistenciaService] uuid=${r.uuid.substring(0, 8)} → almuerzo sin selfie, enviando GPS+hora');
        } else {
          // Sin imagen en disco → marcar como error permanente y saltar.
          // Enviar imagen_selfie vacía causa 500 en el backend.
          debugPrint('[AsistenciaService] uuid=${r.uuid.substring(0, 8)} → selfie no encontrada, descartando');
          await _repo.marcarErrorPermanente(r.uuid);
          await SyncLogger.log(SyncLogEntry(
            id:            SyncLogger.newId(),
            timestamp:     DateTime.now(),
            uuid:          r.uuid,
            tipoMarcacion: r.tipoMarcacion,
            status:        SyncLogStatus.falloServidor,
            errorMessage:  '⛔ Selfie eliminada del disco — registro descartado',
          ));
          continue;
        }

        final resp = await _client.post(
          '/asistencia/marcar',
          body,
          timeout: AppConstants.uploadTimeout,
        );

        debugPrint(
          '[AsistenciaService] uuid=${r.uuid.substring(0, 8)} → HTTP ${resp.statusCode}',
        );

        if (resp.statusCode == 200) {
          await _repo.marcarEnviado(r.uuid);
          enviados++;
          await SyncLogger.log(SyncLogEntry(
            id:            SyncLogger.newId(),
            timestamp:     DateTime.now(),
            uuid:          r.uuid,
            tipoMarcacion: r.tipoMarcacion,
            status:        SyncLogStatus.enviado,
            httpCode:      200,
          ));
        } else {
          final serverMsg = _extractServerMessage(resp.body);
          final code      = resp.statusCode;

          // 4xx (excepto 401 que se captura como excepción): error permanente.
          // Reintentar es inútil — el servidor rechaza estos datos definitivamente.
          final esPermanente = code >= 400 && code < 500;

          debugPrint(
            '[AsistenciaService] uuid=${r.uuid.substring(0, 8)} → '
            '${esPermanente ? "ERROR PERMANENTE" : "fallo"} HTTP $code: $serverMsg',
          );

          if (esPermanente) {
            await _repo.marcarErrorPermanente(r.uuid);
          } else {
            await _repo.registrarFallo(r.uuid);
          }

          await SyncLogger.log(SyncLogEntry(
            id:            SyncLogger.newId(),
            timestamp:     DateTime.now(),
            uuid:          r.uuid,
            tipoMarcacion: r.tipoMarcacion,
            status:        SyncLogStatus.falloServidor,
            httpCode:      code,
            errorMessage:  '${esPermanente ? "⛔ Error permanente: " : ""}'
                           '${serverMsg.isNotEmpty ? serverMsg : "HTTP $code"}',
          ));
        }
      } catch (e) {
        final errStr     = e.toString();
        final isSession  = _isSessionError(errStr);
        final logStatus  = isSession
            ? SyncLogStatus.sesionVencida
            : SyncLogStatus.falloRed;

        debugPrint(
          '[AsistenciaService] uuid=${r.uuid.substring(0, 8)} → '
          'excepción (${isSession ? "SESIÓN VENCIDA" : "RED/OTRO"}): $errStr',
        );

        await _repo.registrarFallo(r.uuid);
        await SyncLogger.log(SyncLogEntry(
          id:            SyncLogger.newId(),
          timestamp:     DateTime.now(),
          uuid:          r.uuid,
          tipoMarcacion: r.tipoMarcacion,
          status:        logStatus,
          errorMessage:  _cleanError(errStr),
        ));

        if (isSession) {
          // Notificar a la UI que la sesión venció — no hay caso de reintentar
          // los registros siguientes con el mismo token inválido.
          debugPrint('[AsistenciaService] ⚠ SESIÓN VENCIDA detectada → deteniendo sync');
          sessionExpiredSyncNotifier.value++;
          break;
        }
        // Para errores de red continuamos con el siguiente registro
      }
    }

    await _repo.limpiarEnviados();
    await _actualizarNotifier();
    debugPrint('[AsistenciaService] _sincronizarInterno → $enviados enviados');
    return enviados;
  }

  Future<int> contarPendientes() => _repo.contarPendientes();

  Future<int> contarAbandonados()        => _repo.contarAbandonados();
  Future<int> contarErroresPermanentes() => _repo.contarErroresPermanentes();

  /// Resetea los registros abandonados por errores transitorios (red, 5xx)
  /// para que puedan reintentarse. NO afecta errores permanentes (4xx).
  Future<int> resetParaReintentar() => _repo.resetParaReintentar();

  /// Resetea los registros con error permanente (4xx) a pendientes para
  /// reintentarlos. Úsalo cuando la causa del rechazo (p. ej. un bug del
  /// backend) ya fue corregida.
  Future<int> resetErroresPermanentes() => _repo.resetErroresPermanentes();

  /// Descarta (borra) registros con error permanente del servidor (4xx).
  /// Úsalo cuando el usuario acepta que esos registros no pueden enviarse.
  Future<int> descartarErroresPermanentes() => _repo.descartarErroresPermanentes();

  /// Descarta todos los registros fallidos (abandonados + errores permanentes).
  /// Actualiza el notifier global al terminar.
  Future<int> descartarTodosLosFallidos() async {
    final result = await _repo.descartarTodosLosFallidos();
    await _actualizarNotifier();
    return result;
  }

  // ── Estado de hoy ─────────────────────────────────────────────────────────

  Future<EstadoHoy> getEstadoHoy() async {
    try {
      final r = await _client.get('/asistencia/estado-hoy');
      if (r.statusCode == 200) {
        final e = EstadoHoy.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
        await _guardarEstadoCache(e);
        return e;
      }
    } catch (_) {}
    return _leerEstadoCache();
  }

  // ── Historial ─────────────────────────────────────────────────────────────

  Future<List<RegistroAsistencia>> getHistorial({int pagina = 1}) async {
    try {
      final r = await _client.get(
        '/asistencia/historial?pagina=$pagina&por_pagina=50',
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (data['registros'] as List?) ?? [];
        return list
            .map((e) => RegistroAsistencia.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Resumen semanal del propio usuario (pantalla personal) ────────────────

  /// Horas de la semana, días trabajados, promedio y puntualidad (vs plan).
  /// Devuelve null si el servidor no responde (la UI degrada con lo local).
  Future<ResumenSemanal?> getResumenSemanal() async {
    try {
      final r = await _client.get('/asistencia/mi-resumen-semanal');
      if (r.statusCode == 200) {
        return ResumenSemanal.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // ── Control de asistencias (supervisión, requiere asistencia:ver) ─────────

  /// Resumen del día por empleado (entrada/salida/almuerzo + horas + cumplimiento).
  /// [fecha] en formato YYYY-MM-DD; null = hoy (zona Perú en el backend).
  Future<ControlAsistenciaDia?> getControlDiario({String? fecha}) async {
    try {
      final q = (fecha != null && fecha.isNotEmpty) ? '?fecha=$fecha' : '';
      final r = await _client.get('/asistencia/control-diario$q');
      if (r.statusCode == 200) {
        return ControlAsistenciaDia.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[AsistenciaService] getControlDiario error: $e');
    }
    return null;
  }

  /// Descarga el reporte de asistencias (día/semana/mes) en CSV, Excel o PDF.
  /// [periodo]: 'dia' | 'semana' | 'mes'. [formato]: 'csv' | 'xlsx' | 'pdf'.
  /// El PDF trae resumen + cronograma (matriz día×empleado) + tabla + anexo.
  /// [fecha] (YYYY-MM-DD) es la fecha ancla del rango (por defecto, hoy en el
  /// servidor). Devuelve los bytes del archivo o null si falla.
  ///
  /// Reintenta una vez ante fallo transitorio (p. ej. un 401 puntual del
  /// preflight/sesión en web, donde la petición idéntica siguiente sí responde
  /// 200): así un tropiezo aislado no muestra error si el servidor ya sirve bien.
  Future<List<int>?> descargarAsistencias({
    required String periodo,
    required String formato,
    String? fecha,
  }) async {
    final q = StringBuffer('?periodo=$periodo&formato=$formato');
    if (fecha != null && fecha.isNotEmpty) q.write('&fecha=$fecha');
    final path = '/asistencia/export$q';

    for (var intento = 1; intento <= 2; intento++) {
      try {
        final r = await _client.get(path, timeout: const Duration(seconds: 60));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          return r.bodyBytes;
        }
        debugPrint(
            '[AsistenciaService] descargarAsistencias intento $intento HTTP ${r.statusCode}');
      } catch (e) {
        debugPrint(
            '[AsistenciaService] descargarAsistencias intento $intento error: $e');
      }
      if (intento == 1) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
    return null;
  }

  /// Turnos de la empresa (para asignar excepciones de horario).
  Future<List<TurnoItem>> getTurnos() async {
    try {
      final r = await _client.get('/asistencia/turnos');
      if (r.statusCode == 200) {
        final list = (jsonDecode(r.body) as List?) ?? [];
        return list
            .map((e) => TurnoItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[AsistenciaService] getTurnos error: $e');
    }
    return [];
  }

  /// Crea un turno (p. ej. "Practicante 08:00–13:00"). Requiere asistencia:validar.
  /// [diasLaborales] es el CSV de días ISO (1=Lun … 7=Dom); por defecto L-V.
  Future<bool> crearTurno({
    required String nombre,
    required String horaEntrada,
    required String horaSalida,
    int duracionAlmuerzoMinutos = 60,
    int toleranciaMinutos = 5,
    String diasLaborales = '1,2,3,4,5',
  }) async {
    try {
      final r = await _client.post('/asistencia/turnos', {
        'nombre': nombre,
        'hora_entrada': horaEntrada,
        'hora_salida': horaSalida,
        'duracion_almuerzo_minutos': duracionAlmuerzoMinutos,
        'tolerancia_minutos': toleranciaMinutos,
        'dias_laborales': diasLaborales,
      });
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('[AsistenciaService] crearTurno error: $e');
      return false;
    }
  }

  /// Asigna un turno-excepción a un empleado con vigencia. Requiere asistencia:validar.
  Future<bool> asignarTurno({
    required String empleadoId,
    required String turnoId,
    String? fechaDesde,
    String? fechaHasta,
  }) async {
    try {
      final r = await _client.post('/asistencia/turno-empleado', {
        'empleado_id': empleadoId,
        'turno_id': turnoId,
        'fecha_desde': ?fechaDesde,
        'fecha_hasta': ?fechaHasta,
      });
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('[AsistenciaService] asignarTurno error: $e');
      return false;
    }
  }

  // ── Caché local del estado de asistencia (offline-first) ──────────────────

  static String _hoyKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _guardarEstadoCache(EstadoHoy e) async {
    final prefs = await SharedPreferences.getInstance();
    final map = e.toJson()..['_fecha'] = _hoyKey();
    await prefs.setString(_estadoCacheKey, jsonEncode(map));
    await prefs.setBool(_fotoBaseCacheKey, e.tieneFotoBase);
  }

  /// Lee el estado cacheado. La foto base persiste entre días; la entrada/salida
  /// solo son válidas si el caché es de hoy (cada día la jornada se reinicia).
  Future<EstadoHoy> _leerEstadoCache() async {
    final prefs = await SharedPreferences.getInstance();
    final fotoBase = prefs.getBool(_fotoBaseCacheKey) ?? false;
    final raw = prefs.getString(_estadoCacheKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['_fecha'] == _hoyKey()) {
          return EstadoHoy.fromJson(map);
        }
      } catch (_) {}
    }
    return EstadoHoy(
      tieneEntrada: false,
      tieneSalida: false,
      tieneFotoBase: fotoBase,
      jornadaCompleta: false,
    );
  }

  /// Refleja en el caché una marcación hecha localmente, para que la UI muestre
  /// el avance (entrada → salida, almuerzo) sin esperar al servidor.
  Future<void> _aplicarMarcaLocalAlCache(String tipo, DateTime ts) async {
    final actual = await _leerEstadoCache();
    final hhmm = '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final t = tipo.toLowerCase();

    if (t == 'entrada_almuerzo') {
      await _guardarEstadoCache(actual.copyWith(
        tieneInicioAlmuerzo: true,
        inicioAlmuerzoHora: hhmm,
        inicioAlmuerzoIso: ts.toIso8601String(),
        enAlmuerzo: true,
      ));
      return;
    }
    if (t == 'salida_almuerzo') {
      int? dur;
      final iso = actual.inicioAlmuerzoIso;
      if (iso != null) {
        final ini = DateTime.tryParse(iso);
        if (ini != null) dur = ts.difference(ini).inMinutes;
      }
      await _guardarEstadoCache(actual.copyWith(
        tieneFinAlmuerzo: true,
        finAlmuerzoHora: hhmm,
        enAlmuerzo: false,
        duracionAlmuerzoMin: dur,
      ));
      return;
    }

    final actualizado = actual.copyWith(
      tieneEntrada: t == 'entrada' ? true : actual.tieneEntrada,
      tieneSalida:  t == 'salida'  ? true : actual.tieneSalida,
      entradaHora:  t == 'entrada' ? hhmm : actual.entradaHora,
      salidaHora:   t == 'salida'  ? hhmm : actual.salidaHora,
    );
    await _guardarEstadoCache(
      actualizado.copyWith(
        jornadaCompleta: actualizado.tieneEntrada && actualizado.tieneSalida,
      ),
    );
  }

  /// Revierte en el caché una marca de almuerzo optimista que el servidor
  /// rechazó (ej. regla "ya almorzaste hoy"), para que el botón no quede
  /// mostrando un estado falso.
  Future<void> _revertirMarcaAlmuerzoCache(String tipo) async {
    final actual = await _leerEstadoCache();
    final t = tipo.toLowerCase();
    if (t == 'entrada_almuerzo') {
      await _guardarEstadoCache(actual.copyWith(
        tieneInicioAlmuerzo: false,
        enAlmuerzo: false,
      ));
    } else if (t == 'salida_almuerzo') {
      await _guardarEstadoCache(actual.copyWith(
        tieneFinAlmuerzo: false,
        enAlmuerzo: true,
      ));
    }
  }

  // ── Helpers privados ──────────────────────────────────────────────────────

  /// Detecta si una excepción corresponde a sesión vencida / token inválido.
  static bool _isSessionError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('sesión expirada') ||
        lower.contains('session') ||
        lower.contains('401') ||
        lower.contains('token') ||
        lower.contains('unauthorized') ||
        lower.contains('no auth');
  }

  /// Limpia el prefijo "Exception: " de los mensajes de error para mostrarlos.
  static String _cleanError(String error) =>
      error.replaceAll('Exception: ', '').trim();

  /// Extrae el campo `detail` del body JSON del servidor para mostrarlo en logs.
  static String _extractServerMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) {
          return (detail.first as Map)['msg']?.toString() ?? '';
        }
        final msg = decoded['message'] ?? decoded['msg'] ?? decoded['error'];
        if (msg is String) return msg;
      }
    } catch (_) {}
    return '';
  }
}

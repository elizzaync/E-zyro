import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/api_client.dart';
import '../core/app_constants.dart';
import '../core/trusted_clock.dart';
import '../models/asistencia_models.dart';
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

  /// Actualiza el notifier global con el conteo real de pendientes.
  Future<void> _actualizarNotifier() async {
    pendientesAsistenciaNotifier.value = await _repo.contarPendientes();
  }

  // ── Foto biométrica base ──────────────────────────────────────────────────

  Future<bool> tieneFotoBase() async {
    try {
      final r = await _client.get('/asistencia/tiene-foto-base');
      if (r.statusCode == 200) {
        return (jsonDecode(r.body)['tiene_foto_base'] as bool?) ?? false;
      }
    } catch (_) {}
    return false;
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
    // Es una consulta UDP de ~20ms; no bloquea perceptiblemente la UI.
    await TrustedClock.sync().timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );

    final trustedTs = TrustedClock.now();
    final ahora = trustedTs.time; // UTC, inmune a cambios del reloj del SO

    // 1a. Copiar selfie a directorio estable (los archivos de cámara en /cache
    //     pueden ser borrados por el SO antes de que se sincronice el registro)
    String? stablePath;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final selfieDir = Directory('${appDir.path}/attendance_selfies');
      await selfieDir.create(recursive: true);
      stablePath = '${selfieDir.path}/$clientUuid.jpg';
      await selfieFile.copy(stablePath);
    } catch (_) {
      stablePath = selfieFile.path; // fallback a ruta original si falla la copia
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

    // 2. Intentar enviar de inmediato
    try {
      final b64 = await compute(_fileToBase64, selfieFile.path);

      final body = <String, dynamic>{
        'imagen_selfie': b64,
        'tipo': tipo.toLowerCase(),
        'uuid_cliente': clientUuid,
        'timestamp': ahora.toIso8601String(),
        'fuente_tiempo': trustedTs.etiqueta,
      };
      if (latitud != null)   body['latitud']    = latitud;
      if (longitud != null)  body['longitud']   = longitud;
      if (precisionM != null) body['precision_m'] = precisionM;
      if (altitud != null)   body['altitud']    = altitud;

      final r = await _client.post(
        '/asistencia/marcar',
        body,
        timeout: AppConstants.uploadTimeout,
      );
      _client.checkResponse(r, fallback: 'Error al registrar asistencia');

      // 3. Éxito — marcar como enviado y actualizar badge
      await _repo.marcarEnviado(clientUuid);
      await _actualizarNotifier();

      return MarcarResponse.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    } catch (_) {
      // Sin red o error transitorio: el registro queda pendiente en BD local.
      // Devolver respuesta "offline" para que la UI lo informe correctamente.
      return MarcarResponse(
        registroId: clientUuid,
        status: 'PENDIENTE_SYNC',
        score: 0,
        motivo: 'Asistencia guardada localmente. Se enviará al servidor cuando recuperes conexión.',
        timestamp: ahora,
        gpsGuardado: latitud != null,
        fotoUrl: null,
        resultadoIa: 'pendiente',
      );
    }
  }

  // ── Sincronización manual de pendientes (llamado por SyncService) ─────────

  Future<int> sincronizarPendientes() async {
    final pendientes = await _repo.obtenerPendientes();
    if (pendientes.isEmpty) return 0;

    int enviados = 0;
    for (final r in pendientes) {
      if (r.retryCount >= 5) continue; // abandonar tras 5 fallos

      await _repo.marcarEnviando(r.uuid);

      try {
        // La selfie puede ya no estar en disco (limpieza del SO)
        final evidenciaExiste = r.evidenciaPath != null &&
            File(r.evidenciaPath!).existsSync();

        final body = <String, dynamic>{
          'tipo': r.tipoMarcacion,
          'uuid_cliente': r.uuid,
          'timestamp': r.timestampDispositivo.toIso8601String(),
          'fuente_tiempo': r.fuenteTiempo,
          if (r.latitud != 0) 'latitud': r.latitud,
          if (r.longitud != 0) 'longitud': r.longitud,
        };

        if (evidenciaExiste) {
          body['imagen_selfie'] =
              await compute(_fileToBase64, r.evidenciaPath!);
        } else {
          // Sin selfie: enviar marcación sin imagen (backend lo acepta sin foto_url)
          body['imagen_selfie'] = '';
        }

        final resp = await _client.post(
          '/asistencia/marcar',
          body,
          timeout: AppConstants.uploadTimeout,
        );

        if (resp.statusCode == 200) {
          await _repo.marcarEnviado(r.uuid);
          enviados++;
        } else {
          await _repo.registrarFallo(r.uuid);
        }
      } catch (_) {
        await _repo.registrarFallo(r.uuid);
      }
    }

    // Limpiar enviados antiguos y actualizar el badge global
    await _repo.limpiarEnviados();
    await _actualizarNotifier();
    return enviados;
  }

  Future<int> contarPendientes() => _repo.contarPendientes();

  // ── Estado de hoy ─────────────────────────────────────────────────────────

  Future<EstadoHoy> getEstadoHoy() async {
    try {
      final r = await _client.get('/asistencia/estado-hoy');
      if (r.statusCode == 200) {
        return EstadoHoy.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return EstadoHoy.empty();
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
}

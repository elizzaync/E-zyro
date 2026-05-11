import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import '../core/api_client.dart';
import '../core/app_constants.dart';
import '../models/asistencia_models.dart';

String _fileToBase64(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  return base64Encode(bytes);
}

class AsistenciaService {
  final ApiClient _client;
  AsistenciaService(this._client);

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

  /// Encodes [foto] in an isolate then POSTs it to the backend.
  Future<void> subirFotoBase(File foto) async {
    final b64 = await compute(_fileToBase64, foto.path);
    final r = await _client.post('/asistencia/foto-base', {
      'imagen_base': b64,
    }, timeout: AppConstants.uploadTimeout);
    _client.checkResponse(r, fallback: 'Error al subir foto biométrica');
  }

  // ── Marcar asistencia ─────────────────────────────────────────────────────

  Future<MarcarResponse> marcar({
    required File selfieFile,
    required String tipo,
    double? latitud,
    double? longitud,
    double? precisionM,
    double? altitud,
  }) async {
    final b64 = await compute(_fileToBase64, selfieFile.path);

    final body = <String, dynamic>{
      'imagen_selfie': b64,
      'tipo': tipo.toLowerCase(),
    };
    if (latitud != null) {
      body['latitud'] = latitud;
    }
    if (longitud != null) {
      body['longitud'] = longitud;
    }
    if (precisionM != null) {
      body['precision_m'] = precisionM;
    }
    if (altitud != null) {
      body['altitud'] = altitud;
    }

    final r = await _client.post(
      '/asistencia/marcar',
      body,
      timeout: AppConstants.uploadTimeout,
    );
    _client.checkResponse(r, fallback: 'Error al registrar asistencia');
    return MarcarResponse.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

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

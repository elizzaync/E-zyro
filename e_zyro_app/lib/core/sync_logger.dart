import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Tipos de estado de un intento de sync ────────────────────────────────────

enum SyncLogStatus {
  enviado,       // HTTP 200 OK
  falloRed,      // Exception de red / timeout
  falloServidor, // HTTP 4xx/5xx distinto de 401
  sesionVencida, // HTTP 401 / token vacío
  iniciando,     // Intento comenzando (útil para detectar crasheos)
}

extension SyncLogStatusLabel on SyncLogStatus {
  String get label {
    switch (this) {
      case SyncLogStatus.enviado:       return 'ENVIADO';
      case SyncLogStatus.falloRed:      return 'ERROR RED';
      case SyncLogStatus.falloServidor: return 'ERROR SERVIDOR';
      case SyncLogStatus.sesionVencida: return 'SESIÓN VENCIDA';
      case SyncLogStatus.iniciando:     return 'INICIANDO';
    }
  }
}

// ── Modelo de entrada de log ─────────────────────────────────────────────────

class SyncLogEntry {
  final String id;
  final DateTime timestamp;
  final String uuid;
  final String tipoMarcacion; // 'entrada' | 'salida'
  final SyncLogStatus status;
  final String? errorMessage;
  final int? httpCode;

  SyncLogEntry({
    required this.id,
    required this.timestamp,
    required this.uuid,
    required this.tipoMarcacion,
    required this.status,
    this.errorMessage,
    this.httpCode,
  });

  Map<String, dynamic> toJson() => {
    'id':              id,
    'timestamp':       timestamp.toIso8601String(),
    'uuid':            uuid,
    'tipoMarcacion':   tipoMarcacion,
    'status':          status.name,
    'errorMessage':    errorMessage,
    'httpCode':        httpCode,
  };

  factory SyncLogEntry.fromJson(Map<String, dynamic> j) {
    final statusName = j['status'] as String? ?? 'falloRed';
    final status = SyncLogStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => SyncLogStatus.falloRed,
    );
    return SyncLogEntry(
      id:            j['id'] as String,
      timestamp:     DateTime.parse(j['timestamp'] as String),
      uuid:          j['uuid'] as String,
      tipoMarcacion: j['tipoMarcacion'] as String,
      status:        status,
      errorMessage:  j['errorMessage'] as String?,
      httpCode:      j['httpCode'] as int?,
    );
  }
}

// ── Motor de logs ─────────────────────────────────────────────────────────────

class SyncLogger {
  static const _key       = 'sync_logs_v1';
  static const _maxEntries = 50;

  /// Registra un evento de sync.
  /// Persiste en SharedPreferences Y emite debugPrint en consola.
  static Future<void> log(SyncLogEntry entry) async {
    // ── Consola (visible en Android Studio / VS Code con cable) ──────────────
    final httpStr  = entry.httpCode != null ? ' HTTP ${entry.httpCode}' : '';
    final errStr   = entry.errorMessage != null ? ' | ${entry.errorMessage}' : '';
    debugPrint(
      '[SyncLogger] ${entry.status.label}$httpStr | ${entry.tipoMarcacion.toUpperCase()} '
      '| uuid=${entry.uuid.substring(0, 8)}...$errStr',
    );

    // ── Persistencia ──────────────────────────────────────────────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getStringList(_key) ?? [];
      raw.insert(0, jsonEncode(entry.toJson()));
      if (raw.length > _maxEntries) raw.removeRange(_maxEntries, raw.length);
      await prefs.setStringList(_key, raw);
    } catch (e) {
      debugPrint('[SyncLogger] No se pudo persistir log: $e');
    }
  }

  /// Devuelve los últimos [limit] eventos (más reciente primero).
  static Future<List<SyncLogEntry>> getLogs({int limit = _maxEntries}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getStringList(_key) ?? [];
      return raw
          .take(limit)
          .map((s) {
            try {
              return SyncLogEntry.fromJson(jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<SyncLogEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Borra todos los logs guardados.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  /// Genera un ID único para cada entrada de log.
  static String newId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${Object().hashCode.abs()}';
}

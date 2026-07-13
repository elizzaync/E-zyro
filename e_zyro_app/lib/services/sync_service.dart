import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mantenimiento_models.dart';
import 'asistencia_service.dart';
import 'mantenimiento_service.dart';

class SyncService {
  static const _queueKey = 'evidencias_pendientes';

  // ── Cola de evidencias de mantenimiento (SharedPreferences) ───────────────

  Future<List<EvidenciaPendiente>> getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queueKey) ?? [];
    return raw
        .map((s) =>
            EvidenciaPendiente.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> enqueue(EvidenciaPendiente ev) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queueKey) ?? [];
    raw.add(jsonEncode(ev.toJson()));
    await prefs.setStringList(_queueKey, raw);
  }

  Future<void> _removeFromQueue(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queueKey) ?? [];
    raw.removeWhere((s) {
      try {
        return (jsonDecode(s) as Map)['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_queueKey, raw);
  }

  Future<bool> isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none) && results.isNotEmpty;
  }

  /// Sube todas las evidencias de mantenimiento pendientes en un solo lote
  /// (POST /sync/mantenimientos) en vez de una request secuencial por foto.
  Future<int> processQueue(MantenimientoService service) async {
    if (!await isOnline()) return 0;
    final queue = await getQueue();
    if (queue.isEmpty) return 0;

    final vivas = <EvidenciaPendiente>[];
    for (final ev in queue) {
      if (File(ev.filePath).existsSync()) {
        vivas.add(ev);
      } else {
        await _removeFromQueue(ev.id); // archivo local perdido, no reintentar
      }
    }
    if (vivas.isEmpty) return 0;

    final confirmadas = await service.syncMantenimientos(vivas);
    for (final id in confirmadas) {
      await _removeFromQueue(id);
    }
    return confirmadas.length;
  }

  // ── Cola de asistencias offline (SQLite) ──────────────────────────────────

  bool _syncingAsistencias = false;

  /// Sincroniza registros de asistencia pendientes con el servidor.
  /// No bloquea la UI: se llama fire-and-forget o desde el listener de red.
  Future<int> procesarColaAsistencias(AsistenciaService asistenciaService) async {
    if (_syncingAsistencias) return 0; // evitar ejecuciones concurrentes
    if (!await isOnline()) return 0;

    _syncingAsistencias = true;
    try {
      return await asistenciaService.sincronizarPendientes();
    } finally {
      _syncingAsistencias = false;
    }
  }

  /// Ejecuta ambas colas secuencialmente cuando se recupera la red.
  Future<void> procesarTodo({
    required MantenimientoService mantenimientoService,
    required AsistenciaService asistenciaService,
  }) async {
    await processQueue(mantenimientoService);
    await procesarColaAsistencias(asistenciaService);
  }
}

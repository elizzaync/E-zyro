import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/mantenimiento_models.dart';
import 'mantenimiento_service.dart';

class SyncService {
  static const _queueKey = 'evidencias_pendientes';

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
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Uploads all pending items. Returns number of successfully uploaded items.
  Future<int> processQueue(MantenimientoService service) async {
    if (!await isOnline()) return 0;
    final queue = await getQueue();
    if (queue.isEmpty) return 0;

    int uploaded = 0;
    for (final ev in queue) {
      if (!File(ev.filePath).existsSync()) {
        await _removeFromQueue(ev.id);
        continue;
      }
      final ok = await service.uploadEvidencia(
        ev.pasoId,
        ev.tipo,
        ev.filePath,
        lat: ev.lat,
        lng: ev.lng,
        takenAt: ev.createdAt.toIso8601String(),
      );
      if (ok) {
        await _removeFromQueue(ev.id);
        uploaded++;
      }
    }
    return uploaded;
  }
}

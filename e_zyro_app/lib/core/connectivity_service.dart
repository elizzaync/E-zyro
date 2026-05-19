import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'trusted_clock.dart';

/// Notifier global — true = hay red, false = sin red.
final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Llama una vez en main() antes de runApp.
  Future<void> initialize() async {
    // Cargar último anchor NTP del disco antes de verificar conectividad
    await TrustedClock.loadFromPrefs();

    final initial = await Connectivity().checkConnectivity();
    isOnlineNotifier.value = isConnected(initial);

    // Si arranca con internet, sincronizar NTP de inmediato
    if (isOnlineNotifier.value) {
      TrustedClock.sync(); // fire-and-forget
    }

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !isOnlineNotifier.value;
      isOnlineNotifier.value = isConnected(results);

      // Al recuperar conexión: re-sincronizar NTP
      if (wasOffline && isOnlineNotifier.value) {
        TrustedClock.sync(); // fire-and-forget
      }
    });
  }

  static bool isConnected(List<ConnectivityResult> r) =>
      r.isNotEmpty && !r.contains(ConnectivityResult.none);

  void dispose() => _sub?.cancel();
}

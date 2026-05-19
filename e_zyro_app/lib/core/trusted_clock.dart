import 'package:ntp/ntp.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fuente del timestamp — determina cuánto se puede confiar en él.
enum TimestampSource {
  /// NTP consultado esta sesión + Stopwatch monotónico. No manipulable.
  ntpMonotonic,

  /// NTP de sesión anterior + tiempo transcurrido por reloj de dispositivo.
  /// Vulnerable si el reloj fue cambiado entre sesiones.
  ntpDevice,

  /// Sin referencia NTP disponible. Solo reloj del dispositivo.
  deviceOnly,

  /// Reloj fue cambiado hacia atrás desde el último anchor NTP.
  /// Indica manipulación.
  sospechoso,
}

class TrustedTimestamp {
  final DateTime time; // siempre en UTC
  final TimestampSource source;

  const TrustedTimestamp({required this.time, required this.source});

  bool get esConfiable =>
      source == TimestampSource.ntpMonotonic ||
      source == TimestampSource.ntpDevice;

  String get etiqueta {
    switch (source) {
      case TimestampSource.ntpMonotonic: return 'ntp_monotonic';
      case TimestampSource.ntpDevice:    return 'ntp_device';
      case TimestampSource.deviceOnly:   return 'device_only';
      case TimestampSource.sospechoso:   return 'sospechoso';
    }
  }
}

/// Reloj confiable que no puede ser engañado cambiando la hora del sistema.
///
/// Funcionamiento:
///  1. Al sincronizar con NTP se guarda: ntpAnchor + Stopwatch(reset).
///  2. `now()` = ntpAnchor + stopwatch.elapsed  ← el Stopwatch es MONOTÓNICO,
///     no se ve afectado por cambios del reloj del SO.
///  3. Si la app se reinició (Stopwatch = 0) usa ntpAnchor + diferencia de
///     DateTime.now(). Si esa diferencia es NEGATIVA → manipulación detectada.
class TrustedClock {
  TrustedClock._();

  static DateTime? _ntpAnchor;     // hora NTP en el momento del último sync
  static DateTime? _deviceAnchor;  // hora del dispositivo en ese mismo momento
  static final _watch = Stopwatch();

  static const _keyNtp = 'tc_ntp_utc';
  static const _keyDev = 'tc_dev_utc';

  // ── Sincronización con NTP ─────────────────────────────────────────────────

  /// Consulta NTP y fija el anchor. Llamar cuando hay internet.
  /// Retorna true si la sincronización fue exitosa.
  static Future<bool> sync() async {
    try {
      final deviceBefore = DateTime.now().toUtc();
      final ntpTime = await NTP.now().timeout(const Duration(seconds: 5));
      final ntpUtc = ntpTime.toUtc();

      _ntpAnchor   = ntpUtc;
      _deviceAnchor = deviceBefore;
      _watch
        ..reset()
        ..start();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyNtp, ntpUtc.toIso8601String());
      await prefs.setString(_keyDev, deviceBefore.toIso8601String());

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Carga el último anchor desde SharedPreferences (para cuando la app
  /// se reinicia sin internet). Llamar en main() antes de runApp.
  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ntpStr = prefs.getString(_keyNtp);
      final devStr = prefs.getString(_keyDev);
      if (ntpStr == null || devStr == null) return;
      _ntpAnchor    = DateTime.tryParse(ntpStr);
      _deviceAnchor = DateTime.tryParse(devStr);
      // El Stopwatch no se reinicia; quedará parado hasta el próximo sync.
    } catch (_) {}
  }

  // ── Obtener hora confiable ─────────────────────────────────────────────────

  /// Devuelve la hora actual con metadata de confiabilidad.
  static TrustedTimestamp now() {
    // Caso 1 — Stopwatch corriendo esta sesión (más seguro)
    if (_ntpAnchor != null && _watch.isRunning) {
      return TrustedTimestamp(
        time: _ntpAnchor!.add(_watch.elapsed),
        source: TimestampSource.ntpMonotonic,
      );
    }

    // Caso 2 — Anchor de sesión anterior, calcular con reloj del dispositivo
    if (_ntpAnchor != null && _deviceAnchor != null) {
      final elapsed = DateTime.now().toUtc().difference(_deviceAnchor!);

      if (elapsed.isNegative) {
        // El reloj del dispositivo retrocedió desde el último sync → sospechoso
        return TrustedTimestamp(
          time: _ntpAnchor!, // usar el último anchor conocido como mejor estimación
          source: TimestampSource.sospechoso,
        );
      }

      return TrustedTimestamp(
        time: _ntpAnchor!.add(elapsed),
        source: TimestampSource.ntpDevice,
      );
    }

    // Caso 3 — Sin referencia NTP: solo reloj del dispositivo
    return TrustedTimestamp(
      time: DateTime.now().toUtc(),
      source: TimestampSource.deviceOnly,
    );
  }

  static bool get isSynced => _ntpAnchor != null;
}

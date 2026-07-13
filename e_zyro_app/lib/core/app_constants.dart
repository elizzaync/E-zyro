class AppConstants {
  /// URL del API. Conmutables en build/run sin tocar código:
  ///   flutter run --dart-define=API_URL=https://mi-servidor.com
  ///
  /// Default: backend LOCAL (Railway agotó el plan gratuito 2026-07;
  /// hasta contratar Contabo se trabaja contra el PC de desarrollo).
  /// El teléfono debe estar en la MISMA red Wi-Fi que el PC.
  ///   - PC (IP LAN):        http://192.168.18.28:8000
  ///   - Emulador Android:   http://10.0.2.2:8000
  ///   - Railway (retirado): https://e-zyro-production-7f7d.up.railway.app
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://192.168.18.28:8000',
  );
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 60);
}

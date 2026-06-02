class AppConstants {
  // ── PRUEBAS LOCALES: backend en el PC (datos de Railway + Ollama local) ──
  // Dispositivo físico en la misma WiFi → IP LAN del PC.
  // Emulador Android → usar 'http://10.0.2.2:8000'.
  static const String baseUrl = 'http://192.168.18.65:8000';
  // Producción (revertir antes de compilar el APK de release):
  // static const String baseUrl = 'https://e-zyro-production-7f7d.up.railway.app';
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 60);
}

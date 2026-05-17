import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import 'notification_service.dart';

// Handler de mensajes en background / app terminada.
// DEBE ser función top-level (fuera de cualquier clase).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Firebase ya está inicializado por el runtime; el OS muestra la notificación
  // automáticamente usando el payload `notification`. No necesitamos hacer nada.
}

class FcmFlutterService {
  static final _messaging = FirebaseMessaging.instance;
  static GlobalKey<NavigatorState>? _navKey;
  static ApiClient? _client;

  static final _messageController = StreamController<RemoteMessage>.broadcast();

  /// Stream que emite cada mensaje FCM recibido en primer plano.
  /// Suscríbete para recargar datos en tiempo real.
  static Stream<RemoteMessage> get messageStream => _messageController.stream;

  // ── Inicialización principal ──────────────────────────────────────────────

  /// Llama a esto UNA VEZ después de iniciar sesión exitosamente.
  /// [navKey] debe ser el mismo que se pasa al MaterialApp.
  static Future<void> initialize({
    required ApiClient client,
    required GlobalKey<NavigatorState> navKey,
  }) async {
    _client = client;
    _navKey = navKey;

    // 1. Solicitar permiso (iOS / Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (kDebugMode) debugPrint('[FCM] Permiso denegado.');
      return;
    }

    // 2. Configurar APNs en iOS (obligatorio antes de getToken en iOS)
    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // 3. Mensajes con app en primer plano → mostrar notificación local
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 4. App en background → usuario tocó la notificación
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

    // 5. App terminada → usuario tocó la notificación
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onNotificationTap(initial);

    // 6. Obtener token FCM y registrarlo en el backend
    final token = await _messaging.getToken();
    if (token != null) await _registerDevice(token);

    // 7. Refrescar token cuando FCM lo rota
    _messaging.onTokenRefresh.listen(_registerDevice);

    if (kDebugMode) debugPrint('[FCM] Servicio inicializado.');
  }

  // ── Mensajes en primer plano ──────────────────────────────────────────────

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    _messageController.add(message);
    final n = message.notification;
    if (n == null) return;
    await NotificationService.show(
      title: n.title ?? 'E-System TIC',
      body: n.body ?? '',
    );
  }

  // ── Manejo del toque en notificación ─────────────────────────────────────

  static void _onNotificationTap(RemoteMessage message) {
    final tipo = message.data['tipo'] as String? ?? '';
    final ctx = _navKey?.currentContext;
    if (ctx == null) return;

    switch (tipo) {
      case 'comunicado':
        Navigator.of(ctx).pushNamedAndRemoveUntil('/more', (_) => false);
      case 'servicio':
        Navigator.of(ctx).pushNamedAndRemoveUntil('/operations', (_) => false);
      case 'recordatorio':
        Navigator.of(ctx).pushNamedAndRemoveUntil('/calendario', (_) => false);
      default:
        Navigator.of(ctx).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  // ── Registro de dispositivo ───────────────────────────────────────────────

  static Future<void> _registerDevice(String token) async {
    if (_client == null) return;
    try {
      await _client!.post('/notificaciones/dispositivos/registrar', {
        'token_push': token,
        'plataforma': Platform.isAndroid ? 'android' : 'ios',
      });
      if (kDebugMode) debugPrint('[FCM] Token registrado.');
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] Error al registrar token.');
    }
  }

  /// Llama a esto al hacer logout para desactivar el token en el backend.
  static Future<void> unregisterDevice(ApiClient client) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await client.post('/notificaciones/dispositivos/desregistrar', {
        'token_push': token,
        'plataforma': Platform.isAndroid ? 'android' : 'ios',
      });
      if (kDebugMode) debugPrint('[FCM] Token desregistrado.');
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] Error al desregistrar token.');
    }
  }

  /// Devuelve el token FCM actual (útil para debug/admin).
  static Future<String?> getToken() => _messaging.getToken();
}

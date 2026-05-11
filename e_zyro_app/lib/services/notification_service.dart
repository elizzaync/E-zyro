import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _androidChannel = AndroidNotificationDetails(
    'esystemtic_general',
    'E-System TIC',
    channelDescription: 'Notificaciones generales de E-System TIC',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  static Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    // Request Android 13+ runtime permission
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  static Future<void> show({
    required String title,
    required String body,
    int id = 0,
  }) async {
    await initialize();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: _androidChannel,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showComunicado(String titulo) => show(
        id: 1,
        title: 'Nuevo Comunicado',
        body: titulo,
      );

  static Future<void> showServicioAsignado(String tipoServicio) => show(
        id: 2,
        title: 'Nuevo Servicio Asignado',
        body: tipoServicio,
      );
}

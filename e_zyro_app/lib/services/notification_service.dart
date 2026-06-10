import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _tzReady = false;

  // IDs reservados para los avisos programados del almuerzo (cancelables).
  static const int idAlmuerzoFin = 1001;       // "tu descanso está por terminar"
  static const int idAlmuerzoRecordatorio = 1002; // "es hora de almorzar"

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
    _ensureTz();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Crear el canal explícitamente para que Android lo reconozca desde el inicio
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'esystemtic_general',
      'E-System TIC',
      description: 'Notificaciones generales de E-System TIC',
      importance: Importance.high,
    ));
    await androidPlugin?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Inicializa la base de datos de zonas horarias y fija Lima como local.
  static void _ensureTz() {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('America/Lima'));
    } catch (_) {
      // Si el nombre no existe en el bundle, queda en UTC (no bloquea).
    }
    _tzReady = true;
  }

  /// Programa una notificación local para una hora futura concreta.
  /// Si [when] ya pasó, no hace nada. Reutiliza [id] para poder cancelarla.
  static Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await initialize();
    final target = tz.TZDateTime.from(when, tz.local);
    if (target.isBefore(tz.TZDateTime.now(tz.local))) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        target,
        const NotificationDetails(
          android: _androidChannel,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('[NotificationService] scheduleAt falló: $e');
    }
  }

  /// Cancela una notificación programada por su [id].
  static Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
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

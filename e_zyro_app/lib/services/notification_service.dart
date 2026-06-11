import 'dart:ui' show Color;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Definición de un canal de notificación de Android.
class _Canal {
  final String id;
  final String nombre;
  final String descripcion;
  const _Canal(this.id, this.nombre, this.descripcion);
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _tzReady = false;

  // Ícono monocromático de marca para la barra de estado.
  static const _icon = '@drawable/ic_stat_ezyro';

  // IDs reservados para los avisos programados del almuerzo (cancelables).
  static const int idAlmuerzoFin = 1001; // "tu descanso está por terminar"
  static const int idAlmuerzoRecordatorio = 1002; // "es hora de almorzar"

  // ── Canales por tipo ───────────────────────────────────────────────────────
  // Cada canal es configurable por el usuario en los ajustes de Android
  // (sonido / vibración / importancia) de forma independiente.
  static const _canalGeneral =
      _Canal('esystemtic_general', 'General', 'Notificaciones generales de E-Zyro');
  static const _canalAlmuerzo =
      _Canal('esystemtic_almuerzo', 'Almuerzo', 'Avisos de inicio y fin de tu descanso');
  static const _canalAlertas =
      _Canal('esystemtic_alertas', 'Alertas', 'Mantenimiento y avisos importantes');
  static const _canalComunicados =
      _Canal('esystemtic_comunicados', 'Comunicados', 'Comunicados de la empresa y proyectos');
  static const _canalServicios =
      _Canal('esystemtic_servicios', 'Servicios', 'Asignaciones y novedades de servicios');

  static const _todos = [
    _canalGeneral,
    _canalAlmuerzo,
    _canalAlertas,
    _canalComunicados,
    _canalServicios,
  ];

  /// Resuelve el canal según el tipo/categoría que envía el backend.
  static _Canal _canalPara({String? tipo, String? categoria}) {
    final t = (tipo ?? '').toLowerCase();
    final c = (categoria ?? '').toLowerCase();
    if (c == 'almuerzo') return _canalAlmuerzo;
    if (t == 'warning' || c == 'mantenimiento') return _canalAlertas;
    if (t.startsWith('comunicado')) return _canalComunicados;
    if (t == 'servicio' || t.startsWith('asignacion')) return _canalServicios;
    return _canalGeneral;
  }

  static AndroidNotificationDetails _androidDetails(
    _Canal canal, {
    String? body,
  }) {
    return AndroidNotificationDetails(
      canal.id,
      canal.nombre,
      channelDescription: canal.descripcion,
      importance: Importance.high,
      priority: Priority.high,
      icon: _icon,
      // Tono de marca para el ícono/título en la bandeja.
      color: const Color.fromARGB(255, 143, 209, 27),
      // Texto largo expandible (evita truncado).
      styleInformation: (body != null && body.length > 38)
          ? BigTextStyleInformation(body)
          : null,
    );
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    _ensureTz();
    const android = AndroidInitializationSettings(_icon);
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
    // Crear todos los canales explícitamente para que Android los reconozca.
    for (final canal in _todos) {
      await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
        canal.id,
        canal.nombre,
        description: canal.descripcion,
        importance: Importance.high,
      ));
    }
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
    String? categoria,
  }) async {
    await initialize();
    final target = tz.TZDateTime.from(when, tz.local);
    if (target.isBefore(tz.TZDateTime.now(tz.local))) return;
    final canal = _canalPara(categoria: categoria);
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        target,
        NotificationDetails(
          android: _androidDetails(canal, body: body),
          iOS: const DarwinNotificationDetails(),
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
    String? tipo,
    String? categoria,
    String? tag,
  }) async {
    await initialize();
    final canal = _canalPara(tipo: tipo, categoria: categoria);
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          canal.id,
          canal.nombre,
          channelDescription: canal.descripcion,
          importance: Importance.high,
          priority: Priority.high,
          icon: _icon,
          color: const Color.fromARGB(255, 143, 209, 27),
          // tag → las notificaciones del mismo asunto se reemplazan, no se apilan.
          tag: tag,
          styleInformation: (body.length > 38)
              ? BigTextStyleInformation(body)
              : null,
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: tag),
      ),
    );
  }

  static Future<void> showComunicado(String titulo) => show(
        id: 1,
        title: 'Nuevo Comunicado',
        body: titulo,
        tipo: 'comunicado',
      );

  static Future<void> showServicioAsignado(String tipoServicio) => show(
        id: 2,
        title: 'Nuevo Servicio Asignado',
        body: tipoServicio,
        tipo: 'servicio',
      );
}

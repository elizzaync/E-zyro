import 'package:flutter/material.dart';

/// Controla el tema claro/oscuro de toda la app.
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

/// Controla la pestaña activa del BottomNavigationBar.
final tabNotifier = ValueNotifier<int>(0);

/// Controla la sub-pestaña activa dentro de PersonalScreen (0=Perfil, 1=Asistencia, 2=Documentos).
final personalSubTabNotifier = ValueNotifier<int>(0);

/// Cantidad de registros de asistencia pendientes de sincronización.
/// Lo actualiza AsistenciaService al marcar offline y al terminar cada sync.
final pendientesAsistenciaNotifier = ValueNotifier<int>(0);

/// Cantidad de evidencias de procedimientos pendientes de subir.
/// Lo actualiza ProyectoService al encolar offline y al terminar cada sync.
final pendientesEvidenciaNotifier = ValueNotifier<int>(0);

/// Cantidad de acciones de operaciones pendientes de sincronizar
/// (toggle de tareas, firma de recepción, notas) hechas sin conexión.
final pendientesAccionNotifier = ValueNotifier<int>(0);

/// Se incrementa cada vez que un intento de sync falla con 401 / sesión vencida.
/// MainShell escucha este notifier para mostrar SnackBar + notificación local
/// y redirigir al usuario al login.
final sessionExpiredSyncNotifier = ValueNotifier<int>(0);

/// Se incrementa cada vez que un ciclo de sync envió datos al servidor
/// (asistencias o evidencias). Las pantallas lo escuchan para refrescarse
/// automáticamente sin que el usuario tenga que hacer pull-to-refresh.
final syncCompletedNotifier = ValueNotifier<int>(0);

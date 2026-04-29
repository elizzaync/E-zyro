import 'package:flutter/material.dart';

/// Controla el tema claro/oscuro de toda la app.
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

/// Controla la pestaña activa del BottomNavigationBar.
final tabNotifier = ValueNotifier<int>(0);

/// Controla la sub-pestaña activa dentro de PersonalScreen (0=Perfil, 1=Asistencia, 2=Documentos).
final personalSubTabNotifier = ValueNotifier<int>(0);

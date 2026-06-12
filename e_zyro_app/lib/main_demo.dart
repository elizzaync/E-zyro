// Demo: flutter run -t lib/main_demo.dart
//
// Entry point mínimo para previsualizar el mockup del Dashboard Ejecutivo
// del Portal Cliente B2B (datos 100% de demostración).

import 'package:flutter/material.dart';

import 'portal/pantalla_dashboard_ejecutivo.dart';
import 'portal/portal_design.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'E-zyro Portal — Dashboard Ejecutivo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: PortalColores.fondo,
        colorScheme: const ColorScheme.dark(
          primary: PortalColores.lima,
          surface: PortalColores.superficie,
        ),
        useMaterial3: true,
      ),
      // En web/desktop el layout móvil se estira: lo encerramos en un marco
      // de ancho de teléfono centrado. En un dispositivo real ocupa todo.
      home: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth <= 500) return const PantallaDashboardEjecutivo();
          return ColoredBox(
            color: const Color(0xFF05080F),
            child: Center(
              child: Container(
                width: 430,
                margin: const EdgeInsets.symmetric(vertical: 16),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: const Color(0x22FFFFFF), width: 6),
                ),
                child: const PantallaDashboardEjecutivo(),
              ),
            ),
          );
        },
      ),
    ),
  );
}

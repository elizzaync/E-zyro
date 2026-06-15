import 'package:flutter/material.dart';

import 'pantalla_garantias.dart';
import 'pantalla_correctivos.dart';

/// Apartado "Garantías / Correctivos" con dos pestañas:
///  - Garantías: repositorio central de cartas de garantía (consulta + subir).
///  - Correctivos: trabajos correctivos por servicio (lo existente).
class PantallaGarantiasCorrectivos extends StatelessWidget {
  const PantallaGarantiasCorrectivos({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Garantías / Correctivos',
              style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Garantías'),
              Tab(text: 'Correctivos'),
            ],
          ),
        ),
        // Cada pestaña trae su propio Scaffold SIN AppBar (showAppBar:false),
        // así conserva su FAB sin duplicar encabezado.
        body: const TabBarView(
          children: [
            PantallaGarantias(showAppBar: false),
            PantallaCorrectivos(showAppBar: false),
          ],
        ),
      ),
    );
  }
}

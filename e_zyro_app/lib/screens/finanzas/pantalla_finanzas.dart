import 'package:flutter/material.dart';

import '../../utils/app_session.dart';
import '../../utils/ui_insets.dart';
import 'finanzas_navegacion.dart';

/// Hub del módulo de Finanzas / ERP contable. Agrupa los submódulos por sección
/// (Contabilidad, Cuentas, Tesorería, Activos e inventario, Personal y
/// controlling) y muestra solo los que el rol del usuario puede ver.
/// El mapa de submódulos vive en [finanzasSecciones] (fuente única), que también
/// alimenta el conmutador rápido del AppBar de cada pantalla.
class PantallaFinanzas extends StatelessWidget {
  const PantallaFinanzas({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSession.i;
    final secciones = finanzasSecciones(s);

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Finanzas', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (secciones.isNotEmpty) abrirManualFinanzas(context),
        ],
      ),
      body: secciones.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No tienes permisos para ver módulos de finanzas.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: bottomSafePadding(context),
              children: [
                for (final sec in secciones) ...[
                  _encabezadoSeccion(sec),
                  for (final m in sec.modulos) _tarjeta(context, m),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }

  Widget _encabezadoSeccion(FinSeccion sec) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Icon(sec.icono, size: 17, color: Colors.grey.shade600),
          const SizedBox(width: 7),
          Text(
            sec.titulo.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(BuildContext context, FinModulo m) {
    final surface = Theme.of(context).colorScheme.surface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 1.5,
        shadowColor: Colors.black26,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: m.builder)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: m.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(m.icono, color: m.color, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.titulo,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(m.subtitulo,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

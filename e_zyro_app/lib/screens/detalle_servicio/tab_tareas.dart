// Tab Tareas: cronograma del servicio (responsable + fechas), lo asigna el jefe.
// A diferencia de los Procedimientos, no llevan evidencia ni mueven el avance.
part of '../pantalla_detalle_servicio.dart';

class _TareasTab extends StatelessWidget {
  final List<TareaDetalle> tareas;
  final List<MiembroEquipo> equipo;
  final void Function(TareaDetalle) onToggle;

  const _TareasTab({
    required this.tareas,
    required this.equipo,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (tareas.isEmpty) {
      return _EmptyTab(
        icon: Icons.assignment_outlined,
        label: 'Sin tareas asignadas\nEl jefe las reparte en la configuración',
      );
    }
    final nombrePorId = {for (final m in equipo) m.id: m.nombreCompleto};
    return ListView.separated(
      padding: bottomSafePadding(context),
      itemCount: tareas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _TareaCard(
        tarea: tareas[i],
        responsable: nombrePorId[tareas[i].responsableId ?? ''] ?? '',
        onToggle: onToggle,
      ),
    );
  }
}

class _TareaCard extends StatelessWidget {
  final TareaDetalle tarea;
  final String responsable;
  final void Function(TareaDetalle) onToggle;

  const _TareaCard({
    required this.tarea,
    required this.responsable,
    required this.onToggle,
  });

  Color get _color => switch (tarea.estado) {
        'completado' => _green,
        'en_proceso' => const Color(0xFF3E80C0),
        'bloqueado' => _danger,
        _ => _amber,
      };

  IconData get _icon => switch (tarea.estado) {
        'completado' => Icons.check_circle,
        'en_proceso' => Icons.play_circle_outline,
        'bloqueado' => Icons.block,
        _ => Icons.radio_button_unchecked,
      };

  String _soloFecha(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    return iso.contains('T') ? iso.split('T').first : iso.trim();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final inicio = _soloFecha(tarea.fechaInicioTarea);
    final fin = _soloFecha(tarea.fechaLimite);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: _color.withValues(alpha: isDark ? 0.30 : 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => onToggle(tarea),
                child: Icon(_icon, color: _color, size: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${tarea.orden}. ${tarea.nombre}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 6),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (responsable.isNotEmpty)
                  _meta(Icons.person_outline, responsable),
                if (inicio.isNotEmpty || fin.isNotEmpty)
                  _meta(Icons.calendar_today_outlined,
                      '${inicio.isEmpty ? '—' : inicio} → ${fin.isEmpty ? '—' : fin}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

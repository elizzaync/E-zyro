// Cabecera: datos+progreso, fases, checklist de preparacion.
part of '../pantalla_detalle_servicio.dart';

// ─── Header con datos + progreso ──────────────────────────────────────────────

class _Header extends StatelessWidget {
  final ServicioDetalle detalle;
  /// Progreso a mostrar (override basado en tareas). Si es null usa detalle.progreso.
  final double? progresoMostrado;
  const _Header({required this.detalle, this.progresoMostrado});

  double get _progreso => progresoMostrado ?? detalle.progreso;

  Color get _statusColor => switch (detalle.estado) {
        'Completado' => _green,
        'En_Proceso' => const Color(0xFF3B82F6),
        'Cancelado' => _danger,
        _ => _amber,
      };

  String get _estadoLabel => switch (detalle.estado) {
        'En_Proceso' => 'En Proceso',
        _ => detalle.estado,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: _green.withValues(alpha: 0.30)) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detalle.cliente,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 2),
                    Text(detalle.tipoServicio,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_estadoLabel,
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(Icons.location_on_outlined, detalle.ubicacion),
          _InfoRow(Icons.calendar_today_outlined, detalle.fechaStr),
          _InfoRow(Icons.access_time_outlined, detalle.horaStr),
          if (detalle.descripcion.isNotEmpty)
            _InfoRow(Icons.notes_outlined, detalle.descripcion),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Progreso de tareas',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
              const Spacer(),
              Text('${_progreso.round()}%',
                  style: TextStyle(
                      color: _progreso >= 100 ? _green : _amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progreso / 100,
              backgroundColor:
                  isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                  _progreso >= 100 ? _green : _amber),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Fila de info ─────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─── Stepper de 4 fases (Preparación · En sitio · Ejecución · Cierre) ─────────

class _FasesStepper extends StatelessWidget {
  final String estado;
  final double progreso;
  const _FasesStepper({required this.estado, required this.progreso});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          for (final f in fasesServicio) ...[
            Builder(builder: (_) {
              final clase = faseClase(f.n, estado, progreso);
              final done = clase == 'done';
              final active = clase == 'active';
              final color = (done || active) ? _green : muted;
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 3,
                            color: f.n == 1
                                ? Colors.transparent
                                : (faseClase(f.n - 1, estado, progreso) == 'done'
                                    ? _green
                                    : muted.withValues(alpha: 0.3)),
                          ),
                        ),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: done
                                ? _green
                                : (active ? _green.withValues(alpha: 0.15) : Colors.transparent),
                            shape: BoxShape.circle,
                            border: Border.all(color: color, width: 2),
                          ),
                          child: done
                              ? const Icon(Icons.check, size: 13, color: Colors.white)
                              : Center(
                                  child: Text('${f.n}',
                                      style: TextStyle(
                                          color: color,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ),
                        ),
                        Expanded(
                          child: Container(
                            height: 3,
                            color: f.n == fasesServicio.length
                                ? Colors.transparent
                                : (done ? _green : muted.withValues(alpha: 0.3)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(f.nombre,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9.5,
                            height: 1.1,
                            color: (done || active) ? null : muted,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ─── Checklist de Preparación (Fase 1) ────────────────────────────────────────

class _ChecklistPreparacion extends StatelessWidget {
  final bool equipoListo;
  final bool tareasListo;
  final bool materialesListo;
  final bool puedeIniciar;
  final bool esJefe;
  final bool iniciando;
  final List<String> motivos;
  final VoidCallback onIniciar;

  const _ChecklistPreparacion({
    required this.equipoListo,
    required this.tareasListo,
    required this.materialesListo,
    required this.puedeIniciar,
    required this.esJefe,
    required this.iniciando,
    required this.motivos,
    required this.onIniciar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: puedeIniciar
                ? _green.withValues(alpha: 0.35)
                : _amber.withValues(alpha: isDark ? 0.30 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.fact_check_outlined, size: 16, color: _amber),
              SizedBox(width: 6),
              Text('Fase 1 · Preparación',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          _PrepStep(n: 1, ok: equipoListo, label: 'Asignar equipo técnico'),
          _PrepStep(n: 2, ok: tareasListo, label: 'Repartir tareas (con responsable)'),
          _PrepStep(n: 3, ok: materialesListo, label: 'Elegir materiales y herramientas'),
          const SizedBox(height: 8),
          if (!puedeIniciar)
            Text('Falta: ${motivos.join(' · ')}.',
                style: const TextStyle(
                    color: _amber, fontSize: 11.5, fontWeight: FontWeight.w500))
          else if (!esJefe)
            const Text(
                'Todo listo. Espera que el Jefe de Operaciones marque EN SITIO.',
                style: TextStyle(
                    color: _green, fontSize: 11.5, fontWeight: FontWeight.w600))
          else
            const Text('Todo listo. Marca EN SITIO al llegar al lugar.',
                style: TextStyle(
                    color: _green, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (puedeIniciar && esJefe && !iniciando) ? onIniciar : null,
              icon: iniciando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(
                      (puedeIniciar && esJefe)
                          ? Icons.location_on_rounded
                          : Icons.lock_outline,
                      size: 18),
              label: Text(
                  (puedeIniciar && esJefe)
                      ? 'Marcar EN SITIO'
                      : (!esJefe ? 'EN SITIO (solo Jefe de Op.)' : 'EN SITIO (bloqueado)'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    Theme.of(context).disabledColor.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrepStep extends StatelessWidget {
  final int n;
  final bool ok;
  final String label;
  const _PrepStep({required this.n, required this.ok, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: ok ? _green : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: ok ? _green : Colors.grey, width: 1.5),
            ),
            child: ok
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Center(
                    child: Text('$n',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.w700)),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: ok ? null : Colors.grey,
                    fontWeight: ok ? FontWeight.w500 : FontWeight.w400)),
          ),
          if (ok) const Icon(Icons.check_circle, size: 14, color: _green),
        ],
      ),
    );
  }
}

// ─── Tarjeta Fase Ejecución / Cierre (servicio En Proceso) ────────────────────

class _FaseEjecucionCard extends StatelessWidget {
  final int totalTareas;
  final int tareasCompletas;
  final bool todasCompletas;
  final bool esJefe;
  final bool cerrando;
  final VoidCallback onCerrar;

  const _FaseEjecucionCard({
    required this.totalTareas,
    required this.tareasCompletas,
    required this.todasCompletas,
    required this.esJefe,
    required this.cerrando,
    required this.onCerrar,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final listoCerrar = todasCompletas && totalTareas > 0;
    final color = listoCerrar ? _green : const Color(0xFF3B82F6);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(listoCerrar ? Icons.flag_circle_outlined : Icons.engineering_outlined,
                  size: 16, color: color),
              const SizedBox(width: 6),
              Text(listoCerrar ? 'Fase 4 · Cierre' : 'Fase 3 · Ejecución',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              const Spacer(),
              Text('$tareasCompletas / $totalTareas tareas',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          if (totalTareas == 0)
            const Text('Reparte tareas en el cronograma para ejecutar el servicio.',
                style: TextStyle(
                    color: _amber, fontSize: 11.5, fontWeight: FontWeight.w500))
          else if (!todasCompletas)
            const Text('Marca todas las tareas para poder cerrar el servicio.',
                style: TextStyle(
                    color: Color(0xFF3B82F6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500))
          else if (!esJefe)
            const Text(
                'Todas las tareas listas. Espera que el Jefe de Operaciones cierre el servicio.',
                style: TextStyle(
                    color: _green, fontSize: 11.5, fontWeight: FontWeight.w600))
          else
            const Text('Todas las tareas completas. Ya puedes cerrar el servicio.',
                style: TextStyle(
                    color: _green, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (listoCerrar && esJefe && !cerrando) ? onCerrar : null,
              icon: cerrando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(
                      (listoCerrar && esJefe)
                          ? Icons.check_circle_outline
                          : Icons.lock_outline,
                      size: 18),
              label: Text(
                  (listoCerrar && esJefe)
                      ? 'Cerrar servicio'
                      : (!esJefe ? 'Cerrar (solo Jefe de Op.)' : 'Cerrar (bloqueado)'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    Theme.of(context).disabledColor.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


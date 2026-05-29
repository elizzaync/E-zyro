// Tab Equipo: miembros + card de equipos/herramientas (prestamos).
part of '../pantalla_detalle_servicio.dart';

// ─── Tab: Equipo ──────────────────────────────────────────────────────────────

class _EquipoTab extends StatefulWidget {
  final List<MiembroEquipo> equipo;
  final String servicioId;
  final String proyectoId;
  final ProyectoService service;
  final Future<void> Function() onChanged;

  const _EquipoTab({
    required this.equipo,
    required this.servicioId,
    required this.proyectoId,
    required this.service,
    required this.onChanged,
  });

  @override
  State<_EquipoTab> createState() => _EquipoTabState();
}

class _EquipoTabState extends State<_EquipoTab> {
  bool get _puedeAsignar =>
      AppSession.i.isJefeOperaciones || AppSession.i.isAdmin;

  // ── Abre la pantalla de configuración (equipo + cronograma) ─────────────────
  Future<void> _abrirAsignacion() async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaAsignacionServicio(
          servicioId: widget.servicioId,
          service: widget.service,
          mode: 'editar',
        ),
      ),
    );
    if (guardado == true) {
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Asignación actualizada'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tieneEquipo = widget.equipo.isNotEmpty;
    return Stack(
      children: [
        widget.equipo.isEmpty
            ? const _EmptyTab(
                icon: Icons.group_outlined,
                label: 'Sin equipo asignado')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: widget.equipo.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _MiembroCard(
                  miembro: widget.equipo[i],
                ),
              ),
        // FAB de configuración solo para Jefe de Operaciones / Admin
        if (_puedeAsignar)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              heroTag: 'fab_equipo',
              onPressed: _abrirAsignacion,
              backgroundColor: _green,
              foregroundColor: Colors.white,
              icon: Icon(tieneEquipo
                  ? Icons.edit_calendar_outlined
                  : Icons.group_add_outlined),
              label: Text(
                  tieneEquipo ? 'Editar asignación' : 'Configurar asignación',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}

class _MiembroCard extends StatelessWidget {
  final MiembroEquipo miembro;
  const _MiembroCard({required this.miembro});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? Border.all(color: _green.withValues(alpha: 0.25)) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage:
                miembro.fotoUrl.isNotEmpty ? CachedNetworkImageProvider(miembro.fotoUrl) : null,
            backgroundColor:
                isDark ? _green.withValues(alpha: 0.20) : const Color(0xFFEFFAE0),
            child: miembro.fotoUrl.isEmpty
                ? Text(
                    miembro.nombre.isNotEmpty
                        ? miembro.nombre[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: _green, fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(miembro.nombreCompleto,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(miembro.cargo,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? _green.withValues(alpha: 0.15)
                  : const Color(0xFFEFFAE0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(miembro.rolProyecto,
                style: const TextStyle(
                    color: _green,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ─── Card de acceso a Equipos y Herramientas (FASE 5) ────────────────────────
// Reemplaza la antigua "Solicitar materiales" desde pantalla_logistica: ahora
// los préstamos viven vinculados al servicio.
class _EquiposHerramientasCard extends StatelessWidget {
  final int avisosCount;
  final VoidCallback onTap;
  const _EquiposHerramientasCard({
    required this.avisosCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final hayAvisos = avisosCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: hayAvisos
              ? Border.all(color: _amber.withValues(alpha: 0.5), width: 1.5)
              : (isDark
                  ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                  : null),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: isDark ? 0.15 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.handyman_outlined,
                color: _green, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Equipos y herramientas',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                SizedBox(height: 2),
                Text(
                    'Solicita y devuelve equipos para este servicio',
                    style: TextStyle(color: Colors.grey, fontSize: 11.5)),
              ],
            ),
          ),
          if (hayAvisos)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _amber.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded, size: 12, color: _amber),
                const SizedBox(width: 4),
                Text('$avisosCount sin confirmar',
                    style: const TextStyle(
                        color: _amber,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ]),
      ),
    );
  }
}


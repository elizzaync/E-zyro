import 'package:flutter/material.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';
import 'pantalla_chat.dart';

class DetalleServicioScreen extends StatefulWidget {
  final String servicioId;
  final String proyectoId;
  final String nombreServicio;
  final ProyectoService service;

  const DetalleServicioScreen({
    super.key,
    required this.servicioId,
    required this.proyectoId,
    required this.nombreServicio,
    required this.service,
  });

  @override
  State<DetalleServicioScreen> createState() => _DetalleServicioScreenState();
}

class _DetalleServicioScreenState extends State<DetalleServicioScreen>
    with SingleTickerProviderStateMixin {
  ServicioDetalle? _detalle;
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await widget.service.getDetalleServicio(widget.servicioId);
    if (!mounted) return;
    setState(() {
      _detalle = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.nombreServicio,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
              ),
            )
          : _detalle == null
          ? _ErrorView(onRetry: _load)
          : _DetalleContent(
              detalle: _detalle!,
              tabController: _tabController,
              proyectoId: widget.proyectoId,
            ),
    );
  }
}

// ─── Contenido principal ──────────────────────────────────────────────────────

class _DetalleContent extends StatelessWidget {
  final ServicioDetalle detalle;
  final TabController tabController;
  final String proyectoId;

  const _DetalleContent({
    required this.detalle,
    required this.tabController,
    required this.proyectoId,
  });

  Color get _statusColor => switch (detalle.estado) {
    'Completado' => const Color(0xFF8FD11B),
    'En_Proceso' => const Color(0xFF3B82F6),
    'Cancelado' => Colors.red,
    _ => const Color(0xFFF59E0B),
  };

  String get _estadoLabel => switch (detalle.estado) {
    'En_Proceso' => 'En Proceso',
    _ => detalle.estado,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF8FD11B);

    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: isDark
                ? Border.all(color: green.withValues(alpha: 0.30))
                : null,
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
                        Text(
                          detalle.cliente,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detalle.tipoServicio,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? _statusColor.withValues(alpha: 0.15)
                          : _statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _estadoLabel,
                      style: TextStyle(
                        color: _statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

              // Barra de progreso
              Row(
                children: [
                  const Text(
                    'Progreso',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  const Spacer(),
                  Text(
                    '${detalle.progreso.round()}%',
                    style: TextStyle(
                      color: detalle.progreso >= 100
                          ? green
                          : const Color(0xFFF59E0B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: detalle.progreso / 100,
                  backgroundColor: isDark
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    detalle.progreso >= 100 ? green : const Color(0xFFF59E0B),
                  ),
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),

        // ── Tabs ────────────────────────────────────────────────────────────
        const SizedBox(height: 12),
        TabBar(
          controller: tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: green,
          unselectedLabelColor: Colors.grey,
          indicatorColor: green,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: [
            Tab(text: 'Procedimientos (${detalle.procedimientos.length})'),
            Tab(text: 'Equipo (${detalle.equipo.length})'),
            Tab(
              text:
                  'Materiales (${detalle.materialesAsignados.length + detalle.materialesSolicitados.length})',
            ),
            Tab(text: 'Notas (${detalle.notas.length})'),
            const Tab(
              icon: Icon(Icons.chat_bubble_outline, size: 16),
              text: 'Chat',
            ),
          ],
        ),

        // ── Tab views ───────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              _ProcedimientosTab(procedimientos: detalle.procedimientos),
              _EquipoTab(equipo: detalle.equipo),
              _MaterialesTab(
                asignados: detalle.materialesAsignados,
                solicitados: detalle.materialesSolicitados,
              ),
              _NotasTab(notas: detalle.notas),
              ChatTab(
                room: proyectoId,
                fotosPorId: {
                  for (final m in detalle.equipo)
                    if (m.fotoUrl.isNotEmpty) m.id: m.fotoUrl,
                },
              ),
            ],
          ),
        ),
      ],
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
            child: Text(
              text,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Procedimientos ──────────────────────────────────────────────────────

class _ProcedimientosTab extends StatelessWidget {
  final List<ProcedimientoDetalle> procedimientos;
  const _ProcedimientosTab({required this.procedimientos});

  @override
  Widget build(BuildContext context) {
    if (procedimientos.isEmpty) {
      return _EmptyTab(
        icon: Icons.checklist_outlined,
        label: 'Sin procedimientos registrados',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: procedimientos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ProcedimientoCard(proc: procedimientos[i]),
    );
  }
}

class _ProcedimientoCard extends StatelessWidget {
  final ProcedimientoDetalle proc;
  const _ProcedimientoCard({required this.proc});

  Color get _color => switch (proc.estado) {
    'completado' => const Color(0xFF8FD11B),
    'en_proceso' => const Color(0xFF3B82F6),
    'bloqueado' => Colors.red,
    _ => const Color(0xFFF59E0B),
  };

  IconData get _icon => switch (proc.estado) {
    'completado' => Icons.check_circle,
    'en_proceso' => Icons.play_circle_outline,
    'bloqueado' => Icons.block,
    _ => Icons.radio_button_unchecked,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? _color.withValues(alpha: 0.30)
              : _color.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${proc.orden}. ${proc.nombre}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (proc.descripcion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                proc.descripcion,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
          if (proc.evidencias.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: proc.evidencias
                    .map((e) => _EvidenciaThumb(ev: e))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenciaThumb extends StatelessWidget {
  final EvidenciaDetalle ev;
  const _EvidenciaThumb({required this.ev});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          ev.urlCloudinary,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 64,
            height: 64,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Image.network(ev.urlCloudinary, fit: BoxFit.contain),
            if (ev.descripcion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  ev.descripcion,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab: Equipo ──────────────────────────────────────────────────────────────

class _EquipoTab extends StatelessWidget {
  final List<MiembroEquipo> equipo;
  const _EquipoTab({required this.equipo});

  @override
  Widget build(BuildContext context) {
    if (equipo.isEmpty) {
      return _EmptyTab(
        icon: Icons.group_outlined,
        label: 'Sin miembros de equipo',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: equipo.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _MiembroCard(miembro: equipo[i]),
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
    const green = Color(0xFF8FD11B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark
            ? Border.all(color: green.withValues(alpha: 0.25))
            : null,
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
            backgroundImage: miembro.fotoUrl.isNotEmpty
                ? NetworkImage(miembro.fotoUrl)
                : null,
            backgroundColor: isDark
                ? green.withValues(alpha: 0.20)
                : const Color(0xFFEFFAE0),
            child: miembro.fotoUrl.isEmpty
                ? Text(
                    miembro.nombre.isNotEmpty
                        ? miembro.nombre[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Color(0xFF8FD11B),
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  miembro.nombreCompleto,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  miembro.cargo,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? green.withValues(alpha: 0.15)
                  : const Color(0xFFEFFAE0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              miembro.rolProyecto,
              style: const TextStyle(
                color: Color(0xFF8FD11B),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Materiales ──────────────────────────────────────────────────────────

class _MaterialesTab extends StatelessWidget {
  final List<ItemMaterial> asignados;
  final List<ItemMaterial> solicitados;

  const _MaterialesTab({required this.asignados, required this.solicitados});

  @override
  Widget build(BuildContext context) {
    if (asignados.isEmpty && solicitados.isEmpty) {
      return _EmptyTab(
        icon: Icons.inventory_2_outlined,
        label: 'Sin materiales registrados',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (asignados.isNotEmpty) ...[
          _SectionTitle(
            'Materiales Asignados',
            Icons.check_circle_outline,
            const Color(0xFF8FD11B),
          ),
          const SizedBox(height: 8),
          ...asignados.map((m) => _MaterialCard(item: m)),
          const SizedBox(height: 16),
        ],
        if (solicitados.isNotEmpty) ...[
          _SectionTitle(
            'Materiales Solicitados',
            Icons.pending_outlined,
            const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 8),
          ...solicitados.map((m) => _MaterialCard(item: m)),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionTitle(this.title, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final ItemMaterial item;
  const _MaterialCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.grey.withValues(alpha: 0.20)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.nombre,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '${item.cantidad} ${item.unidad}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Notas ───────────────────────────────────────────────────────────────

class _NotasTab extends StatelessWidget {
  final List<NotaSeguimiento> notas;
  const _NotasTab({required this.notas});

  @override
  Widget build(BuildContext context) {
    if (notas.isEmpty) {
      return _EmptyTab(
        icon: Icons.notes_outlined,
        label: 'Sin notas de seguimiento',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: notas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _NotaCard(nota: notas[i]),
    );
  }
}

class _NotaCard extends StatelessWidget {
  final NotaSeguimiento nota;
  const _NotaCard({required this.nota});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark
            ? Border.all(color: green.withValues(alpha: 0.20))
            : null,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? green.withValues(alpha: 0.15)
                      : const Color(0xFFEFFAE0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 14,
                  color: Color(0xFF8FD11B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nota.autor,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      nota.fecha,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            nota.texto,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ─── Estado vacío genérico ────────────────────────────────────────────────────

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No se pudo cargar el servicio',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF8FD11B)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Reintentar',
              style: TextStyle(color: Color(0xFF8FD11B)),
            ),
          ),
        ],
      ),
    );
  }
}

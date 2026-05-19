import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../models/proyecto_models.dart';
import '../models/comunicado_models.dart';
import '../services/proyecto_service.dart';
import '../utils/app_session.dart';
import '../services/comunicado_service.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/api_provider.dart';
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
    _tabController = TabController(length: 6, vsync: this);
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
              servicioId: widget.servicioId,
            ),
    );
  }
}

// ─── Contenido principal ──────────────────────────────────────────────────────

class _DetalleContent extends StatelessWidget {
  final ServicioDetalle detalle;
  final TabController tabController;
  final String proyectoId;
  final String servicioId;

  const _DetalleContent({
    required this.detalle,
    required this.tabController,
    required this.proyectoId,
    required this.servicioId,
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
            const Tab(
              icon: Icon(Icons.campaign_outlined, size: 16),
              text: 'Comunicados',
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
                room: 'servicio/$servicioId',
                fotosPorId: {
                  for (final m in detalle.equipo)
                    if (m.fotoUrl.isNotEmpty) m.id: m.fotoUrl,
                },
              ),
              // HU-13: Canal de difusión por proyecto
              _ComunicadosTab(proyectoId: proyectoId),
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

// ─── Tab: Comunicados del Proyecto (HU-13) ────────────────────────────────────

class _ComunicadosTab extends StatefulWidget {
  final String proyectoId;
  const _ComunicadosTab({required this.proyectoId});

  @override
  State<_ComunicadosTab> createState() => _ComunicadosTabState();
}

class _ComunicadosTabState extends State<_ComunicadosTab>
    with AutomaticKeepAliveClientMixin {
  ComunicadoService? _service;
  List<ComunicadoProyecto> _comunicados = [];
  bool _loading = true;
  bool _puedeEnviar = false;
  bool _sessionExpired = false;
  StreamSubscription<RemoteMessage>? _fcmSub;

  static const _green = Color(0xFF8FD11B);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
    _fcmSub = FcmFlutterService.messageStream.listen((msg) {
      if ((msg.data['tipo'] as String?) == 'comunicado_proyecto' &&
          (msg.data['proyecto_id'] as String?) == widget.proyectoId) {
        _load();
      }
    });
    _checkPermiso();
  }

  Future<void> _checkPermiso() async {
    await AppSession.load();
    if (mounted) setState(() => _puedeEnviar = AppSession.i.canEnviarComunicado);
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getComunicadoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() { _loading = true; _sessionExpired = false; });
    try {
      final data = await _service!.getComunicadosProyecto(widget.proyectoId);
      if (!mounted) return;
      setState(() { _comunicados = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      final expired = e.toString().contains('expirada') || e.toString().contains('Sesión');
      setState(() { _loading = false; _sessionExpired = expired; });
    }
  }

  Future<void> _marcarLeido(ComunicadoProyecto c) async {
    if (c.leido) return;
    await _service?.marcarLeidoProyecto(c.id);
    if (!mounted) return;
    setState(() {
      final idx = _comunicados.indexWhere((e) => e.id == c.id);
      if (idx != -1) _comunicados[idx] = _comunicados[idx].markRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(_green),
        ),
      );
    }

    if (_sessionExpired) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_clock_outlined, size: 44, color: Colors.orange),
            const SizedBox(height: 10),
            const Text('Sesión expirada',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            const Text('Cierra sesión e inicia nuevamente.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false),
              child: const Text('Ir al Login',
                  style: TextStyle(color: _green, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    if (_comunicados.isEmpty) {
      return _EmptyTab(
        icon: Icons.campaign_outlined,
        label: 'Sin comunicados del proyecto',
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          color: _green,
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(16, 16, 16, _puedeEnviar ? 90 : 16),
            itemCount: _comunicados.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ComunicadoCard(
              comunicado: _comunicados[i],
              onTap: () => _marcarLeido(_comunicados[i]),
            ),
          ),
        ),
        if (_puedeEnviar)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'fab_comunicado_${widget.proyectoId}',
              onPressed: _openNuevoComunicado,
              backgroundColor: _green,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Nuevo',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  void _openNuevoComunicado() {
    final tituloCtrl = TextEditingController();
    final mensajeCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          bool sending = false;
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.campaign_outlined,
                        color: Color(0xFFF59E0B), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nuevo Comunicado',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('Enviar al proyecto',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ]),
                const SizedBox(height: 20),
                const Text('Título',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: tituloCtrl,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: 'Título del comunicado...',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Mensaje',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: mensajeCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Escribe el comunicado...',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 24),
                StatefulBuilder(
                  builder: (_, setSend) => SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: sending ? null : () async {
                        final titulo = tituloCtrl.text.trim();
                        final mensaje = mensajeCtrl.text.trim();
                        if (titulo.isEmpty || mensaje.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Completa el título y el mensaje'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        setSend(() => sending = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await _service?.crearComunicado(
                          proyectoId: widget.proyectoId,
                          titulo: titulo,
                          mensaje: mensaje,
                        ) ?? false;
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        if (ok) {
                          _load();
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text('Comunicado enviado'),
                              backgroundColor: _green,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        } else {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Error al enviar. Intenta nuevamente.'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: sending
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Enviar Comunicado',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ComunicadoCard extends StatelessWidget {
  final ComunicadoProyecto comunicado;
  final VoidCallback onTap;

  const _ComunicadoCard({required this.comunicado, required this.onTap});

  static const _amber = Color(0xFFF59E0B);
  static const _green = Color(0xFF8FD11B);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final isUnread = !comunicado.leido;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnread
              ? _amber.withValues(alpha: isDark ? 0.08 : 0.05)
              : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnread
                ? _amber.withValues(alpha: 0.35)
                : isDark
                    ? _green.withValues(alpha: 0.15)
                    : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? _amber.withValues(alpha: 0.15)
                        : const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.campaign_outlined,
                    color: _amber,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comunicado.titulo,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isUnread
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 11, color: Colors.grey),
                          const SizedBox(width: 3),
                          Text(
                            comunicado.autor,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.access_time_outlined,
                              size: 11, color: Colors.grey),
                          const SizedBox(width: 3),
                          Text(
                            comunicado.fecha,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: const BoxDecoration(
                      color: _amber,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              comunicado.mensaje,
              style: const TextStyle(
                  fontSize: 12, color: Colors.grey, height: 1.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (comunicado.adjuntoUrl != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.attach_file_outlined,
                      size: 13, color: _green.withValues(alpha: 0.8)),
                  const SizedBox(width: 4),
                  const Text(
                    'Archivo adjunto disponible',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8FD11B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
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

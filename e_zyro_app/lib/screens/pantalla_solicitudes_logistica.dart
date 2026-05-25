import 'package:flutter/material.dart';
import '../models/requerimiento_models.dart';
import '../services/requerimiento_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kBlue = Color(0xFF3B82F6);

/// Bandeja del encargado de logística: aprobar / rechazar / entregar
/// las solicitudes de materiales de los técnicos.
class PantallaSolicitudesLogistica extends StatefulWidget {
  const PantallaSolicitudesLogistica({super.key});

  @override
  State<PantallaSolicitudesLogistica> createState() =>
      _PantallaSolicitudesLogisticaState();
}

class _PantallaSolicitudesLogisticaState
    extends State<PantallaSolicitudesLogistica> {
  RequerimientoService? _service;
  List<SolicitudGestion> _solicitudes = [];
  bool _isLoading = true;
  String _filtro = 'todos'; // todos | pendiente | aprobado | entregado | rechazado

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getRequerimientoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final estado = _filtro == 'todos' ? null : _filtro;
    final data = await _service!.getSolicitudesPendientes(estado: estado);
    if (!mounted) return;
    setState(() {
      _solicitudes = data;
      _isLoading = false;
    });
  }

  void _setFiltro(String f) {
    setState(() => _filtro = f);
    _load();
  }

  Future<void> _aprobar(SolicitudGestion s) async {
    final ok = await _service!.gestionarSolicitud(s.id, 'aprobar');
    _feedback(ok, 'Solicitud aprobada', 'No se pudo aprobar');
    if (ok) await _load();
  }

  Future<void> _rechazar(SolicitudGestion s) async {
    final ctrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Indica el motivo del rechazo (opcional):',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Motivo...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rechazar', style: TextStyle(color: _kRed))),
        ],
      ),
    );
    if (confirmar != true) return;
    final ok = await _service!
        .gestionarSolicitud(s.id, 'rechazar', observacion: ctrl.text.trim());
    _feedback(ok, 'Solicitud rechazada', 'No se pudo rechazar');
    if (ok) await _load();
  }

  Future<void> _entregar(SolicitudGestion s) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar entrega'),
        content: const Text(
            'Se descontará el stock de los materiales aprobados. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Entregar', style: TextStyle(color: _kGreen))),
        ],
      ),
    );
    if (confirmar != true) return;
    final ok = await _service!.entregarSolicitud(s.id);
    _feedback(ok, 'Materiales entregados', 'No se pudo entregar');
    if (ok) await _load();
  }

  void _feedback(bool ok, String okMsg, String errMsg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? okMsg : errMsg),
        backgroundColor: ok ? _kGreen : _kRed,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Solicitudes',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16,
        amp: 9,
        stroke: 0.38,
        speed: 0.45,
        child: Column(
          children: [
            // ── Filtros ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Chip(
                        label: 'Todos',
                        selected: _filtro == 'todos',
                        onTap: () => _setFiltro('todos')),
                    _Chip(
                        label: 'Pendientes',
                        selected: _filtro == 'pendiente',
                        color: _kAmber,
                        onTap: () => _setFiltro('pendiente')),
                    _Chip(
                        label: 'Aprobadas',
                        selected: _filtro == 'aprobado',
                        color: _kBlue,
                        onTap: () => _setFiltro('aprobado')),
                    _Chip(
                        label: 'Entregadas',
                        selected: _filtro == 'entregado',
                        color: _kGreen,
                        onTap: () => _setFiltro('entregado')),
                    _Chip(
                        label: 'Rechazadas',
                        selected: _filtro == 'rechazado',
                        color: _kRed,
                        onTap: () => _setFiltro('rechazado')),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kGreen))
                  : _solicitudes.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _kGreen,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _solicitudes.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _SolicitudCard(
                              solicitud: _solicitudes[i],
                              onAprobar: () => _aprobar(_solicitudes[i]),
                              onRechazar: () => _rechazar(_solicitudes[i]),
                              onEntregar: () => _entregar(_solicitudes[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          const Text('No hay solicitudes en este estado',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _load,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _kGreen),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.refresh_rounded, color: _kGreen, size: 16),
            label: const Text('Actualizar', style: TextStyle(color: _kGreen)),
          ),
        ],
      ),
    );
  }
}

// ─── Chip de filtro ─────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    this.color = _kGreen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color
                : (isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ─── Card de solicitud ──────────────────────────────────────────────────────
class _SolicitudCard extends StatelessWidget {
  final SolicitudGestion solicitud;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;
  final VoidCallback onEntregar;

  const _SolicitudCard({
    required this.solicitud,
    required this.onAprobar,
    required this.onRechazar,
    required this.onEntregar,
  });

  Color get _estadoColor => switch (solicitud.estado) {
        'aprobado' => _kBlue,
        'entregado' => _kGreen,
        'rechazado' => _kRed,
        _ => _kAmber,
      };

  String get _estadoLabel => switch (solicitud.estado) {
        'aprobado' => 'Aprobada',
        'entregado' => 'Entregada',
        'rechazado' => 'Rechazada',
        _ => 'Pendiente',
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final esPendiente = solicitud.estado == 'pendiente';
    final esAprobada = solicitud.estado == 'aprobado';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? Border.all(color: _estadoColor.withValues(alpha: 0.30))
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Solicitante + estado ──────────────────────────────────────
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _estadoColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    solicitud.solicitanteNombre.isNotEmpty
                        ? solicitud.solicitanteNombre[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: _estadoColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(solicitud.solicitanteNombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('${solicitud.proyectoNombre} · ${solicitud.fecha}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _estadoColor.withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_estadoLabel,
                    style: TextStyle(
                        color: _estadoColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ── Items ─────────────────────────────────────────────────────
          ...solicitud.items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        size: 7, color: _kGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(it.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text(
                      '${it.cantidadAprobada ?? it.cantidad} ${it.unidad}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )),

          // ── Observaciones ─────────────────────────────────────────────
          if (solicitud.observacion != null &&
              solicitud.observacion!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Nota: ${solicitud.observacion}',
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                    fontStyle: FontStyle.italic)),
          ],
          if (solicitud.observacionLogistico != null &&
              solicitud.observacionLogistico!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Logística: ${solicitud.observacionLogistico}',
                style: const TextStyle(
                    color: _kRed,
                    fontSize: 11,
                    fontStyle: FontStyle.italic)),
          ],

          // ── Acciones ──────────────────────────────────────────────────
          if (esPendiente || esAprobada) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (esPendiente) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRechazar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kRed,
                        side: const BorderSide(color: _kRed),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Rechazar',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onAprobar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Aprobar',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onEntregar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.local_shipping_outlined, size: 16),
                      label: const Text('Marcar como entregado',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

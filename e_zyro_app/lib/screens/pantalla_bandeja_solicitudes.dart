import 'package:flutter/material.dart';
import '../models/solicitud_models.dart';
import '../services/solicitud_service.dart';

/// Bandeja de RR.HH. para revisar solicitudes del personal: justificaciones
/// (tardanza/falta), permisos y trámites. Aprobar / rechazar con observación.
class PantallaBandejaSolicitudes extends StatefulWidget {
  const PantallaBandejaSolicitudes({super.key});

  @override
  State<PantallaBandejaSolicitudes> createState() =>
      _PantallaBandejaSolicitudesState();
}

class _PantallaBandejaSolicitudesState
    extends State<PantallaBandejaSolicitudes> with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF8FD11B);

  late final TabController _tab;
  SolicitudService? _svc;
  bool _cargando = true;
  List<SolicitudLaboral> _todas = [];
  String _estadoFiltro = 'pendiente'; // pendiente | aprobada | rechazada | ''

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getSolicitudService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() => _cargando = true);
    final items = await _svc!.bandeja(estado: _estadoFiltro);
    if (!mounted) return;
    setState(() {
      _todas = items;
      _cargando = false;
    });
  }

  List<SolicitudLaboral> _porCategoria(CategoriaSolicitud c) =>
      _todas.where((s) => s.categoria == c).toList();

  Future<void> _evaluar(SolicitudLaboral s) async {
    final obsCtrl = TextEditingController();
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.tipoLabel, style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.empleadoNombre != null)
              Text(s.empleadoNombre!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(s.descripcion, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: obsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observación (obligatoria)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'rechazada'),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Rechazar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'aprobada'),
            style: FilledButton.styleFrom(backgroundColor: _green),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
    if (accion == null || !mounted) return;
    if (obsCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La observación es obligatoria')));
      return;
    }
    final res = await _svc!
        .evaluar(s.id, estado: accion, observacion: obsCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.mensaje),
        backgroundColor: res.ok ? _green : Colors.red.shade700));
    if (res.ok) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitudes del personal',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tab,
          labelColor: _green,
          indicatorColor: _green,
          tabs: const [
            Tab(text: 'Justificaciones'),
            Tab(text: 'Permisos'),
            Tab(text: 'Trámites'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Filtrar por estado',
            icon: const Icon(Icons.filter_list),
            onSelected: (v) {
              _estadoFiltro = v;
              _cargar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pendiente', child: Text('Pendientes')),
              PopupMenuItem(value: 'aprobada', child: Text('Aprobadas')),
              PopupMenuItem(value: 'rechazada', child: Text('Rechazadas')),
              PopupMenuItem(value: '', child: Text('Todas')),
            ],
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_green)))
          : TabBarView(
              controller: _tab,
              children: [
                _lista(_porCategoria(CategoriaSolicitud.justificacion)),
                _lista(_porCategoria(CategoriaSolicitud.permiso)),
                _lista(_porCategoria(CategoriaSolicitud.tramite)),
              ],
            ),
    );
  }

  Widget _lista(List<SolicitudLaboral> items) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: _green,
        onRefresh: _cargar,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('Sin solicitudes', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _green,
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: items.length,
        itemBuilder: (_, i) => _tarjeta(items[i]),
      ),
    );
  }

  Widget _tarjeta(SolicitudLaboral s) {
    final Color color;
    final String estadoLabel;
    switch (s.estado) {
      case 'aprobada':
        color = _green;
        estadoLabel = 'Aprobada';
        break;
      case 'rechazada':
        color = Colors.red;
        estadoLabel = 'Rechazada';
        break;
      default:
        color = Colors.orange;
        estadoLabel = 'Pendiente';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _green.withValues(alpha: 0.15),
                  backgroundImage: (s.empleadoFotoUrl ?? '').isNotEmpty
                      ? NetworkImage(s.empleadoFotoUrl!)
                      : null,
                  child: (s.empleadoFotoUrl ?? '').isEmpty
                      ? Text(s.empleadoIniciales ?? '?',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5E9A1C)))
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.empleadoNombre ?? 'Empleado',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13.5)),
                      Text(
                          [s.empleadoCargo, s.empleadoArea]
                              .where((x) => (x ?? '').isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(estadoLabel,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(s.tipoLabel,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Text(s.descripcion, style: const TextStyle(fontSize: 12.5)),
            if ((s.observacion ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('RR.HH.: ${s.observacion}',
                  style: TextStyle(fontSize: 11.5, color: color)),
            ],
            if (s.esPendiente) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _evaluar(s),
                  icon: const Icon(Icons.gavel_outlined, size: 16),
                  label: const Text('Evaluar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: const BorderSide(color: _green),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/historial_models.dart';
import '../services/historial_service.dart';
import '../utils/api_provider.dart';

// HU-45: Historial de Participación — proyectos cerrados donde el empleado
// logueado fue miembro.
class PantallaHistorialProyectos extends StatefulWidget {
  const PantallaHistorialProyectos({super.key});

  @override
  State<PantallaHistorialProyectos> createState() =>
      _PantallaHistorialProyectosState();
}

class _PantallaHistorialProyectosState
    extends State<PantallaHistorialProyectos> {
  HistorialService? _service;
  List<ProyectoHistorial> _historial = [];
  bool _loading = true;

  static const _green = Color(0xFF8FD11B);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getHistorialService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _loading = true);
    final data = await _service!.getMisProyectosHistorial();
    if (!mounted) return;
    setState(() {
      _historial = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Historial de Proyectos'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_green),
              ),
            )
          : _historial.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _green,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    itemCount: _historial.length,
                    itemBuilder: (_, i) => _ProyectoCard(
                      item: _historial[i],
                      isDark: isDark,
                      surface: surface,
                    ),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Sin proyectos en tu historial',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Los proyectos en los que participaste\naparecerán aquí al cerrarse',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ProyectoCard extends StatelessWidget {
  final ProyectoHistorial item;
  final bool isDark;
  final Color surface;

  const _ProyectoCard({
    required this.item,
    required this.isDark,
    required this.surface,
  });

  static const _green = Color(0xFF8FD11B);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: _green.withValues(alpha: 0.20)) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.nombreProyecto,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Completado',
                  style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _InfoRow(icon: Icons.business_outlined, label: item.cliente),
          if (item.rolProyecto != null && item.rolProyecto!.isNotEmpty) ...[
            const SizedBox(height: 3),
            _InfoRow(icon: Icons.badge_outlined, label: item.rolProyecto!),
          ],
          if (item.fechaFinReal != null) ...[
            const SizedBox(height: 3),
            _InfoRow(icon: Icons.event_available_outlined, label: 'Cerrado: ${item.fechaFinReal}'),
          ],
          const SizedBox(height: 3),
          _InfoRow(icon: Icons.numbers_outlined, label: 'OT ${item.ordenTrabajo}'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

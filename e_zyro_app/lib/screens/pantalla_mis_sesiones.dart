import 'package:flutter/material.dart';
import '../models/seguridad_models.dart';
import '../services/seguridad_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../widgets/topo_background.dart';

const _kGreen = Color(0xFF8FD11B);
const _kAmber = Color(0xFFF59E0B);
const _kBlue  = Color(0xFF3B82F6);
const _kGray  = Color(0xFF6B7280);

class PantallaMisSesiones extends StatefulWidget {
  const PantallaMisSesiones({super.key});

  @override
  State<PantallaMisSesiones> createState() => _PantallaMisSesionesState();
}

class _PantallaMisSesionesState extends State<PantallaMisSesiones> {
  SeguridadService? _service;
  List<SesionConexion> _sesiones = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getSeguridadService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _loading = true);
    final data = await _service!.getMisSesiones();
    if (!mounted) return;
    setState(() {
      _sesiones = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activas = _sesiones.where((s) => s.activa).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis conexiones',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            if (!_loading)
              Text('$activas activa${activas == 1 ? '' : 's'} · ${_sesiones.length} total',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16, amp: 9, stroke: 0.38, speed: 0.45,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kGreen))
            : _sesiones.isEmpty
                ? _buildEmpty()
                : RefreshIndicator(
                    onRefresh: _load,
                    color: _kGreen,
                    child: ListView.separated(
                      padding: bottomSafePadding(context, top: 10, extra: 24),
                      itemCount: _sesiones.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => SesionCard(item: _sesiones[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other_rounded, size: 52, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            const Text('Sin sesiones registradas',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kGreen),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh_rounded, color: _kGreen, size: 16),
              label: const Text('Actualizar', style: TextStyle(color: _kGreen)),
            ),
          ],
        ),
      );
}

// ─── Tarjeta de sesión (reutilizada por pantalla_personal.dart) ────────────────

class SesionCard extends StatelessWidget {
  final SesionConexion item;
  const SesionCard({super.key, required this.item});

  ({String marca, IconData icon}) get _device {
    final ua = item.userAgent.toLowerCase();
    if (ua.contains('android')) return (marca: 'Android', icon: Icons.android_rounded);
    if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('darwin')) {
      return (marca: 'iOS', icon: Icons.phone_iphone_rounded);
    }
    if (ua.contains('windows'))  return (marca: 'Windows',  icon: Icons.laptop_windows_rounded);
    if (ua.contains('mac os'))   return (marca: 'macOS',    icon: Icons.laptop_mac_rounded);
    if (ua.contains('linux'))    return (marca: 'Linux',    icon: Icons.computer_rounded);
    if (ua.contains('mozilla') || ua.contains('chrome') || ua.contains('safari')) {
      return (marca: 'Navegador', icon: Icons.public_rounded);
    }
    return (marca: 'Otro', icon: Icons.devices_rounded);
  }

  ({String label, Color color, IconData icon}) get _estado {
    if (item.esActual) return (label: 'Esta sesión', color: _kBlue,  icon: Icons.fiber_manual_record);
    if (item.activa)   return (label: 'Activa',      color: _kGreen, icon: Icons.check_circle_outline);
    if (item.fechaCierre != null) {
      return (label: 'Cerrada', color: _kGray, icon: Icons.logout_rounded);
    }
    return (label: 'Expirada', color: _kAmber, icon: Icons.hourglass_disabled_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final dev = _device;
    final est = _estado;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: item.esActual
            ? Border.all(color: _kBlue.withValues(alpha: 0.4), width: 1.5)
            : (isDark ? Border.all(color: Colors.white.withValues(alpha: 0.08)) : null),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: est.color.withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(dev.icon, color: est.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dev.marca,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(item.ip.isEmpty ? '—' : 'IP: ${item.ip}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: est.color.withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(est.icon, size: 11, color: est.color),
                  const SizedBox(width: 4),
                  Text(est.label,
                      style: TextStyle(
                          color: est.color, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
          if (item.userAgent.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(item.userAgent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 11, height: 1.3)),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.login_rounded, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text(item.fechaInicio.isEmpty ? '—' : item.fechaInicio,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const Spacer(),
            if (item.fechaCierre != null) ...[
              const Icon(Icons.logout_rounded, size: 12, color: _kGray),
              const SizedBox(width: 4),
              Text(item.fechaCierre!,
                  style: const TextStyle(fontSize: 11, color: _kGray)),
            ] else ...[
              const Icon(Icons.hourglass_top_rounded, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Text('Expira ${item.fechaExpiracion}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ]),
        ],
      ),
    );
  }
}

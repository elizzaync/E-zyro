import 'package:flutter/material.dart';
import '../models/requerimiento_models.dart';
import '../services/requerimiento_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';
import 'pantalla_solicitudes_logistica.dart';
import 'pantalla_movimientos_logistica.dart';
import 'pantalla_materiales_logistica.dart';
import 'pantalla_compras_logistica.dart';
import 'pantalla_proveedores_logistica.dart';
import 'pantalla_transferencias_logistica.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kBlue = Color(0xFF3B82F6);

/// Panel del encargado de logística — dashboard de inventario + accesos a la
/// gestión (solicitudes, movimientos, compras, etc.). Cada acceso se irá
/// activando por fases.
class PantallaInventarioPanel extends StatefulWidget {
  const PantallaInventarioPanel({super.key});

  @override
  State<PantallaInventarioPanel> createState() =>
      _PantallaInventarioPanelState();
}

class _PantallaInventarioPanelState extends State<PantallaInventarioPanel> {
  RequerimientoService? _service;
  InventarioResumen _resumen = const InventarioResumen();
  bool _isLoading = true;

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
    final r = await _service!.getResumenInventario();
    if (!mounted) return;
    setState(() {
      _resumen = r;
      _isLoading = false;
    });
  }

  void _proximamente(String funcion) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$funcion estará disponible próximamente'),
        backgroundColor: _kAmber,
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
        title: const Text('Panel de Logística',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16,
        amp: 9,
        stroke: 0.38,
        speed: 0.45,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: _kGreen))
            : RefreshIndicator(
                onRefresh: _load,
                color: _kGreen,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildKpis(isDark),
                      const SizedBox(height: 22),
                      _buildGestion(isDark),
                      const SizedBox(height: 22),
                      _buildAlertas(isDark),
                      const SizedBox(height: 22),
                      _buildIaPlaceholder(isDark),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ── KPIs ────────────────────────────────────────────────────────────────────
  Widget _buildKpis(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            icon: Icons.inventory_2_outlined,
            color: _kBlue,
            value: '${_resumen.totalItems}',
            label: 'Items totales',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            icon: Icons.warning_amber_rounded,
            color: _kAmber,
            value: '${_resumen.bajoStock}',
            label: 'Bajo stock',
            highlight: _resumen.bajoStock > 0,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            icon: Icons.remove_shopping_cart_outlined,
            color: _kRed,
            value: '${_resumen.sinStock}',
            label: 'Sin stock',
            highlight: _resumen.sinStock > 0,
          ),
        ),
      ],
    );
  }

  // ── Accesos de gestión ────────────────────────────────────────────────────
  Widget _buildGestion(bool isDark) {
    final accesos = <_AccesoData>[
      _AccesoData(
        icon: Icons.inbox_outlined,
        color: _kGreen,
        label: 'Solicitudes',
        subtitle: 'Aprobar / entregar',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PantallaSolicitudesLogistica(),
          ),
        ),
      ),
      _AccesoData(
        icon: Icons.swap_vert_rounded,
        color: _kBlue,
        label: 'Movimientos',
        subtitle: 'Ajuste de stock',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PantallaMovimientosLogistica(),
          ),
        ),
      ),
      _AccesoData(
        icon: Icons.shopping_cart_checkout_rounded,
        color: const Color(0xFF8B5CF6),
        label: 'Compras',
        subtitle: 'Órdenes',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PantallaComprasLogistica(),
          ),
        ),
      ),
      _AccesoData(
        icon: Icons.local_shipping_outlined,
        color: _kAmber,
        label: 'Proveedores',
        subtitle: 'Directorio',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PantallaProveedoresLogistica(),
          ),
        ),
      ),
      _AccesoData(
        icon: Icons.compare_arrows_rounded,
        color: const Color(0xFF06B6D4),
        label: 'Transferencias',
        subtitle: 'Entre almacenes',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PantallaTransferenciasLogistica(),
          ),
        ),
      ),
      _AccesoData(
        icon: Icons.category_outlined,
        color: const Color(0xFFEC4899),
        label: 'Materiales',
        subtitle: 'Editar / categorías',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PantallaMaterialesLogistica(),
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Gestión'),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
          ),
          itemCount: accesos.length,
          itemBuilder: (_, i) => _AccesoCard(data: accesos[i], isDark: isDark),
        ),
      ],
    );
  }

  // ── Alertas de bajo stock ─────────────────────────────────────────────────
  Widget _buildAlertas(bool isDark) {
    final surface = Theme.of(context).colorScheme.surface;
    final items = _resumen.itemsBajoStock;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle('Alertas de bajo stock'),
            const Spacer(),
            if (items.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${items.length}',
                    style: const TextStyle(
                        color: _kRed,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: isDark
                  ? Border.all(color: _kGreen.withValues(alpha: 0.25))
                  : null,
            ),
            child: Column(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 36, color: _kGreen.withValues(alpha: 0.7)),
                const SizedBox(height: 8),
                const Text('Todo el inventario está por encima del mínimo',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          )
        else
          ...items.map((m) => _AlertaCard(item: m, isDark: isDark)),
      ],
    );
  }

  // ── Placeholder IA de predicción ──────────────────────────────────────────
  Widget _buildIaPlaceholder(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A2A0A), const Color(0xFF0D1A06)]
              : [const Color(0xFFF0FAE0), const Color(0xFFE6F5D0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: _kGreen, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text('Predicción de stock con IA',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Pronto',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Anticipará faltantes de material según el consumo histórico y los servicios programados.',
                  style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      fontSize: 12,
                      height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      );
}

// ── KPI card ───────────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final bool highlight;

  const _KpiCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: highlight
            ? color.withValues(alpha: isDark ? 0.15 : 0.10)
            : surface,
        borderRadius: BorderRadius.circular(14),
        border: highlight
            ? Border.all(color: color.withValues(alpha: 0.4))
            : (isDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                : null),
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
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ── Acceso de gestión ───────────────────────────────────────────────────────────
class _AccesoData {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _AccesoData({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
}

class _AccesoCard extends StatelessWidget {
  final _AccesoData data;
  final bool isDark;
  const _AccesoCard({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return GestureDetector(
      onTap: data.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.08))
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: isDark ? 0.18 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(data.icon, color: data.color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(data.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 1),
            Text(data.subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ── Card de alerta de bajo stock ──────────────────────────────────────────────
class _AlertaCard extends StatelessWidget {
  final MaterialBajoStock item;
  final bool isDark;
  const _AlertaCard({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final agotado = item.stock == 0;
    final color = agotado ? _kRed : _kAmber;
    final ratio = item.minimo > 0
        ? (item.stock / item.minimo).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.35 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    if (item.categoria != null) ...[
                      const SizedBox(height: 2),
                      Text(item.categoria!,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(agotado ? 'Agotado' : 'Bajo stock',
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor:
                  isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Stock: ${item.stock} ${item.unidad}',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              Text('Mín: ${item.minimo} ${item.unidad}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

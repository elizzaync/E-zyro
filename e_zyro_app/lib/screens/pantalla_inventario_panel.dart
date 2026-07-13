import 'package:flutter/material.dart';
import '../models/requerimiento_models.dart';
import '../services/requerimiento_service.dart';
import '../utils/api_provider.dart';
import '../theme/ez_theme.dart';
import 'pantalla_movimientos_logistica.dart';
import 'pantalla_materiales_logistica.dart';
import 'pantalla_compras_logistica.dart';
import 'pantalla_proveedores_logistica.dart';
import 'pantalla_equipos_logistica.dart';
import 'pantalla_epp.dart';
import 'logistica/almacen/pantalla_requerimientos_logistica.dart';
import 'logistica/almacen/pantalla_transferencias_almacen.dart';
import 'logistica/pantalla_ingreso_directo.dart';

/// Panel del encargado de logística — dashboard de inventario + accesos a la
/// gestión. Migrado del estilo "Paper Dots" al Sistema de Diseño E-Zyro
/// (Paper se elimina, no se funde — ver lib/widgets/paper.dart).
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

  @override
  Widget build(BuildContext context) {
    final ez = context.ez;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Logística'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHero(ez),
                    const SizedBox(height: EzSpace.x4),
                    _buildKpis(ez),
                    const SizedBox(height: EzSpace.x6),
                    _sectionHeader(ez, 'Gestión', '09 áreas'),
                    const SizedBox(height: EzSpace.x3),
                    _buildGestion(ez),
                    const SizedBox(height: EzSpace.x6),
                    _buildAlertas(ez),
                    const SizedBox(height: EzSpace.x6),
                    _buildIaPlaceholder(ez),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Encabezado de sección reutilizable ─────────────────────────────────────
  Widget _sectionHeader(EzColors ez, String title, String? trailing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (trailing != null)
          Text(trailing,
              style: TextStyle(
                  fontFamily: EzType.mono, fontSize: 12, color: ez.inkMuted)),
      ],
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────
  Widget _buildHero(EzColors ez) {
    final bajo = _resumen.bajoStock;
    final sin = _resumen.sinStock;
    final todoOk = bajo == 0 && sin == 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Panel de Logística',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: EzSpace.x2),
              Text(
                todoOk
                    ? '${_resumen.totalItems} materiales en bodega · todo en orden.'
                    : '$bajo bajo el mínimo${sin > 0 ? ', $sin agotado' : ''}.',
                style: TextStyle(color: ez.inkSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: EzSpace.x2),
        todoOk
            ? EzStatusChip.success('Al día')
            : EzStatusChip.warning('Revisar'),
      ],
    );
  }

  // ── KPIs ────────────────────────────────────────────────────────────────────
  Widget _buildKpis(EzColors ez) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _KpiCard(
            icon: Icons.inventory_2_outlined,
            value: '${_resumen.totalItems}',
            label: 'Items',
            sub: 'totales',
          ),
        ),
        const SizedBox(width: EzSpace.x2),
        Expanded(
          child: _KpiCard(
            icon: Icons.warning_amber_rounded,
            value: '${_resumen.bajoStock}',
            label: 'Bajo stock',
            sub: _resumen.bajoStock > 0 ? 'bajo mínimo' : 'sin alerta',
            tint: _resumen.bajoStock > 0 ? ez.warning : null,
          ),
        ),
        const SizedBox(width: EzSpace.x2),
        Expanded(
          child: _KpiCard(
            icon: Icons.remove_shopping_cart_outlined,
            value: '${_resumen.sinStock}',
            label: 'Sin stock',
            sub: _resumen.sinStock > 0 ? 'agotado' : 'todo OK',
            tint: _resumen.sinStock > 0 ? ez.danger : null,
          ),
        ),
      ],
    );
  }

  // ── Accesos de gestión ────────────────────────────────────────────────────
  Widget _buildGestion(EzColors ez) {
    final accesos = <_AccesoData>[
      _AccesoData(
        icon: Icons.inbox_outlined,
        color: ez.brand,
        label: 'Requerimientos',
        subtitle: 'Materiales y equipos',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaRequerimientosLogistica())),
      ),
      _AccesoData(
        icon: Icons.swap_vert_rounded,
        color: ez.info,
        label: 'Movimientos',
        subtitle: 'Ajuste de stock',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaMovimientosLogistica())),
      ),
      _AccesoData(
        icon: Icons.shopping_cart_checkout_rounded,
        color: ez.accentStrong,
        label: 'Compras',
        subtitle: 'Tickets',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaComprasLogistica())),
      ),
      _AccesoData(
        icon: Icons.category_outlined,
        color: ez.danger,
        label: 'Materiales',
        subtitle: 'Editar / categorías',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaMaterialesLogistica())),
      ),
      _AccesoData(
        icon: Icons.precision_manufacturing_outlined,
        color: ez.brand,
        label: 'Equipos',
        subtitle: 'Equipos y herram.',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaEquiposLogistica())),
      ),
      _AccesoData(
        icon: Icons.health_and_safety_outlined,
        color: ez.danger,
        label: 'EPP',
        subtitle: 'Protección personal',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaEpp())),
      ),
      _AccesoData(
        icon: Icons.local_shipping_outlined,
        color: ez.warning,
        label: 'Proveedores',
        subtitle: 'Directorio',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaProveedoresLogistica())),
      ),
      _AccesoData(
        icon: Icons.compare_arrows_rounded,
        color: ez.brand,
        label: 'Transferencias',
        subtitle: 'Entre almacenes',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaTransferenciasAlmacen())),
      ),
      _AccesoData(
        icon: Icons.move_to_inbox_outlined,
        color: ez.info,
        label: 'Ingreso Directo',
        subtitle: 'Alta de artículos',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaIngresoDirecto())),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: accesos.length,
      itemBuilder: (_, i) => _AccesoCard(data: accesos[i]),
    );
  }

  // ── Alertas de bajo stock ─────────────────────────────────────────────────
  Widget _buildAlertas(EzColors ez) {
    final items = _resumen.itemsBajoStock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(ez, 'Alertas de bajo stock',
            items.isEmpty ? null : '${items.length} items'),
        const SizedBox(height: EzSpace.x3),
        if (items.isEmpty)
          EzCard(
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 28, color: ez.success),
                const SizedBox(width: EzSpace.x3),
                Expanded(
                  child: Text(
                    'Todo el inventario está por encima del mínimo.',
                    style: TextStyle(color: ez.inkSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else
          ...items.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: EzSpace.x2),
                child: _AlertaCard(item: m),
              )),
      ],
    );
  }

  // ── Placeholder IA de predicción ──────────────────────────────────────────
  Widget _buildIaPlaceholder(EzColors ez) {
    return EzCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ez.accentSoft,
              borderRadius: EzRadius.r(EzRadius.md),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: ez.accentStrong, size: 22),
          ),
          const SizedBox(width: EzSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('Predicción de stock con IA',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: ez.ink)),
                    ),
                    const SizedBox(width: EzSpace.x2),
                    EzStatusChip('Pronto', status: EzStatus.info),
                  ],
                ),
                const SizedBox(height: EzSpace.x1),
                Text(
                  'Anticipará faltantes según el consumo histórico y los servicios programados.',
                  style: TextStyle(color: ez.inkSecondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── KPI card ─────────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String sub;
  final Color? tint;

  const _KpiCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.sub,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final ez = context.ez;
    return EzCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tint ?? ez.brand),
          const SizedBox(height: EzSpace.x2),
          Text(value,
              style: TextStyle(
                  fontFamily: EzType.mono,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: ez.ink)),
          const SizedBox(height: EzSpace.x1),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ez.ink)),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: ez.inkMuted)),
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
  const _AccesoCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final ez = context.ez;
    return EzCard(
      onTap: data.onTap,
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.14),
              borderRadius: EzRadius.r(EzRadius.md),
            ),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const SizedBox(height: EzSpace.x2),
          Text(data.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ez.ink)),
          const SizedBox(height: 1),
          Text(data.subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: ez.inkMuted)),
        ],
      ),
    );
  }
}

// ── Card de alerta de bajo stock ──────────────────────────────────────────────
class _AlertaCard extends StatelessWidget {
  final MaterialBajoStock item;
  const _AlertaCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final ez = context.ez;
    final agotado = item.stock == 0;
    final color = agotado ? ez.danger : ez.warning;
    final ratio =
        item.minimo > 0 ? (item.stock / item.minimo).clamp(0.0, 1.0) : 0.0;

    return EzCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: EzRadius.r(EzRadius.sm),
                ),
                child: Icon(
                    agotado
                        ? Icons.remove_shopping_cart_outlined
                        : Icons.warning_amber_rounded,
                    color: color,
                    size: 18),
              ),
              const SizedBox(width: EzSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, color: ez.ink)),
                    if (item.categoria != null)
                      Text(item.categoria!,
                          style: TextStyle(color: ez.inkMuted, fontSize: 11)),
                  ],
                ),
              ),
              agotado
                  ? EzStatusChip.danger('Agotado')
                  : EzStatusChip.warning('Bajo'),
            ],
          ),
          const SizedBox(height: EzSpace.x3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: ez.canvasSunken,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: EzSpace.x2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Stock: ${item.stock} ${item.unidad}',
                  style: TextStyle(
                      fontFamily: EzType.mono,
                      color: ez.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              Text('Mín: ${item.minimo} ${item.unidad}',
                  style: TextStyle(fontFamily: EzType.mono, color: ez.inkMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

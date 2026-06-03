import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/requerimiento_models.dart';
import '../services/requerimiento_service.dart';
import '../utils/api_provider.dart';
import '../widgets/paper.dart';
import 'pantalla_solicitudes_logistica.dart';
import 'pantalla_movimientos_logistica.dart';
import 'pantalla_materiales_logistica.dart';
import 'pantalla_compras_logistica.dart';
import 'pantalla_proveedores_logistica.dart';
import 'pantalla_transferencias_logistica.dart';
import 'pantalla_prestamos_logistica.dart';
import 'pantalla_equipos_logistica.dart';
import 'pantalla_epp.dart';

/// Panel del encargado de logística — dashboard de inventario + accesos a la
/// gestión. Usa el estilo "Paper Dots" (bitácora) de forma permanente.
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(color: kPaperInk),
        title: Text('Panel de Logística',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700, fontSize: 18, color: kPaperInk)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: kPaperInk,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20, color: kPaperInk),
            onPressed: _load,
          ),
        ],
      ),
      body: PaperBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kPaperLimeDeep))
            : RefreshIndicator(
                onRefresh: _load,
                color: kPaperLimeDeep,
                backgroundColor: Colors.white,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHero(),
                      const SizedBox(height: 16),
                      _buildKpis(),
                      const SizedBox(height: 22),
                      const PaperSectionHeader(title: 'Gestión', trailing: '07 áreas'),
                      const SizedBox(height: 12),
                      _buildGestion(),
                      const SizedBox(height: 22),
                      _buildAlertas(),
                      const SizedBox(height: 22),
                      _buildIaPlaceholder(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────
  Widget _buildHero() {
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
              Text('Panel de\nLogística',
                  style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                      color: kPaperInk)),
              const SizedBox(height: 4),
              const PaperUnderline(width: 120),
              const SizedBox(height: 8),
              Text(
                todoOk
                    ? '${_resumen.totalItems} materiales en bodega · todo en orden.'
                    : '$bajo bajo el mínimo${sin > 0 ? ', $sin agotado' : ''}.',
                style: GoogleFonts.workSans(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: kPaperInkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PaperSticker(
          text: todoOk ? 'Al día' : 'Revisar',
          bg: todoOk ? kPaperLime : kPaperWarm,
          rotate: 5,
        ),
      ],
    );
  }

  // ── KPIs ────────────────────────────────────────────────────────────────────
  Widget _buildKpis() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PaperKpi(
            icon: Icons.inventory_2_outlined,
            value: '${_resumen.totalItems}',
            label: 'Items',
            sub: 'totales',
            rotate: -2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PaperKpi(
            icon: Icons.warning_amber_rounded,
            value: '${_resumen.bajoStock}',
            label: 'Bajo stock',
            sub: _resumen.bajoStock > 0 ? 'bajo mínimo' : 'sin alerta',
            bg: _resumen.bajoStock > 0 ? kPaperWarm : Colors.white,
            rotate: 1.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PaperKpi(
            icon: Icons.remove_shopping_cart_outlined,
            value: '${_resumen.sinStock}',
            label: 'Sin stock',
            sub: _resumen.sinStock > 0 ? 'agotado' : 'todo OK',
            bg: _resumen.sinStock > 0 ? kPaperRose : Colors.white,
            rotate: -1.2,
          ),
        ),
      ],
    );
  }

  // ── Accesos de gestión ────────────────────────────────────────────────────
  Widget _buildGestion() {
    final accesos = <_AccesoData>[
      _AccesoData(
        icon: Icons.inbox_outlined,
        color: kPaperLime,
        label: 'Solicitudes',
        subtitle: 'Aprobar / entregar',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaSolicitudesLogistica())),
      ),
      _AccesoData(
        icon: Icons.swap_vert_rounded,
        color: kPaperSky,
        label: 'Movimientos',
        subtitle: 'Ajuste de stock',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaMovimientosLogistica())),
      ),
      _AccesoData(
        icon: Icons.shopping_cart_checkout_rounded,
        color: kPaperLilac,
        label: 'Compras',
        subtitle: 'Tickets',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaComprasLogistica())),
      ),
      _AccesoData(
        icon: Icons.local_shipping_outlined,
        color: kPaperWarm,
        label: 'Proveedores',
        subtitle: 'Directorio',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaProveedoresLogistica())),
      ),
      _AccesoData(
        icon: Icons.compare_arrows_rounded,
        color: kPaperLime,
        label: 'Transferencias',
        subtitle: 'Entre almacenes',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaTransferenciasLogistica())),
      ),
      _AccesoData(
        icon: Icons.category_outlined,
        color: kPaperRose,
        label: 'Materiales',
        subtitle: 'Editar / categorías',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaMaterialesLogistica())),
      ),
      _AccesoData(
        icon: Icons.handyman_outlined,
        color: kPaperSky,
        label: 'Préstamos',
        subtitle: 'Equipos / herram.',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaPrestamosLogistica())),
      ),
      _AccesoData(
        icon: Icons.precision_manufacturing_outlined,
        color: kPaperLime,
        label: 'Equipos',
        subtitle: 'Equipos y herram.',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaEquiposLogistica())),
      ),
      _AccesoData(
        icon: Icons.health_and_safety_outlined,
        color: kPaperRose,
        label: 'EPP',
        subtitle: 'Protección personal',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PantallaEpp())),
      ),
    ];

    const rots = [-1.5, 1.5, -1.2, 1.5, -1.5, 1.5, -1.5];
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
      itemBuilder: (_, i) => _AccesoCard(data: accesos[i], rotate: rots[i % rots.length]),
    );
  }

  // ── Alertas de bajo stock ─────────────────────────────────────────────────
  Widget _buildAlertas() {
    final items = _resumen.itemsBajoStock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaperSectionHeader(
          title: 'Alertas de bajo stock',
          trailing: items.isEmpty ? null : '${items.length} items',
          underlineWidth: 120,
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          PaperCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 30, color: kPaperLimeDeep),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Todo el inventario está por encima del mínimo.',
                    style: GoogleFonts.workSans(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: kPaperInkSoft),
                  ),
                ),
              ],
            ),
          )
        else
          ...items.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AlertaCard(item: m),
              )),
      ],
    );
  }

  // ── Placeholder IA de predicción ──────────────────────────────────────────
  Widget _buildIaPlaceholder() {
    return PaperCard(
      bg: const Color(0xFFF1F6E4),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Transform.rotate(
            angle: -4 * 3.1415926 / 180,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kPaperLime,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPaperInk, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: kPaperInk, offset: Offset(2, 2), blurRadius: 0),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: kPaperInk, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('Predicción de stock con IA',
                          style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kPaperInk)),
                    ),
                    const SizedBox(width: 8),
                    const PaperSticker(text: 'Pronto', bg: kPaperWarm, rotate: 4),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Anticipará faltantes según el consumo histórico y los servicios programados.',
                  style: GoogleFonts.workSans(
                      color: kPaperInkSoft, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── KPI card (paper) ────────────────────────────────────────────────────────
class _PaperKpi extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String sub;
  final Color bg;
  final double rotate;

  const _PaperKpi({
    required this.icon,
    required this.value,
    required this.label,
    required this.sub,
    this.bg = Colors.white,
    this.rotate = 0,
  });

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      bg: bg,
      rotate: rotate,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 18, color: kPaperInk),
              Text('UNID.',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 9, letterSpacing: 1, color: kPaperInkSoft)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.outfit(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: kPaperInk)),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.workSans(
                  fontSize: 11, fontWeight: FontWeight.w700, color: kPaperInk)),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.workSans(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: kPaperInkSoft)),
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
  final double rotate;
  const _AccesoCard({required this.data, this.rotate = 0});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: data.onTap,
      child: PaperCard(
        rotate: rotate,
        radius: 14,
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.rotate(
              angle: -4 * 3.1415926 / 180,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: data.color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kPaperInk, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: kPaperInk, offset: Offset(2, 2), blurRadius: 0),
                  ],
                ),
                child: Icon(data.icon, color: kPaperInk, size: 22),
              ),
            ),
            const SizedBox(height: 9),
            Text(data.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: kPaperInk)),
            const SizedBox(height: 1),
            Text(data.subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.workSans(
                    fontSize: 9,
                    fontStyle: FontStyle.italic,
                    color: kPaperInkSoft)),
          ],
        ),
      ),
    );
  }
}

// ── Card de alerta de bajo stock (paper) ──────────────────────────────────────
class _AlertaCard extends StatelessWidget {
  final MaterialBajoStock item;
  const _AlertaCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final agotado = item.stock == 0;
    final color = agotado ? kPaperRose : kPaperWarm;
    final ratio =
        item.minimo > 0 ? (item.stock / item.minimo).clamp(0.0, 1.0) : 0.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Transform.rotate(
                    angle: -4 * 3.1415926 / 180,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kPaperInk, width: 1.5),
                      ),
                      child: Icon(
                          agotado
                              ? Icons.remove_shopping_cart_outlined
                              : Icons.warning_amber_rounded,
                          color: kPaperInk,
                          size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: kPaperInk)),
                        if (item.categoria != null)
                          Text(item.categoria!,
                              style: GoogleFonts.workSans(
                                  color: kPaperInkSoft,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  PaperSticker(
                    text: agotado ? 'Agotado' : 'Bajo',
                    bg: color,
                    rotate: 3,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 7,
                  backgroundColor: kPaperHair,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      agotado ? kPaperRose : kPaperLimeDeep),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Stock: ${item.stock} ${item.unidad}',
                      style: GoogleFonts.jetBrainsMono(
                          color: kPaperInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  Text('Mín: ${item.minimo} ${item.unidad}',
                      style: GoogleFonts.jetBrainsMono(
                          color: kPaperInkSoft, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        // Cinta washi decorativa
        Positioned(
          top: -6,
          left: 18,
          child: PaperTape(color: color, width: 46, rotate: -3),
        ),
      ],
    );
  }
}

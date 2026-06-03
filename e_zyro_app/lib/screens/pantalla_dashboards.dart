import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analitica_models.dart';
import '../services/analitica_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';

/// Dashboards ejecutivos — 4 tabs (Operaciones · Logística · Personal · Activos).
class PantallaDashboards extends StatefulWidget {
  const PantallaDashboards({super.key});
  @override
  State<PantallaDashboards> createState() => _PantallaDashboardsState();
}

class _PantallaDashboardsState extends State<PantallaDashboards>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF8FD11B);

  // Paleta para gráficos (consistente, legible en claro/oscuro)
  static const _palette = [
    Color(0xFF8FD11B), Color(0xFF1E88E5), Color(0xFFF59E0B),
    Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF14B8A6),
    Color(0xFFEC4899), Color(0xFF64748B),
  ];

  late final TabController _tab;
  AnaliticaService? _svc;

  DashOperaciones? _op;
  DashLogistica? _log;
  DashPersonal? _per;
  DashActivos? _act;
  bool _loading = true;
  bool _sinPermiso = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getAnaliticaService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() => _loading = true);
    final res = await Future.wait([
      _svc!.operaciones(),
      _svc!.logistica(),
      _svc!.personal(),
      _svc!.activos(),
    ]);
    if (!mounted) return;
    setState(() {
      _op = res[0] as DashOperaciones?;
      _log = res[1] as DashLogistica?;
      _per = res[2] as DashPersonal?;
      _act = res[3] as DashActivos?;
      // Si todo vino nulo (sin permiso o error), marcar
      _sinPermiso = _op == null && _log == null && _per == null && _act == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Dashboards',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
              onPressed: _loading ? null : _cargar,
              icon: const Icon(Icons.refresh, color: _green)),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: _green,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _green,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Operaciones'),
            Tab(text: 'Logística'),
            Tab(text: 'Personal'),
            Tab(text: 'Activos'),
          ],
        ),
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16, amp: 9, stroke: 0.36, speed: 0.4,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _green))
            : _sinPermiso
                ? _mensaje(Icons.lock_outline_rounded,
                    'No tienes permiso para ver los dashboards.')
                : TabBarView(
                    controller: _tab,
                    children: [
                      _tabOperaciones(),
                      _tabLogistica(),
                      _tabPersonal(),
                      _tabActivos(),
                    ],
                  ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // TABS
  // ════════════════════════════════════════════════════════════════════════
  Widget _tabOperaciones() {
    final d = _op;
    if (d == null) return _mensaje(Icons.bar_chart_outlined, 'Sin datos.');
    return _scroll([
      _kpiGrid([
        _Kpi('Proyectos activos', '${d.proyectosActivos}', Icons.work_outline, _palette[1]),
        _Kpi('Servicios', '${d.serviciosTotal}', Icons.build_outlined, _green),
        _Kpi('Cumplimiento', '${d.tasaCumplimiento}%', Icons.check_circle_outline, _palette[5]),
        _Kpi('Clientes', '${d.clientes}', Icons.apartment_outlined, _palette[4]),
      ]),
      _donutCard('Servicios por estado', d.porEstado),
      _rankCard('Servicios por cliente', d.porCliente, Icons.apartment_outlined),
      _trendCard(
        'Tendencia de servicios (6 meses)',
        d.tendencia.map((e) => Punto(e.label, e.total)).toList(),
        serie2: d.tendencia.map((e) => Punto(e.label, e.completados)).toList(),
        serie1Label: 'Total',
        serie2Label: 'Completados',
      ),
    ]);
  }

  Widget _tabLogistica() {
    final d = _log;
    if (d == null) return _mensaje(Icons.inventory_2_outlined, 'Sin datos.');
    return _scroll([
      _kpiGrid([
        _Kpi('Items', '${d.items}', Icons.inventory_2_outlined, _green),
        _Kpi('Unidades', _miles(d.unidades), Icons.numbers_outlined, _palette[1]),
        _Kpi('Bajo mínimo', '${d.bajo}', Icons.warning_amber_rounded, _palette[2]),
        _Kpi('Agotados', '${d.agotado}', Icons.remove_shopping_cart_outlined, _palette[3]),
        _Kpi('Equipos', '${d.equipos}', Icons.handyman_outlined, _palette[4]),
        _Kpi('Valor inv.', 'S/ ${_miles(d.valor.round())}', Icons.payments_outlined, _palette[5]),
      ]),
      _donutCard('Salud del stock', d.stockHealth,
          colores: [_green, _palette[2], _palette[3]]),
      _donutCard('Equipos por clase', d.equiposPorClase),
      _rankCard('Top materiales por stock', d.topStock, Icons.inventory_outlined),
      _rankCard('Categorías con más items', d.topCategorias, Icons.category_outlined),
    ]);
  }

  Widget _tabPersonal() {
    final d = _per;
    if (d == null) return _mensaje(Icons.groups_2_outlined, 'Sin datos.');
    return _scroll([
      _kpiGrid([
        _Kpi('Empleados', '${d.empleados}', Icons.badge_outlined, _green),
        _Kpi('Asist. mes', '${d.asistenciasMes}', Icons.event_available_outlined, _palette[1]),
        _Kpi('Asist. total', _miles(d.asistenciasTotal), Icons.fact_check_outlined, _palette[5]),
        _Kpi('Áreas', '${d.areas}', Icons.account_tree_outlined, _palette[4]),
      ]),
      _trendCard('Asistencia diaria (30 días)', d.asistenciaDiaria, area: true),
      _donutCard('Empleados por área', d.porArea),
      _rankCard('Top asistencia del mes', d.topAsistencia, Icons.emoji_events_outlined),
    ]);
  }

  Widget _tabActivos() {
    final d = _act;
    if (d == null) return _mensaje(Icons.precision_manufacturing_outlined, 'Sin datos.');
    return _scroll([
      _kpiGrid([
        _Kpi('Equipos', '${d.equipos}', Icons.precision_manufacturing_outlined, _green),
        _Kpi('Operativos', '${d.operativos}', Icons.check_circle_outline, _palette[5]),
        _Kpi('Mantenim.', '${d.mantenimiento}', Icons.build_circle_outlined, _palette[2]),
        _Kpi('Intervenidos', '${d.intervenidos}', Icons.electrical_services_outlined, _palette[1]),
        _Kpi('ITSE', '${d.itse}', Icons.fact_check_outlined, _palette[4]),
        _Kpi('Entregas EPP', '${d.eppEntregas}', Icons.health_and_safety_outlined, _palette[7]),
      ]),
      _donutCard('Equipos por estado', d.porEstado,
          colores: [_green, _palette[2], _palette[3], _palette[7]]),
      _donutCard('Equipos por clase', d.porClase),
      _trendCard('Inspecciones ITSE por mes', d.itsePorMes),
      _rankCard('Equipos intervenidos por ubicación', d.intervenidosPorUbicacion,
          Icons.location_on_outlined),
    ]);
  }

  // ════════════════════════════════════════════════════════════════════════
  // WIDGETS REUTILIZABLES
  // ════════════════════════════════════════════════════════════════════════
  Widget _scroll(List<Widget> children) => RefreshIndicator(
        onRefresh: _cargar,
        color: _green,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: children,
        ),
      );

  Widget _mensaje(IconData icon, String txt) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(txt, style: const TextStyle(color: Colors.grey)),
        ]),
      );

  Color get _surface => Theme.of(context).colorScheme.surface;

  Widget _card({required String title, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: _green.withValues(alpha: 0.12)) : null,
        boxShadow: isDark
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── KPI grid ──────────────────────────────────────────────────────────────
  Widget _kpiGrid(List<_Kpi> kpis) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: kpis.map(_kpiCard).toList(),
    );
  }

  Widget _kpiCard(_Kpi k) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: k.color.withValues(alpha: 0.20)) : null,
        boxShadow: isDark
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: k.color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(k.icon, color: k.color, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(k.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(k.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Donut (PieChart) + leyenda ─────────────────────────────────────────────
  Widget _donutCard(String title, List<Punto> pts, {List<Color>? colores}) {
    final data = pts.where((p) => p.value > 0).toList();
    if (data.isEmpty) {
      return _card(title: title, child: _emptyChart());
    }
    final total = data.fold<double>(0, (a, p) => a + p.value);
    final cols = colores ?? _palette;
    return _card(
      title: title,
      child: Row(
        children: [
          SizedBox(
            width: 130, height: 130,
            child: PieChart(PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 38,
              sections: [
                for (var i = 0; i < data.length; i++)
                  PieChartSectionData(
                    value: data[i].value.toDouble(),
                    color: cols[i % cols.length],
                    radius: 26,
                    title: '${((data[i].value / total) * 100).round()}%',
                    titleStyle: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
              ],
            )),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < data.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(width: 11, height: 11,
                          decoration: BoxDecoration(
                              color: cols[i % cols.length],
                              borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(data[i].label,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                      ),
                      Text('${data[i].value.toInt()}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Ranking horizontal (barras proporcionales) ────────────────────────────
  Widget _rankCard(String title, List<Punto> pts, IconData icon) {
    final data = pts.where((p) => p.value > 0).toList();
    if (data.isEmpty) return _card(title: title, child: _emptyChart());
    final maxv = data.fold<double>(0, (a, p) => p.value > a ? p.value.toDouble() : a);
    return _card(
      title: title,
      child: Column(
        children: [
          for (var i = 0; i < data.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(data[i].label,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 8),
                    Text(_miles(data[i].value.toInt()),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: maxv > 0 ? (data[i].value / maxv) : 0,
                      minHeight: 7,
                      backgroundColor: Colors.grey.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(_palette[i % _palette.length]),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Tendencia (LineChart, 1 o 2 series) ────────────────────────────────────
  Widget _trendCard(String title, List<Punto> serie1,
      {List<Punto>? serie2, String? serie1Label, String? serie2Label, bool area = false}) {
    final data = serie1;
    if (data.isEmpty) return _card(title: title, child: _emptyChart());
    final maxY = [
      ...data.map((e) => e.value),
      ...(serie2 ?? const <Punto>[]).map((e) => e.value),
    ].fold<double>(0, (a, v) => v > a ? v.toDouble() : a);
    final step = (data.length / 5).ceil().clamp(1, 999);

    LineChartBarData barOf(List<Punto> pts, Color c, bool fill) => LineChartBarData(
          spots: [for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].value.toDouble())],
          isCurved: true,
          curveSmoothness: 0.25,
          color: c,
          barWidth: 3,
          dotData: FlDotData(show: data.length <= 12),
          belowBarData: BarAreaData(show: fill, color: c.withValues(alpha: 0.12)),
        );

    return _card(
      title: title,
      child: Column(
        children: [
          if (serie2 != null) ...[
            Row(children: [
              _legendDot(_green, serie1Label ?? 'Serie 1'),
              const SizedBox(width: 16),
              _legendDot(_palette[1], serie2Label ?? 'Serie 2'),
            ]),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 170,
            child: LineChart(LineChartData(
              minY: 0,
              maxY: maxY <= 0 ? 1 : (maxY * 1.2),
              lineBarsData: [
                barOf(data, _green, area || serie2 == null),
                if (serie2 != null) barOf(serie2, _palette[1], false),
              ],
              gridData: FlGridData(
                show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.grey.withValues(alpha: 0.12), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 30,
                    getTitlesWidget: (v, m) => Text(
                      v % 1 == 0 ? v.toInt().toString() : '',
                      style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= data.length || i % step != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(data[i].label,
                            style: TextStyle(fontSize: 8.5, color: Colors.grey.shade500)),
                      );
                    },
                  ),
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11.5)),
      ]);

  Widget _emptyChart() => Container(
        height: 80,
        alignment: Alignment.center,
        child: Text('Sin datos para mostrar',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5)),
      );

  static String _miles(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _Kpi {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Kpi(this.label, this.value, this.icon, this.color);
}

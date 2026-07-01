import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/indicadores_models.dart';
import '../services/indicadores_service.dart';
import '../utils/api_provider.dart';
import '../widgets/verdant_charts.dart';
import '../widgets/verdant_theme.dart';

/// Indicadores de desempeño (Punto 3.4): resumen de empresa + ranking por
/// empleado (evaluaciones, puntualidad, vacaciones, score global, tendencia).
class PantallaIndicadores extends StatefulWidget {
  const PantallaIndicadores({super.key});

  @override
  State<PantallaIndicadores> createState() => _PantallaIndicadoresState();
}

class _PantallaIndicadoresState extends State<PantallaIndicadores> {
  static const _medal = [Color(0xFFE8B53A), Color(0xFFB9C2CC), Color(0xFFCD8E52)];
  static const _avatarPalette = [
    Color(0xFF3E9A4E), Color(0xFF3E80C0), Color(0xFFC58A1C),
    Color(0xFF7E57C2), Color(0xFFD6584F), Color(0xFF2BA89F),
  ];

  IndicadoresService? _svc;
  ResumenDesempeno? _resumen;
  List<IndicadorEmpleado> _items = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getIndicadoresService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = await _svc!.resumen();
    final lst = await _svc!.desempeno();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok) _resumen = res.data;
      if (lst.ok) {
        _items = lst.data ?? [];
      } else {
        _error = lst.errorMessage;
      }
    });
  }

  Color _scoreColor(VerdantColors v, double? s) {
    if (s == null) return v.mut;
    if (s >= 80) return v.grn;
    if (s >= 60) return v.amb;
    return v.red;
  }

  String _iniciales(String? nombre, String fallbackId) {
    final n = (nombre ?? '').trim();
    if (n.isEmpty) return fallbackId.isNotEmpty ? fallbackId[0].toUpperCase() : '?';
    final p = n.split(RegExp(r'\s+'));
    final i1 = p.isNotEmpty ? p[0][0] : '';
    final i2 = p.length > 1 ? p[1][0] : '';
    return ('$i1$i2').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final v = VerdantColors.of(context);
    return Scaffold(
      backgroundColor: v.dark ? const Color(0xFF091310) : const Color(0xFFF4F6EF),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _hero(v)),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            Text('Ranking por empleado',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16, fontWeight: FontWeight.w700, color: v.ink)),
                            const SizedBox(height: 10),
                            if (_items.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text('Sin datos de empleados.',
                                    style: TextStyle(color: v.mut)),
                              )
                            else
                              ..._items.asMap().entries.map(
                                  (e) => _fila(v, e.key, e.value)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _hero(VerdantColors v) {
    final r = _resumen;
    final promEval = r?.promedioEvaluaciones; // escala 1-10
    final puntualidad = r?.puntualidadPromedio ?? 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        gradient: v.heroGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icon(Icons.arrow_back, color: v.onHero),
                ),
                Expanded(
                  child: Text('Desempeño',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 19, fontWeight: FontWeight.w700, color: v.onHero)),
                ),
                IconButton(
                  onPressed: _cargar,
                  icon: Icon(Icons.refresh, color: v.onHero),
                  style: IconButton.styleFrom(backgroundColor: v.heroChip),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: v.heroCard,
                      border: Border.all(color: v.heroBd),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Prom. evaluación', style: TextStyle(fontSize: 12, color: v.onHeroSub)),
                        Text(promEval != null ? promEval.toStringAsFixed(1) : '—',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 28, fontWeight: FontWeight.w700, color: v.onHero)),
                        const SizedBox(height: 7),
                        StarRating(
                          value: (promEval ?? 0) / 2, // 1-10 → 0-5 estrellas
                          color: v.lime,
                          empty: v.heroBd,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Container(
                  width: 128,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: v.heroCard,
                    border: Border.all(color: v.heroBd),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RingChart(
                        percent: puntualidad,
                        size: 74,
                        strokeWidth: 9,
                        color: v.lime,
                        track: v.heroBd,
                        textColor: v.onHero,
                      ),
                      const SizedBox(height: 7),
                      Text('Puntualidad', style: TextStyle(fontSize: 11.5, color: v.onHeroSub)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(child: _kpiChip(v, '${r?.empleados ?? 0}', 'Empleados')),
                const SizedBox(width: 13),
                Expanded(
                  child: _kpiChip(
                    v,
                    r?.calificacionCliente != null ? r!.calificacionCliente!.toStringAsFixed(1) : '—',
                    'Calif. cliente',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiChip(VerdantColors v, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: v.heroChip, borderRadius: BorderRadius.circular(15)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700, color: v.lime)),
          const SizedBox(width: 9),
          Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: v.onHeroSub))),
        ],
      ),
    );
  }

  Widget _fila(VerdantColors v, int index, IndicadorEmpleado i) {
    final rank = index + 1;
    final medalColor = index < 3 ? _medal[index] : null;
    final scoreColor = _scoreColor(v, i.scoreGlobal);
    final avatarColor = _avatarPalette[index % _avatarPalette.length];
    final tendenciaOk = i.tendencia.length >= 2;

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: v.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: v.bd),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: v.dark ? 0.30 : 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: avatarColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: medalColor ?? Colors.transparent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(_iniciales(i.empleadoNombre, i.empleadoId),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ),
                Positioned(
                  bottom: -6, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: medalColor ?? scoreColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('#$rank',
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.empleadoNombre ?? i.empleadoId,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: v.ink)),
                if (i.cargo != null) ...[
                  const SizedBox(height: 1),
                  Text(i.cargo!, style: TextStyle(fontSize: 11.5, color: v.mut)),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 11,
                  runSpacing: 2,
                  children: [
                    _metric(v, 'Eval', i.promedioEvaluaciones != null ? i.promedioEvaluaciones!.toStringAsFixed(1) : '—'),
                    _metric(v, 'Punt', i.puntualidadPct != null ? '${i.puntualidadPct!.toStringAsFixed(0)}%' : '—'),
                    Text('${i.asistenciaValidados}/${i.asistenciaTotal}',
                        style: TextStyle(fontSize: 11.5, color: v.sub)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              RingChart(
                percent: i.scoreGlobal ?? 0,
                size: 48,
                strokeWidth: 5,
                color: scoreColor,
                track: v.track,
                textColor: v.ink,
                suffix: '',
                label: i.scoreGlobal != null ? i.scoreGlobal!.round().toString() : '—',
              ),
              if (tendenciaOk) ...[
                const SizedBox(height: 5),
                Sparkline(points: i.tendencia, color: scoreColor, width: 56, height: 20),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(VerdantColors v, String k, String val) => RichText(
        text: TextSpan(style: TextStyle(fontSize: 11.5, color: v.sub), children: [
          TextSpan(text: '$k '),
          TextSpan(text: val, style: TextStyle(fontWeight: FontWeight.w700, color: v.ink)),
        ]),
      );
}

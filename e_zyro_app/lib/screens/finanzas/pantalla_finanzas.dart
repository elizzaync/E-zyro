import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import '../../utils/ui_insets.dart';
import '../../widgets/verdant_theme.dart';
import 'finanzas_navegacion.dart';

/// Hub del módulo de Finanzas, ahora dashboard-first (lenguaje visual Verdant):
/// arriba la foto económica de la empresa (disponible, te deben/debes con
/// semáforo, resultado del mes, flujo 6 meses y caja proyectada) y debajo los
/// submódulos por sección. Si el rol no tiene `finanzas_resumen:ver`, muestra
/// solo la lista de módulos (comportamiento previo).
class PantallaFinanzas extends StatefulWidget {
  const PantallaFinanzas({super.key});

  @override
  State<PantallaFinanzas> createState() => _PantallaFinanzasState();
}

class _PantallaFinanzasState extends State<PantallaFinanzas> {
  FinanzasService? _svc;
  ResumenFinanciero? _res;
  bool _cargando = true;
  String? _error;

  static final _fmt = NumberFormat('#,##0.00', 'es_PE');
  static final _fmt0 = NumberFormat('#,##0', 'es_PE');

  bool get _puedeVerResumen =>
      AppSession.i.isAdmin || AppSession.i.canVerResumenFinanzas;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!_puedeVerResumen) {
      setState(() => _cargando = false);
      return;
    }
    _svc = await getFinanzasService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final r = await _svc!.resumenFinanciero();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _res = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  /// Abre un módulo y, al volver, refresca el resumen en silencio (sin
  /// spinner): lo registrado adentro (una factura, un cobro) se ve al salir.
  Future<void> _abrirModulo(WidgetBuilder builder) async {
    await Navigator.push(context, MaterialPageRoute(builder: builder));
    if (!mounted || _svc == null || !_puedeVerResumen) return;
    final r = await _svc!.resumenFinanciero();
    if (!mounted) return;
    if (r.ok) setState(() => _res = r.data);
  }

  String _s(double v) => 'S/ ${_fmt.format(v)}';
  String _sCorto(double v) {
    final a = v.abs();
    if (a >= 1000000) return 'S/ ${(v / 1000000).toStringAsFixed(1)}M';
    if (a >= 10000) return 'S/ ${_fmt0.format(v / 1000)}k';
    return 'S/ ${_fmt0.format(v)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSession.i;
    final v = VerdantColors.of(context);
    final secciones = finanzasSecciones(s);

    return Scaffold(
      backgroundColor: v.dark ? const Color(0xFF0E1611) : const Color(0xFFF3F1E6),
      appBar: AppBar(
        title: const Text('Finanzas',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_puedeVerResumen)
            IconButton(
                tooltip: 'Actualizar',
                onPressed: _cargar,
                icon: const Icon(Icons.refresh)),
          if (secciones.isNotEmpty) abrirManualFinanzas(context),
        ],
      ),
      body: secciones.isEmpty && !_puedeVerResumen
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No tienes permisos para ver módulos de finanzas.',
                    textAlign: TextAlign.center),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: bottomSafePadding(context),
                children: [
                  if (_puedeVerResumen) ..._dashboard(v),
                  for (final sec in secciones) ...[
                    _encabezadoSeccion(v, sec),
                    for (final m in sec.modulos) _tarjeta(context, v, m),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────
  List<Widget> _dashboard(VerdantColors v) {
    if (_cargando) {
      return const [
        SizedBox(
            height: 220, child: Center(child: CircularProgressIndicator())),
      ];
    }
    final r = _res;
    if (r == null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            Text(_error ?? 'No se pudo cargar el resumen.',
                style: TextStyle(color: v.sub), textAlign: TextAlign.center),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      ];
    }
    return [
      _hero(v, r),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _kpiCuentas(v, 'Te deben', r.cxc, esCobro: true)),
        const SizedBox(width: 12),
        Expanded(child: _kpiCuentas(v, 'Debes', r.cxp, esCobro: false)),
      ]),
      const SizedBox(height: 12),
      _accionesRapidas(v),
      const SizedBox(height: 12),
      _cardFlujo(v, r),
      const SizedBox(height: 12),
      _cardProyeccion(v, r),
      if (r.topGastosMes.isNotEmpty) ...[
        const SizedBox(height: 12),
        _cardTopGastos(v, r),
      ],
      const SizedBox(height: 4),
    ];
  }

  /// Hero verde: disponible hoy + desglose caja/bancos + resultado del mes.
  Widget _hero(VerdantColors v, ResumenFinanciero r) {
    final resPos = r.resultadoMes >= 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: v.heroGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('DISPONIBLE HOY',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: v.onHeroSub)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: v.heroChip, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  r.periodoActualAbierto
                      ? Icons.lock_open_rounded
                      : Icons.lock_outline_rounded,
                  size: 13,
                  color: v.onHero),
              const SizedBox(width: 5),
              Text(r.periodoActualAbierto ? 'Mes abierto' : 'Mes cerrado',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: v.onHero)),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        Text(_s(r.disponible.total),
            style: GoogleFonts.spaceGrotesk(
                fontSize: 34, fontWeight: FontWeight.w700, color: v.onHero)),
        const SizedBox(height: 12),
        Row(children: [
          _heroDato(v, Icons.payments_outlined, 'Caja', _sCorto(r.disponible.caja)),
          const SizedBox(width: 10),
          _heroDato(v, Icons.account_balance_outlined, 'Bancos',
              _sCorto(r.disponible.bancos)),
          const SizedBox(width: 10),
          _heroDato(
              v,
              resPos ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              'Mes',
              '${resPos ? '+' : ''}${_sCorto(r.resultadoMes)}',
              destacado: true,
              negativo: !resPos),
        ]),
      ]),
    );
  }

  Widget _heroDato(VerdantColors v, IconData ic, String label, String valor,
      {bool destacado = false, bool negativo = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: destacado ? v.lime : v.heroCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: destacado ? Colors.transparent : v.heroBd),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ic,
                size: 13,
                color: destacado
                    ? (negativo ? v.red : v.limeInk)
                    : v.onHeroSub),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: destacado ? v.limeInk : v.onHeroSub)),
          ]),
          const SizedBox(height: 3),
          Text(valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: destacado ? v.limeInk : v.onHero)),
        ]),
      ),
    );
  }

  /// KPI CxC/CxP con semáforo: vencido en rojo, al día en verde.
  Widget _kpiCuentas(VerdantColors v, String titulo, BucketsVencimiento b,
      {required bool esCobro}) {
    final tieneVencido = b.vencido > 0;
    final modulo =
        moduloFinanzasPorId(AppSession.i, esCobro ? FinId.cxc : FinId.cxp);
    return Material(
      color: v.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: modulo == null
            ? null
            : () => _abrirModulo(modulo.builder),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: v.bd),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(
                  esCobro
                      ? Icons.call_received_rounded
                      : Icons.call_made_rounded,
                  size: 15,
                  color: esCobro ? v.grn : v.amb),
              const SizedBox(width: 5),
              Text(titulo,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: v.sub)),
            ]),
            const SizedBox(height: 6),
            Text(_s(b.total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18, fontWeight: FontWeight.w700, color: v.ink)),
            const SizedBox(height: 7),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: tieneVencido ? v.redBg : v.grnBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tieneVencido
                    ? '${b.nVencidos} vencida${b.nVencidos == 1 ? '' : 's'} · ${_sCorto(b.vencido)}'
                    : 'Al día',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: tieneVencido ? v.red : v.grn),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Las 3 operaciones más frecuentes, gateadas por permiso.
  Widget _accionesRapidas(VerdantColors v) {
    final s = AppSession.i;
    final acciones = <(String, IconData, String)>[
      ('Registrar gasto', Icons.remove_circle_outline, FinId.cxp),
      ('Registrar cobro', Icons.add_circle_outline, FinId.cxc),
      ('Caja chica', Icons.savings_outlined, FinId.cajaChica),
    ];
    final visibles = [
      for (final a in acciones)
        if (moduloFinanzasPorId(s, a.$3) != null) a,
    ];
    if (visibles.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      for (var i = 0; i < visibles.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: Material(
            color: v.lime,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                final m = moduloFinanzasPorId(s, visibles[i].$3);
                if (m != null) _abrirModulo(m.builder);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(children: [
                  Icon(visibles[i].$2, size: 20, color: v.limeInk),
                  const SizedBox(height: 4),
                  Text(visibles[i].$1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: v.limeInk)),
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
  }

  /// Flujo de caja de los últimos 6 meses: barras entrada/salida por mes.
  Widget _cardFlujo(VerdantColors v, ResumenFinanciero r) {
    final meses = r.flujoMensual;
    final maxV = meses.fold<double>(
        1, (m, f) => [m, f.entradas, f.salidas].reduce((a, b) => a > b ? a : b));
    const mesesCortos = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul',
      'Ago', 'Set', 'Oct', 'Nov', 'Dic'];
    return _card(v, 'Flujo de caja · 6 meses', Icons.waterfall_chart_rounded,
        child: Column(children: [
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final f in meses)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _barra(v.grn, f.entradas / maxV),
                              const SizedBox(width: 3),
                              _barra(v.red, f.salidas / maxV),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            mesesCortos[
                                int.tryParse(f.periodo.split('-').last) ?? 0],
                            style: TextStyle(fontSize: 9.5, color: v.mut),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _leyenda(v, v.grn, 'Entradas'),
            const SizedBox(width: 16),
            _leyenda(v, v.red, 'Salidas'),
          ]),
        ]));
  }

  Widget _barra(Color c, double frac) {
    return Container(
      width: 9,
      height: (72 * frac.clamp(0.02, 1.0)),
      decoration: BoxDecoration(
        color: c,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );
  }

  Widget _leyenda(VerdantColors v, Color c, String t) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(t, style: TextStyle(fontSize: 11, color: v.sub)),
    ]);
  }

  /// Caja proyectada 30/60/90 días: disponible + cobros − pagos.
  Widget _cardProyeccion(VerdantColors v, ResumenFinanciero r) {
    return _card(v, 'Caja proyectada', Icons.query_stats_rounded,
        child: Row(children: [
          for (var i = 0; i < r.proyeccion.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _chipProyeccion(v, r.proyeccion[i])),
          ],
        ]),
        pie:
            'Disponible + cobros por vencer − pagos comprometidos en cada horizonte.');
  }

  Widget _chipProyeccion(VerdantColors v, ProyeccionCaja p) {
    final neg = p.saldoProyectado < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: neg ? v.redBg : v.cardAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text('${p.dias} días',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w600, color: v.sub)),
        const SizedBox(height: 4),
        Text(_sCorto(p.saldoProyectado),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: neg ? v.red : v.ink)),
        const SizedBox(height: 4),
        Text('▲ ${_sCorto(p.cobrosEsperados)}  ▼ ${_sCorto(p.pagosComprometidos)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: v.mut)),
      ]),
    );
  }

  /// Top 5 gastos del mes con barra proporcional.
  Widget _cardTopGastos(VerdantColors v, ResumenFinanciero r) {
    final maxV = r.topGastosMes.first.monto <= 0
        ? 1.0
        : r.topGastosMes.first.monto;
    return _card(v, 'En qué gastas este mes', Icons.donut_small_outlined,
        child: Column(children: [
          for (final g in r.topGastosMes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('${g.codigo} · ${g.nombre}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: v.ink)),
                      ),
                      Text(_s(g.monto),
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: v.ink)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (g.monto / maxV).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: v.track,
                        valueColor:
                            AlwaysStoppedAnimation(v.heroSolid),
                      ),
                    ),
                  ]),
            ),
        ]));
  }

  Widget _card(VerdantColors v, String titulo, IconData icono,
      {required Widget child, String? pie}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: v.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: v.bd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icono, size: 16, color: v.heroSolid),
          const SizedBox(width: 7),
          Text(titulo,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: v.ink)),
        ]),
        const SizedBox(height: 12),
        child,
        if (pie != null) ...[
          const SizedBox(height: 4),
          Text(pie, style: TextStyle(fontSize: 10, color: v.mut)),
        ],
      ]),
    );
  }

  // ── Módulos (lista existente, con estilo Verdant) ──────────────────────────
  Widget _encabezadoSeccion(VerdantColors v, FinSeccion sec) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Icon(sec.icono, size: 17, color: v.mut),
          const SizedBox(width: 7),
          Text(
            sec.titulo.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: v.mut,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(BuildContext context, VerdantColors v, FinModulo m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: v.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _abrirModulo(m.builder),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: v.bd),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: m.color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(m.icono, color: m.color, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.titulo,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: v.ink)),
                      const SizedBox(height: 2),
                      Text(m.subtitulo,
                          style: TextStyle(fontSize: 11.5, color: v.sub)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: v.mut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

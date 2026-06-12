// Pantalla "Dashboard Ejecutivo" del Portal Cliente B2B de e-zyro.
//
// Mockup de alto nivel con datos 100% de demostración: scorecards con
// count-up y sparklines, tendencia de servicios (12 meses), donut del parque
// de equipos, gauge de cumplimiento SLA, heatmap calendario de
// mantenimientos, proyectos en curso y actividad reciente.
//
// Solo móvil (portrait). Previsualizar con: flutter run -t lib/main_demo.dart

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'portal_design.dart';

// ---------------------------------------------------------------------------
// Modelos de datos mock
// ---------------------------------------------------------------------------

enum _Periodo {
  d30('30 días'),
  d90('90 días'),
  m12('12 meses');

  const _Periodo(this.etiqueta);
  final String etiqueta;
}

enum _FormatoKpi { porcentaje, entero }

class _DatoKpi {
  const _DatoKpi({
    required this.titulo,
    required this.icono,
    required this.acento,
    required this.valor,
    required this.formato,
    required this.deltaTexto,
    required this.deltaPositivo,
    this.deltaInvertido = false,
    required this.spark,
  });

  final String titulo;
  final IconData icono;
  final Color acento;
  final double valor;
  final _FormatoKpi formato;
  final String deltaTexto;
  final bool deltaPositivo;
  final bool deltaInvertido;
  final List<double> spark;

  String formatear(double v) => formato == _FormatoKpi.porcentaje
      ? PortalFormato.porcentaje(v)
      : PortalFormato.entero(v.round());
}

class _DatosPeriodo {
  const _DatosPeriodo({
    required this.kpis,
    required this.programados,
    required this.completados,
    required this.sla,
    required this.tiempoRespuesta,
    required this.resolucionPrimeraVisita,
    required this.reincidencias,
  });

  final List<_DatoKpi> kpis;
  final List<double> programados;
  final List<double> completados;
  final double sla;
  final double tiempoRespuesta;
  final double resolucionPrimeraVisita;
  final double reincidencias;
}

final Map<_Periodo, _DatosPeriodo> _datosPorPeriodo = {
  _Periodo.d30: _DatosPeriodo(
    kpis: const [
      _DatoKpi(
        titulo: 'Disponibilidad de equipos',
        icono: Icons.bolt_rounded,
        acento: PortalColores.lima,
        valor: 96.8,
        formato: _FormatoKpi.porcentaje,
        deltaTexto: '1,2 pts',
        deltaPositivo: true,
        spark: [94.1, 94.8, 95.2, 94.9, 95.7, 96.1, 96.4, 96.8],
      ),
      _DatoKpi(
        titulo: 'Servicios completados',
        icono: Icons.task_alt_rounded,
        acento: PortalColores.cian,
        valor: 47,
        formato: _FormatoKpi.entero,
        deltaTexto: '8',
        deltaPositivo: true,
        spark: [31, 34, 33, 38, 39, 42, 44, 47],
      ),
      _DatoKpi(
        titulo: 'Cumplimiento de cronograma',
        icono: Icons.event_available_rounded,
        acento: PortalColores.ambar,
        valor: 91.4,
        formato: _FormatoKpi.porcentaje,
        deltaTexto: '2,1 pts',
        deltaPositivo: false,
        spark: [94.6, 94.1, 93.5, 93.8, 92.9, 92.2, 91.8, 91.4],
      ),
      _DatoKpi(
        titulo: 'Equipos críticos',
        icono: Icons.warning_amber_rounded,
        acento: PortalColores.coral,
        valor: 3,
        formato: _FormatoKpi.entero,
        deltaTexto: '2',
        deltaPositivo: false,
        deltaInvertido: true,
        spark: [7, 6, 6, 5, 5, 4, 4, 3],
      ),
    ],
    programados: [38, 41, 40, 44, 42, 45, 43, 47, 46, 48, 45, 49],
    completados: [34, 37, 38, 40, 39, 43, 40, 44, 44, 45, 43, 47],
    sla: 94.2,
    tiempoRespuesta: 4.2,
    resolucionPrimeraVisita: 87,
    reincidencias: 2.3,
  ),
  _Periodo.d90: _DatosPeriodo(
    kpis: const [
      _DatoKpi(
        titulo: 'Disponibilidad de equipos',
        icono: Icons.bolt_rounded,
        acento: PortalColores.lima,
        valor: 95.9,
        formato: _FormatoKpi.porcentaje,
        deltaTexto: '0,6 pts',
        deltaPositivo: true,
        spark: [94.4, 94.9, 95.1, 95.6, 95.3, 95.8, 95.6, 95.9],
      ),
      _DatoKpi(
        titulo: 'Servicios completados',
        icono: Icons.task_alt_rounded,
        acento: PortalColores.cian,
        valor: 132,
        formato: _FormatoKpi.entero,
        deltaTexto: '15',
        deltaPositivo: true,
        spark: [96, 104, 101, 112, 118, 121, 127, 132],
      ),
      _DatoKpi(
        titulo: 'Cumplimiento de cronograma',
        icono: Icons.event_available_rounded,
        acento: PortalColores.ambar,
        valor: 92.8,
        formato: _FormatoKpi.porcentaje,
        deltaTexto: '1,4 pts',
        deltaPositivo: true,
        spark: [90.2, 90.9, 91.4, 91.1, 91.9, 92.3, 92.5, 92.8],
      ),
      _DatoKpi(
        titulo: 'Equipos críticos',
        icono: Icons.warning_amber_rounded,
        acento: PortalColores.coral,
        valor: 5,
        formato: _FormatoKpi.entero,
        deltaTexto: '1',
        deltaPositivo: false,
        deltaInvertido: true,
        spark: [9, 8, 8, 7, 7, 6, 6, 5],
      ),
    ],
    programados: [35, 38, 42, 40, 44, 41, 46, 44, 47, 45, 48, 46],
    completados: [31, 35, 38, 37, 41, 39, 42, 41, 44, 43, 45, 44],
    sla: 93.1,
    tiempoRespuesta: 4.6,
    resolucionPrimeraVisita: 84,
    reincidencias: 2.8,
  ),
  _Periodo.m12: _DatosPeriodo(
    kpis: const [
      _DatoKpi(
        titulo: 'Disponibilidad de equipos',
        icono: Icons.bolt_rounded,
        acento: PortalColores.lima,
        valor: 96.2,
        formato: _FormatoKpi.porcentaje,
        deltaTexto: '2,3 pts',
        deltaPositivo: true,
        spark: [93.1, 93.8, 94.5, 94.2, 95.1, 95.6, 95.9, 96.2],
      ),
      _DatoKpi(
        titulo: 'Servicios completados',
        icono: Icons.task_alt_rounded,
        acento: PortalColores.cian,
        valor: 486,
        formato: _FormatoKpi.entero,
        deltaTexto: '61',
        deltaPositivo: true,
        spark: [318, 342, 361, 388, 402, 431, 458, 486],
      ),
      _DatoKpi(
        titulo: 'Cumplimiento de cronograma',
        icono: Icons.event_available_rounded,
        acento: PortalColores.ambar,
        valor: 90.6,
        formato: _FormatoKpi.porcentaje,
        deltaTexto: '0,8 pts',
        deltaPositivo: false,
        spark: [92.4, 92.0, 91.6, 91.9, 91.2, 90.9, 91.0, 90.6],
      ),
      _DatoKpi(
        titulo: 'Equipos críticos',
        icono: Icons.warning_amber_rounded,
        acento: PortalColores.coral,
        valor: 4,
        formato: _FormatoKpi.entero,
        deltaTexto: '3',
        deltaPositivo: false,
        deltaInvertido: true,
        spark: [11, 10, 9, 8, 7, 6, 5, 4],
      ),
    ],
    programados: [40, 43, 41, 46, 44, 48, 45, 50, 47, 52, 49, 53],
    completados: [35, 39, 38, 42, 41, 45, 41, 47, 44, 49, 46, 51],
    sla: 95.0,
    tiempoRespuesta: 3.9,
    resolucionPrimeraVisita: 89,
    reincidencias: 1.9,
  ),
};

const List<String> _meses = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];

// ---------------------------------------------------------------------------
// Pantalla
// ---------------------------------------------------------------------------

class PantallaDashboardEjecutivo extends StatefulWidget {
  const PantallaDashboardEjecutivo({super.key});

  @override
  State<PantallaDashboardEjecutivo> createState() =>
      _PantallaDashboardEjecutivoState();
}

class _PantallaDashboardEjecutivoState
    extends State<PantallaDashboardEjecutivo> {
  _Periodo _periodo = _Periodo.d30;

  _DatosPeriodo get _datos => _datosPorPeriodo[_periodo]!;

  String get _saludo {
    final int hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  Widget _conmutado(Widget hijo, String clave) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey('$clave-${_periodo.name}'),
          child: hijo,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final List<Widget> secciones = [
      _Encabezado(
        saludo: _saludo,
        periodo: _periodo,
        onPeriodo: (p) => setState(() => _periodo = p),
      ),
      _conmutado(_GrillaScorecards(kpis: _datos.kpis), 'kpis'),
      _conmutado(
        _CardServicios(
          programados: _datos.programados,
          completados: _datos.completados,
        ),
        'servicios',
      ),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(child: _CardParqueEquipos()),
            const SizedBox(width: 12),
            Expanded(
              child: _conmutado(
                _CardSla(
                  valor: _datos.sla,
                  tiempoRespuesta: _datos.tiempoRespuesta,
                  resolucionPrimeraVisita: _datos.resolucionPrimeraVisita,
                  reincidencias: _datos.reincidencias,
                ),
                'sla',
              ),
            ),
          ],
        ),
      ),
      const _CardHeatmap(),
      const _CardProyectos(),
      const _CardActividad(),
      const _PieDePagina(),
    ];

    return Scaffold(
      backgroundColor: PortalColores.fondo,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _EntradaAnimada(
                  indice: i,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i == secciones.length - 1 ? 0 : 14,
                    ),
                    child: secciones[i],
                  ),
                ),
                childCount: secciones.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entrada escalonada (fade + slide)
// ---------------------------------------------------------------------------

class _EntradaAnimada extends StatefulWidget {
  const _EntradaAnimada({required this.indice, required this.child});

  final int indice;
  final Widget child;

  @override
  State<_EntradaAnimada> createState() => _EntradaAnimadaState();
}

class _EntradaAnimadaState extends State<_EntradaAnimada> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 70 * widget.indice), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.08),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Encabezado y selector de periodo
// ---------------------------------------------------------------------------

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.saludo,
    required this.periodo,
    required this.onPeriodo,
  });

  final String saludo;
  final _Periodo periodo;
  final ValueChanged<_Periodo> onPeriodo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 36, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$saludo, TALMA', style: PortalTipografia.titulo(tamano: 24)),
          const SizedBox(height: 4),
          Text(
            'Resumen ejecutivo de sus servicios',
            style: PortalTipografia.cuerpo(tamano: 13.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final p in _Periodo.values) ...[
                _ChipPeriodo(
                  etiqueta: p.etiqueta,
                  activo: p == periodo,
                  onTap: () => onPeriodo(p),
                ),
                if (p != _Periodo.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipPeriodo extends StatelessWidget {
  const _ChipPeriodo({
    required this.etiqueta,
    required this.activo,
    required this.onTap,
  });

  final String etiqueta;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: activo
              ? PortalColores.lima.withValues(alpha: 0.16)
              : PortalColores.superficie,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: activo
                ? PortalColores.lima.withValues(alpha: 0.55)
                : PortalColores.bordeCard,
          ),
        ),
        child: Text(
          etiqueta,
          style: PortalTipografia.etiqueta(
            tamano: 12,
            color: activo ? PortalColores.lima : PortalColores.textoSecundario,
            peso: activo ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scorecards (grid 2x2)
// ---------------------------------------------------------------------------

class _GrillaScorecards extends StatelessWidget {
  const _GrillaScorecards({required this.kpis});

  final List<_DatoKpi> kpis;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _Scorecard(dato: kpis[0])),
            const SizedBox(width: 12),
            Expanded(child: _Scorecard(dato: kpis[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _Scorecard(dato: kpis[2])),
            const SizedBox(width: 12),
            Expanded(child: _Scorecard(dato: kpis[3])),
          ],
        ),
      ],
    );
  }
}

class _Scorecard extends StatelessWidget {
  const _Scorecard({required this.dato});

  final _DatoKpi dato;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 172,
      padding: const EdgeInsets.all(14),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: PortalDecoraciones.contenedorIcono(dato.acento),
                child: Icon(dato.icono, size: 19, color: dato.acento),
              ),
              const Spacer(),
              ChipDelta(
                texto: dato.deltaTexto,
                positivo: dato.deltaPositivo,
                invertirColor: dato.deltaInvertido,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _NumeroAnimado(
            valor: dato.valor,
            formatear: dato.formatear,
            estilo: PortalTipografia.kpi(tamano: 26),
          ),
          const SizedBox(height: 3),
          Text(
            dato.titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PortalTipografia.cuerpo(tamano: 11.5),
          ),
          const Spacer(),
          SizedBox(
            height: 30,
            width: double.infinity,
            child: _Sparkline(valores: dato.spark, color: dato.acento),
          ),
        ],
      ),
    );
  }
}

/// Número grande con animación de conteo (count-up).
class _NumeroAnimado extends StatelessWidget {
  const _NumeroAnimado({
    required this.valor,
    required this.formatear,
    required this.estilo,
  });

  final double valor;
  final String Function(double) formatear;
  final TextStyle estilo;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valor),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(formatear(v), style: estilo),
    );
  }
}

/// Mini sparkline sin ejes con gradiente bajo la curva.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.valores, required this.color});

  final List<double> valores;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double minV = valores.reduce(math.min);
    final double maxV = valores.reduce(math.max);
    final double margen = (maxV - minV) == 0 ? 1 : (maxV - minV) * 0.25;

    return LineChart(
      LineChartData(
        minY: minV - margen,
        maxY: maxV + margen,
        lineTouchData: const LineTouchData(enabled: false),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < valores.length; i++)
                FlSpot(i.toDouble(), valores[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.32,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.30),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
    );
  }
}

// ---------------------------------------------------------------------------
// Card grande: servicios programados vs completados
// ---------------------------------------------------------------------------

class _CardServicios extends StatelessWidget {
  const _CardServicios({
    required this.programados,
    required this.completados,
  });

  final List<double> programados;
  final List<double> completados;

  @override
  Widget build(BuildContext context) {
    final double maxY =
        [...programados, ...completados].reduce(math.max) * 1.25;

    LineChartBarData serie({
      required List<double> valores,
      required Color color,
      bool punteada = false,
      bool area = false,
    }) =>
        LineChartBarData(
          spots: [
            for (var i = 0; i < valores.length; i++)
              FlSpot(i.toDouble(), valores[i]),
          ],
          isCurved: true,
          curveSmoothness: 0.28,
          color: color,
          barWidth: punteada ? 2 : 3,
          dashArray: punteada ? [6, 6] : null,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: area,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.22),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Servicios: programados vs completados',
            style: PortalTipografia.titulo(tamano: 15),
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              _PuntoLeyenda(color: PortalColores.cian, texto: 'Programados'),
              SizedBox(width: 14),
              _PuntoLeyenda(color: PortalColores.lima, texto: 'Completados'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                lineBarsData: [
                  serie(
                    valores: programados,
                    color: PortalColores.cian.withValues(alpha: 0.65),
                    punteada: true,
                  ),
                  serie(
                    valores: completados,
                    color: PortalColores.lima,
                    area: true,
                  ),
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (v) => const FlLine(
                    color: PortalColores.divisor,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final int i = v.toInt();
                        if (i < 0 || i > 11 || v % 1 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _meses[i],
                            style: PortalTipografia.etiqueta(tamano: 8.5),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => PortalColores.tooltipFondo,
                    tooltipRoundedRadius: 12,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    getTooltipItems: (spots) => spots.map((s) {
                      final bool esCompletados = s.barIndex == 1;
                      return LineTooltipItem(
                        '${esCompletados ? 'Completados' : 'Programados'}'
                        ' ${s.y.toInt()}',
                        PortalTipografia.etiqueta(
                          tamano: 11,
                          color: esCompletados
                              ? PortalColores.lima
                              : PortalColores.cian,
                          peso: FontWeight.w700,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }
}

class _PuntoLeyenda extends StatelessWidget {
  const _PuntoLeyenda({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(texto, style: PortalTipografia.etiqueta(tamano: 11)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Donut: estado del parque de equipos
// ---------------------------------------------------------------------------

class _SegmentoParque {
  const _SegmentoParque(this.nombre, this.cantidad, this.color);
  final String nombre;
  final int cantidad;
  final Color color;
}

class _CardParqueEquipos extends StatelessWidget {
  const _CardParqueEquipos();

  static const List<_SegmentoParque> _segmentos = [
    _SegmentoParque('Operativo', 218, PortalColores.lima),
    _SegmentoParque('En mantenimiento', 14, PortalColores.ambar),
    _SegmentoParque('Observado', 10, PortalColores.cian),
    _SegmentoParque('Fuera de servicio', 3, PortalColores.coral),
  ];

  @override
  Widget build(BuildContext context) {
    final int total =
        _segmentos.fold(0, (acumulado, s) => acumulado + s.cantidad);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estado del parque de equipos',
            style: PortalTipografia.titulo(tamano: 13),
          ),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: 124,
              height: 124,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 40,
                      startDegreeOffset: -90,
                      sections: [
                        for (final s in _segmentos)
                          PieChartSectionData(
                            value: s.cantidad.toDouble(),
                            color: s.color,
                            radius: 18,
                            showTitle: false,
                          ),
                      ],
                    ),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        PortalFormato.entero(total),
                        style: PortalTipografia.kpi(tamano: 24),
                      ),
                      Text(
                        'equipos',
                        style: PortalTipografia.etiqueta(tamano: 9.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final s in _segmentos) ...[
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: s.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PortalTipografia.etiqueta(tamano: 10),
                  ),
                ),
                Text(
                  PortalFormato.porcentaje(s.cantidad / total * 100),
                  style: PortalTipografia.etiqueta(
                    tamano: 10,
                    color: PortalColores.textoPrimario,
                    peso: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (s != _segmentos.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gauge: cumplimiento SLA
// ---------------------------------------------------------------------------

class _CardSla extends StatelessWidget {
  const _CardSla({
    required this.valor,
    required this.tiempoRespuesta,
    required this.resolucionPrimeraVisita,
    required this.reincidencias,
  });

  final double valor;
  final double tiempoRespuesta;
  final double resolucionPrimeraVisita;
  final double reincidencias;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cumplimiento SLA', style: PortalTipografia.titulo(tamano: 13)),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: 132,
              height: 78,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: valor),
                duration: const Duration(milliseconds: 950),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => CustomPaint(
                  painter: _GaugePainter(fraccion: v / 100),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Text(
                      PortalFormato.porcentaje(v),
                      style: PortalTipografia.kpi(tamano: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'del objetivo contratado',
              style: PortalTipografia.etiqueta(tamano: 9.5),
            ),
          ),
          const Spacer(),
          _MicroMetrica(
            etiqueta: 'Tiempo de respuesta',
            valor: '${PortalFormato.decimal1(tiempoRespuesta)} h',
          ),
          const SizedBox(height: 7),
          _MicroMetrica(
            etiqueta: 'Resolución primera visita',
            valor: PortalFormato.porcentaje(resolucionPrimeraVisita),
          ),
          const SizedBox(height: 7),
          _MicroMetrica(
            etiqueta: 'Reincidencias',
            valor: PortalFormato.porcentaje(reincidencias),
          ),
        ],
      ),
    );
  }
}

class _MicroMetrica extends StatelessWidget {
  const _MicroMetrica({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            etiqueta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PortalTipografia.etiqueta(tamano: 10),
          ),
        ),
        Text(
          valor,
          style: PortalTipografia.etiqueta(
            tamano: 10.5,
            color: PortalColores.textoPrimario,
            peso: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Gauge semicircular con escala de color coral -> ámbar -> lima.
class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.fraccion});

  final double fraccion;

  @override
  void paint(Canvas canvas, Size size) {
    const double grosor = 13;
    final Offset centro = Offset(size.width / 2, size.height - 4);
    final double radio =
        math.min(size.width / 2, size.height) - grosor / 2 - 2;
    final Rect rect = Rect.fromCircle(center: centro, radius: radio);

    final Paint pista = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x12FFFFFF);
    canvas.drawArc(rect, math.pi, math.pi, false, pista);

    final Paint arco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: math.pi,
        endAngle: 2 * math.pi,
        colors: [
          PortalColores.coral,
          PortalColores.ambar,
          PortalColores.lima,
        ],
        stops: [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * fraccion.clamp(0.0, 1.0),
      false,
      arco,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter anterior) =>
      anterior.fraccion != fraccion;
}

// ---------------------------------------------------------------------------
// Heatmap calendario de mantenimientos
// ---------------------------------------------------------------------------

class _CardHeatmap extends StatelessWidget {
  const _CardHeatmap();

  static const List<String> _dias = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const int _semanas = 12;

  /// Intensidades mock con clusters realistas: más actividad martes-jueves,
  /// poca los fines de semana. Determinista (semilla fija).
  static List<List<int>> _generarIntensidades() {
    final math.Random azar = math.Random(2026);
    return List.generate(_semanas, (semana) {
      final bool semanaFuerte = azar.nextDouble() < 0.4;
      return List.generate(7, (dia) {
        double base;
        if (dia >= 1 && dia <= 3) {
          base = semanaFuerte ? 4.4 : 2.6; // martes-jueves
        } else if (dia == 0 || dia == 4) {
          base = semanaFuerte ? 2.4 : 1.4; // lunes y viernes
        } else {
          base = 0.5; // fin de semana
        }
        final double valor = base + azar.nextDouble() * 2.2 - 1.1;
        return valor.round().clamp(0, 7);
      });
    });
  }

  static Color _colorIntensidad(int v) {
    if (v <= 0) return const Color(0x0AFFFFFF);
    if (v <= 2) return PortalColores.lima.withValues(alpha: 0.25);
    if (v <= 4) return PortalColores.lima.withValues(alpha: 0.55);
    return PortalColores.lima;
  }

  @override
  Widget build(BuildContext context) {
    final List<List<int>> datos = _generarIntensidades();

    Widget celda(Color color) => AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mapa de calor de mantenimientos',
            style: PortalTipografia.titulo(tamano: 15),
          ),
          const SizedBox(height: 2),
          Text(
            'Últimas 12 semanas',
            style: PortalTipografia.etiqueta(tamano: 10.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final d in _dias)
                Expanded(
                  child: Center(
                    child:
                        Text(d, style: PortalTipografia.etiqueta(tamano: 10)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final semana in datos) ...[
            Row(
              children: [
                for (var d = 0; d < 7; d++) ...[
                  Expanded(child: celda(_colorIntensidad(semana[d]))),
                  if (d < 6) const SizedBox(width: 5),
                ],
              ],
            ),
            const SizedBox(height: 5),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Menos', style: PortalTipografia.etiqueta(tamano: 10)),
              const SizedBox(width: 6),
              for (final v in const [0, 2, 4, 6]) ...[
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: _colorIntensidad(v),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const SizedBox(width: 2),
              Text('Más', style: PortalTipografia.etiqueta(tamano: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Proyectos en curso
// ---------------------------------------------------------------------------

class _Proyecto {
  const _Proyecto({
    required this.nombre,
    required this.avance,
    required this.estado,
    required this.colorEstado,
    required this.spark,
  });

  final String nombre;
  final double avance; // 0..1
  final String estado;
  final Color colorEstado;
  final List<double> spark;
}

class _CardProyectos extends StatelessWidget {
  const _CardProyectos();

  static const List<_Proyecto> _proyectos = [
    _Proyecto(
      nombre: 'Mantenimiento PCI — Almacén Callao',
      avance: 0.82,
      estado: 'A tiempo',
      colorEstado: PortalColores.lima,
      spark: [12, 24, 35, 48, 58, 67, 74, 82],
    ),
    _Proyecto(
      nombre: 'Pozos a tierra — Sede Lurín',
      avance: 0.64,
      estado: 'En curso',
      colorEstado: PortalColores.cian,
      spark: [8, 15, 24, 31, 42, 50, 58, 64],
    ),
    _Proyecto(
      nombre: 'ITSE — Planta Norte',
      avance: 0.45,
      estado: 'En riesgo',
      colorEstado: PortalColores.ambar,
      spark: [10, 18, 24, 28, 33, 38, 42, 45],
    ),
    _Proyecto(
      nombre: 'Iluminación LED — CD Ventanilla',
      avance: 0.18,
      estado: 'Por iniciar',
      colorEstado: PortalColores.violeta,
      spark: [0, 2, 4, 6, 9, 12, 15, 18],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Proyectos en curso', style: PortalTipografia.titulo(tamano: 15)),
          const SizedBox(height: 14),
          for (final p in _proyectos) ...[
            _FilaProyecto(proyecto: p),
            if (p != _proyectos.last) ...[
              const SizedBox(height: 12),
              const Divider(
                color: PortalColores.divisor,
                height: 1,
                thickness: 1,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _FilaProyecto extends StatelessWidget {
  const _FilaProyecto({required this.proyecto});

  final _Proyecto proyecto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      proyecto.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PortalTipografia.cuerpo(
                        tamano: 12.5,
                        color: PortalColores.textoPrimario,
                        peso: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: proyecto.colorEstado.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      proyecto.estado,
                      style: PortalTipografia.etiqueta(
                        tamano: 9.5,
                        color: proyecto.colorEstado,
                        peso: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: proyecto.avance),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => _BarraProgreso(fraccion: v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${(proyecto.avance * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: PortalTipografia.etiqueta(
                        tamano: 11.5,
                        color: PortalColores.textoPrimario,
                        peso: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 56,
          height: 30,
          child: _Sparkline(
            valores: proyecto.spark,
            color: proyecto.colorEstado,
          ),
        ),
      ],
    );
  }
}

class _BarraProgreso extends StatelessWidget {
  const _BarraProgreso({required this.fraccion});

  final double fraccion;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 10,
        color: const Color(0x12FFFFFF),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraccion.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                colors: [PortalColores.cian, PortalColores.lima],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actividad reciente
// ---------------------------------------------------------------------------

class _Actividad {
  const _Actividad({
    required this.fecha,
    required this.servicio,
    required this.tecnico,
    required this.colorTecnico,
    required this.estado,
    required this.colorEstado,
    required this.duracion,
  });

  final String fecha;
  final String servicio;
  final String tecnico;
  final Color colorTecnico;
  final String estado;
  final Color colorEstado;
  final String duracion;
}

class _CardActividad extends StatelessWidget {
  const _CardActividad();

  static const List<_Actividad> _actividades = [
    _Actividad(
      fecha: '10 jun',
      servicio: 'Medición de pozo a tierra',
      tecnico: 'Jorge Quispe',
      colorTecnico: PortalColores.lima,
      estado: 'Completado',
      colorEstado: PortalColores.lima,
      duracion: '2,5 h',
    ),
    _Actividad(
      fecha: '09 jun',
      servicio: 'Mantenimiento de tablero eléctrico',
      tecnico: 'María Huamán',
      colorTecnico: PortalColores.cian,
      estado: 'Completado',
      colorEstado: PortalColores.lima,
      duracion: '4,0 h',
    ),
    _Actividad(
      fecha: '08 jun',
      servicio: 'Inspección de luminarias de emergencia',
      tecnico: 'Ricardo Chávez',
      colorTecnico: PortalColores.violeta,
      estado: 'Observado',
      colorEstado: PortalColores.ambar,
      duracion: '1,5 h',
    ),
    _Actividad(
      fecha: '06 jun',
      servicio: 'Mantenimiento de aire acondicionado',
      tecnico: 'Lucía Mamani',
      colorTecnico: PortalColores.ambar,
      estado: 'Completado',
      colorEstado: PortalColores.lima,
      duracion: '3,2 h',
    ),
    _Actividad(
      fecha: '05 jun',
      servicio: 'Levantamiento ITSE — Planta Norte',
      tecnico: 'Carlos Paredes',
      colorTecnico: PortalColores.coral,
      estado: 'En proceso',
      colorEstado: PortalColores.cian,
      duracion: '6,0 h',
    ),
    _Actividad(
      fecha: '04 jun',
      servicio: 'Cambio de luminarias LED — Nave 2',
      tecnico: 'Ana Flores',
      colorTecnico: PortalColores.cian,
      estado: 'Reprogramado',
      colorEstado: PortalColores.coral,
      duracion: '—',
    ),
  ];

  static String _iniciales(String nombre) {
    final partes = nombre.split(' ');
    final String a = partes.isNotEmpty && partes[0].isNotEmpty
        ? partes[0][0]
        : '';
    final String b = partes.length > 1 && partes[1].isNotEmpty
        ? partes[1][0]
        : '';
    return '$a$b'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Actividad reciente', style: PortalTipografia.titulo(tamano: 15)),
          const SizedBox(height: 6),
          for (final a in _actividades) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: a.colorTecnico.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _iniciales(a.tecnico),
                      style: PortalTipografia.etiqueta(
                        tamano: 11,
                        color: a.colorTecnico,
                        peso: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.servicio,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PortalTipografia.cuerpo(
                            tamano: 12.5,
                            color: PortalColores.textoPrimario,
                            peso: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${a.fecha}  ·  ${a.tecnico}',
                          style: PortalTipografia.etiqueta(tamano: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: a.colorEstado.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          a.estado,
                          style: PortalTipografia.etiqueta(
                            tamano: 9,
                            color: a.colorEstado,
                            peso: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.duracion,
                        style: PortalTipografia.etiqueta(tamano: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (a != _actividades.last)
              const Divider(
                color: PortalColores.divisor,
                height: 1,
                thickness: 1,
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

class _PieDePagina extends StatelessWidget {
  const _PieDePagina();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 18),
      child: Center(
        child: Text(
          'Datos demo · E-zyro Portal Analytics',
          style: PortalTipografia.etiqueta(
            tamano: 10.5,
            color: PortalColores.textoSecundario.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

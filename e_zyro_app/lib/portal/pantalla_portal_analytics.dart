// Dashboard ejecutivo CONECTADO del Portal Cliente B2B.
//
// Versión real de `pantalla_dashboard_ejecutivo.dart` (mockup): consume
// GET /portal-cliente/analytics/ejecutivo y muestra SOLO datos reales. No
// incluye sparklines, deltas, gauge SLA ni selector de período porque el
// backend no dispone de histórico (snapshot) ni de módulo correctivo: no se
// inventan tendencias. Tema "Ejecutivo Oscuro" (portal_design.dart).

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/api_result.dart';
import 'portal_design.dart';
import 'portal_models.dart';
import 'portal_service.dart';

class PantallaPortalAnalytics extends StatefulWidget {
  const PantallaPortalAnalytics({
    super.key,
    required this.servicio,
    this.empresa = '',
  });

  final PortalService servicio;
  final String empresa;

  @override
  State<PantallaPortalAnalytics> createState() =>
      _PantallaPortalAnalyticsState();
}

class _PantallaPortalAnalyticsState extends State<PantallaPortalAnalytics> {
  late Future<ApiResult<PortalAnalytics>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = widget.servicio.getAnalyticsEjecutivo();
  }

  Future<void> _refrescar() async {
    setState(() => _futuro = widget.servicio.getAnalyticsEjecutivo());
    await _futuro;
  }

  String get _saludo {
    final int hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColores.fondo,
      appBar: AppBar(
        backgroundColor: PortalColores.fondo,
        foregroundColor: PortalColores.textoPrimario,
        elevation: 0,
        title: Text(
          'Dashboard ejecutivo',
          style: PortalTipografia.titulo(tamano: 17),
        ),
      ),
      body: FutureBuilder<ApiResult<PortalAnalytics>>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: PortalColores.lima),
            );
          }
          final res = snap.data;
          if (res == null || !res.ok || res.data == null) {
            return _Error(onReintentar: _refrescar);
          }
          return RefreshIndicator(
            color: PortalColores.lima,
            backgroundColor: PortalColores.superficie,
            onRefresh: _refrescar,
            child: _Contenido(
              datos: res.data!,
              saludo: _saludo,
              empresa: widget.empresa,
            ),
          );
        },
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onReintentar});
  final Future<void> Function() onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: PortalColores.textoSecundario, size: 44),
          const SizedBox(height: 12),
          Text('No se pudo cargar el dashboard',
              style: PortalTipografia.cuerpo(tamano: 14)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh, color: PortalColores.lima),
            label: Text('Reintentar',
                style: PortalTipografia.etiqueta(
                    tamano: 13, color: PortalColores.lima)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: PortalColores.bordeCard),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Contenido ───────────────────────────────────────────────────────────────

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.datos,
    required this.saludo,
    required this.empresa,
  });

  final PortalAnalytics datos;
  final String saludo;
  final String empresa;

  @override
  Widget build(BuildContext context) {
    final r = datos.resumen;
    final secciones = <Widget>[
      _Encabezado(saludo: saludo, empresa: empresa),
      _GrillaScorecards(resumen: r),
      if (_tieneLinea) _CardServicios(meses: datos.linea12Meses),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _CardParque(
                segmentos: datos.parqueIntervencion,
                total: r.totalEquipos,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _CardCriticidad(v: datos.ventana)),
          ],
        ),
      ),
      if (datos.porSede.isNotEmpty) _CardSedes(sedes: datos.porSede),
      if (datos.inspeccionesCalendario.isNotEmpty)
        _CardHeatmap(dias: datos.inspeccionesCalendario),
      if (datos.garantias.isNotEmpty) _CardGarantias(garantias: datos.garantias),
      if (datos.itse.isNotEmpty) _CardItse(itse: datos.itse),
      const _PieDePagina(),
    ];

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: secciones.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) => secciones[i],
    );
  }

  bool get _tieneLinea =>
      datos.linea12Meses.any((m) => m.programados > 0 || m.completados > 0);
}

// ─── Encabezado ──────────────────────────────────────────────────────────────

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.saludo, required this.empresa});
  final String saludo;
  final String empresa;

  @override
  Widget build(BuildContext context) {
    final titulo = empresa.isEmpty ? saludo : '$saludo, $empresa';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PortalTipografia.titulo(tamano: 22)),
          const SizedBox(height: 4),
          Text('Resumen ejecutivo de sus servicios · datos en tiempo real',
              style: PortalTipografia.cuerpo(tamano: 13)),
        ],
      ),
    );
  }
}

// ─── Scorecards ──────────────────────────────────────────────────────────────

class _GrillaScorecards extends StatelessWidget {
  const _GrillaScorecards({required this.resumen});
  final AnalyticsResumen resumen;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _Scorecard(
        icono: Icons.precision_manufacturing_outlined,
        acento: PortalColores.lima,
        valor: resumen.totalEquipos,
        titulo: 'Equipos del parque',
      ),
      _Scorecard(
        icono: Icons.warning_amber_rounded,
        acento: PortalColores.coral,
        valor: resumen.equiposCriticos,
        titulo: 'Equipos críticos',
        subtitulo: 'mantenimiento vencido',
      ),
      _Scorecard(
        icono: Icons.task_alt_rounded,
        acento: PortalColores.cian,
        valor: resumen.serviciosCompletados,
        titulo: 'Servicios completados',
        subtitulo: 'de ${resumen.serviciosTotal} en total',
      ),
      _Scorecard(
        icono: Icons.assignment_late_outlined,
        acento: PortalColores.ambar,
        valor: resumen.conformidadesPendientes,
        titulo: 'Conformidades pend.',
      ),
    ];
    return Column(
      children: [
        Row(children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 12),
          Expanded(child: cards[1]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: cards[2]),
          const SizedBox(width: 12),
          Expanded(child: cards[3]),
        ]),
      ],
    );
  }
}

class _Scorecard extends StatelessWidget {
  const _Scorecard({
    required this.icono,
    required this.acento,
    required this.valor,
    required this.titulo,
    this.subtitulo,
  });

  final IconData icono;
  final Color acento;
  final int valor;
  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(14),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: PortalDecoraciones.contenedorIcono(acento),
            child: Icon(icono, size: 19, color: acento),
          ),
          const Spacer(),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: valor.toDouble()),
            duration: const Duration(milliseconds: 850),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              PortalFormato.entero(v.round()),
              style: PortalTipografia.kpi(tamano: 26),
            ),
          ),
          const SizedBox(height: 3),
          Text(titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PortalTipografia.cuerpo(tamano: 11.5)),
          if (subtitulo != null)
            Text(subtitulo!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PortalTipografia.etiqueta(tamano: 9.5)),
        ],
      ),
    );
  }
}

// ─── Servicios: línea 12 meses ───────────────────────────────────────────────

class _CardServicios extends StatelessWidget {
  const _CardServicios({required this.meses});
  final List<AnalyticsLineaMes> meses;

  static const List<String> _abrev = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  String _etiqueta(String ym) {
    // 'YYYY-MM' -> 'Mmm'
    final partes = ym.split('-');
    if (partes.length != 2) return '';
    final m = int.tryParse(partes[1]) ?? 0;
    return (m >= 1 && m <= 12) ? _abrev[m - 1] : '';
  }

  @override
  Widget build(BuildContext context) {
    final programados =
        meses.map((m) => m.programados.toDouble()).toList(growable: false);
    final completados =
        meses.map((m) => m.completados.toDouble()).toList(growable: false);
    final double maxData =
        [...programados, ...completados].fold(0.0, math.max);
    final double maxY = maxData <= 0 ? 4 : maxData * 1.25;

    LineChartBarData serie(List<double> v, Color c,
            {bool punteada = false, bool area = false}) =>
        LineChartBarData(
          spots: [for (var i = 0; i < v.length; i++) FlSpot(i.toDouble(), v[i])],
          isCurved: true,
          curveSmoothness: 0.28,
          color: c,
          barWidth: punteada ? 2 : 3,
          dashArray: punteada ? [6, 6] : null,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: area,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0.0)],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Servicios: programados vs completados',
              style: PortalTipografia.titulo(tamano: 15)),
          const SizedBox(height: 4),
          Text('Últimos 12 meses',
              style: PortalTipografia.etiqueta(tamano: 10.5)),
          const SizedBox(height: 12),
          Row(children: const [
            _PuntoLeyenda(color: PortalColores.cian, texto: 'Programados'),
            SizedBox(width: 14),
            _PuntoLeyenda(color: PortalColores.lima, texto: 'Completados'),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                lineBarsData: [
                  serie(programados, PortalColores.cian.withValues(alpha: 0.65),
                      punteada: true),
                  serie(completados, PortalColores.lima, area: true),
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (v) => const FlLine(
                      color: PortalColores.divisor, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final int i = v.toInt();
                        if (i < 0 || i >= meses.length || v % 1 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_etiqueta(meses[i].mes),
                              style: PortalTipografia.etiqueta(tamano: 8.5)),
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
                        horizontal: 12, vertical: 8),
                    getTooltipItems: (spots) => spots.map((s) {
                      final bool comp = s.barIndex == 1;
                      return LineTooltipItem(
                        '${comp ? 'Completados' : 'Programados'} ${s.y.toInt()}',
                        PortalTipografia.etiqueta(
                          tamano: 11,
                          color: comp ? PortalColores.lima : PortalColores.cian,
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

// ─── Donut: parque por estado de intervención ────────────────────────────────

class _CardParque extends StatelessWidget {
  const _CardParque({required this.segmentos, required this.total});
  final List<AnalyticsConteo> segmentos;
  final int total;

  static const Map<String, (String, Color)> _meta = {
    'completado': ('Completado', PortalColores.lima),
    'en_proceso': ('En proceso', PortalColores.cian),
    'pendiente': ('Pendiente', PortalColores.ambar),
  };

  (String, Color) _info(String estado) =>
      _meta[estado] ?? (_capitalizar(estado), PortalColores.violeta);

  static String _capitalizar(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final visibles = segmentos.where((s) => s.cantidad > 0).toList();
    final int suma =
        visibles.fold(0, (a, s) => a + s.cantidad);
    final int totalMostrado = total > 0 ? total : suma;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parque de equipos',
              style: PortalTipografia.titulo(tamano: 13)),
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
                        for (final s in visibles)
                          PieChartSectionData(
                            value: s.cantidad.toDouble(),
                            color: _info(s.etiqueta).$2,
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
                      Text(PortalFormato.entero(totalMostrado),
                          style: PortalTipografia.kpi(tamano: 24)),
                      Text('equipos',
                          style: PortalTipografia.etiqueta(tamano: 9.5)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final s in visibles) ...[
            Builder(builder: (_) {
              final info = _info(s.etiqueta);
              final pct = suma > 0 ? s.cantidad / suma * 100 : 0.0;
              return Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: info.$2, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(info.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PortalTipografia.etiqueta(tamano: 10)),
                  ),
                  Text(PortalFormato.porcentaje(pct),
                      style: PortalTipografia.etiqueta(
                          tamano: 10,
                          color: PortalColores.textoPrimario,
                          peso: FontWeight.w700)),
                ],
              );
            }),
            if (s != visibles.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

// ─── Criticidad: ventanas de próximo mantenimiento ───────────────────────────

class _CardCriticidad extends StatelessWidget {
  const _CardCriticidad({required this.v});
  final AnalyticsVentana v;

  @override
  Widget build(BuildContext context) {
    final filas = <(String, int, Color)>[
      ('Vencidos', v.vencidos, PortalColores.coral),
      ('En 30 días', v.en30d, PortalColores.ambar),
      ('31–90 días', v.en90d, PortalColores.cian),
      ('Más de 90 días', v.mas90d, PortalColores.lima),
      if (v.sinFecha > 0) ('Sin programar', v.sinFecha, PortalColores.violeta),
    ];
    final int maxV = filas.fold(0, (a, f) => math.max(a, f.$2));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Próximos mantenimientos',
              style: PortalTipografia.titulo(tamano: 13)),
          const SizedBox(height: 16),
          for (int i = 0; i < filas.length; i++) ...[
            _BarraVentana(
              etiqueta: filas[i].$1,
              valor: filas[i].$2,
              color: filas[i].$3,
              fraccion: maxV > 0 ? filas[i].$2 / maxV : 0,
            ),
            if (i != filas.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _BarraVentana extends StatelessWidget {
  const _BarraVentana({
    required this.etiqueta,
    required this.valor,
    required this.color,
    required this.fraccion,
  });

  final String etiqueta;
  final int valor;
  final Color color;
  final double fraccion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PortalTipografia.etiqueta(tamano: 10.5)),
            ),
            Text(PortalFormato.entero(valor),
                style: PortalTipografia.etiqueta(
                    tamano: 11,
                    color: PortalColores.textoPrimario,
                    peso: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraccion.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeOutCubic,
            builder: (context, f, _) => LinearProgressIndicator(
              value: f,
              minHeight: 6,
              backgroundColor: const Color(0x12FFFFFF),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Distribución por sede ───────────────────────────────────────────────────

class _CardSedes extends StatelessWidget {
  const _CardSedes({required this.sedes});
  final List<AnalyticsSede> sedes;

  @override
  Widget build(BuildContext context) {
    final visibles = sedes.take(8).toList();
    final int maxV = visibles.fold(0, (a, s) => math.max(a, s.cantidad));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Equipos por sede',
              style: PortalTipografia.titulo(tamano: 15)),
          if (sedes.length > visibles.length) ...[
            const SizedBox(height: 4),
            Text('Top ${visibles.length} de ${sedes.length} sedes',
                style: PortalTipografia.etiqueta(tamano: 10.5)),
          ],
          const SizedBox(height: 14),
          for (int i = 0; i < visibles.length; i++) ...[
            _BarraVentana(
              etiqueta: visibles[i].sede,
              valor: visibles[i].cantidad,
              color: PortalColores.cian,
              fraccion: maxV > 0 ? visibles[i].cantidad / maxV : 0,
            ),
            if (i != visibles.length - 1) const SizedBox(height: 11),
          ],
        ],
      ),
    );
  }
}

// ─── Heatmap de inspecciones ─────────────────────────────────────────────────

class _CardHeatmap extends StatelessWidget {
  const _CardHeatmap({required this.dias});
  final List<AnalyticsDia> dias;

  static const List<String> _diasSemana = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const int _semanas = 12;

  static Color _color(int v) {
    if (v <= 0) return const Color(0x0AFFFFFF);
    if (v <= 1) return PortalColores.lima.withValues(alpha: 0.30);
    if (v <= 3) return PortalColores.lima.withValues(alpha: 0.60);
    return PortalColores.lima;
  }

  @override
  Widget build(BuildContext context) {
    // Mapa fecha(YYYY-MM-DD) -> cantidad
    final mapa = <String, int>{for (final d in dias) d.fecha: d.cantidad};

    // Última columna = semana actual; alineamos a lunes.
    final hoy = DateTime.now();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);
    final int desdeLunes = (hoySolo.weekday - DateTime.monday) % 7;
    final lunesActual = hoySolo.subtract(Duration(days: desdeLunes));

    String key(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    // columnas[semana][dia] -> cantidad (semana 0 = más antigua)
    final columnas = List.generate(_semanas, (s) {
      final lunesSemana =
          lunesActual.subtract(Duration(days: 7 * (_semanas - 1 - s)));
      return List.generate(7, (d) {
        final fecha = lunesSemana.add(Duration(days: d));
        if (fecha.isAfter(hoySolo)) return -1; // futuro: vacío sin borde
        return mapa[key(fecha)] ?? 0;
      });
    });

    Widget celda(int v) => AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: v < 0 ? PortalColores.transparente : _color(v),
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
          Text('Actividad de inspecciones',
              style: PortalTipografia.titulo(tamano: 15)),
          const SizedBox(height: 4),
          Text('Últimas 12 semanas',
              style: PortalTipografia.etiqueta(tamano: 10.5)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  for (final d in _diasSemana) ...[
                    SizedBox(
                      height: 16,
                      child: Text(d,
                          style: PortalTipografia.etiqueta(tamano: 8.5)),
                    ),
                    const SizedBox(height: 3),
                  ],
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    for (int dia = 0; dia < 7; dia++) ...[
                      Row(
                        children: [
                          for (int sem = 0; sem < _semanas; sem++) ...[
                            Expanded(child: celda(columnas[sem][dia])),
                            if (sem != _semanas - 1) const SizedBox(width: 3),
                          ],
                        ],
                      ),
                      if (dia != 6) const SizedBox(height: 3),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Garantías ───────────────────────────────────────────────────────────────

class _CardGarantias extends StatelessWidget {
  const _CardGarantias({required this.garantias});
  final List<AnalyticsGarantia> garantias;

  String _fecha(String? iso) {
    if (iso == null) return '—';
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }

  @override
  Widget build(BuildContext context) {
    final visibles = garantias.take(6).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Garantías', style: PortalTipografia.titulo(tamano: 15)),
          const SizedBox(height: 14),
          for (int i = 0; i < visibles.length; i++) ...[
            Row(
              children: [
                Icon(
                  visibles[i].vencida
                      ? Icons.error_outline
                      : Icons.verified_outlined,
                  size: 18,
                  color: visibles[i].vencida
                      ? PortalColores.coral
                      : PortalColores.lima,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    visibles[i].razonSocial.isEmpty
                        ? 'Carta de garantía'
                        : visibles[i].razonSocial,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PortalTipografia.cuerpo(
                        tamano: 12, color: PortalColores.textoPrimario),
                  ),
                ),
                Text(
                  '${visibles[i].vencida ? 'Venció' : 'Vence'} ${_fecha(visibles[i].vigencia)}',
                  style: PortalTipografia.etiqueta(
                    tamano: 10,
                    color: visibles[i].vencida
                        ? PortalColores.coral
                        : PortalColores.textoSecundario,
                  ),
                ),
              ],
            ),
            if (i != visibles.length - 1)
              const Divider(height: 18, color: PortalColores.divisor),
          ],
        ],
      ),
    );
  }
}

// ─── ITSE ────────────────────────────────────────────────────────────────────

class _CardItse extends StatelessWidget {
  const _CardItse({required this.itse});
  final List<AnalyticsConteo> itse;

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final int total = itse.fold(0, (a, e) => a + e.cantidad);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PortalDecoraciones.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inspecciones ITSE',
              style: PortalTipografia.titulo(tamano: 15)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in itse)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: PortalColores.fondo,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PortalColores.bordeCard),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${e.cantidad}',
                          style: PortalTipografia.kpi(tamano: 18)),
                      const SizedBox(width: 6),
                      Text(_cap(e.etiqueta),
                          style: PortalTipografia.etiqueta(tamano: 11)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('$total inspecciones en total',
              style: PortalTipografia.etiqueta(tamano: 10)),
        ],
      ),
    );
  }
}

// ─── Pie de página ───────────────────────────────────────────────────────────

class _PieDePagina extends StatelessWidget {
  const _PieDePagina();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Text(
          'Información en tiempo real, sin proyecciones.',
          style: PortalTipografia.etiqueta(tamano: 10),
        ),
      ),
    );
  }
}

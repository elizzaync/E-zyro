import 'dart:math' show pi;
import 'package:flutter/material.dart';

import '../models/personal_models.dart';
import '../models/evaluacion_models.dart';
import '../models/vacaciones_models.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_preview_screen.dart';
import '../services/personal_service.dart';
import '../services/vacaciones_service.dart';
import '../utils/abrir_enlace.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import 'pantalla_evaluaciones.dart'
    show ConfigEvaluacionesScreen, DetalleEvaluacionScreen;
import 'pantalla_vacaciones.dart';
import 'pantalla_indicadores.dart';
import 'pantalla_bandeja_solicitudes.dart';
import 'pantalla_control_asistencias.dart';
import 'pantalla_personal.dart';

// ─── Design tokens (Ficha Colaborador) ────────────────────────────────────────
const _kBg = Color(0xFFF4F4EC);
const _kGreen = Color(0xFF5E9A1C);
const _kGreenBg = Color(0xFFE9F3DA);
const _kDark = Color(0xFF2A2E2A);
const _kLabel = Color(0xFFA8AD9F);
const _kSub = Color(0xFF9AA093);
const _kOrange = Color(0xFFE0992C);
const _kOrangeBg = Color(0xFFFCEFD9);
const _kRed = Color(0xFFD85C52);
const _kRedBg = Color(0xFFFBEBEA);
const _kBlue = Color(0xFF4A90C2);
const _kBlueBg = Color(0xFFE3EEF5);
const _kDivider = Color(0xFFF2F3EC);

const _kShadow = [
  BoxShadow(color: Color(0x0A28322A), blurRadius: 8, offset: Offset(0, 2)),
];

BoxDecoration _cardDec([double radius = 16]) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: _kShadow,
);

Widget _sectionHeader(String label, {int? badge}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Row(
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kLabel,
          letterSpacing: 0.8,
        ),
      ),
      if (badge != null) ...[
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFECEDE4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$badge',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _kDark,
            ),
          ),
        ),
      ],
    ],
  ),
);

({Color col, Color bg}) _evalColors(String estado) => switch (estado) {
  'completada' => (col: _kGreen, bg: _kGreenBg),
  'asignada' => (col: _kOrange, bg: _kOrangeBg),
  'enviada' => (col: _kBlue, bg: _kBlueBg),
  _ => (col: _kSub, bg: const Color(0xFFF1F2EB)),
};

String _evalStatusLabel(String estado) => switch (estado) {
  'completada' => 'Completada',
  'asignada' => 'Pendiente',
  'enviada' => 'Enviada',
  _ => 'Borrador',
};

// ═══════════════════════════════════════════════════════════════════════════
// Hub de Personal (lista + accesos globales RR.HH.)
// ═══════════════════════════════════════════════════════════════════════════
class PantallaPersonalHub extends StatefulWidget {
  const PantallaPersonalHub({super.key});

  @override
  State<PantallaPersonalHub> createState() => _PantallaPersonalHubState();
}

class _PantallaPersonalHubState extends State<PantallaPersonalHub> {
  PersonalService? _svc;
  final _busca = TextEditingController();
  List<Empleado> _empleados = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getPersonalService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final r = await _svc!.listar(q: _busca.text);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _empleados = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Recursos Humanos',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          _accesosEmpresa(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _busca,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, cargo o código',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _cargar,
                ),
              ),
              onSubmitted: (_) => _cargar(),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _empleados.isEmpty
                ? const Center(child: Text('Sin empleados.'))
                : RefreshIndicator(onRefresh: _cargar, child: _lista()),
          ),
        ],
      ),
    );
  }

  void _push(Widget pantalla) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));

  Widget _accesosEmpresa() {
    final s = AppSession.i;
    final chips = <Widget>[
      if (s.canVerControlAsistencias)
        _chip(
          'Asistencias',
          Icons.how_to_reg_outlined,
          Colors.green.shade700,
          () => _push(const PantallaControlAsistencias()),
        ),
      if (s.canVerControlAsistencias || s.canVerPersonal)
        _chip(
          'Solicitudes',
          Icons.fact_check_outlined,
          Colors.orange.shade800,
          () => _push(const PantallaBandejaSolicitudes()),
        ),
      if (s.canVerIndicadores)
        _chip(
          'Indicadores',
          Icons.insights_outlined,
          Colors.indigo,
          () => _push(const PantallaIndicadores()),
        ),
      if (s.canVerVacaciones)
        _chip(
          'Vacaciones',
          Icons.beach_access_outlined,
          Colors.teal,
          () => _push(const PantallaVacaciones()),
        ),
      if (s.canVerEvaluacion)
        _chip(
          'Config. Eval.',
          Icons.assessment_outlined,
          Colors.deepPurple,
          () => _push(const ConfigEvaluacionesScreen()),
        ),
      if (s.canVerPersonal)
        _chip(
          'Sesiones',
          Icons.phonelink_lock_outlined,
          Colors.blueGrey,
          () => _push(const PantallaPersonal()),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 8, children: chips),
      ),
    );
  }

  Widget _chip(String label, IconData icon, Color color, VoidCallback onTap) =>
      ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
        onPressed: onTap,
        backgroundColor: color.withValues(alpha: 0.08),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      );

  Widget _lista() => ListView.separated(
    itemCount: _empleados.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, i) {
      final e = _empleados[i];
      return ListTile(
        leading: CircleAvatar(
          backgroundImage: (e.fotoUrl != null && e.fotoUrl!.isNotEmpty)
              ? NetworkImage(e.fotoUrl!)
              : null,
          child: (e.fotoUrl == null || e.fotoUrl!.isEmpty)
              ? const Icon(Icons.person_outline)
              : null,
        ),
        title: Text(e.nombre ?? e.codigo ?? e.id),
        subtitle: Text(
          [e.cargo, e.area].where((s) => s != null && s.isNotEmpty).join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PantallaEmpleadoDetalle(empleado: e),
          ),
        ),
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Detalle de empleado — Ficha Colaborador (3 tabs)
// ═══════════════════════════════════════════════════════════════════════════
class PantallaEmpleadoDetalle extends StatelessWidget {
  final Empleado empleado;
  const PantallaEmpleadoDetalle({super.key, required this.empleado});

  String _initials() {
    final name = (empleado.nombre ?? '').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          foregroundColor: _kDark,
          toolbarHeight: 48,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(130),
            child: Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Employee info row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kGreenBg,
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: _kGreen,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                empleado.nombre ?? 'Empleado',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: _kDark,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  if (empleado.area != null &&
                                      empleado.area!.isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _kGreenBg,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        empleado.area!,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: _kGreen,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                  ],
                                  if (empleado.codigo != null &&
                                      empleado.codigo!.isNotEmpty)
                                    Text(
                                      '#${empleado.codigo}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF6B7064),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // TabBar
                  const TabBar(
                    indicatorColor: _kGreen,
                    indicatorWeight: 2.5,
                    labelColor: _kDark,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelColor: _kLabel,
                    unselectedLabelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    dividerColor: Color(0xFFE6E7DE),
                    tabs: [
                      Tab(text: 'Historial'),
                      Tab(text: 'Evaluaciones'),
                      Tab(text: 'Vacaciones'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _HistorialTab(empleado: empleado),
            _EvaluacionesTab(empleado: empleado),
            _VacacionesTab(empleado: empleado),
          ],
        ),
      ),
    );
  }
}

// ─── Tab Historial ────────────────────────────────────────────────────────────
class _HistorialTab extends StatefulWidget {
  final Empleado empleado;
  const _HistorialTab({required this.empleado});

  @override
  State<_HistorialTab> createState() => _HistorialTabState();
}

class _HistorialTabState extends State<_HistorialTab>
    with AutomaticKeepAliveClientMixin {
  HistorialPersonal? _h;
  bool _cargando = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final svc = await getPersonalService();
    final r = await svc.historial(widget.empleado.id);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _h = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  Future<void> _exportarPdf() async {
    final h = _h;
    if (h == null) return;
    final bytes = await PdfService.historialPersonal(h);
    if (!mounted) return;
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo: 'historial_personal_${widget.empleado.id}.pdf',
      titulo: 'Historial de personal',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final h = _h;
    if (h == null) return const Center(child: Text('Sin datos.'));
    final e = h.empleado;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // PDF export button
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _exportarPdf,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 15, color: _kGreen),
                  SizedBox(width: 6),
                  Text(
                    'Exportar PDF',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _kGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Resumen de asistencia
          _sectionHeader('Resumen de asistencia'),
          Row(
            children: [
              _statCard('Total', h.asistencia.total, _kDark),
              const SizedBox(width: 10),
              _statCard('Validados', h.asistencia.validados, _kGreen),
              const SizedBox(width: 10),
              _statCard('Pendientes', h.asistencia.pendientes, _kOrange),
              const SizedBox(width: 10),
              _statCard(
                'Rechaz.',
                h.asistencia.rechazados,
                const Color(0xFFC2C7BB),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Datos del colaborador
          _sectionHeader('Datos del colaborador'),
          Container(
            decoration: _cardDec(),
            child: Column(
              children: [
                _dataRow(
                  Icons.work_outline,
                  _kGreen,
                  _kGreenBg,
                  'Cargo',
                  e.cargo,
                ),
                _dataRow(
                  Icons.location_city_outlined,
                  _kBlue,
                  _kBlueBg,
                  'Área',
                  e.area,
                ),
                _dataRow(
                  Icons.calendar_today_outlined,
                  _kGreen,
                  _kGreenBg,
                  'Ingreso',
                  e.fechaIngreso,
                ),
                _dataRow(
                  Icons.event_outlined,
                  _kSub,
                  const Color(0xFFF1F2EB),
                  'Fin contrato',
                  e.fechaFinContrato ?? 'Indefinido',
                  valueColor: _kSub,
                ),
                _dataRow(
                  Icons.check_circle_outline,
                  e.activo ? _kGreen : _kRed,
                  e.activo ? _kGreenBg : _kRedBg,
                  'Estado',
                  e.activo ? 'Activo' : 'Inactivo',
                  valueColor: e.activo ? _kGreen : _kRed,
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Mini stats
          Row(
            children: [
              _miniStat('Contratos', h.contratos.length),
              const SizedBox(width: 10),
              _miniStat('Solicitudes', h.solicitudes.length),
              const SizedBox(width: 10),
              _miniStat('EPP', h.epp.length),
            ],
          ),
          const SizedBox(height: 18),

          // Últimas marcaciones
          if (h.marcaciones.isNotEmpty) ...[
            _sectionHeader('Últimas marcaciones', badge: h.marcaciones.length),
            Container(
              decoration: _cardDec(),
              child: Column(
                children: [
                  for (int i = 0; i < h.marcaciones.length; i++)
                    _marcacionRow(
                      h.marcaciones[i],
                      isLast: i == h.marcaciones.length - 1,
                    ),
                ],
              ),
            ),
          ],

          // Contratos
          if (h.contratos.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionHeader('Contratos', badge: h.contratos.length),
            Container(
              decoration: _cardDec(),
              child: Column(
                children: [
                  for (int i = 0; i < h.contratos.length; i++)
                    _listaRow(
                      icon: Icons.description_outlined,
                      title: h.contratos[i].tipo,
                      subtitle:
                          '${h.contratos[i].fechaInicio ?? '-'} → ${h.contratos[i].fechaFin ?? '-'} · ${h.contratos[i].estado ?? '-'}',
                      isLast: i == h.contratos.length - 1,
                    ),
                ],
              ),
            ),
          ],

          // Solicitudes laborales
          if (h.solicitudes.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionHeader('Solicitudes', badge: h.solicitudes.length),
            Container(
              decoration: _cardDec(),
              child: Column(
                children: [
                  for (int i = 0; i < h.solicitudes.length; i++)
                    _listaRow(
                      icon: Icons.event_note_outlined,
                      title: h.solicitudes[i].tipo,
                      subtitle:
                          '${h.solicitudes[i].fechaInicio ?? '-'} → ${h.solicitudes[i].fechaFin ?? '-'} · ${h.solicitudes[i].estado ?? '-'}',
                      trailing: h.solicitudes[i].urlPdf != null
                          ? GestureDetector(
                              onTap: () => abrirEnlace(h.solicitudes[i].urlPdf),
                              child: const Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: _kSub,
                              ),
                            )
                          : null,
                      isLast: i == h.solicitudes.length - 1,
                    ),
                ],
              ),
            ),
          ],

          // EPP
          if (h.epp.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionHeader('EPP entregado', badge: h.epp.length),
            Container(
              decoration: _cardDec(),
              child: Column(
                children: [
                  for (int i = 0; i < h.epp.length; i++)
                    _listaRow(
                      icon: Icons.health_and_safety_outlined,
                      title:
                          '${h.epp[i].fecha ?? '-'} · ${h.epp[i].items} ítem(s)',
                      subtitle: h.epp[i].estado ?? '-',
                      isLast: i == h.epp.length - 1,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCard(String label, int value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: _cardDec(),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: _kSub,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _dataRow(
    IconData icon,
    Color iconColor,
    Color iconBg,
    String label,
    String? value, {
    Color? valueColor,
    bool isLast = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      border: isLast
          ? null
          : const Border(bottom: BorderSide(color: _kDivider, width: 1)),
    ),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _kSub,
            ),
          ),
        ),
        Text(
          value ?? '—',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: valueColor ?? _kDark,
          ),
          textAlign: TextAlign.right,
        ),
      ],
    ),
  );

  Widget _miniStat(String label, int value) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: _cardDec(14),
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _kDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: _kSub,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _marcacionRow(MarcacionItem m, {bool isLast = false}) {
    final isEntrada = m.tipo.toLowerCase().contains('entrada');
    final iconColor = isEntrada ? _kGreen : _kBlue;
    final iconBg = isEntrada ? _kGreenBg : _kBlueBg;
    final estadoCol = switch (m.estado?.toLowerCase()) {
      'validado' || 'válido' => _kGreen,
      'rechazado' => _kRed,
      _ => _kOrange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _kDivider, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEntrada ? Icons.login : Icons.logout,
              size: 15,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.tipo,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _kDark,
                  ),
                ),
                Text(
                  m.fechaHora ?? '-',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _kSub,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: estadoCol,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                m.estado ?? '-',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: estadoCol,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listaRow({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    bool isLast = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      border: isLast
          ? null
          : const Border(bottom: BorderSide(color: _kDivider, width: 1)),
    ),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F2EB),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: _kSub),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _kDark,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _kSub,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );
}

// ─── Tab Evaluaciones ─────────────────────────────────────────────────────────
class _EvaluacionesTab extends StatefulWidget {
  final Empleado empleado;
  const _EvaluacionesTab({required this.empleado});

  @override
  State<_EvaluacionesTab> createState() => _EvaluacionesTabState();
}

class _EvaluacionesTabState extends State<_EvaluacionesTab>
    with AutomaticKeepAliveClientMixin {
  List<Evaluacion> _items = [];
  bool _cargando = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final svc = await getEvaluacionService();
    final r = await svc.listar(empleadoId: widget.empleado.id);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _items = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  Future<void> _asignarEvaluacion() async {
    final svc = await getEvaluacionService();
    final r = await svc.listarPlantillas();
    if (!mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(r.errorMessage)));
      return;
    }
    final plantillas = r.data ?? [];
    if (plantillas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay plantillas activas. Crea una en Config. Evaluaciones.',
          ),
        ),
      );
      return;
    }

    PlantillaEvaluacion? selPlantilla;
    final periodo = TextEditingController(
      text: '${DateTime.now().year}-S${DateTime.now().month <= 6 ? '1' : '2'}',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Asignar evaluación'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: periodo,
                  decoration: const InputDecoration(
                    labelText: 'Periodo (ej. 2026-S1)',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Plantilla',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                ...plantillas.map(
                  (p) => RadioListTile<PlantillaEvaluacion>(
                    dense: true,
                    title: Text(p.nombre, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${TipoEvaluacion.etiquetaCorta(p.tipo)} · ${p.items.length} criterios',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: p,
                    groupValue: selPlantilla,
                    onChanged: (v) => setLocal(() => selPlantilla = v),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (selPlantilla == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona una plantilla')));
      return;
    }
    if (periodo.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Indica el periodo')));
      return;
    }

    final r2 = await svc.asignarPlantilla(
      plantillaId: selPlantilla!.id,
      empleadoIds: [widget.empleado.id],
      periodo: periodo.text.trim(),
    );
    if (!mounted) return;
    if (r2.ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Evaluación asignada')));
      _cargar();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(r2.errorMessage)));
    }
  }

  String _promedioLabel(double v) {
    if (v >= 9) return 'Excelente desempeño';
    if (v >= 7) return 'Buen desempeño';
    if (v >= 5) return 'Desempeño regular';
    return 'Necesita mejora';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    final completadas = _items.where((e) => e.estado == 'completada').toList();
    final promedio = completadas.isEmpty
        ? null
        : completadas.map((e) => e.promedio ?? 0.0).reduce((a, b) => a + b) /
              completadas.length;

    return Scaffold(
      backgroundColor: _kBg,
      floatingActionButton: AppSession.i.canCrearEvaluacion
          ? FloatingActionButton.extended(
              onPressed: _asignarEvaluacion,
              backgroundColor: _kGreen,
              elevation: 6,
              icon: const Icon(Icons.assignment_add, color: Colors.white),
              label: const Text(
                'Asignar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // Summary card (donut + promedio)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDec(18),
              child: Row(
                children: [
                  // Donut chart
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(76, 76),
                          painter: _DonutPainter(promedio ?? 0),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              promedio != null
                                  ? promedio.toStringAsFixed(1)
                                  : '—',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _kDark,
                                height: 1,
                              ),
                            ),
                            const Text(
                              '/ 10',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: _kSub,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PROMEDIO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _kLabel,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          promedio != null
                              ? _promedioLabel(promedio)
                              : 'Sin evaluaciones',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _kDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${completadas.length} evaluación(es) completada(s)',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _kSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            if (_items.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Sin evaluaciones para este colaborador.',
                    style: TextStyle(color: _kSub),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              _sectionHeader('Evaluaciones', badge: _items.length),
              ..._items.map(_evalCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _evalCard(Evaluacion e) {
    final cs = _evalColors(e.estado);
    final score = e.promedio?.toStringAsFixed(1) ?? '—';
    final statusLabel = _evalStatusLabel(e.estado);

    return GestureDetector(
      onTap: () async {
        final cambio = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => DetalleEvaluacionScreen(evaluacionId: e.id),
          ),
        );
        if (cambio == true) _cargar();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: _cardDec(),
        child: Row(
          children: [
            // Score chip
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.bg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(
                  score,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: cs.col,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TipoEvaluacion.etiqueta(e.tipo),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _kDark,
                    ),
                  ),
                  Text(
                    'Periodo ${e.periodo} · ${e.fecha ?? '-'}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: _kSub,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.col,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFC2C7BB), size: 17),
          ],
        ),
      ),
    );
  }
}

// ─── Donut chart painter ───────────────────────────────────────────────────────
class _DonutPainter extends CustomPainter {
  final double value; // 0–10

  _DonutPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - 8) / 2;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFFEEF0E8)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke,
    );

    if (value > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -pi / 2,
        2 * pi * (value / 10).clamp(0.0, 1.0),
        false,
        Paint()
          ..color = _kGreen
          ..strokeWidth = 8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.value != value;
}

// ─── Tab Vacaciones ───────────────────────────────────────────────────────────
class _VacacionesTab extends StatefulWidget {
  final Empleado empleado;
  const _VacacionesTab({required this.empleado});

  @override
  State<_VacacionesTab> createState() => _VacacionesTabState();
}

class _VacacionesTabState extends State<_VacacionesTab>
    with AutomaticKeepAliveClientMixin {
  VacacionesService? _svc;
  SaldoVacaciones? _saldo;
  List<SolicitudVacaciones> _solicitudes = [];
  bool _cargando = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getVacacionesService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final sld = await _svc!.listarSaldos();
    final sol = await _svc!.listarSolicitudes(empleadoId: widget.empleado.id);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (sld.ok) {
        final lista = sld.data ?? [];
        _saldo = lista
            .where((s) => s.empleadoId == widget.empleado.id)
            .firstOrNull;
      }
      if (sol.ok) {
        _solicitudes = sol.data ?? [];
      } else {
        _error = sol.errorMessage;
      }
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _resolver(SolicitudVacaciones s, bool aprobar) async {
    final r = await _svc!.resolver(s.id, aprobar: aprobar);
    if (!mounted) return;
    r.ok ? _cargar() : _snack(r.errorMessage, error: true);
  }

  Color _colorEstado(String e) => switch (e) {
    'aprobada' => _kGreen,
    'rechazada' => _kRed,
    'cancelada' => _kSub,
    _ => _kOrange,
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    final pendientes = _solicitudes
        .where((s) => s.estado == 'pendiente')
        .toList();
    final historial = _solicitudes
        .where((s) => s.estado != 'pendiente')
        .toList();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Balance hero card
          if (_saldo != null) _heroSaldo(_saldo!),

          // Solicitudes pendientes
          if (pendientes.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionHeader('Solicitudes pendientes', badge: pendientes.length),
            ...pendientes.map(_solicitudCard),
          ],

          // Historial
          if (historial.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionHeader('Historial', badge: historial.length),
            Container(
              decoration: _cardDec(),
              child: Column(
                children: [
                  for (int i = 0; i < historial.length; i++) ...[
                    _historialRow(
                      historial[i],
                      isLast: i == historial.length - 1,
                    ),
                  ],
                ],
              ),
            ),
          ],

          if (_solicitudes.isEmpty && _saldo == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Sin información de vacaciones.',
                  style: TextStyle(color: _kSub),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heroSaldo(SaldoVacaciones s) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2FAF8F), Color(0xFF1E8C72)],
      ),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1E8C72).withValues(alpha: 0.45),
          blurRadius: 28,
          spreadRadius: -10,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Stack(
      children: [
        // Decorative circle
        Positioned(
          right: -30,
          top: -30,
          child: Container(
            width: 130,
            height: 130,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x14FFFFFF),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      s.disponible.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'días',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const Text(
                  'disponibles',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xD9FFFFFF),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xD9FFFFFF),
                    ),
                    children: [
                      const TextSpan(text: 'Devengado  '),
                      TextSpan(
                        text: s.devengado.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xD9FFFFFF),
                    ),
                    children: [
                      const TextSpan(text: 'Gozado  '),
                      TextSpan(
                        text: '${s.gozado}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${s.mesesServicio} meses · tope ${s.topeAcumulacion}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xB3FFFFFF),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  Widget _solicitudCard(SolicitudVacaciones s) {
    final puedeResolver =
        AppSession.i.canAprobarVacaciones || AppSession.i.canRechazarVacaciones;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDec(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Days chip
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _kOrangeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${s.dias}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kOrange,
                        height: 1,
                      ),
                    ),
                    const Text(
                      'días',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: _kOrange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.fechaInicio ?? '-'} → ${s.fechaFin ?? '-'}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kDark,
                      ),
                    ),
                    if (s.motivo != null)
                      Text(
                        s.motivo!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: _kSub,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (puedeResolver) ...[
            const SizedBox(height: 13),
            Row(
              children: [
                if (AppSession.i.canAprobarVacaciones)
                  Expanded(
                    child: _accionBtn(
                      'Aprobar',
                      Icons.check,
                      _kGreen,
                      _kGreenBg,
                      () => _resolver(s, true),
                    ),
                  ),
                if (AppSession.i.canAprobarVacaciones &&
                    AppSession.i.canRechazarVacaciones)
                  const SizedBox(width: 9),
                if (AppSession.i.canRechazarVacaciones)
                  Expanded(
                    child: _accionBtn(
                      'Rechazar',
                      Icons.close,
                      _kRed,
                      _kRedBg,
                      () => _resolver(s, false),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _accionBtn(
    String label,
    IconData icon,
    Color col,
    Color bg,
    VoidCallback onTap,
  ) => Material(
    color: bg,
    borderRadius: BorderRadius.circular(11),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: col),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: col,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _historialRow(SolicitudVacaciones s, {bool isLast = false}) {
    final col = _colorEstado(s.estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _kDivider, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.beach_access_outlined, size: 18, color: col),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.fechaInicio ?? '-'} → ${s.fechaFin ?? '-'} · ${s.dias} día(s)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kDark,
                  ),
                ),
                if (s.motivo != null)
                  Text(
                    s.motivo!,
                    style: const TextStyle(fontSize: 11, color: _kSub),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              s.estado,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: col,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_result.dart';
import '../models/asistencia_models.dart';
import '../models/evaluacion_models.dart';
import '../models/solicitud_models.dart';
import '../models/vacaciones_models.dart';
import '../services/solicitud_service.dart';
import '../services/vacaciones_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import 'pantalla_editar_perfil.dart';
import 'pantalla_evaluaciones.dart' show DetalleEvaluacionScreen;

// ── Design tokens ────────────────────────────────────────────────────────────
const _kGreen      = Color(0xFF5E9A1C);
const _kGreenLight = Color(0xFF8FC53C);
const _kBg         = Color(0xFFF4F4EC);
const _kTextDark   = Color(0xFF2A2E2A);
const _kTextMuted  = Color(0xFF9AA093);
const _kTextLabel  = Color(0xFFA8AD9F);
const _kBorder     = Color(0xFFE6E7DE);
const _kBlue       = Color(0xFF4A90C2);
const _kPurple     = Color(0xFF8267C0);
const _kOrange     = Color(0xFFE0992C);
const _kOrangeBg   = Color(0xFFFCEFD9);
const _kGreenBg    = Color(0xFFE9F3DA);

BoxDecoration _cardDeco({double radius = 16}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A28302A),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    );

// ── Root ─────────────────────────────────────────────────────────────────────
class PantallaMiEspacio extends StatelessWidget {
  const PantallaMiEspacio({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text(
            'Mi perfil',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: _kTextDark),
          ),
          iconTheme: const IconThemeData(color: _kTextDark),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(44),
            child: _TabBarEstilo(),
          ),
        ),
        body: const TabBarView(children: [
          _ResumenTab(),
          _MisVacacionesTab(),
          _MisEvaluacionesTab(),
        ]),
      ),
    );
  }
}

class _TabBarEstilo extends StatelessWidget {
  const _TabBarEstilo();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder, width: 1)),
      ),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: _kGreen, width: 2.5),
          insets: EdgeInsets.symmetric(horizontal: 4),
        ),
        labelColor: _kTextDark,
        unselectedLabelColor: _kTextLabel,
        labelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Resumen'),
          Tab(text: 'Mis vacaciones'),
          Tab(text: 'Mis evaluaciones'),
        ],
      ),
    );
  }
}

// ── Helpers: agrupar marcaciones por día ─────────────────────────────────────
class _JornadaDia {
  final DateTime fecha;
  DateTime? entrada;
  DateTime? salida;

  _JornadaDia({required this.fecha});

  static const _meses = [
    'Ene','Feb','Mar','Abr','May','Jun',
    'Jul','Ago','Sep','Oct','Nov','Dic'
  ];

  String get entradaStr => _fmt(entrada);
  String get salidaStr  => _fmt(salida);

  static String _fmt(DateTime? d) {
    if (d == null) return '--:--';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String get totalStr {
    if (entrada == null || salida == null) return '--';
    final diff = salida!.difference(entrada!);
    if (diff.isNegative) return '--';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  bool get esHoy {
    final now = DateTime.now();
    return fecha.year == now.year &&
        fecha.month == now.month &&
        fecha.day == now.day;
  }

  String get dayNum => fecha.day.toString();
  String get mon    => _meses[fecha.month - 1];
}

List<_JornadaDia> _agruparJornadas(List<RegistroAsistencia> marcaciones) {
  final Map<String, _JornadaDia> grupos = {};
  for (final m in marcaciones) {
    if (m.status != 'APROBADO') continue;
    final dt  = m.timestamp;
    final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    grupos.putIfAbsent(key, () => _JornadaDia(fecha: dt));
    if (m.tipo == 'ENTRADA') {
      grupos[key]!.entrada ??= dt;
    } else if (m.tipo == 'SALIDA') {
      if (grupos[key]!.salida == null || dt.isAfter(grupos[key]!.salida!)) {
        grupos[key]!.salida = dt;
      }
    }
  }
  final sorted = grupos.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return sorted.take(4).map((e) => e.value).toList();
}

// ── Resumen ───────────────────────────────────────────────────────────────────
class _ResumenTab extends StatefulWidget {
  const _ResumenTab();

  @override
  State<_ResumenTab> createState() => _ResumenTabState();
}

class _ResumenTabState extends State<_ResumenTab>
    with AutomaticKeepAliveClientMixin {
  ResumenSemanal? _resumen;
  List<SolicitudLaboral> _solicitudes = [];
  List<_JornadaDia> _jornadas = [];
  String _nombre = '';
  bool _cargando = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    final prefs  = await SharedPreferences.getInstance();
    final asis   = await getAsistenciaService();
    final solSvc = await getSolicitudService();
    final resF   = asis.getResumenSemanal();
    final solF   = solSvc.misSolicitudes();
    final histF  = asis.getHistorial();
    final res    = await resF;
    final sol    = await solF;
    final hist   = await histF;
    if (!mounted) return;
    setState(() {
      _nombre     = prefs.getString('user_name') ?? 'Usuario';
      _resumen    = res;
      _solicitudes = sol;
      _jornadas   = _agruparJornadas(hist);
      _cargando   = false;
    });
  }

  String _dur(int min) {
    final h = min ~/ 60;
    final m = min % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String get _iniciales {
    final partes = _nombre.trim().split(RegExp(r'\s+'));
    final a = partes.isNotEmpty && partes[0].isNotEmpty ? partes[0][0] : '';
    final b = partes.length > 1 && partes[1].isNotEmpty ? partes[1][0] : '';
    final ini = (a + b).toUpperCase();
    return ini.isEmpty ? '?' : ini;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) {
      return const Center(
          child: CircularProgressIndicator(color: _kGreen));
    }
    final r = _resumen;

    return RefreshIndicator(
      color: _kGreen,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // ── Perfil + stats de la semana ──────────────────────────────
          Container(
            decoration: _cardDeco(radius: 18),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Color(0xFFDCE7CB),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _iniciales,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: _kGreen),
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nombre,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _kTextDark),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              AppSession.i.cargo.isNotEmpty
                                  ? AppSession.i.cargo
                                  : (AppSession.i.rol.isEmpty
                                      ? 'Colaborador'
                                      : AppSession.i.rol),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _kTextMuted),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const EditProfileScreen())),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _kBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.edit_outlined,
                              size: 14, color: Color(0xFF6B7064)),
                        ),
                      ),
                    ],
                  ),
                ),
                // Stats semana
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                        top: BorderSide(color: Color(0xFFF2F3EC), width: 1)),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        _statCell(
                          r != null ? _dur(r.minutosTrabajadosSemana) : '--',
                          'Horas',
                          _kBlue,
                          right: true,
                        ),
                        _statCell(
                          r != null ? '${r.diasTrabajados}' : '--',
                          'Días',
                          _kPurple,
                          right: true,
                        ),
                        _statCell(
                          r?.puntualidadPct != null
                              ? '${r!.puntualidadPct}%'
                              : '--',
                          'Puntualidad',
                          _kGreen,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Jornadas recientes ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'JORNADAS RECIENTES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kTextLabel,
                    letterSpacing: 0.8),
              ),
              Text(
                'Historial',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _kGreen),
              ),
            ],
          ),
          const SizedBox(height: 9),

          if (_jornadas.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDeco(),
              child: const Center(
                child: Text('Sin jornadas registradas.',
                    style: TextStyle(color: _kTextMuted, fontSize: 13)),
              ),
            )
          else
            ...(_jornadas.map((j) => _jornadaCard(j))),

          const SizedBox(height: 20),

          // ── Mis solicitudes ───────────────────────────────────────────
          const Text(
            'MIS SOLICITUDES',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _kTextLabel,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 9),

          if (_solicitudes.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDeco(),
              child: const Center(
                child: Text('Aún no tienes solicitudes.',
                    style: TextStyle(color: _kTextMuted, fontSize: 13)),
              ),
            )
          else
            ...(_solicitudes.take(5).map((s) => _solicitudCard(s))),
        ],
      ),
    );
  }

  Widget _statCell(String value, String label, Color color,
      {bool right = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: right
              ? const Border(
                  right: BorderSide(color: Color(0xFFF2F3EC), width: 1))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _kTextMuted)),
          ],
        ),
      ),
    );
  }

  Widget _jornadaCard(_JornadaDia j) {
    final chipBg  = j.esHoy ? _kGreenBg : const Color(0xFFF1F2EB);
    final chipCol = j.esHoy ? _kGreen   : const Color(0xFF6B7064);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: _cardDeco(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(12)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(j.dayNum,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: chipCol,
                        height: 1)),
                Text(j.mon,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: chipCol)),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Row(
              children: [
                _tiempoCol('Entrada', j.entradaStr),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.arrow_forward,
                      size: 16, color: Color(0xFFC9CDC1)),
                ),
                _tiempoCol('Salida', j.salidaStr),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(j.totalStr,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _kGreen)),
              const Text('trabajadas',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB0B5AB))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tiempoCol(String label, String hora) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _kTextMuted,
                  letterSpacing: 0.3)),
          const SizedBox(height: 1),
          Text(hora,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _kTextDark)),
        ],
      );

  Widget _solicitudCard(SolicitudLaboral s) {
    Color stCol;
    Color stBg;
    switch (s.estado) {
      case 'aprobada':
        stCol = _kGreen;
        stBg  = _kGreenBg;
        break;
      case 'rechazada':
        stCol = Colors.red.shade600;
        stBg  = Colors.red.shade50;
        break;
      default:
        stCol = _kOrange;
        stBg  = _kOrangeBg;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: _cardDeco(),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: _kOrangeBg,
                borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.calendar_today_outlined,
                size: 17, color: _kOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.tipoLabel,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark)),
                const SizedBox(height: 1),
                Text(s.descripcion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: _kTextMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: stBg, borderRadius: BorderRadius.circular(20)),
            child: Text(
              s.estado[0].toUpperCase() + s.estado.substring(1),
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: stCol),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mis vacaciones ────────────────────────────────────────────────────────────
class _MisVacacionesTab extends StatefulWidget {
  const _MisVacacionesTab();

  @override
  State<_MisVacacionesTab> createState() => _MisVacacionesTabState();
}

class _MisVacacionesTabState extends State<_MisVacacionesTab>
    with AutomaticKeepAliveClientMixin {
  VacacionesService? _svc;
  SaldoVacaciones? _saldo;
  List<SolicitudVacaciones> _solicitudes = [];
  bool _cargando = true;
  String? _error;
  bool _sinFicha = false;

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
      _error    = null;
      _sinFicha = false;
    });
    final sld = await _svc!.miSaldo();
    final sol = await _svc!.misSolicitudes();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (sld.ok) {
        _saldo = sld.data;
      } else if (sld.error?.kind == ApiErrorKind.notFound) {
        _sinFicha = true;
      } else {
        _error = sld.errorMessage;
      }
      if (sol.ok) _solicitudes = sol.data ?? [];
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _solicitar() async {
    DateTime? ini;
    DateTime? fin;
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        String fmt(DateTime? d) => d == null
            ? 'Seleccionar'
            : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        Future<void> pick(bool inicio) async {
          final now = DateTime.now();
          final d = await showDatePicker(
              context: ctx,
              initialDate: now,
              firstDate: now,
              lastDate: DateTime(now.year + 2));
          if (d != null) setLocal(() => inicio ? ini = d : fin = d);
        }
        return AlertDialog(
          title: const Text('Solicitar vacaciones'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Desde'),
                trailing: Text(fmt(ini)),
                onTap: () => pick(true)),
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hasta'),
                trailing: Text(fmt(fin)),
                onTap: () => pick(false)),
            TextField(
                controller: motivo,
                decoration: const InputDecoration(
                    labelText: 'Motivo (opcional)')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Solicitar')),
          ],
        );
      }),
    );
    if (ok != true) return;
    if (ini == null || fin == null) {
      _snack('Selecciona las fechas', error: true);
      return;
    }
    final diasSolicitados = fin!.difference(ini!).inDays + 1;
    final disponible = _saldo?.disponible ?? 0.0;
    if (diasSolicitados > disponible) {
      _snack(
          'Saldo insuficiente: solicitas $diasSolicitados día(s), disponible ${disponible.toStringAsFixed(1)} d',
          error: true);
      return;
    }
    String iso(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = await _svc!.crearSolicitud(
        fechaInicio: iso(ini!),
        fechaFin: iso(fin!),
        motivo: motivo.text.trim().isEmpty ? null : motivo.text.trim());
    if (!mounted) return;
    if (r.ok) {
      _snack('Solicitud enviada');
      _cargar();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  String _antiguedad(SaldoVacaciones s) {
    final a = s.anosServicio;
    final m = s.mesesServicio % 12;
    if (a > 0 && m > 0) return '${a}a ${m}m';
    if (a > 0) return '${a}a';
    return '${m}m';
  }

  ({Color stCol, Color stBg, Color iconCol, Color iconBg}) _colores(String e) {
    return switch (e) {
      'aprobada' => (
          stCol: _kGreen,
          stBg: _kGreenBg,
          iconCol: _kGreen,
          iconBg: _kGreenBg
        ),
      'rechazada' || 'cancelada' => (
          stCol: const Color(0xFF8A8F82),
          stBg: const Color(0xFFF1F2EB),
          iconCol: const Color(0xFF6B7064),
          iconBg: const Color(0xFFF1F2EB)
        ),
      _ => (
          stCol: _kOrange,
          stBg: _kOrangeBg,
          iconCol: _kOrange,
          iconBg: _kOrangeBg
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: _kGreen));
    }
    if (_sinFicha) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.badge_outlined, size: 48, color: Color(0xFF9AA093)),
              SizedBox(height: 12),
              Text('Aún no tienes ficha de empleado',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: _kTextDark)),
              SizedBox(height: 6),
              Text(
                'Tus vacaciones aparecerán aquí cuando\nRecursos Humanos registre tu ficha.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: _kTextMuted, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextMuted)));
    }

    final s = _saldo;
    final disponible   = s?.disponible ?? 0.0;
    final tope         = s?.topeAcumulacion.toDouble() ?? 30.0;
    final progreso     = tope > 0 ? (disponible / tope).clamp(0.0, 1.0) : 0.0;
    final devengado    = s?.devengado ?? 0.0;
    final gozado       = s?.gozado ?? 0;
    final diasPorAnio  = s?.diasPorAnio ?? 30;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: _kGreen,
            onRefresh: _cargar,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              children: [
                // ── Hero saldo ────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2FAF8F), Color(0xFF1E8C72)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x8C1E8C72),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Días disponibles',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xD9FFFFFF)),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            disponible.toStringAsFixed(0),
                            style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '/ $diasPorAnio días',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xD9FFFFFF)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: LinearProgressIndicator(
                          value: progreso,
                          minHeight: 7,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.22),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Régimen: $diasPorAnio días por año',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xD1FFFFFF)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Mini stats ────────────────────────────────────────
                Row(
                  children: [
                    _miniStat(devengado.toStringAsFixed(1), 'Devengados',
                        _kBlue),
                    const SizedBox(width: 10),
                    _miniStat('$gozado', 'Gozados', _kOrange),
                    const SizedBox(width: 10),
                    _miniStat(
                        s != null ? _antiguedad(s) : '--',
                        'Antigüedad',
                        _kTextDark),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Mis solicitudes ───────────────────────────────────
                const Text(
                  'MIS SOLICITUDES',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kTextLabel,
                      letterSpacing: 0.8),
                ),
                const SizedBox(height: 9),

                if (_solicitudes.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: _cardDeco(),
                    child: const Center(
                      child: Text('Sin solicitudes de vacaciones.',
                          style: TextStyle(
                              color: _kTextMuted, fontSize: 13)),
                    ),
                  )
                else
                  ...(_solicitudes.map((v) {
                    final c = _colores(v.estado);
                    final label = v.estado[0].toUpperCase() +
                        v.estado.substring(1);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: _cardDeco(),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: c.iconBg,
                                borderRadius:
                                    BorderRadius.circular(12)),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${v.dias}',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: c.iconCol,
                                      height: 1),
                                ),
                                Text(
                                  'días',
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: c.iconCol),
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
                                  '${v.fechaInicio ?? '-'} – ${v.fechaFin ?? '-'}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _kTextDark),
                                ),
                                if (v.motivo != null) ...[
                                  const SizedBox(height: 1),
                                  Text(v.motivo!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: _kTextMuted)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                                color: c.stBg,
                                borderRadius:
                                    BorderRadius.circular(20)),
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: c.stCol)),
                          ),
                        ],
                      ),
                    );
                  })),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // ── Botón solicitar (sticky bottom) ──────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: GestureDetector(
            onTap: _solicitar,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_kGreenLight, _kGreen],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: _kGreen.withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                      spreadRadius: -8),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: Colors.white, size: 20),
                  SizedBox(width: 9),
                  Text('Solicitar vacaciones',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String value, String label, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: _cardDeco(),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: _kTextMuted)),
            ],
          ),
        ),
      );
}

// ── Mis evaluaciones ──────────────────────────────────────────────────────────
class _MisEvaluacionesTab extends StatefulWidget {
  const _MisEvaluacionesTab();

  @override
  State<_MisEvaluacionesTab> createState() => _MisEvaluacionesTabState();
}

class _MisEvaluacionesTabState extends State<_MisEvaluacionesTab>
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
      _error    = null;
    });
    final svc = await getEvaluacionService();
    final r   = await svc.mias();
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

  double? get _promedioGeneral {
    final completadas =
        _items.where((e) => e.estado == 'completada' && e.promedio != null);
    if (completadas.isEmpty) return null;
    final sum = completadas.fold<double>(0, (acc, e) => acc + e.promedio!);
    return sum / completadas.length;
  }

  double? get _tendencia {
    final completadas = _items
        .where((e) => e.estado == 'completada' && e.promedio != null)
        .toList();
    if (completadas.length < 2) return null;
    return completadas[0].promedio! - completadas[1].promedio!;
  }

  Widget _evalCardAsignada(Evaluacion e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kOrange.withValues(alpha: 0.35)),
        boxShadow: const [
          BoxShadow(color: Color(0x0A28302A), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: _kOrangeBg, borderRadius: BorderRadius.circular(12)),
            child: const Center(
              child: Icon(Icons.pending_actions_outlined,
                  color: _kOrange, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.plantillaNombre ??
                      (e.tipo.isNotEmpty
                          ? e.tipo[0].toUpperCase() + e.tipo.substring(1)
                          : 'Evaluación'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark),
                ),
                const SizedBox(height: 1),
                Text(e.periodo,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: _kTextMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kOrange,
              visualDensity: VisualDensity.compact,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: () async {
              final done = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) => CompletarEvaluacionScreen(evaluacion: e)),
              );
              if (done == true) _cargar();
            },
            child: const Text('Completar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  ({Color scCol, Color scBg}) _scoreColors(Evaluacion e) {
    if (e.estado == 'borrador' || e.estado == 'enviada' || e.estado == 'asignada') {
      return (scCol: _kOrange, scBg: _kOrangeBg);
    }
    final p = e.promedio ?? 0;
    if (p >= 8) return (scCol: _kGreen, scBg: _kGreenBg);
    return (scCol: _kBlue, scBg: const Color(0xFFE3EEF5));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: _kGreen));
    }
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: const TextStyle(color: _kTextMuted)));
    }

    final prom = _promedioGeneral;
    final tend = _tendencia;
    final asignadas = _items.where((e) => e.esAsignada).toList();
    final historial = _items.where((e) => !e.esAsignada).toList();

    return RefreshIndicator(
      color: _kGreen,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // ── Score hero ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: _cardDeco(radius: 22),
            child: Row(
              children: [
                _ScoreGauge(score: prom ?? 0, hasData: prom != null),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PROMEDIO GENERAL',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _kTextLabel,
                            letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        prom == null
                            ? 'Sin evaluaciones'
                            : (prom >= 9
                                ? 'Excelente desempeño'
                                : prom >= 7
                                    ? 'Buen desempeño'
                                    : 'Desempeño en progreso'),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _kTextDark),
                      ),
                      if (tend != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tend >= 0 ? _kGreenBg : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                tend >= 0
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                size: 12,
                                color: tend >= 0
                                    ? _kGreen
                                    : Colors.red.shade600,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${tend >= 0 ? '+' : ''}${tend.toStringAsFixed(1)} vs anterior',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: tend >= 0
                                        ? _kGreen
                                        : Colors.red.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Evaluaciones por completar (asignadas) ───────────────────
          if (asignadas.isNotEmpty) ...[
            const Text(
              'POR COMPLETAR',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kOrange,
                  letterSpacing: 0.8),
            ),
            const SizedBox(height: 9),
            ...asignadas.map(_evalCardAsignada),
            const SizedBox(height: 20),
          ],

          // ── Historial evaluaciones ────────────────────────────────────
          const Text(
            'EVALUACIONES',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _kTextLabel,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 9),

          if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDeco(),
              child: const Center(
                child: Text('No tienes evaluaciones asignadas.',
                    style: TextStyle(color: _kTextMuted, fontSize: 13)),
              ),
            )
          else if (historial.isEmpty)
            const SizedBox.shrink()
          else
            ...historial.map((e) {
              final c = _scoreColors(e);
              final esPend = e.esPendiente;
              final barPct = e.promedio != null ? e.promedio! / 10 : 0.0;
              return GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            DetalleEvaluacionScreen(evaluacionId: e.id))),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: _cardDeco(),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: c.scBg,
                                borderRadius: BorderRadius.circular(12)),
                            child: Center(
                              child: Text(
                                e.promedio?.toStringAsFixed(1) ?? '—',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: c.scCol),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.tipo.isNotEmpty
                                      ? e.tipo[0].toUpperCase() +
                                          e.tipo.substring(1)
                                      : 'Evaluación',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _kTextDark),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  e.periodo,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: _kTextMuted),
                                ),
                              ],
                            ),
                          ),
                          if (esPend)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                  color: _kOrangeBg,
                                  borderRadius:
                                      BorderRadius.circular(20)),
                              child: const Text('Pendiente',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: _kOrange)),
                            )
                          else
                            const Icon(Icons.chevron_right,
                                size: 17, color: Color(0xFFC2C7BB)),
                        ],
                      ),
                      if (!esPend && e.promedio != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: barPct,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFEEF0E8),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                c.scCol),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Completar evaluación asignada (autoservicio) ──────────────────────────────
class CompletarEvaluacionScreen extends StatefulWidget {
  final Evaluacion evaluacion;
  const CompletarEvaluacionScreen({super.key, required this.evaluacion});

  @override
  State<CompletarEvaluacionScreen> createState() =>
      _CompletarEvaluacionScreenState();
}

class _CompletarEvaluacionScreenState
    extends State<CompletarEvaluacionScreen> {
  late Map<String, int> _puntajes;
  final _notas = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _puntajes = {
      for (final d in widget.evaluacion.detalles)
        d.criterioId: d.puntaje > 0 ? d.puntaje : 7,
    };
  }

  @override
  void dispose() {
    _notas.dispose();
    super.dispose();
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _enviar() async {
    setState(() => _guardando = true);
    final svc = await getEvaluacionService();
    final detalles = widget.evaluacion.detalles
        .map((d) => DetalleEvaluacion(
              criterioId: d.criterioId,
              puntaje: _puntajes[d.criterioId] ?? 7,
            ))
        .toList();
    final r = await svc.completarPropia(
      evaluacionId: widget.evaluacion.id,
      detalles: detalles,
      notasEvaluador:
          _notas.text.trim().isEmpty ? null : _notas.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.evaluacion;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Completar evaluación',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: _kTextDark)),
        iconTheme: const IconThemeData(color: _kTextDark),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _cardDeco(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.plantillaNombre != null)
                  Text(e.plantillaNombre!,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _kTextDark)),
                Text('Periodo: ${e.periodo}',
                    style: const TextStyle(
                        color: _kTextMuted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 8),
          if (e.detalles.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDeco(),
              child: const Center(
                child: Text('Sin criterios cargados.',
                    style: TextStyle(color: _kTextMuted)),
              ),
            )
          else
            ...e.detalles.map((d) {
              final v = _puntajes[d.criterioId] ?? 7;
              final color = v >= 8
                  ? _kGreen
                  : v >= 6
                      ? _kBlue
                      : _kOrange;
              // Muestra la pregunta si existe, si no el nombre del criterio
              final pregunta = d.criterioPreg?.isNotEmpty == true
                  ? d.criterioPreg!
                  : d.criterioNombre ?? d.criterioId;
              final tienePreguntaExtra = d.criterioPreg?.isNotEmpty == true &&
                  d.criterioNombre != null;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                decoration: _cardDeco(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pregunta principal
                    Text(
                      pregunta,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _kTextDark),
                    ),
                    if (tienePreguntaExtra) ...[
                      const SizedBox(height: 2),
                      Text(
                        d.criterioNombre!,
                        style: const TextStyle(
                            fontSize: 11, color: _kTextMuted, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Escala visual 1-10
                    Row(children: [
                      const Text('1', style: TextStyle(fontSize: 11, color: _kTextMuted)),
                      Expanded(
                        child: Slider(
                          value: v.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$v',
                          activeColor: color,
                          onChanged: (nv) => setState(
                              () => _puntajes[d.criterioId] = nv.round()),
                        ),
                      ),
                      const Text('10', style: TextStyle(fontSize: 11, color: _kTextMuted)),
                      const SizedBox(width: 8),
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                        child: Center(
                          child: Text('$v',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: color)),
                        ),
                      ),
                    ]),
                    // Etiqueta verbal
                    Padding(
                      padding: const EdgeInsets.only(left: 24, bottom: 2),
                      child: Text(
                        v >= 9 ? 'Excelente' : v >= 7 ? 'Bueno' : v >= 5 ? 'Regular' : 'Necesita mejora',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _cardDeco(),
            child: TextField(
              controller: _notas,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: GestureDetector(
            onTap: _guardando ? null : _enviar,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_kGreenLight, _kGreen],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: _kGreen.withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                      spreadRadius: -8),
                ],
              ),
              child: _guardando
                  ? const Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white)))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: Colors.white, size: 20),
                        SizedBox(width: 9),
                        Text('Enviar evaluación',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Gauge circular (evaluaciones) ─────────────────────────────────────────────
class _ScoreGauge extends StatelessWidget {
  final double score; // 0..10
  final bool hasData;

  const _ScoreGauge({required this.score, required this.hasData});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: CustomPaint(
        painter: _GaugePainter(hasData ? (score / 10).clamp(0.0, 1.0) : 0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasData ? score.toStringAsFixed(1) : '—',
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _kTextDark,
                    height: 1),
              ),
              const Text('/10',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: _kTextMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  const _GaugePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 9) / 2;
    final paint  = Paint()
      ..strokeWidth = 9
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    paint.color = const Color(0xFFEEF0E8);
    canvas.drawCircle(center, radius, paint);

    if (progress > 0) {
      paint.color = _kGreen;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress;
}

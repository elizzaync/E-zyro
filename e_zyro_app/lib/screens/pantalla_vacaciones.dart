import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/vacaciones_models.dart';
import '../services/vacaciones_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import '../widgets/verdant_charts.dart';
import '../widgets/verdant_theme.dart';

/// Vacaciones por ley (Punto 3.3): configuración del régimen, saldos por
/// empleado y solicitudes con aprobación/rechazo.
class PantallaVacaciones extends StatefulWidget {
  const PantallaVacaciones({super.key});

  @override
  State<PantallaVacaciones> createState() => _PantallaVacacionesState();
}

class _PantallaVacacionesState extends State<PantallaVacaciones> {
  VacacionesService? _svc;
  ConfigVacaciones? _config;
  List<SaldoVacaciones> _saldos = [];
  List<SolicitudVacaciones> _solicitudes = [];
  bool _cargando = true;
  String? _error;

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
    final cfg = await _svc!.obtenerConfig();
    final sal = await _svc!.listarSaldos();
    final sol = await _svc!.listarSolicitudes();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (cfg.ok) _config = cfg.data;
      if (sal.ok) _saldos = sal.data ?? [];
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
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  // ── Config ─────────────────────────────────────────────────────────────────
  Future<void> _editarConfig() async {
    String regimen = _config?.regimen ?? 'general';
    final dias = TextEditingController(text: '${_config?.diasPorAnio ?? 30}');
    final tope = TextEditingController(text: '${_config?.topeAcumulacion ?? 30}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Configuración de vacaciones'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: regimen,
              decoration: const InputDecoration(labelText: 'Régimen'),
              items: const [
                DropdownMenuItem(value: 'general', child: Text('General (30 días/año)')),
                DropdownMenuItem(value: 'remype', child: Text('REMYPE (15 días/año)')),
                DropdownMenuItem(value: 'otro', child: Text('Otro (personalizado)')),
              ],
              onChanged: (v) => setLocal(() {
                regimen = v ?? 'general';
                if (regimen == 'general') dias.text = '30';
                if (regimen == 'remype') dias.text = '15';
              }),
            ),
            TextField(
              controller: dias,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Días por año'),
              enabled: regimen == 'otro',
            ),
            TextField(
              controller: tope,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Tope de acumulación (días)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final res = await _svc!.guardarConfig(
      regimen: regimen,
      diasPorAnio: int.tryParse(dias.text.trim()),
      topeAcumulacion: int.tryParse(tope.text.trim()),
    );
    if (!mounted) return;
    if (res.ok) {
      _snack('Configuración actualizada');
      _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
  }


  Future<void> _resolver(SolicitudVacaciones s, bool aprobar) async {
    final res = await _svc!.resolver(s.id, aprobar: aprobar);
    if (!mounted) return;
    res.ok ? _cargar() : _snack(res.errorMessage, error: true);
  }

  Future<void> _fijarSaldoInicial(SaldoVacaciones s) async {
    final ctrl = TextEditingController(
        text: s.disponible > 0 ? s.disponible.toStringAsFixed(0) : '');
    final notasCtrl = TextEditingController(text: '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Saldo inicial · ${s.empleadoNombre ?? s.empleadoId}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Años de servicio: ${s.anosServicio}  ·  Devengado: ${s.devengado.toStringAsFixed(0)} d',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Días disponibles actuales',
              helperText: 'Ingresa los días reales que tiene el trabajador',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: notasCtrl,
            decoration: const InputDecoration(labelText: 'Notas (opcional)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final dias = double.tryParse(ctrl.text.trim());
    if (dias == null || dias < 0) {
      _snack('Ingresa un número válido de días', error: true);
      return;
    }
    final res = await _svc!.setSaldoInicial(
      empleadoId: s.empleadoId,
      diasDisponibles: dias,
      notas: notasCtrl.text.trim().isEmpty ? null : notasCtrl.text.trim(),
    );
    if (!mounted) return;
    if (res.ok) {
      _snack('Saldo inicial guardado');
      _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  static const _avatarPalette = [
    Color(0xFF3E9A4E), Color(0xFF3E80C0), Color(0xFFC58A1C),
    Color(0xFF7E57C2), Color(0xFFD6584F), Color(0xFF2BA89F),
  ];

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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: v.dark ? const Color(0xFF091310) : const Color(0xFFF4F6EF),
        body: Column(
          children: [
            _hero(v),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : TabBarView(children: [_saldosTab(v), _solicitudesTab(v)]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(VerdantColors v) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                  child: Text('Vacaciones',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 19, fontWeight: FontWeight.w700, color: v.onHero)),
                ),
                if (AppSession.i.canConfigurarVacaciones)
                  IconButton(
                    onPressed: _editarConfig,
                    icon: Icon(Icons.settings_outlined, color: v.onHero),
                    style: IconButton.styleFrom(backgroundColor: v.heroChip),
                  ),
                IconButton(
                  onPressed: _cargar,
                  icon: Icon(Icons.refresh, color: v.onHero),
                ),
              ],
            ),
            if (_config != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(color: v.heroChip, borderRadius: BorderRadius.circular(13)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: v.onHeroSub),
                      const SizedBox(width: 7),
                      Text(
                        'Régimen ${_config!.regimen} · ${_config!.diasPorAnio} días/año · tope ${_config!.topeAcumulacion} días',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: v.onHeroSub),
                      ),
                    ],
                  ),
                ),
              ),
            TabBar(
              indicator: BoxDecoration(color: v.lime, borderRadius: BorderRadius.circular(14)),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: v.limeInk,
              unselectedLabelColor: v.onHeroSub,
              labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              tabs: const [Tab(text: 'Saldos'), Tab(text: 'Solicitudes')],
            ),
          ],
        ),
      ),
    );
  }

  Widget _saldosTab(VerdantColors v) {
    if (_saldos.isEmpty) {
      return Center(child: Text('Sin empleados.', style: TextStyle(color: v.mut)));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _saldos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 11),
        itemBuilder: (_, i) => _tarjetaSaldo(v, _saldos[i], i),
      ),
    );
  }

  Widget _tarjetaSaldo(VerdantColors v, SaldoVacaciones s, int index) {
    final avatarColor = _avatarPalette[index % _avatarPalette.length];
    final tope = s.topeAcumulacion > 0 ? s.topeAcumulacion : 30;
    final pct = (s.disponible / tope * 100).clamp(0, 100).toDouble();
    final ringColor = pct >= 66 ? v.grn : (pct > 0 ? v.amb : v.mut);
    final tieneAjuste = s.ajusteDias != 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: v.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: v.bd),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: v.dark ? 0.30 : 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: avatarColor, borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.center,
            child: Text(_iniciales(s.empleadoNombre, s.empleadoId),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.empleadoNombre ?? s.empleadoId,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: v.ink)),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(style: TextStyle(fontSize: 11.5, color: v.sub), children: [
                    const TextSpan(text: 'Deveng '),
                    TextSpan(text: '${s.devengado.toStringAsFixed(0)}d', style: TextStyle(fontWeight: FontWeight.w700, color: v.ink)),
                    const TextSpan(text: ' · Gozado '),
                    TextSpan(text: '${s.gozado}d', style: TextStyle(fontWeight: FontWeight.w700, color: v.ink)),
                    if (tieneAjuste)
                      TextSpan(
                          text: ' · Ajuste ${s.ajusteDias > 0 ? '+' : ''}${s.ajusteDias}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: v.ink)),
                  ]),
                ),
                const SizedBox(height: 2),
                Text('${s.anosServicio} año(s) · ${s.mesesServicio} meses',
                    style: TextStyle(fontSize: 11, color: v.mut)),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RingChart(
                percent: pct,
                size: 50,
                strokeWidth: 6,
                color: ringColor,
                track: v.track,
                textColor: v.ink,
                suffix: '',
                label: s.disponible.toStringAsFixed(0),
              ),
              const SizedBox(height: 3),
              Text('disp', style: TextStyle(fontSize: 9.5, color: v.mut)),
            ],
          ),
          if (AppSession.i.canConfigurarVacaciones) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.edit_calendar_outlined, size: 19, color: v.mut),
              tooltip: 'Fijar saldo inicial',
              onPressed: () => _fijarSaldoInicial(s),
            ),
          ],
        ],
      ),
    );
  }

  Widget _solicitudesTab(VerdantColors v) {
    if (_solicitudes.isEmpty) {
      return Center(child: Text('Sin solicitudes.', style: TextStyle(color: v.mut)));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _solicitudes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 11),
        itemBuilder: (_, i) => _tarjetaSolicitud(v, _solicitudes[i], i),
      ),
    );
  }

  ({Color fg, Color bg}) _coloresEstado(VerdantColors v, String estado) => switch (estado) {
        'aprobada' => (fg: v.grn, bg: v.grnBg),
        'rechazada' => (fg: v.red, bg: v.redBg),
        'cancelada' => (fg: v.mut, bg: v.cardAlt),
        _ => (fg: v.amb, bg: v.ambBg),
      };

  Widget _tarjetaSolicitud(VerdantColors v, SolicitudVacaciones s, int index) {
    final avatarColor = _avatarPalette[index % _avatarPalette.length];
    final col = _coloresEstado(v, s.estado);
    final puedeResolver = s.estado == 'pendiente';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: v.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: v.bd),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: v.dark ? 0.30 : 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: avatarColor, borderRadius: BorderRadius.circular(13)),
                alignment: Alignment.center,
                child: Text(_iniciales(s.empleadoNombre, s.empleadoId),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.empleadoNombre ?? s.empleadoId,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: v.ink)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 13, color: v.sub),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('${s.fechaInicio ?? '-'} · ${s.fechaFin ?? '-'} · ${s.dias} día(s)',
                              style: TextStyle(fontSize: 12, color: v.sub)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(color: col.bg, borderRadius: BorderRadius.circular(20)),
                child: Text(s.estado,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: col.fg)),
              ),
            ],
          ),
          if (s.motivo != null && s.motivo!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.motivo!, style: TextStyle(fontSize: 12, color: v.mut)),
          ],
          if (puedeResolver && (AppSession.i.canAprobarVacaciones || AppSession.i.canRechazarVacaciones)) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (AppSession.i.canRechazarVacaciones)
                  TextButton.icon(
                    onPressed: () => _resolver(s, false),
                    icon: Icon(Icons.close, size: 17, color: v.red),
                    label: Text('Rechazar', style: TextStyle(color: v.red, fontWeight: FontWeight.w700)),
                  ),
                if (AppSession.i.canAprobarVacaciones)
                  FilledButton.icon(
                    onPressed: () => _resolver(s, true),
                    style: FilledButton.styleFrom(backgroundColor: v.grn, foregroundColor: Colors.white),
                    icon: const Icon(Icons.check, size: 17),
                    label: const Text('Aprobar', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

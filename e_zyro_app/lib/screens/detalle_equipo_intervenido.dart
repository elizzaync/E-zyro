import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/equipo_intervenido_models.dart';
import '../services/equipo_intervenido_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';

/// Detalle de un equipo intervenido: identidad, gauge de próximo
/// mantenimiento, recordatorio local, historial (timeline), ficha técnica
/// y registro de mantenimientos.
class DetalleEquipoIntervenido extends StatefulWidget {
  final EquipoIntervenido equipo;
  const DetalleEquipoIntervenido({super.key, required this.equipo});

  @override
  State<DetalleEquipoIntervenido> createState() => _DetalleEquipoIntervenidoState();
}

class _DetalleEquipoIntervenidoState extends State<DetalleEquipoIntervenido> {
  static const _green = Color(0xFF8FD11B);
  static const _mesesAbr = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  static const _anticLabels = ['1 semana', '2 semanas', '1 mes'];
  static const _anticDias = [7, 14, 30];

  EquipoIntervenidoService? _svc;
  late EquipoIntervenido _equipo;
  List<MantenimientoEquipo> _historial = [];
  bool _cargandoHist = true;
  bool _huboCambios = false;

  // Recordatorio (solo UI local, sin backend)
  bool _avisoOn = true;
  int _antic = 1;

  @override
  void initState() {
    super.initState();
    _equipo = widget.equipo;
    _init();
  }

  Future<void> _init() async {
    _svc = await getEquipoIntervenidoService();
    await Future.wait([_refrescarEquipo(), _cargarHistorial()]);
  }

  Future<void> _refrescarEquipo() async {
    if (_svc == null) return;
    final res = await _svc!.obtener(_equipo.id);
    if (!mounted || !res.ok) return;
    setState(() => _equipo = res.data!);
  }

  Future<void> _cargarHistorial() async {
    if (_svc == null) return;
    final res = await _svc!.listarMantenimientos(_equipo.id);
    if (!mounted) return;
    setState(() {
      _cargandoHist = false;
      if (res.ok) _historial = res.data ?? [];
    });
  }

  // ── Helpers de fechas / semáforo ──────────────────────────────────────────

  String _fmt(DateTime? d) =>
      d == null ? '—' : '${d.day} ${_mesesAbr[d.month - 1]} ${d.year}';

  String _fmtIso(String? iso) => _fmt(iso == null ? null : DateTime.tryParse(iso));

  Color _colorSemaforo(int? dias) {
    if (dias == null) return Colors.grey;
    if (dias < 0) return Colors.red.shade600;
    if (dias <= 30) return Colors.amber.shade700;
    return _green;
  }

  /// Fracción 0..1 del ciclo de mantenimiento transcurrido.
  double _fraccionCiclo() {
    final proximo = _equipo.proximoMantDate;
    if (proximo == null) return 0;
    DateTime? inicio = _equipo.ultimoMantDate;
    // Sin último registrado: estimar inicio restando la frecuencia
    inicio ??= DateTime(
        proximo.year, proximo.month - (_equipo.frecuenciaMeses ?? 6), proximo.day);
    final total = proximo.difference(inicio).inDays;
    if (total <= 0) return 1;
    final transcurrido = DateTime.now().difference(inicio).inDays;
    return (transcurrido / total).clamp(0.0, 1.0);
  }

  Color _colorEstado(String estado) => switch (estado) {
        'operativo'     => const Color(0xFF8FD11B),
        'inoperativo'   => Colors.red.shade600,
        'mantenimiento' => Colors.orange.shade700,
        'en_revision'   => Colors.blue.shade600,
        _               => Colors.grey,
      };

  String _labelEstado(String estado) => switch (estado) {
        'operativo'     => 'Operativo',
        'inoperativo'   => 'Inoperativo',
        'mantenimiento' => 'Mantenimiento',
        'en_revision'   => 'En revisión',
        _               => estado,
      };

  String _labelTipoMant(String tipo) => switch (tipo) {
        'preventivo'  => 'Mantenimiento preventivo',
        'correctivo'  => 'Mantenimiento correctivo',
        'inspeccion'  => 'Inspección',
        _             => 'Mantenimiento',
      };

  // ── Registrar mantenimiento ───────────────────────────────────────────────

  void _abrirRegistrarMantenimiento() {
    DateTime fecha = DateTime.now();
    String tipo = 'preventivo';
    final descCtrl = TextEditingController();
    final realizadoCtrl = TextEditingController();
    bool guardando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final surface = Theme.of(ctx).colorScheme.surface;

          InputDecoration deco(String label, IconData icon) => InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon, size: 20, color: _green),
                filled: true,
                fillColor: isDark ? _green.withValues(alpha: 0.04) : Colors.grey.shade50,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: isDark ? _green.withValues(alpha: 0.2) : Colors.grey.shade200)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: isDark ? _green.withValues(alpha: 0.2) : Colors.grey.shade200)),
                focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: _green, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              );

          return Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.build_outlined, color: _green, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text('Registrar mantenimiento',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Fecha
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final sel = await showDatePicker(
                          context: ctx,
                          initialDate: fecha,
                          firstDate: DateTime(2015),
                          lastDate: DateTime.now(),
                        );
                        if (sel != null) setLocal(() => fecha = sel);
                      },
                      child: InputDecorator(
                        decoration: deco('Fecha realizada', Icons.event_outlined),
                        child: Text(_fmt(fecha), style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: tipo,
                      decoration: deco('Tipo', Icons.category_outlined),
                      items: const [
                        DropdownMenuItem(value: 'preventivo', child: Text('Preventivo')),
                        DropdownMenuItem(value: 'correctivo', child: Text('Correctivo')),
                        DropdownMenuItem(value: 'inspeccion', child: Text('Inspección')),
                        DropdownMenuItem(value: 'otro',       child: Text('Otro')),
                      ],
                      onChanged: (v) => setLocal(() => tipo = v ?? 'preventivo'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: deco('Descripción / trabajos realizados', Icons.notes_outlined),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: realizadoCtrl,
                      decoration: deco('Realizado por (opcional)', Icons.person_outline),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Se actualizará el próximo mantenimiento a '
                      '${_equipo.frecuenciaMeses ?? 6} meses desde la fecha indicada.',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: guardando
                            ? null
                            : () async {
                                setLocal(() => guardando = true);
                                final iso =
                                    '${fecha.year.toString().padLeft(4, '0')}-'
                                    '${fecha.month.toString().padLeft(2, '0')}-'
                                    '${fecha.day.toString().padLeft(2, '0')}';
                                final res = await _svc!.registrarMantenimiento(
                                  _equipo.id,
                                  fecha: iso,
                                  tipo: tipo,
                                  descripcion: descCtrl.text.trim().isEmpty
                                      ? null
                                      : descCtrl.text.trim(),
                                  realizadoPor: realizadoCtrl.text.trim().isEmpty
                                      ? null
                                      : realizadoCtrl.text.trim(),
                                );
                                if (!ctx.mounted) return;
                                if (res.ok) {
                                  Navigator.pop(ctx);
                                  if (!mounted) return;
                                  setState(() {
                                    _equipo = res.data!;
                                    _huboCambios = true;
                                  });
                                  _cargarHistorial();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Mantenimiento registrado'),
                                      backgroundColor: _green,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                } else {
                                  setLocal(() => guardando = false);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(res.errorMessage),
                                      backgroundColor: Colors.red.shade700,
                                    ),
                                  );
                                }
                              },
                        icon: guardando
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.build_outlined, size: 18),
                        label: const Text('Registrar',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final puedeEditar = AppSession.i.canEditarEquipoIntervenido;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _huboCambios);
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        body: SafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.07),
                      blurRadius: 16, offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      onPressed: () => Navigator.pop(context, _huboCambios),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Equipo intervenido',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    if (puedeEditar)
                      IconButton(
                        tooltip: 'Editar equipo',
                        icon: const Icon(Icons.edit_outlined, size: 20, color: _green),
                        onPressed: () => Navigator.pop(context, 'editar'),
                      ),
                  ],
                ),
              ),
              // ── Contenido ────────────────────────────────────────────────
              Expanded(
                child: RefreshIndicator(
                  color: _green,
                  onRefresh: () async {
                    await Future.wait([_refrescarEquipo(), _cargarHistorial()]);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _tarjetaIdentidad(isDark, surface),
                      const SizedBox(height: 14),
                      _heroMantenimiento(isDark, surface),
                      const SizedBox(height: 14),
                      _tarjetaRecordatorio(isDark, surface),
                      const SizedBox(height: 18),
                      _tituloSeccion('HISTORIAL DE MANTENIMIENTOS'),
                      const SizedBox(height: 8),
                      _historialCard(isDark, surface),
                      if (_equipo.procedimientos.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _tituloSeccion('PROCEDIMIENTOS DEL SERVICIO'),
                        const SizedBox(height: 8),
                        _procedimientosCard(isDark, surface),
                      ],
                      const SizedBox(height: 18),
                      _tituloSeccion('FICHA TÉCNICA'),
                      const SizedBox(height: 8),
                      _fichaTecnicaCard(isDark, surface),
                      if (_equipo.observaciones != null &&
                          _equipo.observaciones!.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _tituloSeccion('OBSERVACIONES'),
                        const SizedBox(height: 8),
                        _card(
                          isDark, surface,
                          child: Text(_equipo.observaciones!,
                              style: const TextStyle(fontSize: 13, height: 1.5)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // ── Barra de acción inferior ─────────────────────────────────
              if (puedeEditar)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                        blurRadius: 12, offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _abrirRegistrarMantenimiento,
                        icon: const Icon(Icons.build_outlined, size: 18),
                        label: const Text('Registrar mantenimiento',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Secciones ─────────────────────────────────────────────────────────────

  Widget _card(bool isDark, Color surface, {required Widget child, EdgeInsets? padding}) =>
      Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: isDark ? Border.all(color: _green.withValues(alpha: 0.15)) : null,
          boxShadow: isDark
              ? [BoxShadow(color: _green.withValues(alpha: 0.06), blurRadius: 10)]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: child,
      );

  Widget _tituloSeccion(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: Colors.grey, letterSpacing: 0.8)),
      );

  Widget _tarjetaIdentidad(bool isDark, Color surface) {
    final colorEstado = _colorEstado(_equipo.estado);
    return _card(
      isDark, surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.electrical_services_outlined,
                    size: 26, color: _green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_equipo.nombre,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (_equipo.codigo != null && _equipo.codigo!.isNotEmpty)
                      Text(_equipo.codigo!,
                          style: const TextStyle(
                              fontSize: 12.5, color: Colors.grey,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: colorEstado.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colorEstado.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(color: colorEstado, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(_labelEstado(_equipo.estado),
                        style: TextStyle(
                            color: colorEstado, fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_equipo.tipoEquipoNombre != null)
                _chipInfo(Icons.memory_outlined, _equipo.tipoEquipoNombre!, isDark),
              _chipInfo(Icons.settings_outlined,
                  'Cada ${_equipo.frecuenciaMeses ?? 6} meses', isDark),
              if (_equipo.marca != null && _equipo.marca!.isNotEmpty)
                _chipInfo(Icons.verified_outlined, _equipo.marca!, isDark),
            ],
          ),
          if (_equipo.ubicacionCompleta.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(_equipo.ubicacionCompleta,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipInfo(IconData ic, String t, bool isDark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ic, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(t,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
          ],
        ),
      );

  Widget _heroMantenimiento(bool isDark, Color surface) {
    final dias = _equipo.diasParaMantenimiento;
    final color = _colorSemaforo(dias);
    final proximo = _equipo.proximoMantDate;
    final ultimo = _equipo.ultimoMantDate;

    // Texto central del gauge
    String big, sub;
    if (dias == null) {
      big = '—';
      sub = 'sin plan';
    } else if (dias < 0) {
      big = '${-dias}';
      sub = -dias == 1 ? 'día vencido' : 'días vencido';
    } else if (dias >= 60) {
      final meses = (dias / 30).round();
      big = '$meses';
      sub = 'meses';
    } else {
      big = '$dias';
      sub = dias == 1 ? 'día' : 'días';
    }

    String estadoTexto;
    IconData estadoIcono;
    if (dias == null) {
      estadoTexto = 'Sin programar';
      estadoIcono = Icons.event_busy_outlined;
    } else if (dias < 0) {
      estadoTexto = 'Vencido';
      estadoIcono = Icons.warning_amber_rounded;
    } else if (dias <= 30) {
      estadoTexto = 'Próximo a vencer';
      estadoIcono = Icons.schedule_outlined;
    } else {
      estadoTexto = 'Al día';
      estadoIcono = Icons.event_available_outlined;
    }

    return _card(
      isDark, surface,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('PRÓXIMO MANTENIMIENTO'),
          const SizedBox(height: 14),
          Row(
            children: [
              _MantGauge(
                fraction: _fraccionCiclo(),
                color: color,
                big: big,
                sub: sub,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fmt(proximo),
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800, height: 1.15)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(estadoIcono, size: 15, color: color),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(estadoTexto,
                              style: TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w700,
                                  color: color)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Último: ${_fmt(ultimo)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('Realizados: ${_historial.length}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjetaRecordatorio(bool isDark, Color surface) {
    final proximo = _equipo.proximoMantDate;
    final fechaAviso = proximo?.subtract(Duration(days: _anticDias[_antic]));
    return _card(
      isDark, surface,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.notifications_active_outlined,
                    size: 21, color: Colors.blue.shade600),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aviso de mantenimiento',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text('Recordatorio antes de la fecha',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                  ],
                ),
              ),
              Switch(
                value: _avisoOn,
                onChanged: proximo == null
                    ? null
                    : (v) => setState(() => _avisoOn = v),
                activeTrackColor: _green,
              ),
            ],
          ),
          if (_avisoOn && proximo != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                for (int i = 0; i < _anticLabels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _antic = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _antic == i
                              ? _green
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_anticLabels[i],
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _antic == i ? Colors.white : Colors.grey.shade600,
                            )),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, size: 15, color: _green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aviso programado para el ${_fmt(fechaAviso)}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historialCard(bool isDark, Color surface) {
    if (_cargandoHist) {
      return _card(
        isDark, surface,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: _green),
            ),
          ),
        ),
      );
    }

    // Timeline: eventos del historial + alta del equipo al final
    final alta = DateTime.tryParse(_equipo.createdAt);
    final items = <({IconData icono, String titulo, String fecha, String? detalle, String? por})>[
      for (final m in _historial)
        (
          icono: m.tipo == 'correctivo'
              ? Icons.handyman_outlined
              : (m.tipo == 'inspeccion'
                  ? Icons.search_outlined
                  : Icons.build_outlined),
          titulo: _labelTipoMant(m.tipo),
          fecha: _fmtIso(m.fecha),
          detalle: m.descripcion,
          por: m.realizadoPor,
        ),
      (
        icono: Icons.add_rounded,
        titulo: 'Registro del equipo',
        fecha: _fmt(alta),
        detalle: 'Alta del equipo en plataforma',
        por: null,
      ),
    ];

    return _card(
      isDark, surface,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(items[i].icono, size: 15, color: _green),
                      ),
                      if (i < items.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.grey.shade200,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i < items.length - 1 ? 16 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(items[i].titulo,
                                    style: const TextStyle(
                                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 8),
                              Text(items[i].fecha,
                                  style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.w600,
                                      color: Colors.grey)),
                            ],
                          ),
                          if (items[i].detalle != null &&
                              items[i].detalle!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(items[i].detalle!,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                          if (items[i].por != null && items[i].por!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text('Por ${items[i].por}',
                                style: TextStyle(
                                    fontSize: 11.5, color: Colors.grey.shade500)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _colorEstadoProc(String estado) => switch (estado) {
        'completado'  => _green,
        'en_progreso' => Colors.orange.shade700,
        _             => Colors.grey,
      };

  String _labelEstadoProc(String estado) => switch (estado) {
        'completado'  => 'Completado',
        'en_progreso' => 'En progreso',
        _             => 'Pendiente',
      };

  /// Pasos fijos (avance/informe) del servicio al que está vinculado este
  /// equipo — designados por tipo de servicio en Procedimientos Estándar.
  /// Solo lectura: la captura de evidencia sigue viviendo en el detalle de
  /// servicio (pantalla_detalle_servicio.dart).
  Widget _procedimientosCard(bool isDark, Color surface) {
    final pasos = _equipo.procedimientos;
    return _card(
      isDark, surface,
      child: Column(
        children: [
          for (int i = 0; i < pasos.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < pasos.length - 1 ? 14 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26, height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _colorEstadoProc(pasos[i].estado).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: pasos[i].estado == 'completado'
                        ? Icon(Icons.check_rounded, size: 15, color: _colorEstadoProc(pasos[i].estado))
                        : Text('${pasos[i].orden}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: _colorEstadoProc(pasos[i].estado))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pasos[i].nombre,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        if (pasos[i].descripcion.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(pasos[i].descripcion,
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _colorEstadoProc(pasos[i].estado).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(_labelEstadoProc(pasos[i].estado),
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700,
                                      color: _colorEstadoProc(pasos[i].estado))),
                            ),
                            if (pasos[i].evidencias.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.photo_camera_outlined, size: 13, color: Colors.grey),
                                  const SizedBox(width: 3),
                                  Text('${pasos[i].evidencias.length}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _fichaTecnicaCard(bool isDark, Color surface) {
    final filas = <({IconData icono, String label, String valor})>[
      if (_equipo.tipoEquipoNombre != null)
        (icono: Icons.memory_outlined, label: 'Tipo', valor: _equipo.tipoEquipoNombre!),
      if (_equipo.marca != null && _equipo.marca!.isNotEmpty)
        (icono: Icons.verified_outlined, label: 'Marca', valor: _equipo.marca!),
      if (_equipo.modelo != null && _equipo.modelo!.isNotEmpty)
        (icono: Icons.info_outline, label: 'Modelo', valor: _equipo.modelo!),
      if (_equipo.numeroSerie != null && _equipo.numeroSerie!.isNotEmpty)
        (icono: Icons.qr_code_outlined, label: 'N° de serie', valor: _equipo.numeroSerie!),
      if (_equipo.fechaInstalacion != null)
        (icono: Icons.event_outlined, label: 'Instalación',
            valor: _fmtIso(_equipo.fechaInstalacion)),
      (icono: Icons.settings_outlined, label: 'Frecuencia',
          valor: '${_equipo.frecuenciaMeses ?? 6} meses'),
      (icono: Icons.build_outlined, label: 'N° mantenimientos',
          valor: '${_historial.length}'),
      // JSONB clave → valor
      if (_equipo.fichaTecnica != null)
        for (final en in _equipo.fichaTecnica!.entries)
          if (en.value != null && en.value.toString().trim().isNotEmpty)
            (
              icono: Icons.electrical_services_outlined,
              label: _humanizar(en.key),
              valor: en.value.toString(),
            ),
    ];

    return _card(
      isDark, surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (int i = 0; i < filas.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: i < filas.length - 1
                    ? Border(
                        bottom: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.grey.shade200))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(filas[i].icono, size: 16, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(filas[i].label,
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(filas[i].valor,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _humanizar(String clave) {
    final t = clave.replaceAll('_', ' ').trim();
    if (t.isEmpty) return clave;
    return t[0].toUpperCase() + t.substring(1);
  }
}

// ── Gauge circular del ciclo de mantenimiento ────────────────────────────────

class _MantGauge extends StatelessWidget {
  final double fraction; // 0..1 del ciclo transcurrido
  final Color color;
  final String big;
  final String sub;
  static const double size = 124;

  const _MantGauge({
    required this.fraction,
    required this.color,
    required this.big,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MantGaugePainter(fraction: fraction, color: color),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(big,
                  style: TextStyle(
                      fontSize: size * 0.21, fontWeight: FontWeight.w800,
                      color: color, height: 1)),
              const SizedBox(height: 3),
              Text(sub,
                  style: TextStyle(
                      fontSize: size * 0.09, fontWeight: FontWeight.w600,
                      color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MantGaugePainter extends CustomPainter {
  final double fraction;
  final Color color;

  _MantGaugePainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke - 4) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.12);
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [color.withValues(alpha: 0.55), color],
      ).createShader(rect);

    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    final f = fraction.clamp(0.0, 1.0);
    if (f > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * f, false, progress);
    }
  }

  @override
  bool shouldRepaint(_MantGaugePainter old) =>
      old.fraction != fraction || old.color != color;
}

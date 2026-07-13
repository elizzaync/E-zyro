import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/finanzas_models.dart';
import '../../utils/app_session.dart';
import '../../utils/api_provider.dart';
import '../../widgets/verdant_theme.dart';
import '../../pdf/pdf_service.dart';
import '../../pdf/pdf_preview_screen.dart';
import '../../theme/ez_theme.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

class PantallaPlanilla extends StatefulWidget {
  const PantallaPlanilla({super.key});
  @override
  State<PantallaPlanilla> createState() => _State();
}

class _State extends State<PantallaPlanilla> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<Planilla> _planillas = [];
  bool _loadingPlanillas = true;

  List<ConceptoRemunerativo> _conceptos = [];
  bool _loadingConceptos = true;

  bool? _descTardanzaAuto; // null mientras carga
  bool _togglingConfig = false;

  List<EmpleadoPlanilla> _empleados = [];
  List<AsignacionConcepto> _asignaciones = [];
  bool _loadingSueldos = true;

  // ── Vista previa (motor legal, paridad con la web) ─────────────────────────
  int _vpYear = DateTime.now().year;
  int _vpMonth = DateTime.now().month;
  String _vpPeriodoPago = 'mes'; // mes | q1 | q2
  PlanillaConfig? _vpConfig;
  PlanillaPreviewPagina? _vpPreview;
  EmpresaInfo? _vpEmpresaInfo;
  bool _vpLoading = true;
  int _vpPage = 1;
  bool _vpAccionando = false;
  final Map<String, bool> _vpSeleccionLegajo = {};
  bool _vpEnviandoMasivo = false;
  String _vpMasivoProgreso = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _cargarPlanillas();
    _cargarConceptos();
    _cargarSueldos();
    _cargarConfig();
    _cargarPreview();
    _cargarEmpresaInfo();
  }

  Future<void> _cargarEmpresaInfo() async {
    final svc = await getFinanzasService();
    final r = await svc.getEmpresaInfo();
    if (!mounted) return;
    if (r.ok) setState(() => _vpEmpresaInfo = r.data);
  }

  Future<void> _cargarConfig() async {
    final svc = await getFinanzasService();
    final r = await svc.getConfigPlanillaCompleto();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _descTardanzaAuto = r.data!.descuentoTardanzaAuto;
        _vpConfig = r.data;
        if (_vpConfig!.esquemaPagoPlanilla == 'mensual') _vpPeriodoPago = 'mes';
      }
    });
  }

  Future<void> _toggleDescTardanza(bool v) async {
    setState(() => _togglingConfig = true);
    final svc = await getFinanzasService();
    final r = await svc.setDescuentoTardanzaAuto(v);
    if (!mounted) return;
    setState(() {
      _togglingConfig = false;
      if (r.ok) _descTardanzaAuto = r.data!;
    });
    if (r.ok) {
      mostrarOk(context, v
          ? 'Las tardanzas se descontarán automáticamente.'
          : 'Descuento automático de tardanzas desactivado.');
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  void _abrirAjustes() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ajustes de planilla', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_descTardanzaAuto == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Descontar tardanzas automáticamente'),
                  subtitle: const Text(
                    'Al calcular la planilla, descuenta las tardanzas registradas en asistencia.',
                  ),
                  value: _descTardanzaAuto!,
                  onChanged: _togglingConfig
                      ? null
                      : (v) async {
                          await _toggleDescTardanza(v);
                          if (ctx.mounted) setSt(() {});
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _marcarBase(ConceptoRemunerativo c) async {
    if (c.esBase) return;
    final svc = await getFinanzasService();
    final r = await svc.marcarConceptoBase(c.id, true);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, '"${c.nombre}" marcado como concepto base (sueldo).');
      _cargarConceptos();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  // ── Vista previa: período ───────────────────────────────────────────────────
  String get _vpMM => _vpMonth.toString().padLeft(2, '0');
  String get _vpPeriodoStr => '$_vpYear-$_vpMM';

  String get _vpFechaInicio {
    final dia = _vpPeriodoPago == 'q2' ? 16 : 1;
    return '$_vpYear-$_vpMM-${dia.toString().padLeft(2, '0')}';
  }

  String get _vpFechaFin {
    if (_vpPeriodoPago == 'q1') return '$_vpYear-$_vpMM-15';
    final ultimo = DateTime(_vpYear, _vpMonth + 1, 0).day;
    return '$_vpYear-$_vpMM-${ultimo.toString().padLeft(2, '0')}';
  }

  bool get _vpEsMesActual {
    final hoy = DateTime.now();
    return _vpYear == hoy.year && _vpMonth == hoy.month;
  }

  String get _vpLabelPeriodo {
    const meses = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return '${meses[_vpMonth]} $_vpYear';
  }

  /// Planilla ya calculada de este período (si existe), buscada en la lista
  /// que ya carga la tab "Planillas" — evita una llamada extra al backend.
  Planilla? get _vpPlanillaActual {
    for (final p in _planillas) {
      if (p.fechaProceso.startsWith(_vpPeriodoStr) && p.estado != 'anulada') return p;
    }
    return null;
  }

  void _vpMesAnterior() {
    setState(() {
      if (_vpMonth == 1) { _vpMonth = 12; _vpYear--; } else { _vpMonth--; }
      _vpPage = 1;
    });
    _cargarPreview();
  }

  void _vpMesSiguiente() {
    if (_vpEsMesActual) return;
    setState(() {
      if (_vpMonth == 12) { _vpMonth = 1; _vpYear++; } else { _vpMonth++; }
      _vpPage = 1;
    });
    _cargarPreview();
  }

  void _vpSetPeriodoPago(String v) {
    if (_vpPeriodoPago == v) return;
    setState(() { _vpPeriodoPago = v; _vpPage = 1; });
    _cargarPreview();
  }

  Future<void> _cargarPreview() async {
    setState(() => _vpLoading = true);
    final svc = await getFinanzasService();
    final r = await svc.previewPlanilla(
      fechaInicio: _vpFechaInicio, fechaFin: _vpFechaFin,
      periodoPago: _vpPeriodoPago, page: _vpPage, limit: 10,
    );
    if (!mounted) return;
    setState(() {
      _vpLoading = false;
      if (r.ok) _vpPreview = r.data;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  void _vpIrPagina(int p) {
    final tp = _vpPreview?.totalPaginas ?? 1;
    if (p < 1 || p > tp) return;
    setState(() => _vpPage = p);
    _cargarPreview();
  }

  // ── Vista previa: configuración de empresa ──────────────────────────────────
  Future<void> _vpSetRegimen(String val) async {
    final anterior = _vpConfig;
    if (anterior == null || anterior.regimenLaboral == val) return;
    setState(() => _vpConfig = PlanillaConfig(
          descuentoTardanzaAuto: anterior.descuentoTardanzaAuto, regimenLaboral: val,
          esquemaPagoPlanilla: anterior.esquemaPagoPlanilla,
          pagarHorasExtraSinTramite: anterior.pagarHorasExtraSinTramite,
        ));
    final svc = await getFinanzasService();
    final r = await svc.actualizarConfigPlanilla(regimenLaboral: val);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Régimen actualizado');
      _cargarPreview();
    } else {
      setState(() => _vpConfig = anterior);
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _vpSetHorasExtraGate(bool val) async {
    final anterior = _vpConfig;
    if (anterior == null) return;
    setState(() => _vpConfig = PlanillaConfig(
          descuentoTardanzaAuto: anterior.descuentoTardanzaAuto,
          regimenLaboral: anterior.regimenLaboral,
          esquemaPagoPlanilla: anterior.esquemaPagoPlanilla,
          pagarHorasExtraSinTramite: val,
        ));
    final svc = await getFinanzasService();
    final r = await svc.actualizarConfigPlanilla(pagarHorasExtraSinTramite: val);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, val
          ? 'Ahora se paga todo el sobretiempo registrado'
          : 'Ahora solo se paga el sobretiempo con trámite aprobado');
      _cargarPreview();
    } else {
      setState(() => _vpConfig = anterior);
      mostrarError(context, r.errorMessage);
    }
  }

  // ── Vista previa: edición por empleado ──────────────────────────────────────
  Future<void> _vpGuardarSueldoBase(PlanillaPreviewEmpleado e, double monto) async {
    final svc = await getFinanzasService();
    final r = await svc.actualizarSueldoBase(e.id, monto);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Sueldo base actualizado');
      _cargarPreview();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _vpGuardarModalidad(PlanillaPreviewEmpleado e, String tipo) async {
    if (e.tipoContrato == tipo) return;
    final svc = await getFinanzasService();
    final r = await svc.actualizarModalidad(e.id, tipo);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Modalidad actualizada');
      _cargarPreview();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _vpGuardarAsignacionFamiliar(PlanillaPreviewEmpleado e, bool val) async {
    final svc = await getFinanzasService();
    final r = await svc.actualizarPension(e.id, tieneAsignacionFamiliar: val);
    if (!mounted) return;
    if (r.ok) {
      _cargarPreview();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  void _vpAbrirPension(PlanillaPreviewEmpleado e) {
    String sistema = e.sistemaPension;
    String entidad = e.entidadAfp ?? 'integra';
    String tipoComision = e.tipoComisionAfp;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sistema de pensión', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(e.nombreCompleto ?? 'Empleado', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'onp', label: Text('ONP')),
                  ButtonSegment(value: 'afp', label: Text('AFP')),
                ],
                selected: {sistema},
                onSelectionChanged: (s) => setSt(() => sistema = s.first),
              ),
              if (sistema == 'afp') ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: entidad,
                  decoration: const InputDecoration(labelText: 'Entidad AFP', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'integra', child: Text('AFP Integra')),
                    DropdownMenuItem(value: 'prima', child: Text('AFP Prima')),
                    DropdownMenuItem(value: 'profuturo', child: Text('Profuturo AFP')),
                    DropdownMenuItem(value: 'habitat', child: Text('AFP Habitat')),
                  ],
                  onChanged: (v) => setSt(() => entidad = v!),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: tipoComision,
                  decoration: const InputDecoration(labelText: 'Esquema de comisión', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'saldo', child: Text('Saldo (no se descuenta)')),
                    DropdownMenuItem(value: 'flujo', child: Text('Flujo (se descuenta cada mes)')),
                  ],
                  onChanged: (v) => setSt(() => tipoComision = v!),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final svc = await getFinanzasService();
                  final r = await svc.actualizarPension(
                    e.id, sistemaPension: sistema,
                    entidadAfp: sistema == 'afp' ? entidad : null,
                    tipoComisionAfp: sistema == 'afp' ? tipoComision : null,
                  );
                  if (!mounted) return;
                  if (r.ok) {
                    mostrarOk(context, 'Pensión actualizada');
                    _cargarPreview();
                  } else {
                    mostrarError(context, r.errorMessage);
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _vpAbrirBoleta(PlanillaPreviewEmpleado e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HojaBoletaPreview(
        empleado: e, labelPeriodo: _vpLabelPeriodo,
        regimenEmpresa: _vpConfig?.regimenLaboral ?? 'micro',
        periodoPago: _vpPeriodoPago, empresaInfo: _vpEmpresaInfo,
        mes: _vpMonth, anio: _vpYear,
      ),
    );
  }

  void _vpAbrirAsistencia(PlanillaPreviewEmpleado e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HojaAsistenciaDetalle(
        empleadoId: e.id, nombre: e.nombreCompleto ?? 'Empleado',
        inicio: _vpFechaInicio, fin: _vpFechaFin,
      ),
    );
  }

  // ── Vista previa: ciclo calcular/aprobar/pagar/anular del período actual ───
  Future<void> _vpCalcular() async {
    setState(() => _vpAccionando = true);
    final svc = await getFinanzasService();
    final r = await svc.calcularPlanilla(_vpPeriodoStr);
    if (!mounted) return;
    setState(() => _vpAccionando = false);
    if (r.ok) {
      mostrarOk(context, 'Planilla de $_vpLabelPeriodo calculada');
      _cargarPlanillas();
      _cargarPreview();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _vpAccionPlanillaActual(String accion, String tituloOk) async {
    final p = _vpPlanillaActual;
    if (p == null) return;
    setState(() => _vpAccionando = true);
    final svc = await getFinanzasService();
    final r = switch (accion) {
      'aprobar' => await svc.aprobarPlanilla(p.id),
      'marcar-pagada' => await svc.pagarPlanilla(p.id),
      _ => await svc.anularPlanilla(p.id),
    };
    if (!mounted) return;
    setState(() => _vpAccionando = false);
    if (r.ok) {
      mostrarOk(context, tituloOk);
      _cargarPlanillas();
      _cargarPreview();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  // ── Vista previa: envío masivo de boletas a Legajo Digital (solo mes, admin) ─
  void _vpToggleSeleccion(String empId) {
    setState(() => _vpSeleccionLegajo[empId] = !(_vpSeleccionLegajo[empId] ?? false));
  }

  bool get _vpTodaPaginaSeleccionada {
    final emps = _vpPreview?.empleados ?? const [];
    return emps.isNotEmpty && emps.every((e) => _vpSeleccionLegajo[e.id] == true);
  }

  void _vpToggleSeleccionarTodaPagina() {
    final marcar = !_vpTodaPaginaSeleccionada;
    setState(() {
      for (final e in _vpPreview?.empleados ?? const []) {
        _vpSeleccionLegajo[e.id] = marcar;
      }
    });
  }

  int get _vpSeleccionCount => _vpSeleccionLegajo.values.where((v) => v).length;

  Future<void> _vpEnviarLegajoMasivo() async {
    if (_vpEmpresaInfo == null) {
      mostrarError(context, 'Datos de la empresa aún no cargan. Intenta de nuevo.');
      return;
    }
    setState(() { _vpEnviandoMasivo = true; _vpMasivoProgreso = 'Preparando…'; });
    List<PlanillaPreviewEmpleado> objetivo;
    if (_vpSeleccionCount == 0) {
      final svc = await getFinanzasService();
      final r = await svc.previewPlanilla(
        fechaInicio: _vpFechaInicio, fechaFin: _vpFechaFin,
        periodoPago: _vpPeriodoPago, page: 1, limit: 1000,
      );
      if (!mounted) return;
      if (!r.ok) {
        setState(() { _vpEnviandoMasivo = false; _vpMasivoProgreso = ''; });
        mostrarError(context, r.errorMessage);
        return;
      }
      objetivo = r.data!.empleados.where((e) => e.sueldoBase > 0).toList();
    } else {
      final ids = _vpSeleccionLegajo.entries.where((e) => e.value).map((e) => e.key).toSet();
      objetivo = (_vpPreview?.empleados ?? const [])
          .where((e) => ids.contains(e.id) && e.sueldoBase > 0).toList();
    }
    if (objetivo.isEmpty) {
      setState(() { _vpEnviandoMasivo = false; _vpMasivoProgreso = ''; });
      mostrarError(context, 'Ningún empleado seleccionado tiene sueldo registrado.');
      return;
    }
    await _vpProcesarEnvioMasivo(objetivo);
  }

  Future<void> _vpProcesarEnvioMasivo(List<PlanillaPreviewEmpleado> emps) async {
    final svc = await getFinanzasService();
    int enviados = 0, errores = 0;
    for (var i = 0; i < emps.length; i++) {
      if (!mounted) return;
      setState(() => _vpMasivoProgreso = 'Procesando ${i + 1} / ${emps.length}…');
      try {
        final bytes = await PdfService.boletaPago(
          empleado: emps[i], empresa: _vpEmpresaInfo!, labelPeriodo: _vpLabelPeriodo,
          regimenEmpresa: _vpConfig?.regimenLaboral ?? 'micro',
        );
        final nombreDoc = 'Boleta_de_Pago_$_vpMM$_vpYear.pdf';
        final r = await svc.enviarBoletaALegajo(emps[i].id, bytes, nombreDoc,
            mes: _vpMonth, anio: _vpYear);
        if (r.ok) { enviados++; } else { errores++; }
      } catch (_) {
        errores++;
      }
    }
    if (!mounted) return;
    setState(() { _vpEnviandoMasivo = false; _vpMasivoProgreso = ''; _vpSeleccionLegajo.clear(); });
    if (errores == 0) {
      mostrarOk(context, '$enviados boleta(s) enviadas al Legajo Digital');
    } else {
      mostrarError(context, '$enviados enviadas · $errores con error — reintenta esos');
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargarPlanillas() async {
    setState(() => _loadingPlanillas = true);
    final svc = await getFinanzasService();
    final r = await svc.planillas();
    if (!mounted) return;
    setState(() {
      _loadingPlanillas = false;
      if (r.ok) _planillas = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarConceptos() async {
    setState(() => _loadingConceptos = true);
    final svc = await getFinanzasService();
    final r = await svc.conceptosPlanilla();
    if (!mounted) return;
    setState(() {
      _loadingConceptos = false;
      if (r.ok) _conceptos = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarSueldos() async {
    setState(() => _loadingSueldos = true);
    final svc = await getFinanzasService();
    final re = await svc.empleadosPlanilla();
    final ra = await svc.asignacionesPlanilla();
    if (!mounted) return;
    setState(() {
      _loadingSueldos = false;
      if (re.ok) _empleados = re.data!;
      if (ra.ok) _asignaciones = ra.data!;
    });
    if (!re.ok) mostrarError(context, re.errorMessage);
  }

  Future<void> _calcular() async {
    String periodo = periodoActual();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Calcular planilla'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Selecciona el periodo a calcular:'),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final parts = periodo.split('-');
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime(int.parse(parts[0]), int.parse(parts[1]), 1),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) {
                    setSt(() => periodo =
                        '${d.year}-${d.month.toString().padLeft(2, '0')}');
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Periodo',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(periodo),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Calcular')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final svc = await getFinanzasService();
    final r = await svc.calcularPlanilla(periodo);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Planilla $periodo calculada (estado: calculada).');
      _cargarPlanillas();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _accion(Planilla p, String accion) async {
    final textos = {
      'aprobar': ('Aprobar planilla', 'Se generará el asiento de provisión (62 → 41/40).', 'Aprobar'),
      'pagar': ('Marcar pagada', 'Se generará el asiento de pago (41/40 → 10 Caja).', 'Pagar'),
      'anular': ('Anular planilla', '¿Anular esta planilla? Esta acción no se puede deshacer.', 'Anular'),
    };
    final t = textos[accion]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.$1),
        content: Text(t.$2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: accion == 'anular' ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.$3),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final svc = await getFinanzasService();
    final r = switch (accion) {
      'aprobar' => await svc.aprobarPlanilla(p.id),
      'pagar' => await svc.pagarPlanilla(p.id),
      _ => await svc.anularPlanilla(p.id),
    };
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, switch (accion) {
        'aprobar' => 'Planilla aprobada (provisión contabilizada).',
        'pagar' => 'Planilla pagada (pago contabilizado).',
        _ => 'Planilla anulada.',
      });
      _cargarPlanillas();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  void _abrirDetalle(Planilla p) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _PantallaDetallePlanilla(planilla: p)));
  }

  void _abrirFormConcepto() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormConcepto(onGuardado: _cargarConceptos),
    );
  }

  @override
  Widget build(BuildContext context) {
    final puedeCalcular = AppSession.i.canCalcularPlanilla;

    FloatingActionButton? fab;
    if (_tabs.index == 1 && puedeCalcular) {
      fab = FloatingActionButton.extended(
        onPressed: _calcular,
        icon: const Icon(Icons.calculate),
        label: const Text('Calcular'),
      );
    } else if (_tabs.index == 2 && puedeCalcular) {
      fab = FloatingActionButton.extended(
        onPressed: _abrirFormConcepto,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo concepto'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planilla'),
        actions: [
          IconButton(
            tooltip: 'Ajustes de planilla',
            icon: const Icon(Icons.tune),
            onPressed: _abrirAjustes,
          ),
          accionConmutadorFinanzas(context, actual: FinId.planilla),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Vista previa'), Tab(text: 'Planillas'),
            Tab(text: 'Conceptos'), Tab(text: 'Sueldos'),
          ],
        ),
      ),
      floatingActionButton: fab,
      body: TabBarView(
        controller: _tabs,
        children: [
          _tabVistaPrevia(),
          _tabPlanillas(),
          _tabConceptos(),
          _tabSueldos(),
        ],
      ),
    );
  }

  Widget _tabVistaPrevia() {
    final v = VerdantColors.of(context);
    final cfg = _vpConfig;
    final prev = _vpPreview;
    final puedeEditar = AppSession.i.canCalcularPlanilla;

    return RefreshIndicator(
      onRefresh: _cargarPreview,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: _vpMesAnterior),
              Column(children: [
                Text(_vpLabelPeriodo, style: Theme.of(context).textTheme.titleMedium),
                if (prev != null)
                  Text('Meta: ${prev.periodo.metaHoras.toStringAsFixed(0)}h',
                      style: TextStyle(color: v.sub, fontSize: 11)),
              ]),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _vpEsMesActual ? null : _vpMesSiguiente,
              ),
            ],
          ),
          if (cfg?.esquemaPagoPlanilla == 'quincenal') ...[
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'q1', label: Text('1ra Quincena')),
                ButtonSegment(value: 'q2', label: Text('2da Quincena')),
                ButtonSegment(value: 'mes', label: Text('Mes Completo')),
              ],
              selected: {_vpPeriodoPago},
              onSelectionChanged: (s) => _vpSetPeriodoPago(s.first),
            ),
          ],
          const SizedBox(height: 12),
          if (puedeEditar && cfg != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Régimen de la empresa',
                        style: TextStyle(fontSize: 12, color: v.sub, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'micro', label: Text('Microempresa')),
                        ButtonSegment(value: 'pequena', label: Text('Peq. Empresa')),
                        ButtonSegment(value: 'general', label: Text('Reg. General')),
                      ],
                      selected: {cfg.regimenLaboral},
                      onSelectionChanged: (s) => _vpSetRegimen(s.first),
                    ),
                    const SizedBox(height: 12),
                    Text('Pago de sobretiempo',
                        style: TextStyle(fontSize: 12, color: v.sub, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Solo con trámite')),
                        ButtonSegment(value: true, label: Text('Todo lo registrado')),
                      ],
                      selected: {cfg.pagarHorasExtraSinTramite},
                      onSelectionChanged: (s) => _vpSetHorasExtraGate(s.first),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (puedeEditar) ...[_vpEstadoBar(_vpPlanillaActual, v), const SizedBox(height: 12)],
          if (_vpLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (prev == null || prev.empleados.isEmpty)
            const EstadoVacio(
              icono: Icons.groups_outlined,
              titulo: 'Sin empleados en este período',
              subtitulo: 'No hay asistencia registrada para calcular la planilla.',
            )
          else ...[
            _vpKpis(prev, v),
            const SizedBox(height: 12),
            if (AppSession.i.isAdmin && _vpPeriodoPago == 'mes') ...[
              _vpBarraLegajoMasivo(prev, v),
              const SizedBox(height: 8),
            ],
            for (final e in prev.empleados)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FilaEmpleadoPreview(
                  empleado: e, v: v, puedeEditar: puedeEditar,
                  mostrarSeleccion: AppSession.i.isAdmin && _vpPeriodoPago == 'mes',
                  seleccionado: _vpSeleccionLegajo[e.id] == true,
                  onToggleSeleccion: () => _vpToggleSeleccion(e.id),
                  onGuardarSueldo: (m) => _vpGuardarSueldoBase(e, m),
                  onGuardarModalidad: (t) => _vpGuardarModalidad(e, t),
                  onToggleAsignacionFamiliar: (val) => _vpGuardarAsignacionFamiliar(e, val),
                  onAbrirPension: () => _vpAbrirPension(e),
                  onAbrirBoleta: () => _vpAbrirBoleta(e),
                  onAbrirAsistencia: () => _vpAbrirAsistencia(e),
                ),
              ),
            const SizedBox(height: 8),
            _vpPaginacion(prev),
          ],
        ],
      ),
    );
  }

  Widget _vpChipEstado(String estado, VerdantColors v) {
    final (Color color, Color bg, String label) = switch (estado) {
      'calculada' => (v.blu, v.bluBg, 'Calculada'),
      'aprobada' => (v.amb, v.ambBg, 'Aprobada'),
      'pagada' => (v.grn, v.grnBg, 'Pagada'),
      'anulada' => (v.red, v.redBg, 'Anulada'),
      _ => (v.mut, v.track, 'Sin calcular'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _vpEstadoBar(Planilla? p, VerdantColors v) {
    if (p == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _vpChipEstado('borrador', v),
              const SizedBox(width: 10),
              const Expanded(child: Text('Sin calcular todavía', style: TextStyle(fontSize: 12))),
              FilledButton.icon(
                onPressed: _vpAccionando ? null : _vpCalcular,
                icon: _vpAccionando
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.calculate, size: 18),
                label: const Text('Calcular'),
                style: FilledButton.styleFrom(backgroundColor: v.heroSolid),
              ),
            ],
          ),
        ),
      );
    }
    final puedeAprobar = AppSession.i.canAprobarPlanilla;
    final esAdmin = AppSession.i.isAdmin;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _vpChipEstado(p.estado, v),
              const SizedBox(width: 10),
              Expanded(child: Text('Neto: ${money(p.totalNeto)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
            if (p.estado == 'calculada' && (puedeAprobar || esAdmin)) ...[
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (esAdmin)
                  TextButton.icon(
                    onPressed: _vpAccionando
                        ? null : () => _vpAccionPlanillaActual('anular', 'Planilla anulada'),
                    icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                    label: const Text('Anular', style: TextStyle(color: Colors.red)),
                  ),
                if (puedeAprobar)
                  FilledButton.icon(
                    onPressed: _vpAccionando ? null : () => _vpAccionPlanillaActual(
                        'aprobar', 'Planilla aprobada — provisión contabilizada'),
                    icon: const Icon(Icons.verified, size: 18),
                    label: const Text('Aprobar'),
                    style: FilledButton.styleFrom(backgroundColor: v.amb),
                  ),
              ]),
            ] else if (p.estado == 'aprobada' && puedeAprobar) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _vpAccionando ? null : () => _vpAccionPlanillaActual(
                      'marcar-pagada', 'Planilla pagada — pago contabilizado'),
                  icon: const Icon(Icons.payments, size: 18),
                  label: const Text('Marcar pagada'),
                  style: FilledButton.styleFrom(backgroundColor: v.heroSolid),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vpKpis(PlanillaPreviewPagina prev, VerdantColors v) {
    final totalNeto = prev.empleados.fold<double>(0, (s, e) => s + e.netoAPagar);
    final totalDesc = prev.empleados.fold<double>(0, (s, e) => s + e.totalDescuentosLegales);
    final totalExtra = prev.empleados.fold<double>(0, (s, e) => s + e.pagoHorasExtra);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.6,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        TarjetaResumen(titulo: 'Total empleados', valor: '${prev.total}',
            color: v.heroSolid, icono: Icons.groups_outlined),
        TarjetaResumen(titulo: 'Total a pagar (página)', valor: money(totalNeto),
            color: v.heroSolid, icono: Icons.payments_outlined),
        TarjetaResumen(titulo: 'Descuentos legales', valor: money(totalDesc),
            color: v.red, icono: Icons.remove_circle_outline),
        TarjetaResumen(titulo: 'Pago horas extra', valor: money(totalExtra),
            color: v.amb, icono: Icons.schedule_outlined),
      ],
    );
  }

  Widget _vpBarraLegajoMasivo(PlanillaPreviewPagina prev, VerdantColors v) {
    final n = _vpSeleccionCount;
    return Card(
      color: v.cardAlt,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: _vpTodaPaginaSeleccionada,
              onChanged: _vpEnviandoMasivo ? null : (_) => _vpToggleSeleccionarTodaPagina(),
            ),
            const Text('Seleccionar página', style: TextStyle(fontSize: 12)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _vpEnviandoMasivo ? null : _vpEnviarLegajoMasivo,
              icon: _vpEnviandoMasivo
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.folder_shared_outlined, size: 16),
              label: Text(
                _vpEnviandoMasivo
                    ? _vpMasivoProgreso
                    : (n > 0 ? 'Enviar $n seleccionados' : 'Enviar a Legajo Digital'),
                style: const TextStyle(fontSize: 12),
              ),
              style: FilledButton.styleFrom(backgroundColor: v.heroSolid),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vpPaginacion(PlanillaPreviewPagina prev) {
    if (prev.totalPaginas <= 1) return const SizedBox.shrink();
    final desde = (prev.page - 1) * prev.limit + 1;
    final hasta = (desde + prev.empleados.length - 1).clamp(0, prev.total);
    return Column(
      children: [
        Text('Mostrando $desde–$hasta de ${prev.total} empleados',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: prev.page > 1 ? () => _vpIrPagina(prev.page - 1) : null,
            ),
            for (var p = (prev.page - 2).clamp(1, prev.totalPaginas);
                p <= (prev.page + 2).clamp(1, prev.totalPaginas); p++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: OutlinedButton(
                  onPressed: p == prev.page ? null : () => _vpIrPagina(p),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: p == prev.page
                        ? VerdantColors.of(context).heroSolid : null,
                    foregroundColor: p == prev.page ? Colors.white : null,
                    minimumSize: const Size(36, 36),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text('$p'),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: prev.page < prev.totalPaginas ? () => _vpIrPagina(prev.page + 1) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _tabSueldos() {
    if (_loadingSueldos || _loadingConceptos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_empleados.isEmpty) {
      return const EstadoVacio(
        icono: Icons.badge_outlined,
        titulo: 'Sin empleados activos',
        subtitulo: 'Registra empleados activos para incluirlos en la planilla.',
      );
    }
    final puedeEditar = AppSession.i.canCalcularPlanilla;
    return RefreshIndicator(
      onRefresh: _cargarSueldos,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _empleados.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final e = _empleados[i];
          final asigs = _asignaciones.where((a) => a.empleadoId == e.id).toList();
          final neto = _netoEstimado(asigs);
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(e.nombre ?? 'Empleado ${e.id}'),
              subtitle: Text(e.cargo ?? '—'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(asigs.isEmpty ? 'Sin asignar' : money(neto),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: asigs.isEmpty ? Colors.grey : VerdantColors.of(context).heroSolid)),
                  Text(asigs.isEmpty ? 'usa referencial' : 'neto estimado',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
              onTap: puedeEditar ? () => _abrirSueldos(e) : null,
            ),
          );
        },
      ),
    );
  }

  /// Neto estimado con los montos asignados (ingresos − descuentos).
  double _netoEstimado(List<AsignacionConcepto> asigs) {
    double neto = 0;
    for (final a in asigs) {
      final matches = _conceptos.where((x) => x.id == a.conceptoId);
      if (matches.isEmpty) continue;
      final tipo = matches.first.tipo;
      if (tipo == 'ingreso') {
        neto += a.monto;
      } else if (tipo == 'descuento') {
        neto -= a.monto;
      }
    }
    return neto;
  }

  void _abrirSueldos(EmpleadoPlanilla e) {
    final asigs = {
      for (final a in _asignaciones.where((a) => a.empleadoId == e.id)) a.conceptoId: a.monto
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormSueldos(
        empleado: e,
        conceptos: _conceptos,
        montosActuales: asigs,
        onGuardado: _cargarSueldos,
      ),
    );
  }

  Widget _tabPlanillas() {
    if (_loadingPlanillas) return const Center(child: CircularProgressIndicator());
    if (_planillas.isEmpty) {
      return const EstadoVacio(
        icono: Icons.payments,
        titulo: 'Sin planillas procesadas',
        subtitulo: 'Calcula tu primera planilla para ver sueldos, aportes y descuentos.',
      );
    }
    final puedeAprobar = AppSession.i.canAprobarPlanilla;
    final puedeAnular = AppSession.i.isAdmin;
    return RefreshIndicator(
      onRefresh: _cargarPlanillas,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _planillas.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = _planillas[i];
          final surface = Theme.of(context).colorScheme.surface;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _abrirDetalle(p),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_note, color: VerdantColors.of(context).heroSolid),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Proceso ${p.fechaProceso}',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      chipEstado(p.estado, context.ez),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  const Divider(height: 18),
                  _filaMonto('Ingresos', p.totalIngresos, Colors.green),
                  _filaMonto('Descuentos', p.totalDescuentos, Colors.deepOrange),
                  _filaMonto('Aportes empleador', p.totalAportes, Colors.blueGrey),
                  const Divider(height: 14),
                  _filaMonto('Neto a pagar', p.totalNeto, VerdantColors.of(context).heroSolid, negrita: true),
                  if ((puedeAprobar || puedeAnular) &&
                      (p.estado == 'calculada' || p.estado == 'aprobada')) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (puedeAnular)
                          TextButton.icon(
                            onPressed: () => _accion(p, 'anular'),
                            icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                            label: const Text('Anular', style: TextStyle(color: Colors.red)),
                          ),
                        if (puedeAprobar && p.estado == 'calculada')
                          FilledButton.tonalIcon(
                            onPressed: () => _accion(p, 'aprobar'),
                            icon: const Icon(Icons.verified, size: 18),
                            label: const Text('Aprobar'),
                          ),
                        if (puedeAprobar && p.estado == 'aprobada') ...[
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => _accion(p, 'pagar'),
                            icon: const Icon(Icons.payments, size: 18),
                            label: const Text('Marcar pagada'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filaMonto(String label, double valor, Color color, {bool negrita = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: TextStyle(
              fontSize: 13, fontWeight: negrita ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          Text(money(valor), style: TextStyle(
              fontSize: 13, color: color, fontWeight: negrita ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _tabConceptos() {
    if (_loadingConceptos) return const Center(child: CircularProgressIndicator());
    if (_conceptos.isEmpty) {
      return const EstadoVacio(
        icono: Icons.list_alt_outlined,
        titulo: 'Sin conceptos remunerativos registrados',
        subtitulo: 'Registra los conceptos que forman parte de la planilla.',
      );
    }
    final puedeEditar = AppSession.i.canCalcularPlanilla;
    final hayBase = _conceptos.any((c) => c.esBase);
    return RefreshIndicator(
      onRefresh: _cargarConceptos,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _conceptos.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          if (i == 0) {
            if (hayBase) return const SizedBox.shrink();
            return Card(
              color: Colors.amber.withValues(alpha: 0.12),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ningún concepto está marcado como Base (sueldo). '
                        'Los descuentos por asistencia (faltas/tardanzas) no se '
                        'calcularán hasta marcar uno.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final c = _conceptos[i - 1];
          final color = switch (c.tipo) {
            'ingreso' => Colors.green,
            'descuento' => Colors.deepOrange,
            _ => Colors.blueGrey,
          };
          // Solo un concepto de tipo ingreso tiene sentido como base (sueldo).
          final puedeSerBase = c.tipo == 'ingreso';
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Text(c.codigo, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
              ),
              title: Row(
                children: [
                  Flexible(child: Text(c.nombre)),
                  if (c.esBase) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: VerdantColors.of(context).heroSolid.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: VerdantColors.of(context).heroSolid.withValues(alpha: 0.5)),
                      ),
                      child: Text('Base (sueldo)',
                          style: TextStyle(color: VerdantColors.of(context).heroSolid,
                              fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
              subtitle: Text(c.tipo.replaceAll('_', ' ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.montoReferencial != null)
                    Text(money(c.montoReferencial!), style: const TextStyle(fontWeight: FontWeight.w600))
                  else if (!c.activo)
                    const Icon(Icons.visibility_off_outlined, size: 18, color: Colors.grey),
                  if (puedeEditar && puedeSerBase && !c.esBase) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Marcar como base (sueldo)',
                      icon: const Icon(Icons.star_outline, size: 20),
                      onPressed: () => _marcarBase(c),
                    ),
                  ] else if (c.esBase)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.star, size: 20, color: VerdantColors.of(context).heroSolid),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Detalle de planilla: boletas de pago por empleado ─────────────────────────

class _PantallaDetallePlanilla extends StatefulWidget {
  final Planilla planilla;
  const _PantallaDetallePlanilla({required this.planilla});

  @override
  State<_PantallaDetallePlanilla> createState() => _PantallaDetallePlanillaState();
}

// Códigos de descuento que provienen del módulo de asistencia.
const _codigosAsistencia = {'DESC_FALTA', 'DESC_TARDANZA'};

class _PantallaDetallePlanillaState extends State<_PantallaDetallePlanilla> {
  List<BoletaPago> _boletas = [];
  bool _loading = true;
  late Planilla _planilla; // mutable: se actualiza tras un override

  bool get _editable => _planilla.estado == 'calculada';

  @override
  void initState() {
    super.initState();
    _planilla = widget.planilla;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final svc = await getFinanzasService();
    final rb = await svc.listarBoletas(_planilla.id);
    final rp = await svc.obtenerPlanilla(_planilla.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (rb.ok) _boletas = rb.data!;
      if (rp.ok) _planilla = rp.data!;
    });
    if (!rb.ok) mostrarError(context, rb.errorMessage);
  }

  Future<void> _editarDetalle(BoletaPago b, BoletaPagoDetalle d) async {
    final ctrl = TextEditingController(text: d.monto.toStringAsFixed(2));
    final esAsistencia = _codigosAsistencia.contains(d.conceptoCodigo);
    final nuevo = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(d.conceptoNombre ?? 'Concepto ${d.conceptoId}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (esAsistencia)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Descuento por asistencia. Ajusta o pon 0 para eliminarlo.',
                    style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
              ),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monto',
                helperText: '0 elimina el concepto de la boleta',
                border: OutlineInputBorder(),
                prefixText: 'S/ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
              if (v == null || v < 0) {
                mostrarError(ctx, 'Ingresa un monto válido (≥ 0).');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nuevo == null || !mounted) return;
    final svc = await getFinanzasService();
    final r = await svc.editarDetalleBoleta(_planilla.id, b.id, d.conceptoId, nuevo);
    if (!mounted) return;
    if (r.ok) {
      setState(() => _planilla = r.data!);
      mostrarOk(context, 'Concepto actualizado. Totales recalculados.');
      _cargar(); // refresca boletas con los nuevos detalles
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _planilla;
    return Scaffold(
      appBar: AppBar(title: Text('Planilla ${p.fechaProceso}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              chipEstado(p.estado, context.ez),
                              const Spacer(),
                              Text('Neto total', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(money(p.totalNeto),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            _editable
                                ? 'Puedes ajustar (override) los conceptos de cada boleta antes de aprobar.'
                                : 'Solo lectura: la planilla ya no está en estado "calculada".',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Boletas de pago (${_boletas.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_boletas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: EstadoVacio(
                        icono: Icons.receipt_long,
                        titulo: 'Sin boletas generadas',
                        subtitulo: 'Las boletas de pago aparecerán aquí cuando se generen.',
                      ),
                    )
                  else
                    ..._boletas.map(_buildBoleta),
                ],
              ),
            ),
    );
  }

  Widget _buildBoleta(BoletaPago b) {
    final ingresos = b.detalles.where((d) {
      final cod = d.conceptoCodigo ?? '';
      return !_codigosAsistencia.contains(cod) && d.monto >= 0 && !cod.startsWith('DESC');
    }).toList();
    final descuentos = b.detalles
        .where((d) => !ingresos.contains(d))
        .toList();
    return Card(
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
        title: Text(b.empleadoNombre ?? 'Empleado ${b.empleadoId}'),
        subtitle: Text('Neto: ${money(b.totalNeto)}'),
        children: [
          ListTile(
            dense: true,
            title: const Text('Ingresos'),
            trailing: Text(money(b.totalIngresos), style: const TextStyle(color: Colors.green)),
          ),
          ListTile(
            dense: true,
            title: const Text('Descuentos'),
            trailing: Text(money(b.totalDescuentos), style: const TextStyle(color: Colors.deepOrange)),
          ),
          ListTile(
            dense: true,
            title: const Text('Aportes empleador'),
            trailing: Text(money(b.totalAportes)),
          ),
          const Divider(height: 1),
          if (ingresos.isNotEmpty) ...[
            _seccionTitulo('Ingresos'),
            ...ingresos.map((d) => _filaDetalle(b, d)),
          ],
          if (descuentos.isNotEmpty) ...[
            _seccionTitulo('Descuentos'),
            ...descuentos.map((d) => _filaDetalle(b, d)),
          ],
        ],
      ),
    );
  }

  Widget _seccionTitulo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5)),
      );

  Widget _filaDetalle(BoletaPago b, BoletaPagoDetalle d) {
    final esAsistencia = _codigosAsistencia.contains(d.conceptoCodigo);
    return ListTile(
      dense: true,
      leading: esAsistencia
          ? const Icon(Icons.event_busy, size: 16, color: Colors.deepOrange)
          : const Icon(Icons.fiber_manual_record, size: 10),
      title: Row(
        children: [
          Flexible(
            child: Text(
              d.conceptoNombre ?? 'Concepto ${d.conceptoId}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (esAsistencia) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Asistencia',
                  style: TextStyle(fontSize: 9.5, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(money(d.monto), style: const TextStyle(fontSize: 12)),
          if (_editable) ...[
            const SizedBox(width: 2),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Ajustar monto',
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => _editarDetalle(b, d),
            ),
          ],
        ],
      ),
      onTap: _editable ? () => _editarDetalle(b, d) : null,
    );
  }
}

// ── Formulario nuevo concepto remunerativo ────────────────────────────────────

class _FormConcepto extends StatefulWidget {
  final VoidCallback onGuardado;
  const _FormConcepto({required this.onGuardado});

  @override
  State<_FormConcepto> createState() => _FormConceptoState();
}

class _FormConceptoState extends State<_FormConcepto> {
  final _form = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  String _tipo = 'ingreso';
  bool _guardando = false;

  static const _tipos = ['ingreso', 'descuento', 'aporte_empleador'];

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final monto = double.tryParse(_montoCtrl.text);
    final r = await svc.crearConceptoPlanilla(
      codigo: _codigoCtrl.text.trim(),
      nombre: _nombreCtrl.text.trim(),
      tipo: _tipo,
      montoReferencial: monto,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Concepto registrado');
      Navigator.pop(context);
      widget.onGuardado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nuevo concepto remunerativo', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codigoCtrl,
                decoration: const InputDecoration(labelText: 'Código', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' ')))).toList(),
                onChanged: (v) => setState(() => _tipo = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto referencial (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Editor de sueldos por empleado (montos por concepto) ──────────────────────

class _FormSueldos extends StatefulWidget {
  final EmpleadoPlanilla empleado;
  final List<ConceptoRemunerativo> conceptos;
  final Map<String, double> montosActuales; // conceptoId -> monto override
  final VoidCallback onGuardado;
  const _FormSueldos({
    required this.empleado,
    required this.conceptos,
    required this.montosActuales,
    required this.onGuardado,
  });

  @override
  State<_FormSueldos> createState() => _FormSueldosState();
}

class _FormSueldosState extends State<_FormSueldos> {
  late final Map<String, TextEditingController> _ctrls;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final c in widget.conceptos)
        c.id: TextEditingController(
          text: widget.montosActuales.containsKey(c.id)
              ? widget.montosActuales[c.id]!.toStringAsFixed(2)
              : '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final items = <Map<String, dynamic>>[];
    for (final c in widget.conceptos) {
      final txt = _ctrls[c.id]!.text.trim();
      final tenia = widget.montosActuales.containsKey(c.id);
      if (txt.isEmpty) {
        // vacío: si tenía override lo eliminamos (vuelve al referencial)
        if (tenia) items.add({'concepto_id': c.id, 'monto': null});
        continue;
      }
      final monto = double.tryParse(txt.replaceAll(',', '.'));
      if (monto == null) continue;
      items.add({'concepto_id': c.id, 'monto': monto});
    }
    final svc = await getFinanzasService();
    final r = await svc.guardarAsignaciones(widget.empleado.id, items);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Sueldo de ${widget.empleado.nombre ?? 'empleado'} guardado');
      Navigator.pop(context);
      widget.onGuardado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    // El sueldo base (concepto es_base) ahora se edita desde la tab "Vista
    // previa" (PUT /planilla/empleados/{id}/sueldo-base) — se excluye aquí
    // para no tener dos lugares editando el mismo dato.
    final activos = widget.conceptos.where((c) => c.activo && !c.esBase).toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.empleado.nombre ?? 'Empleado',
                style: Theme.of(context).textTheme.titleLarge),
            Text(widget.empleado.cargo ?? '',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              'Monto por concepto para este empleado. Vacío = usa el monto referencial del catálogo.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            if (activos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No hay conceptos activos')),
              )
            else
              ...activos.map((c) {
                final color = switch (c.tipo) {
                  'ingreso' => Colors.green,
                  'descuento' => Colors.deepOrange,
                  _ => Colors.blueGrey,
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _ctrls[c.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: c.nombre,
                      helperText: c.tipo.replaceAll('_', ' '),
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(Icons.circle, size: 12, color: color),
                      hintText: c.montoReferencial != null
                          ? 'ref: ${c.montoReferencial!.toStringAsFixed(2)}'
                          : null,
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar sueldo'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Vista previa: fila de empleado (motor legal) ───────────────────────────────

class _FilaEmpleadoPreview extends StatefulWidget {
  final PlanillaPreviewEmpleado empleado;
  final VerdantColors v;
  final bool puedeEditar;
  final bool mostrarSeleccion;
  final bool seleccionado;
  final VoidCallback? onToggleSeleccion;
  final ValueChanged<double> onGuardarSueldo;
  final ValueChanged<String> onGuardarModalidad;
  final ValueChanged<bool> onToggleAsignacionFamiliar;
  final VoidCallback onAbrirPension;
  final VoidCallback onAbrirBoleta;
  final VoidCallback onAbrirAsistencia;
  const _FilaEmpleadoPreview({
    required this.empleado, required this.v, required this.puedeEditar,
    this.mostrarSeleccion = false, this.seleccionado = false, this.onToggleSeleccion,
    required this.onGuardarSueldo, required this.onGuardarModalidad,
    required this.onToggleAsignacionFamiliar, required this.onAbrirPension,
    required this.onAbrirBoleta, required this.onAbrirAsistencia,
  });
  @override
  State<_FilaEmpleadoPreview> createState() => _FilaEmpleadoPreviewState();
}

class _FilaEmpleadoPreviewState extends State<_FilaEmpleadoPreview> {
  late final TextEditingController _sueldoCtrl;

  @override
  void initState() {
    super.initState();
    _sueldoCtrl = TextEditingController(text: widget.empleado.sueldoBase.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant _FilaEmpleadoPreview old) {
    super.didUpdateWidget(old);
    if (old.empleado.sueldoBase != widget.empleado.sueldoBase) {
      _sueldoCtrl.text = widget.empleado.sueldoBase.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _sueldoCtrl.dispose();
    super.dispose();
  }

  void _guardarSueldoSiCambio() {
    final val = double.tryParse(_sueldoCtrl.text.trim().replaceAll(',', '.'));
    if (val == null || val < 0) {
      _sueldoCtrl.text = widget.empleado.sueldoBase.toStringAsFixed(2);
      return;
    }
    if ((val - widget.empleado.sueldoBase).abs() < 0.005) return;
    widget.onGuardarSueldo(val);
  }

  String _modalidadLabel(String t) => switch (t) {
        'contrato' => 'Contrato',
        'practicante' => 'Practicante',
        _ => 'Planilla',
      };

  Color _modalidadColor(String t) => switch (t) {
        'contrato' => widget.v.blu,
        'practicante' => widget.v.amb,
        _ => widget.v.grn,
      };

  String _entidadLabel(String? e) => switch (e) {
        'integra' => 'AFP Integra',
        'prima' => 'AFP Prima',
        'profuturo' => 'Profuturo AFP',
        'habitat' => 'AFP Habitat',
        _ => 'AFP',
      };

  @override
  Widget build(BuildContext context) {
    final e = widget.empleado;
    final v = widget.v;
    final modColor = _modalidadColor(e.tipoContrato);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: widget.mostrarSeleccion
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(
                  value: widget.seleccionado,
                  onChanged: (_) => widget.onToggleSeleccion?.call(),
                ),
                CircleAvatar(
                  backgroundColor: modColor.withValues(alpha: 0.15),
                  child: Text(e.iniciales,
                      style: TextStyle(color: modColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ])
            : CircleAvatar(
                backgroundColor: modColor.withValues(alpha: 0.15),
                child: Text(e.iniciales,
                    style: TextStyle(color: modColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
        title: Text(e.nombreCompleto ?? 'Empleado',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        subtitle: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: modColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(_modalidadLabel(e.tipoContrato),
                style: TextStyle(color: modColor, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(e.cargo ?? '—',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(e.netoAPagar),
                style: TextStyle(fontWeight: FontWeight.bold, color: v.heroSolid, fontSize: 13)),
            Text(e.horasFaltantes <= 0 ? 'Completo' : '-${e.horasFaltantes.toStringAsFixed(1)}h',
                style: TextStyle(fontSize: 10, color: e.horasFaltantes <= 0 ? v.grn : v.amb)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.puedeEditar) ...[
                  DropdownButtonFormField<String>(
                    initialValue: e.tipoContrato,
                    decoration: const InputDecoration(
                        labelText: 'Modalidad', isDense: true, border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'planilla', child: Text('Planilla')),
                      DropdownMenuItem(value: 'contrato', child: Text('Contrato')),
                      DropdownMenuItem(value: 'practicante', child: Text('Practicante')),
                    ],
                    onChanged: (t) { if (t != null) widget.onGuardarModalidad(t); },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _sueldoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Sueldo base', prefixText: 'S/ ',
                      isDense: true, border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _guardarSueldoSiCambio(),
                    onTapOutside: (_) => _guardarSueldoSiCambio(),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  Text('Sueldo base: ${money(e.sueldoBase)}', style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 6),
                ],
                InkWell(
                  onTap: widget.puedeEditar ? widget.onAbrirPension : null,
                  child: Row(children: [
                    Icon(Icons.savings_outlined, size: 16, color: v.sub),
                    const SizedBox(width: 6),
                    Text(e.sistemaPension == 'onp' ? 'ONP' : _entidadLabel(e.entidadAfp),
                        style: const TextStyle(fontSize: 12.5)),
                    Text('  (${(e.comisionAfpPct * 100).toStringAsFixed(2)}%)',
                        style: TextStyle(fontSize: 11, color: v.sub)),
                    if (widget.puedeEditar) ...[
                      const Spacer(),
                      Icon(Icons.edit, size: 14, color: v.sub),
                    ],
                  ]),
                ),
                if (e.cuspp != null && e.cuspp!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('CUSPP: ${e.cuspp}', style: TextStyle(fontSize: 11.5, color: v.sub)),
                ],
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Asignación familiar', style: TextStyle(fontSize: 12.5)),
                  value: e.tieneAsignacionFamiliar,
                  onChanged: widget.puedeEditar ? widget.onToggleAsignacionFamiliar : null,
                ),
                if (e.bajoRmv)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: v.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Sueldo por debajo de la RMV',
                            style: TextStyle(fontSize: 11.5, color: v.red)),
                      ),
                    ]),
                  ),
                if (e.horasExtraSinTramite > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: v.amb),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            '${e.horasExtraSinTramite.toStringAsFixed(1)}h de sobretiempo sin trámite aprobado',
                            style: TextStyle(fontSize: 11.5, color: v.amb)),
                      ),
                    ]),
                  ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onAbrirAsistencia,
                      icon: const Icon(Icons.event_note_outlined, size: 16),
                      label: const Text('Asistencia', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onAbrirBoleta,
                      icon: const Icon(Icons.receipt_long_outlined, size: 16),
                      label: const Text('Ver boleta', style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(backgroundColor: v.heroSolid),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vista previa: boleta (desglose legal completo + exportar PDF/Legajo) ──────

class _HojaBoletaPreview extends StatefulWidget {
  final PlanillaPreviewEmpleado empleado;
  final String labelPeriodo;
  final String regimenEmpresa; // micro | pequena | general
  final String periodoPago; // mes | q1 | q2 — PDF/Legajo solo tienen sentido en 'mes'
  final EmpresaInfo? empresaInfo;
  final int mes;
  final int anio;
  const _HojaBoletaPreview({
    required this.empleado, required this.labelPeriodo, required this.regimenEmpresa,
    required this.periodoPago, required this.empresaInfo, required this.mes, required this.anio,
  });

  @override
  State<_HojaBoletaPreview> createState() => _HojaBoletaPreviewState();
}

class _HojaBoletaPreviewState extends State<_HojaBoletaPreview> {
  bool _descargando = false;
  bool _enviando = false;

  Future<Uint8List> _generarPdf() => PdfService.boletaPago(
        empleado: widget.empleado, empresa: widget.empresaInfo!,
        labelPeriodo: widget.labelPeriodo, regimenEmpresa: widget.regimenEmpresa,
      );

  Future<void> _descargarPdf() async {
    setState(() => _descargando = true);
    try {
      final bytes = await _generarPdf();
      if (!mounted) return;
      await PdfPreviewScreen.abrir(context, bytes: bytes,
          nombreArchivo: 'boleta_${widget.empleado.id}.pdf', titulo: 'Boleta de Pago');
    } catch (_) {
      if (mounted) mostrarError(context, 'No se pudo generar el PDF.');
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  Future<void> _enviarALegajo() async {
    setState(() => _enviando = true);
    try {
      final bytes = await _generarPdf();
      final svc = await getFinanzasService();
      final r = await svc.enviarBoletaALegajo(
        widget.empleado.id, bytes,
        'Boleta_de_Pago_${widget.mes.toString().padLeft(2, '0')}${widget.anio}.pdf',
        mes: widget.mes, anio: widget.anio,
      );
      if (!mounted) return;
      if (r.ok) {
        mostrarOk(context, 'Boleta enviada al Legajo Digital');
      } else {
        mostrarError(context, r.errorMessage);
      }
    } catch (_) {
      if (mounted) mostrarError(context, 'No se pudo generar el PDF.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _fila(String label, String detalle, String monto, {bool destacado = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: destacado ? FontWeight.w700 : FontWeight.w500)),
            ),
            Expanded(
              flex: 3,
              child: Text(detalle, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            ),
            SizedBox(
              width: 80,
              child: Text(monto,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: monto.startsWith('−') ? Colors.deepOrange : null)),
            ),
          ],
        ),
      );

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.bold,
                color: Colors.grey.shade600, letterSpacing: 0.5)),
      );

  @override
  Widget build(BuildContext context) {
    final e = widget.empleado;
    final v = VerdantColors.of(context);
    final puedeExportar = widget.periodoPago == 'mes' && widget.empresaInfo != null;
    final esAdmin = AppSession.i.isAdmin;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boleta de Pago', style: Theme.of(context).textTheme.titleLarge),
            Text('${e.nombreCompleto ?? "Empleado"} · ${widget.labelPeriodo}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
            const Divider(height: 20),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  _seccion('Ingresos'),
                  _fila('Remuneración Básica', 'Jornada ordinaria pactada', money(e.sueldoPeriodo)),
                  if (e.pagoHorasExtra > 0)
                    _fila('Trabajo en Sobretiempo (${e.horasExtraPagables.toStringAsFixed(1)}h)',
                        e.esDependiente ? 'Recargo legal 25%/35%' : 'Tarifa simple (Ley 28518)',
                        '+${money(e.pagoHorasExtra)}'),
                  if (e.pagoDomingo > 0)
                    _fila('Trabajo en Descanso (Domingo, ${e.horasDomingo.toStringAsFixed(1)}h)',
                        'Sobretasa 100% — D.Leg. 713', '+${money(e.pagoDomingo)}'),
                  if (e.pagoFeriado > 0)
                    _fila('Trabajo en Feriado (${e.horasFeriado.toStringAsFixed(1)}h)',
                        'Sobretasa 100% — D.Leg. 713', '+${money(e.pagoFeriado)}'),
                  if (e.asignacionFamiliar > 0)
                    _fila('Asignación Familiar', '10% RMV — D.S. 035-90-TR',
                        '+${money(e.asignacionFamiliar)}'),
                  _seccion('Descuentos'),
                  if (e.descuentoFaltas > 0)
                    _fila('Inasistencias', '${e.diasFaltantes}d + ${e.minutosTardanza}min tardanza',
                        '−${money(e.descuentoFaltas)}')
                  else
                    _fila('Inasistencias', 'Sin faltas ni tardanzas', '—'),
                  if (e.descuentoPension > 0)
                    _fila('Pensión', e.motivoPension, '−${money(e.descuentoPension)}')
                  else
                    _fila('Pensión', e.motivoPension, '—'),
                  if (e.renta5ta > 0)
                    _fila('Renta de 5ta Categoría', 'Retención mensualizada (SUNAT)',
                        '−${money(e.renta5ta)}'),
                  Divider(height: 20, color: v.track),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: v.grnBg, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('NETO A PAGAR',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(money(e.netoAPagar),
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 20, color: v.grn)),
                      ],
                    ),
                  ),
                  _seccion('Beneficios y aportes del empleador'),
                  _fila('Aporte a EsSalud', 'Ley 26790 — no se descuenta al trabajador',
                      money(e.aporteEssalud)),
                  _fila('CTS', e.motivoCts(widget.regimenEmpresa),
                      e.provisionCts > 0 ? money(e.provisionCts) : '—'),
                  _fila('Gratificación', e.motivoGratificacion(widget.regimenEmpresa),
                      e.provisionGratificacion > 0 ? money(e.provisionGratificacion) : '—'),
                  _fila('Vacaciones', e.motivoVacaciones,
                      e.provisionVacaciones > 0 ? money(e.provisionVacaciones) : '—'),
                ],
              ),
            ),
            if (puedeExportar) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _descargando ? null : _descargarPdf,
                    icon: _descargando
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Descargar PDF', style: TextStyle(fontSize: 12)),
                  ),
                ),
                if (esAdmin) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _enviando ? null : _enviarALegajo,
                      icon: _enviando
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.folder_shared_outlined, size: 16),
                      label: const Text('Enviar a Legajo', style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(backgroundColor: v.heroSolid),
                    ),
                  ),
                ],
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Vista previa: asistencia día-por-día (solo lectura) ─────────────────────

class _HojaAsistenciaDetalle extends StatefulWidget {
  final String empleadoId;
  final String nombre;
  final String inicio;
  final String fin;
  const _HojaAsistenciaDetalle({
    required this.empleadoId, required this.nombre, required this.inicio, required this.fin,
  });
  @override
  State<_HojaAsistenciaDetalle> createState() => _HojaAsistenciaDetalleState();
}

class _HojaAsistenciaDetalleState extends State<_HojaAsistenciaDetalle> {
  AsistenciaDetalle? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final svc = await getFinanzasService();
    final r = await svc.getAsistenciaDetalle(widget.empleadoId, widget.inicio, widget.fin);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _data = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  String _h(double v) => v == 0 ? '—' : '${v.toStringAsFixed(1)}h';

  (String, Color, Color) _tipoDia(String tipo, VerdantColors v) => switch (tipo) {
        'domingo' => ('Domingo', v.blu, v.bluBg),
        'feriado' => ('Feriado', v.amb, v.ambBg),
        'no_laborable_turno' => ('Fuera de turno', v.mut, v.track),
        _ => ('Laborable', v.sub, v.track),
      };

  @override
  Widget build(BuildContext context) {
    final v = VerdantColors.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Asistencia', style: Theme.of(context).textTheme.titleLarge),
            Text(widget.nombre, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
            const Divider(height: 20),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: TextStyle(color: v.red)))
                      : _data == null
                          ? const Center(child: Text('Sin datos de asistencia'))
                          : ListView(
                              controller: scrollCtrl,
                              children: [
                                GridView.count(
                                  crossAxisCount: 3,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  childAspectRatio: 1.6,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  children: [
                                    _tarjetaMini('Meta', _h(_data!.totales.metaHoras), v),
                                    _tarjetaMini('Reales', _h(_data!.totales.horasReales), v),
                                    _tarjetaMini('Extra',
                                        _h(_data!.totales.extra25 + _data!.totales.extra35), v,
                                        color: v.grn),
                                    _tarjetaMini('Faltantes', _h(_data!.totales.horasFaltantes), v,
                                        color: v.red),
                                    _tarjetaMini('Domingo', _h(_data!.totales.horasDomingo), v),
                                    _tarjetaMini('Feriado', _h(_data!.totales.horasFeriado), v),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                for (final d in _data!.detalleDias) _filaDia(d, v),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaMini(String label, String valor, VerdantColors v, {Color? color}) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: v.cardAlt, borderRadius: BorderRadius.circular(10)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: v.sub)),
            Text(valor,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: color ?? v.ink)),
          ],
        ),
      );

  Widget _filaDia(DetalleDia d, VerdantColors v) {
    final (label, color, bg) = _tipoDia(d.tipoDia, v);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: d.alerta != null
          ? Icon(Icons.warning_amber_rounded, size: 18, color: v.amb)
          : const Icon(Icons.circle, size: 8, color: Colors.transparent),
      title: Row(children: [
        SizedBox(width: 70, child: Text(d.fecha, style: const TextStyle(fontSize: 12))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
      trailing: Text('${_h(d.horasReales)} / ${_h(d.reqHoras)}',
          style: const TextStyle(fontSize: 11.5)),
    );
  }
}

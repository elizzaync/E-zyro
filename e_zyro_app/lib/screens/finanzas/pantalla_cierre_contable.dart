import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import '../../utils/ui_insets.dart';
import '../../widgets/verdant_theme.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Cierre de ejercicio anual + configuración contable (cuentas del cierre).
///
/// Pensada para un usuario no contable: muestra el estado de los 12 meses, el
/// resultado del año en lenguaje simple (ganancia/pérdida) y un solo botón que
/// genera los asientos de cierre automáticamente. La parte técnica (qué cuentas
/// PCGE usa el cierre) vive como configuración editable, con defaults correctos.
class PantallaCierreContable extends StatefulWidget {
  const PantallaCierreContable({super.key});

  @override
  State<PantallaCierreContable> createState() => _PantallaCierreContableState();
}

class _PantallaCierreContableState extends State<PantallaCierreContable> {
  FinanzasService? _svc;
  EstadoEjercicio? _estado;
  ConfigContable? _config;
  EstadoApertura? _apertura;
  List<CuentaContable> _cuentasDetalle = [];
  int _anio = DateTime.now().year;
  bool _cargando = true;
  bool _procesando = false;
  String? _error;

  static final _fmt = NumberFormat('#,##0.00', 'es_PE');
  String _s(double v) => 'S/ ${_fmt.format(v)}';

  static const _meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul',
    'Ago', 'Set', 'Oct', 'Nov', 'Dic'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getFinanzasService();
    await Future.wait([_cargar(), _cargarConfig()]);
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final r = await _svc!.estadoEjercicio(_anio);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _estado = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  Future<void> _cargarConfig() async {
    if (_svc == null) return;
    final c = await _svc!.configContable();
    final pc = await _svc!.planCuentas(nivel: 'detalle', soloActivas: true);
    final ap = await _svc!.estadoApertura();
    if (!mounted) return;
    setState(() {
      _config = c.ok ? c.data : null;
      _cuentasDetalle = pc.ok ? (pc.data ?? []) : [];
      _apertura = ap.ok ? ap.data : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = VerdantColors.of(context);
    return Scaffold(
      backgroundColor: v.dark ? const Color(0xFF0B120D) : const Color(0xFFF6F8F3),
      appBar: AppBar(
        title: const Text('Cierre y configuración',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          accionConmutadorFinanzas(context, actual: FinId.cierre),
          IconButton(
              onPressed: () async {
                await Future.wait([_cargar(), _cargarConfig()]);
              },
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando && _estado == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: bottomSafePadding(context),
              children: [
                _selectorAnio(v),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: TextStyle(color: v.red),
                        textAlign: TextAlign.center),
                  ),
                if (_estado != null) ...[
                  _cardEjercicio(v, _estado!),
                  const SizedBox(height: 12),
                ],
                _cardApertura(v),
                const SizedBox(height: 12),
                _cardConfiguracion(v),
                const SizedBox(height: 12),
                _cardExplicacion(v),
              ],
            ),
    );
  }

  Widget _selectorAnio(VerdantColors v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: v.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: v.bd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: v.sub),
            onPressed: _procesando
                ? null
                : () {
                    setState(() => _anio--);
                    _cargar();
                  },
          ),
          Text('Ejercicio $_anio',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 17, fontWeight: FontWeight.w700, color: v.ink)),
          IconButton(
            icon: Icon(Icons.chevron_right, color: v.sub),
            onPressed: _procesando || _anio >= DateTime.now().year
                ? null
                : () {
                    setState(() => _anio++);
                    _cargar();
                  },
          ),
        ],
      ),
    );
  }

  Widget _cardEjercicio(VerdantColors v, EstadoEjercicio e) {
    final ganancia = e.resultado >= 0;
    final puedeAccionar = AppSession.i.isAdmin || AppSession.i.canCerrarEjercicio;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: v.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: v.bd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Estado del ejercicio',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: v.ink)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: e.cerrado ? v.bluBg : v.ambBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(e.cerrado ? 'CERRADO' : 'EN CURSO',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: e.cerrado ? v.blu : v.amb)),
          ),
        ]),
        const SizedBox(height: 14),
        // 12 meses con su estado: cerrado (verde), abierto (ámbar), sin abrir (gris)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in e.periodos)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: p.estado == 'cerrado'
                      ? v.grnBg
                      : p.estado == 'abierto'
                          ? v.ambBg
                          : v.cardAlt,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    p.estado == 'cerrado'
                        ? Icons.check_circle_rounded
                        : p.estado == 'abierto'
                            ? Icons.pending_rounded
                            : Icons.circle_outlined,
                    size: 11,
                    color: p.estado == 'cerrado'
                        ? v.grn
                        : p.estado == 'abierto'
                            ? v.amb
                            : v.mut,
                  ),
                  const SizedBox(width: 4),
                  Text(_meses[p.mes - 1],
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: p.estado == null ? v.mut : v.ink)),
                ]),
              ),
          ],
        ),
        const Divider(height: 26),
        Row(children: [
          Expanded(
              child: _dato(v, 'Ingresos', _s(e.ingresos), v.grn)),
          Expanded(child: _dato(v, 'Gastos', _s(e.gastos), v.red)),
          Expanded(
            child: _dato(
                v,
                ganancia ? 'Ganancia' : 'Pérdida',
                _s(e.resultado.abs()),
                ganancia ? v.grn : v.red),
          ),
        ]),
        const SizedBox(height: 16),
        if (e.cerrado && puedeAccionar)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _procesando ? null : () => _confirmarRevertir(e),
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Revertir cierre'),
              style: OutlinedButton.styleFrom(foregroundColor: v.red),
            ),
          )
        else if (!e.cerrado && puedeAccionar)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _procesando || !e.puedeCerrar ? null : () => _confirmarCerrar(e),
              icon: _procesando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.event_available_rounded, size: 18),
              label: Text('Cerrar ejercicio $_anio'),
              style: FilledButton.styleFrom(
                  backgroundColor: v.heroSolid, foregroundColor: Colors.white),
            ),
          ),
        if (!e.cerrado && e.motivo != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.info_outline_rounded, size: 14, color: v.amb),
            const SizedBox(width: 6),
            Expanded(
                child: Text(e.motivo!,
                    style: TextStyle(fontSize: 11.5, color: v.sub))),
          ]),
        ],
      ]),
    );
  }

  Widget _dato(VerdantColors v, String label, String valor, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, color: v.sub)),
      const SizedBox(height: 3),
      Text(valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
    ]);
  }

  Future<void> _confirmarCerrar(EstadoEjercicio e) async {
    final ganancia = e.resultado >= 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Cerrar el ejercicio $_anio?'),
        content: Text(
          'El sistema generará automáticamente los asientos que trasladan '
          'la ${ganancia ? 'ganancia' : 'pérdida'} del año '
          '(${_s(e.resultado.abs())}) al patrimonio de la empresa, y '
          'diciembre quedará cerrado.\n\n'
          'No se borra nada: si luego necesitas corregir algo, puedes '
          'revertir el cierre desde esta misma pantalla.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cerrar ejercicio')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _procesando = true);
    final r = await _svc!.cerrarEjercicio(_anio);
    if (!mounted) return;
    setState(() => _procesando = false);
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ejercicio $_anio cerrado. '
              'Asientos generados: ${(r.data?['asientos'] as List?)?.join(', ') ?? '—'}')));
      await _cargar();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.errorMessage)));
    }
  }

  Future<void> _confirmarRevertir(EstadoEjercicio e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Revertir el cierre de $_anio?'),
        content: const Text(
          'Se generará un asiento de reversión (nada se borra) y diciembre '
          'quedará abierto para que puedas corregir y volver a cerrar.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Revertir')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _procesando = true);
    final r = await _svc!.revertirCierreEjercicio(_anio);
    if (!mounted) return;
    setState(() => _procesando = false);
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cierre de $_anio revertido.')));
      await _cargar();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.errorMessage)));
    }
  }

  // ── Saldos iniciales / asiento de apertura ─────────────────────────────────
  Widget _cardApertura(VerdantColors v) {
    final ap = _apertura;
    final puedeCargar =
        AppSession.i.isAdmin || AppSession.i.canCargarApertura;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: v.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: v.bd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.flag_outlined, size: 16, color: v.heroSolid),
          const SizedBox(width: 7),
          Text('Saldos iniciales',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: v.ink)),
          const Spacer(),
          if (ap != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ap.cargada ? v.grnBg : v.ambBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(ap.cargada ? 'CARGADOS' : 'PENDIENTE',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: ap.cargada ? v.grn : v.amb)),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
          ap != null && ap.cargada
              ? 'Asiento de apertura ${ap.asientoNumero ?? ''} del ${ap.fecha ?? ''}. '
                  'Tu contabilidad parte de los saldos reales de la empresa.'
              : 'Si la empresa ya operaba antes de usar E-Zyro, carga aquí lo que '
                  'tenía (caja, bancos, deudas, capital) para que los reportes '
                  'reflejen la realidad desde el día uno.',
          style: TextStyle(fontSize: 11.5, color: v.sub, height: 1.4),
        ),
        if (puedeCargar) ...[
          const SizedBox(height: 12),
          if (ap != null && ap.cargada)
            OutlinedButton.icon(
              onPressed: _procesando ? null : _confirmarRevertirApertura,
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Revertir saldos iniciales'),
              style: OutlinedButton.styleFrom(foregroundColor: v.red),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _procesando ? null : _abrirFormApertura,
                icon: const Icon(Icons.flag_rounded, size: 18),
                label: const Text('Cargar saldos iniciales'),
                style: FilledButton.styleFrom(
                    backgroundColor: v.heroSolid,
                    foregroundColor: Colors.white),
              ),
            ),
        ],
      ]),
    );
  }

  void _abrirFormApertura() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormApertura(onGuardado: () async {
        await _cargarConfig();
        await _cargar();
      }),
    );
  }

  Future<void> _confirmarRevertirApertura() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Revertir los saldos iniciales?'),
        content: const Text(
            'Se generará un asiento de reversión (nada se borra) y podrás '
            'volver a cargarlos con los montos corregidos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Revertir')),
        ],
      ),
    );
    if (ok != true || _svc == null) return;
    setState(() => _procesando = true);
    final r = await _svc!.revertirApertura();
    if (!mounted) return;
    setState(() => _procesando = false);
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saldos iniciales revertidos.')));
      await _cargarConfig();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.errorMessage)));
    }
  }

  // ── Configuración de cuentas del cierre ────────────────────────────────────
  Widget _cardConfiguracion(VerdantColors v) {
    final cfg = _config;
    final puedeEditar =
        AppSession.i.isAdmin || AppSession.i.canConfigurarContabilidad;
    String nombre(String codigo) {
      final c = _cuentasDetalle.where((x) => x.codigo == codigo).toList();
      return c.isEmpty ? codigo : '$codigo — ${c.first.nombre}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: v.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: v.bd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.tune_rounded, size: 16, color: v.heroSolid),
          const SizedBox(width: 7),
          Text('Cuentas del cierre (avanzado)',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: v.ink)),
        ]),
        const SizedBox(height: 6),
        Text(
          'El cierre usa estas cuentas PCGE automáticamente. Solo cámbialas '
          'si tu contador te lo indica.',
          style: TextStyle(fontSize: 11.5, color: v.sub),
        ),
        const SizedBox(height: 12),
        if (cfg == null)
          Text('Sin configuración cargada.', style: TextStyle(color: v.mut))
        else ...[
          _filaCuenta(v, 'Cuenta puente del cierre',
              nombre(cfg.cuentaCierreCodigo), puedeEditar,
              () => _elegirCuenta('cuenta_cierre_codigo')),
          _filaCuenta(v, 'Destino si hay ganancia',
              nombre(cfg.cuentaUtilidadCodigo), puedeEditar,
              () => _elegirCuenta('cuenta_utilidad_codigo')),
          _filaCuenta(v, 'Destino si hay pérdida',
              nombre(cfg.cuentaPerdidaCodigo), puedeEditar,
              () => _elegirCuenta('cuenta_perdida_codigo')),
        ],
      ]),
    );
  }

  Widget _filaCuenta(VerdantColors v, String label, String valor,
      bool editable, VoidCallback onEditar) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11, color: v.sub)),
            const SizedBox(height: 2),
            Text(valor,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: v.ink)),
          ]),
        ),
        if (editable)
          IconButton(
              icon: Icon(Icons.edit_outlined, size: 18, color: v.sub),
              onPressed: onEditar),
      ]),
    );
  }

  Future<void> _elegirCuenta(String campo) async {
    // Para el cierre solo tienen sentido cuentas de patrimonio (89x/59x).
    final candidatas = _cuentasDetalle
        .where((c) => c.tipo == 'patrimonio')
        .toList()
      ..sort((a, b) => a.codigo.compareTo(b.codigo));
    final elegida = await showModalBottomSheet<CuentaContable>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Elegir cuenta de patrimonio',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            for (final c in candidatas)
              ListTile(
                dense: true,
                title: Text('${c.codigo} — ${c.nombre}'),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (elegida == null || _svc == null) return;
    final r = await _svc!.actualizarConfigContable(
      cuentaCierreCodigo: campo == 'cuenta_cierre_codigo' ? elegida.codigo : null,
      cuentaUtilidadCodigo:
          campo == 'cuenta_utilidad_codigo' ? elegida.codigo : null,
      cuentaPerdidaCodigo:
          campo == 'cuenta_perdida_codigo' ? elegida.codigo : null,
    );
    if (!mounted) return;
    if (r.ok) {
      setState(() => _config = r.data);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.errorMessage)));
    }
  }

  Widget _cardExplicacion(VerdantColors v) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: v.cardAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.school_outlined, size: 18, color: v.heroSolid),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '¿Qué es el cierre de ejercicio? Al terminar el año, la ganancia o '
            'pérdida se traslada al patrimonio de la empresa para empezar el '
            'nuevo año "en cero" en ingresos y gastos. Este sistema lo hace '
            'automáticamente con asientos trazables: nada se digita ni se borra.',
            style: TextStyle(fontSize: 11.5, color: v.sub, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

// ── Formulario de saldos iniciales ───────────────────────────────────────────

/// Carga guiada del asiento de apertura: conceptos cotidianos (caja, bancos,
/// deudas…) mapeados a cuentas PCGE; los campos en cero se ignoran y la
/// diferencia se ajusta sola contra Capital (501) en el backend.
class _FormApertura extends StatefulWidget {
  final Future<void> Function() onGuardado;
  const _FormApertura({required this.onGuardado});

  @override
  State<_FormApertura> createState() => _FormAperturaState();
}

class _FormAperturaState extends State<_FormApertura> {
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  // (código PCGE, etiqueta cotidiana, ícono)
  static const _conceptos = <(String, String, IconData)>[
    ('101', 'Dinero en caja', Icons.payments_outlined),
    ('104', 'Dinero en bancos', Icons.account_balance_outlined),
    ('121', 'Por cobrar a clientes', Icons.call_received_rounded),
    ('201', 'Mercaderías / existencias', Icons.inventory_2_outlined),
    ('333', 'Maquinaria y equipos', Icons.precision_manufacturing_outlined),
    ('336', 'Equipos diversos', Icons.devices_other_outlined),
    ('421', 'Deudas a proveedores', Icons.call_made_rounded),
    ('469', 'Otras deudas', Icons.request_page_outlined),
    ('501', 'Capital aportado', Icons.savings_outlined),
  ];

  final Map<String, TextEditingController> _montos = {
    for (final c in _conceptos) c.$1: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _montos.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final lineas = <Map<String, dynamic>>[];
    for (final c in _conceptos) {
      final m = double.tryParse(_montos[c.$1]!.text) ?? 0;
      if (m > 0) lineas.add({'cuenta_codigo': c.$1, 'monto': m});
    }
    if (lineas.isEmpty) {
      mostrarError(context, 'Ingresa al menos un saldo mayor que cero');
      return;
    }
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final r = await svc.cargarApertura(
      fecha: DateFormat('yyyy-MM-dd').format(_fecha),
      lineas: lineas,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      final ajuste = toNum(r.data?['ajuste_capital']);
      mostrarOk(
          context,
          ajuste == 0
              ? 'Saldos iniciales cargados'
              : 'Saldos cargados · diferencia de ${money(ajuste.abs())} ajustada contra Capital');
      Navigator.pop(context);
      await widget.onGuardado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = VerdantColors.of(context);
    return FinFormSheet(
      titulo: 'Saldos iniciales',
      subtitulo:
          'Lo que la empresa ya tenía al empezar a usar E-Zyro. Los campos en cero se ignoran.',
      icono: Icons.flag_outlined,
      textoBoton: 'Cargar saldos iniciales',
      guardando: _guardando,
      onGuardar: _guardar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _fecha,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => _fecha = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha de corte',
                helperText: 'El día desde el que la contabilidad es real',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(DateFormat('dd/MM/yyyy').format(_fecha)),
            ),
          ),
          const SizedBox(height: 14),
          for (final c in _conceptos) ...[
            TextField(
              controller: _montos[c.$1],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '${c.$2} (S/)',
                prefixIcon: Icon(c.$3, size: 19),
                helperText: 'Cuenta ${c.$1}',
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: v.cardAlt,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_fix_high_outlined, size: 16, color: v.heroSolid),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No necesitas cuadrar nada: si el total no calza, la '
                  'diferencia se ajusta automáticamente contra Capital y se '
                  'registra de forma trazable.',
                  style: TextStyle(fontSize: 11, color: v.sub, height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

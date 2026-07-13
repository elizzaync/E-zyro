import 'package:flutter/material.dart';
import '../../models/finanzas_models.dart';
import '../../utils/app_session.dart';
import '../../utils/api_provider.dart';
import '../../utils/ui_insets.dart';
import '../../theme/ez_theme.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Caja Chica: lista de cajas operativas y, al entrar, sus movimientos.
/// Cada movimiento genera su asiento contable automático en el backend.
class PantallaCajaChica extends StatefulWidget {
  const PantallaCajaChica({super.key});
  @override
  State<PantallaCajaChica> createState() => _State();
}

class _State extends State<PantallaCajaChica> {
  List<CajaChica> _cajas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final svc = await getFinanzasService();
    final r = await svc.cajasChicas();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) _cajas = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  void _abrirFormCaja() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormCaja(onGuardado: _cargar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGestionar = AppSession.i.canGestionarCajaChica;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caja Chica'),
        actions: [accionConmutadorFinanzas(context, actual: FinId.cajaChica)],
      ),
      floatingActionButton: canGestionar
          ? FloatingActionButton.extended(
              onPressed: _abrirFormCaja,
              icon: const Icon(Icons.add),
              label: const Text('Nueva caja'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cajas.isEmpty
              ? const EstadoVacio(
                  icono: Icons.savings_outlined,
                  titulo: 'Sin cajas chicas registradas',
                  subtitulo: 'Registra tu primera caja chica para controlar el efectivo de gastos menores.',
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: bottomSafePadding(context, top: 12),
                    itemCount: _cajas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _tarjetaCaja(_cajas[i]),
                  ),
                ),
    );
  }

  Widget _tarjetaCaja(CajaChica c) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorEstado(c.estado, context.ez).withValues(alpha: 0.15),
          child: Icon(Icons.savings_outlined, color: colorEstado(c.estado, context.ez)),
        ),
        title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.responsableNombre != null && c.responsableNombre!.isNotEmpty)
              Text('Responsable: ${c.responsableNombre}',
                  style: const TextStyle(fontSize: 12)),
            Text('${c.nMovimientos} movimiento(s)',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(c.saldoActual),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            chipEstado(c.estado, context.ez),
          ],
        ),
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => PantallaDetalleCaja(caja: c)));
          if (mounted) _cargar();
        },
      ),
    );
  }
}

// ── Detalle de una caja: saldo + movimientos ──────────────────────────────────

class PantallaDetalleCaja extends StatefulWidget {
  final CajaChica caja;
  const PantallaDetalleCaja({super.key, required this.caja});
  @override
  State<PantallaDetalleCaja> createState() => _DetalleState();
}

class _DetalleState extends State<PantallaDetalleCaja> {
  late CajaChica _caja;
  List<MovimientoCaja> _movs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _caja = widget.caja;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final svc = await getFinanzasService();
    final rc = await svc.obtenerCajaChica(_caja.id);
    final rm = await svc.movimientosCaja(_caja.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (rc.ok) _caja = rc.data!;
      if (rm.ok) _movs = rm.data!;
    });
    if (!rm.ok) mostrarError(context, rm.errorMessage);
  }

  void _abrirFormMovimiento() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormMovimiento(
        cajaId: _caja.id,
        saldoDisponible: _caja.saldoActual,
        onGuardado: _cargar,
      ),
    );
  }

  Future<void> _cerrarCaja() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar caja'),
        content: Text('¿Cerrar "${_caja.nombre}"? No admitirá más movimientos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final svc = await getFinanzasService();
    final r = await svc.cerrarCajaChica(_caja.id);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Caja cerrada');
      _cargar();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canMover = AppSession.i.canRegistrarMovimientoCaja && _caja.abierta;
    final canGestionar = AppSession.i.canGestionarCajaChica;
    return Scaffold(
      appBar: AppBar(
        title: Text(_caja.nombre),
        actions: [
          if (canGestionar && _caja.abierta)
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Cerrar caja',
              onPressed: _cerrarCaja,
            ),
        ],
      ),
      floatingActionButton: canMover
          ? FloatingActionButton.extended(
              onPressed: _abrirFormMovimiento,
              icon: const Icon(Icons.swap_vert),
              label: const Text('Movimiento'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: bottomSafePadding(context, top: 12),
                children: [
                  TarjetaResumen(
                    titulo: 'Saldo actual',
                    valor: money(_caja.saldoActual),
                    color: _caja.saldoActual >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                    icono: Icons.savings,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        Expanded(child: _miniStat('Ingresos', _caja.totalIngresos, Colors.green)),
                        const SizedBox(width: 8),
                        Expanded(child: _miniStat('Egresos', _caja.totalEgresos, Colors.red)),
                      ],
                    ),
                  ),
                  if (!_caja.abierta)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(children: [chipEstado(_caja.estado, context.ez)]),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Movimientos',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  if (_movs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: EstadoVacio(
                        icono: Icons.receipt_long,
                        titulo: 'Sin movimientos',
                        subtitulo: 'Registra un ingreso para constituir el fondo.',
                      ),
                    )
                  else
                    ..._movs.map(_tarjetaMov),
                ],
              ),
            ),
    );
  }

  Widget _miniStat(String label, double valor, MaterialColor color) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(money(valor),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade700)),
        ],
      ),
    );
  }

  Widget _tarjetaMov(MovimientoCaja m) {
    final esIngreso = m.esIngreso;
    final color = esIngreso ? Colors.green : Colors.red;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(esIngreso ? Icons.arrow_downward : Icons.arrow_upward, color: color),
        ),
        title: Text(m.descripcion),
        subtitle: Text(
          '${m.fecha.length >= 10 ? m.fecha.substring(0, 10) : m.fecha}'
          '${m.concepto != null && m.concepto!.isNotEmpty ? ' · ${m.concepto}' : ''}'
          '${m.registradoPorNombre != null && m.registradoPorNombre!.isNotEmpty ? ' · ${m.registradoPorNombre}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text('${esIngreso ? '+' : '−'} ${money(m.monto)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}

// ── Formulario nueva caja ─────────────────────────────────────────────────────

class _FormCaja extends StatefulWidget {
  final VoidCallback onGuardado;
  const _FormCaja({required this.onGuardado});
  @override
  State<_FormCaja> createState() => _FormCajaState();
}

class _FormCajaState extends State<_FormCaja> {
  final _form = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final r = await svc.crearCajaChica(
      nombre: _nombreCtrl.text.trim(),
      descripcion: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      montoAsignado: double.tryParse(_montoCtrl.text.trim()),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Caja creada');
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
              Text('Nueva caja chica', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nombre', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Fondo fijo referencial S/ (opcional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              const Text(
                'El responsable será tu usuario. El saldo arranca en 0; registra un '
                'ingreso para constituir el fondo (Db Caja chica / Cr Bancos).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Crear caja'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Formulario movimiento ─────────────────────────────────────────────────────

class _FormMovimiento extends StatefulWidget {
  final String cajaId;
  final double saldoDisponible;
  final VoidCallback onGuardado;
  const _FormMovimiento({
    required this.cajaId,
    required this.saldoDisponible,
    required this.onGuardado,
  });
  @override
  State<_FormMovimiento> createState() => _FormMovimientoState();
}

class _FormMovimientoState extends State<_FormMovimiento> {
  final _form = GlobalKey<FormState>();
  String _tipo = 'egreso';
  final _montoCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _conceptoCtrl = TextEditingController();
  final _cuentaCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _descCtrl.dispose();
    _conceptoCtrl.dispose();
    _cuentaCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final monto = double.tryParse(_montoCtrl.text.trim()) ?? 0;
    if (_tipo == 'egreso' && monto > widget.saldoDisponible) {
      mostrarError(context, 'El egreso excede el saldo disponible (${money(widget.saldoDisponible)})');
      return;
    }
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final r = await svc.registrarMovimientoCaja(
      cajaId: widget.cajaId,
      tipo: _tipo,
      monto: monto,
      descripcion: _descCtrl.text.trim(),
      concepto: _conceptoCtrl.text.trim().isEmpty ? null : _conceptoCtrl.text.trim(),
      cuentaCodigo: _cuentaCtrl.text.trim().isEmpty ? null : _cuentaCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Movimiento registrado');
      Navigator.pop(context);
      widget.onGuardado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esEgreso = _tipo == 'egreso';
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
              Text('Registrar movimiento', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ingreso', label: Text('Ingreso'), icon: Icon(Icons.arrow_downward)),
                  ButtonSegment(value: 'egreso', label: Text('Egreso'), icon: Icon(Icons.arrow_upward)),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() => _tipo = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Monto S/', border: OutlineInputBorder()),
                validator: (v) {
                  final d = double.tryParse(v ?? '');
                  if (d == null || d <= 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Descripción', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _conceptoCtrl,
                decoration: const InputDecoration(
                    labelText: 'Concepto (ej. movilidad, papelería)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cuentaCtrl,
                decoration: InputDecoration(
                    labelText: esEgreso
                        ? 'Código cuenta de gasto (opcional, def. 659)'
                        : 'Código cuenta origen (opcional, def. 104)',
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Text(
                esEgreso
                    ? 'Asiento: Db cuenta de gasto / Cr 101 Caja chica.'
                    : 'Asiento: Db 101 Caja chica / Cr cuenta de origen.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Registrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

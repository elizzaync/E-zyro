import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Plan de cuentas (PCGE) + balance de comprobación del periodo.
class PantallaPlanCuentas extends StatefulWidget {
  const PantallaPlanCuentas({super.key});

  @override
  State<PantallaPlanCuentas> createState() => _PantallaPlanCuentasState();
}

class _PantallaPlanCuentasState extends State<PantallaPlanCuentas> {
  FinanzasService? _svc;
  List<CuentaContable> _cuentas = [];
  BalanceComprobacion? _balance;
  String _periodo = periodoActual();
  bool _cargando = true;
  String? _error;
  String _filtroTipo = 'todos';

  List<PeriodoContable> _periodos = [];
  bool _cargandoPeriodos = true;

  List<AsientoContable> _asientos = [];
  String? _periodoIdAsientos;
  bool _cargandoAsientos = true;

  static const _tipos = ['todos', 'activo', 'pasivo', 'patrimonio', 'ingreso', 'gasto'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getFinanzasService();
    await Future.wait([_cargar(), _cargarPeriodos(), _cargarAsientos()]);
  }

  Future<void> _cargarPeriodos() async {
    if (_svc == null) return;
    setState(() => _cargandoPeriodos = true);
    final r = await _svc!.periodos();
    if (!mounted) return;
    setState(() {
      _cargandoPeriodos = false;
      if (r.ok) _periodos = r.data ?? [];
    });
  }

  Future<void> _cargarAsientos() async {
    if (_svc == null) return;
    setState(() => _cargandoAsientos = true);
    final r = await _svc!.asientos(periodoId: _periodoIdAsientos);
    if (!mounted) return;
    setState(() {
      _cargandoAsientos = false;
      if (r.ok) _asientos = r.data ?? [];
    });
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final cuentas = await _svc!.planCuentas(soloActivas: false);
    final balance = await _svc!.balanceComprobacion(_periodo);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (cuentas.ok) {
        _cuentas = cuentas.data ?? [];
      } else {
        _error = cuentas.errorMessage;
      }
      _balance = balance.ok ? balance.data : null;
    });
  }

  List<CuentaContable> get _filtradas => _filtroTipo == 'todos'
      ? _cuentas
      : _cuentas.where((c) => c.tipo == _filtroTipo).toList();

  @override
  Widget build(BuildContext context) {
    final puedeCrearAsiento = AppSession.i.isAdmin || AppSession.i.hasPerm('contabilidad:crear_asiento');
    return DefaultTabController(
      length: 4,
      child: Builder(builder: (context) {
        final tabs = DefaultTabController.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Plan de cuentas', style: TextStyle(fontWeight: FontWeight.bold)),
            bottom: const TabBar(isScrollable: true, tabs: [
              Tab(text: 'Cuentas'),
              Tab(text: 'Comprobación'),
              Tab(text: 'Periodos'),
              Tab(text: 'Asientos'),
            ]),
            actions: [
              accionConmutadorFinanzas(context, actual: FinId.planCuentas),
              IconButton(onPressed: () async {
              await _cargar();
              await _cargarPeriodos();
              await _cargarAsientos();
            }, icon: const Icon(Icons.refresh))],
          ),
          body: TabBarView(children: [
            _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _tabCuentas(),
            _cargando ? const Center(child: CircularProgressIndicator()) : _tabBalance(),
            _tabPeriodos(),
            _tabAsientos(),
          ]),
          floatingActionButton: AnimatedBuilder(
            animation: tabs,
            builder: (_, _) => tabs.index == 3 && puedeCrearAsiento
                ? FloatingActionButton.extended(
                    onPressed: _nuevoAsiento,
                    icon: const Icon(Icons.add),
                    label: const Text('Asiento manual'),
                  )
                : const SizedBox.shrink(),
          ),
        );
      }),
    );
  }

  Widget _tabPeriodos() {
    if (_cargandoPeriodos) return const Center(child: CircularProgressIndicator());
    final puedeAbrir = AppSession.i.isAdmin || AppSession.i.hasPerm('contabilidad:abrir_periodo');
    final puedeCerrar = AppSession.i.isAdmin || AppSession.i.hasPerm('contabilidad:cerrar_periodo');
    final puedeReabrir = AppSession.i.isAdmin || AppSession.i.hasPerm('contabilidad:reabrir_periodo');
    return Stack(
      children: [
        _periodos.isEmpty
            ? const Center(child: Text('Sin periodos contables registrados.'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                itemCount: _periodos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final p = _periodos[i];
                  final abierto = p.estado == 'abierto';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (abierto ? Colors.green : Colors.grey).withValues(alpha: 0.15),
                        child: Icon(abierto ? Icons.lock_open_outlined : Icons.lock_outline,
                            color: abierto ? Colors.green : Colors.grey, size: 20),
                      ),
                      title: Text(p.periodo, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        abierto ? 'Abierto' : 'Cerrado${p.cerradoAt != null ? ' · ${p.cerradoAt}' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (accion) => _accionPeriodo(p, accion),
                        itemBuilder: (_) => [
                          if (abierto && puedeCerrar)
                            const PopupMenuItem(value: 'cerrar', child: Text('Cerrar periodo')),
                          if (!abierto && puedeReabrir)
                            const PopupMenuItem(value: 'reabrir', child: Text('Reabrir periodo')),
                        ],
                        child: const Icon(Icons.more_vert),
                      ),
                    ),
                  );
                },
              ),
        if (puedeAbrir)
          Positioned(
            right: 16, bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'abrirPeriodo',
              onPressed: _abrirPeriodo,
              icon: const Icon(Icons.add),
              label: const Text('Abrir periodo'),
            ),
          ),
      ],
    );
  }

  Future<void> _accionPeriodo(PeriodoContable p, String accion) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(accion == 'cerrar' ? 'Cerrar periodo' : 'Reabrir periodo'),
        content: Text('¿Confirma ${accion == 'cerrar' ? 'cerrar' : 'reabrir'} el periodo ${p.periodo}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmar != true || _svc == null) return;
    final r = accion == 'cerrar' ? await _svc!.cerrarPeriodo(p.id) : await _svc!.reabrirPeriodo(p.id);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, accion == 'cerrar' ? 'Periodo cerrado' : 'Periodo reabierto');
      await _cargarPeriodos();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _abrirPeriodo() async {
    final ahora = DateTime.now();
    final d = await showDatePicker(
      context: context, initialDate: ahora,
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      helpText: 'Elige cualquier día del periodo a abrir');
    if (d == null || _svc == null) return;
    final r = await _svc!.abrirPeriodo(d.year, d.month);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Periodo abierto');
      await _cargarPeriodos();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Widget _tabAsientos() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String?>(
            initialValue: _periodoIdAsientos,
            decoration: const InputDecoration(labelText: 'Filtrar por periodo', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos los periodos')),
              ..._periodos.map((p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.periodo))),
            ],
            onChanged: (v) {
              setState(() => _periodoIdAsientos = v);
              _cargarAsientos();
            },
          ),
        ),
        Expanded(
          child: _cargandoAsientos
              ? const Center(child: CircularProgressIndicator())
              : _asientos.isEmpty
                  ? const Center(child: Text('Sin asientos contables.'))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: _asientos.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = _asientos[i];
                        return ExpansionTile(
                          title: Text('N° ${a.numero}  ·  ${a.fecha}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text('${a.descripcion}  ·  ${a.origen}', style: const TextStyle(fontSize: 11)),
                          children: a.lineas.map((l) => ListTile(
                                dense: true,
                                title: Text('${l.cuentaCodigo ?? ''}  ${l.glosa ?? ''}'.trim(),
                                    style: const TextStyle(fontSize: 12)),
                                trailing: Text(
                                  '${l.debito > 0 ? 'D ${money(l.debito)}' : ''}${l.credito > 0 ? 'H ${money(l.credito)}' : ''}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              )).toList(),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _nuevoAsiento() async {
    if (_svc == null) return;
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormAsientoManual(svc: _svc!, cuentas: _cuentas.where((c) => c.esDetalle).toList()),
    );
    if (creado == true) {
      await _cargarAsientos();
    }
  }

  Widget _tabCuentas() {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: _tipos.map((t) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(t),
                selected: _filtroTipo == t,
                onSelected: (_) => setState(() => _filtroTipo = t),
              ),
            )).toList(),
          ),
        ),
        Expanded(
          child: _filtradas.isEmpty
              ? const Center(child: Text('Sin cuentas.'))
              : ListView.separated(
                  itemCount: _filtradas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = _filtradas[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: c.esDetalle ? Colors.green.shade100 : Colors.grey.shade200,
                        child: Text(c.codigo.length > 4 ? c.codigo.substring(0, 4) : c.codigo,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(c.nombre, style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${c.codigo} · ${c.tipo} · ${c.naturaleza}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: c.esDetalle
                          ? const Icon(Icons.edit_note, size: 18, color: Colors.green)
                          : const Icon(Icons.folder_outlined, size: 18, color: Colors.grey),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _tabBalance() {
    final b = _balance;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.calendar_month, size: 18),
              const SizedBox(width: 8),
              Text('Periodo: $_periodo'),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.edit_calendar, size: 18),
                label: const Text('Cambiar'),
                onPressed: _elegirPeriodo,
              ),
            ],
          ),
        ),
        if (b != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (b.cuadrado ? Colors.green : Colors.red).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(b.cuadrado ? Icons.check_circle : Icons.error,
                    color: b.cuadrado ? Colors.green : Colors.red),
                const SizedBox(width: 10),
                Expanded(child: Text(b.cuadrado
                    ? 'Balance cuadrado: Debe = Haber'
                    : 'DESCUADRE detectado')),
                Text(money(b.totalDeudor), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        Expanded(
          child: (b == null || b.cuentas.isEmpty)
              ? const Center(child: Text('Sin movimientos en el periodo.'))
              : ListView.separated(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: b.cuentas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = b.cuentas[i];
                    return ListTile(
                      dense: true,
                      title: Text('${f.codigo} · ${f.nombre}', style: const TextStyle(fontSize: 12)),
                      subtitle: Text('Debe ${money(f.totalDebito)} · Haber ${money(f.totalCredito)}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (f.saldoDeudor > 0)
                            Text(money(f.saldoDeudor),
                                style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                          if (f.saldoAcreedor > 0)
                            Text(money(f.saldoAcreedor),
                                style: const TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _elegirPeriodo() async {
    final elegido = await _pickPeriodo(context, _periodo);
    if (elegido != null && elegido != _periodo) {
      setState(() => _periodo = elegido);
      await _cargar();
    }
  }
}

/// Selector simple de periodo 'YYYY-MM' vía date picker (se toma año-mes).
Future<String?> pickPeriodoMes(BuildContext context, String actual) => _pickPeriodo(context, actual);

Future<String?> _pickPeriodo(BuildContext context, String actual) async {
  final parts = actual.split('-');
  final inicial = DateTime(int.tryParse(parts[0]) ?? DateTime.now().year,
      int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1, 1);
  final d = await showDatePicker(
    context: context,
    initialDate: inicial,
    firstDate: DateTime(2020, 1, 1),
    lastDate: DateTime(2100, 12, 31),
    helpText: 'Elige cualquier día del mes',
  );
  if (d == null) return null;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

class _LineaAsientoForm {
  String? cuentaId;
  final TextEditingController debito = TextEditingController(text: '0');
  final TextEditingController credito = TextEditingController(text: '0');
  final TextEditingController glosa = TextEditingController();
}

class _FormAsientoManual extends StatefulWidget {
  final FinanzasService svc;
  final List<CuentaContable> cuentas;
  const _FormAsientoManual({required this.svc, required this.cuentas});
  @override
  State<_FormAsientoManual> createState() => _FormAsientoManualState();
}

class _FormAsientoManualState extends State<_FormAsientoManual> {
  final _descripcion = TextEditingController();
  DateTime _fecha = DateTime.now();
  final List<_LineaAsientoForm> _lineas = [_LineaAsientoForm(), _LineaAsientoForm()];
  bool _guardando = false;
  String? _error;

  double _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;
  double get _totalDebito => _lineas.fold(0.0, (s, l) => s + _num(l.debito));
  double get _totalCredito => _lineas.fold(0.0, (s, l) => s + _num(l.credito));
  bool get _cuadrado => _totalDebito > 0 && (_totalDebito - _totalCredito).abs() < 0.005;

  @override
  void dispose() {
    _descripcion.dispose();
    for (final l in _lineas) {
      l.debito.dispose();
      l.credito.dispose();
      l.glosa.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _error = null);
    if (_descripcion.text.trim().isEmpty) {
      setState(() => _error = 'Ingrese una descripción.');
      return;
    }
    if (_lineas.any((l) => l.cuentaId == null)) {
      setState(() => _error = 'Seleccione la cuenta en cada línea.');
      return;
    }
    if (!_cuadrado) {
      setState(() => _error = 'El asiento debe estar cuadrado: total débito = total crédito y mayor a cero.');
      return;
    }
    setState(() => _guardando = true);
    final lineas = _lineas.map((l) => {
          'cuenta_id': l.cuentaId,
          'debito': _num(l.debito),
          'credito': _num(l.credito),
          if (l.glosa.text.trim().isNotEmpty) 'glosa': l.glosa.text.trim(),
        }).toList();
    final r = await widget.svc.crearAsientoManual(
      fecha: '${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}',
      descripcion: _descripcion.text.trim(),
      lineas: lineas,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Asiento registrado');
      Navigator.pop(context, true);
    } else {
      setState(() => _error = r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cuentaItems = widget.cuentas
        .map((c) => DropdownMenuItem(value: c.id, child: Text('${c.codigo} — ${c.nombre}', overflow: TextOverflow.ellipsis)))
        .toList();
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
            Text('Nuevo asiento manual', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context, initialDate: _fecha,
                  firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setState(() => _fecha = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Fecha', border: OutlineInputBorder()),
                child: Text('${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descripcion,
              decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Líneas (débito / crédito)', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _lineas.add(_LineaAsientoForm())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar línea'),
              ),
            ]),
            ..._lineas.asMap().entries.map((e) => _filaLinea(e.key, e.value, cuentaItems)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_cuadrado ? Colors.green : Colors.deepOrange).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(_cuadrado ? Icons.check_circle_outline : Icons.error_outline,
                    color: _cuadrado ? Colors.green : Colors.deepOrange, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Débito ${money(_totalDebito)}   ·   Crédito ${money(_totalCredito)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                )),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Registrar asiento'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaLinea(int indice, _LineaAsientoForm linea, List<DropdownMenuItem<String>> cuentaItems) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: linea.cuentaId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cuenta', border: OutlineInputBorder(), isDense: true),
                  items: cuentaItems,
                  onChanged: (v) => setState(() => linea.cuentaId = v),
                ),
              ),
              if (_lineas.length > 2)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _lineas.removeAt(indice)),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: linea.debito,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Débito', border: OutlineInputBorder(), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: linea.credito,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Crédito', border: OutlineInputBorder(), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: linea.glosa,
              decoration: const InputDecoration(labelText: 'Glosa (opcional)', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
      ),
    );
  }
}

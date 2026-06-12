import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/finanzas_models.dart';
import '../../utils/app_session.dart';
import '../../utils/api_provider.dart';
import '../../utils/ui_insets.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Conciliación bancaria: cuentas de la empresa y, al entrar, el extracto vs.
/// los libros. Cada movimiento del extracto se concilia 1-a-1 contra un asiento
/// existente del libro mayor (no genera asientos nuevos).
class PantallaConciliacionBancaria extends StatefulWidget {
  const PantallaConciliacionBancaria({super.key});
  @override
  State<PantallaConciliacionBancaria> createState() => _State();
}

class _State extends State<PantallaConciliacionBancaria> {
  List<CuentaBancaria> _cuentas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final svc = await getFinanzasService();
    final r = await svc.cuentasBancarias();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) _cuentas = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  void _abrirFormCuenta() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormCuenta(onGuardado: _cargar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGestionar = AppSession.i.canGestionarConciliacionBancaria;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conciliación bancaria'),
        actions: [accionConmutadorFinanzas(context, actual: FinId.conciliacion)],
      ),
      floatingActionButton: canGestionar
          ? FloatingActionButton.extended(
              onPressed: _abrirFormCuenta,
              icon: const Icon(Icons.add),
              label: const Text('Nueva cuenta'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cuentas.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Sin cuentas bancarias. Crea una y vincúlala a su '
                      'cuenta de Bancos del PCGE (familia 104).',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: bottomSafePadding(context, top: 12),
                    itemCount: _cuentas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _tarjetaCuenta(_cuentas[i]),
                  ),
                ),
    );
  }

  Widget _tarjetaCuenta(CuentaBancaria c) {
    final cuadrada = c.cuadrada;
    final colorDif = cuadrada ? Colors.green : Colors.orange.shade800;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorDif.withValues(alpha: 0.15),
          child: Icon(Icons.account_balance_outlined, color: colorDif),
        ),
        title: Text('${c.banco} · ${c.numeroCuenta}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.cuentaContableCodigo != null)
              Text('PCGE ${c.cuentaContableCodigo} · ${c.moneda}',
                  style: const TextStyle(fontSize: 12)),
            Text(
              cuadrada
                  ? 'Cuadrada'
                  : 'Diferencia ${money(c.diferencia)} · ${c.nPendientes} pendiente(s)',
              style: TextStyle(fontSize: 12, color: colorDif, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(c.saldoBanco),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Banco', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => PantallaDetalleConciliacion(cuenta: c)));
          if (mounted) _cargar();
        },
      ),
    );
  }
}

// ── Detalle de una cuenta: extracto vs. libros ────────────────────────────────

class PantallaDetalleConciliacion extends StatefulWidget {
  final CuentaBancaria cuenta;
  const PantallaDetalleConciliacion({super.key, required this.cuenta});
  @override
  State<PantallaDetalleConciliacion> createState() => _DetalleState();
}

class _DetalleState extends State<PantallaDetalleConciliacion> {
  late CuentaBancaria _cuenta;
  List<MovimientoBancario> _movs = [];
  bool _loading = true;
  String _filtro = 'pendiente';   // pendiente | conciliado | todos

  @override
  void initState() {
    super.initState();
    _cuenta = widget.cuenta;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final svc = await getFinanzasService();
    final rc = await svc.obtenerCuentaBancaria(_cuenta.id);
    final rm = await svc.movimientosBancarios(
        _cuenta.id, estado: _filtro == 'todos' ? null : _filtro);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (rc.ok) _cuenta = rc.data!;
      if (rm.ok) _movs = rm.data!;
    });
    if (!rm.ok) mostrarError(context, rm.errorMessage);
  }

  void _abrirFormMovimiento() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormMovimiento(cuentaId: _cuenta.id, onGuardado: _cargar),
    );
  }

  Future<void> _importarCsv() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      if (mounted) mostrarError(context, 'No se pudo leer el archivo');
      return;
    }
    final parsed = _parseCsv(utf8.decode(bytes, allowMalformed: true));
    if (parsed.isEmpty) {
      if (mounted) {
        mostrarError(context,
            'CSV sin filas válidas. Columnas: fecha,descripcion,tipo,monto[,referencia]');
      }
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Importar extracto'),
        content: Text('Se importarán ${parsed.length} movimiento(s) desde el CSV. '
            'Quedarán como pendientes de conciliar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Importar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final svc = await getFinanzasService();
    final r = await svc.importarMovimientosBancarios(_cuenta.id, parsed);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, '${r.data} movimiento(s) importado(s)');
      _cargar();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  /// Parsea un CSV simple (coma o punto y coma). Cabecera opcional con los
  /// nombres de columna; si no la hay, asume el orden fecha,descripcion,tipo,monto,referencia.
  List<Map<String, dynamic>> _parseCsv(String texto) {
    final lineas = const LineSplitter().convert(texto).where((l) => l.trim().isNotEmpty).toList();
    if (lineas.isEmpty) return [];
    final sep = lineas.first.contains(';') && !lineas.first.contains(',') ? ';' : ',';
    var idxFecha = 0, idxDesc = 1, idxTipo = 2, idxMonto = 3, idxRef = 4;
    var inicio = 0;
    final primera = lineas.first.toLowerCase();
    if (primera.contains('fecha') || primera.contains('tipo') || primera.contains('monto')) {
      final cols = lineas.first.split(sep).map((c) => c.trim().toLowerCase()).toList();
      int find(List<String> alts, int def) {
        for (final a in alts) {
          final i = cols.indexWhere((c) => c.contains(a));
          if (i >= 0) return i;
        }
        return def;
      }
      idxFecha = find(['fecha', 'date'], 0);
      idxDesc = find(['descrip', 'concepto', 'detalle', 'glosa'], 1);
      idxTipo = find(['tipo', 'cargo', 'abono'], 2);
      idxMonto = find(['monto', 'importe', 'amount'], 3);
      idxRef = find(['referencia', 'operacion', 'ref'], 4);
      inicio = 1;
    }
    final res = <Map<String, dynamic>>[];
    for (var k = inicio; k < lineas.length; k++) {
      final p = lineas[k].split(sep);
      if (p.length <= idxMonto) continue;
      final fecha = _normFecha(p[idxFecha].trim());
      final monto = double.tryParse(
          p[idxMonto].trim().replaceAll(',', '.').replaceAll(RegExp(r'[^\d.\-]'), ''));
      if (fecha == null || monto == null || monto == 0) continue;
      final tipoRaw = p.length > idxTipo ? p[idxTipo].trim().toLowerCase() : '';
      final tipo = _normTipo(tipoRaw, monto);
      res.add({
        'fecha': fecha,
        'descripcion': p.length > idxDesc ? p[idxDesc].trim() : 'Movimiento',
        'tipo': tipo,
        'monto': monto.abs(),
        if (p.length > idxRef && p[idxRef].trim().isNotEmpty) 'referencia': p[idxRef].trim(),
      });
    }
    return res;
  }

  String? _normFecha(String v) {
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v)) return v.substring(0, 10);
    final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(v);
    if (m != null) {
      final d = m.group(1)!.padLeft(2, '0');
      final mo = m.group(2)!.padLeft(2, '0');
      return '${m.group(3)}-$mo-$d';
    }
    return null;
  }

  String _normTipo(String raw, double monto) {
    if (raw.contains('abono') || raw.contains('credito') || raw.contains('ingreso') ||
        raw.contains('deposito')) {
      return 'abono';
    }
    if (raw.contains('cargo') || raw.contains('debito') || raw.contains('egreso') ||
        raw.contains('retiro') || raw.contains('pago')) {
      return 'cargo';
    }
    // Sin tipo explícito: el signo del monto decide (positivo=abono).
    return monto >= 0 ? 'abono' : 'cargo';
  }

  @override
  Widget build(BuildContext context) {
    final canGestionar = AppSession.i.canGestionarConciliacionBancaria;
    final c = _cuenta;
    final colorDif = c.cuadrada ? Colors.green.shade700 : Colors.orange.shade800;
    return Scaffold(
      appBar: AppBar(
        title: Text('${c.banco} · ${c.numeroCuenta}'),
        actions: [
          if (canGestionar)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Importar extracto (CSV)',
              onPressed: _importarCsv,
            ),
        ],
      ),
      floatingActionButton: canGestionar
          ? FloatingActionButton.extended(
              onPressed: _abrirFormMovimiento,
              icon: const Icon(Icons.add),
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
                    titulo: c.cuadrada ? 'Conciliada (sin diferencia)' : 'Diferencia banco − libros',
                    valor: money(c.diferencia),
                    color: colorDif,
                    icono: c.cuadrada ? Icons.check_circle_outline : Icons.report_problem_outlined,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        Expanded(child: _miniStat('Saldo banco', c.saldoBanco, Colors.blue)),
                        const SizedBox(width: 8),
                        Expanded(child: _miniStat('Saldo libros', c.saldoLibros, Colors.indigo)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'pendiente', label: Text('Pendientes')),
                        ButtonSegment(value: 'conciliado', label: Text('Conciliados')),
                        ButtonSegment(value: 'todos', label: Text('Todos')),
                      ],
                      selected: {_filtro},
                      onSelectionChanged: (s) {
                        setState(() => _filtro = s.first);
                        _cargar();
                      },
                    ),
                  ),
                  if (_movs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Sin movimientos en este filtro.',
                          style: TextStyle(color: Colors.grey))),
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

  Widget _tarjetaMov(MovimientoBancario m) {
    final esAbono = m.esAbono;
    final color = esAbono ? Colors.green : Colors.red;
    final conciliado = m.conciliado;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(esAbono ? Icons.arrow_downward : Icons.arrow_upward, color: color),
        ),
        title: Text(m.descripcion, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${m.fecha.length >= 10 ? m.fecha.substring(0, 10) : m.fecha}'
          '${m.referencia != null && m.referencia!.isNotEmpty ? ' · ${m.referencia}' : ''}'
          '${conciliado && m.asientoNumero != null ? ' · Asiento ${m.asientoNumero}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${esAbono ? '+' : '−'} ${money(m.monto)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            chipEstado(m.estado),
          ],
        ),
        onTap: () => _accionMov(m),
      ),
    );
  }

  Future<void> _accionMov(MovimientoBancario m) async {
    if (!AppSession.i.canConciliar) return;
    if (m.conciliado) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Desconciliar'),
          content: Text('¿Liberar este movimiento del asiento ${m.asientoNumero ?? ''}? '
              'Volverá a quedar pendiente.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Desconciliar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final svc = await getFinanzasService();
      final r = await svc.desconciliarMovimiento(m.id);
      if (!mounted) return;
      if (r.ok) {
        mostrarOk(context, 'Movimiento liberado');
        _cargar();
      } else {
        mostrarError(context, r.errorMessage);
      }
      return;
    }
    // Pendiente → abrir sugerencias para conciliar.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SheetSugerencias(movimiento: m, onConciliado: _cargar),
    );
  }
}

// ── Hoja de sugerencias de asiento ────────────────────────────────────────────

class _SheetSugerencias extends StatefulWidget {
  final MovimientoBancario movimiento;
  final VoidCallback onConciliado;
  const _SheetSugerencias({required this.movimiento, required this.onConciliado});
  @override
  State<_SheetSugerencias> createState() => _SheetSugerenciasState();
}

class _SheetSugerenciasState extends State<_SheetSugerencias> {
  List<SugerenciaAsiento> _sug = [];
  bool _loading = true;
  bool _conciliando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final svc = await getFinanzasService();
    final r = await svc.sugerenciasConciliacion(widget.movimiento.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) _sug = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _conciliar(SugerenciaAsiento s) async {
    setState(() => _conciliando = true);
    final svc = await getFinanzasService();
    final r = await svc.conciliarMovimiento(widget.movimiento.id, s.asientoId);
    if (!mounted) return;
    setState(() => _conciliando = false);
    if (r.ok) {
      mostrarOk(context, 'Movimiento conciliado con asiento ${s.numero}');
      Navigator.pop(context);
      widget.onConciliado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.movimiento;
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Conciliar movimiento', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('${m.descripcion} · ${m.esAbono ? '+' : '−'} ${money(m.monto)}',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_sug.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No hay asientos candidatos con el mismo importe en la cuenta de bancos '
                '(±30 días). Registra primero el asiento del cobro/pago en el libro mayor.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _sug.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _tarjetaSug(_sug[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tarjetaSug(SugerenciaAsiento s) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.indigo.withValues(alpha: 0.12),
        child: Text(s.numero.length > 4 ? s.numero.substring(s.numero.length - 4) : s.numero,
            style: const TextStyle(fontSize: 11, color: Colors.indigo)),
      ),
      title: Text(s.descripcion, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${s.fecha.length >= 10 ? s.fecha.substring(0, 10) : s.fecha}'
          ' · ${s.origen} · ${s.diasDiferencia} día(s) de desfase'),
      trailing: _conciliando
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : FilledButton(
              onPressed: () => _conciliar(s),
              child: const Text('Vincular'),
            ),
    );
  }
}

// ── Formulario nueva cuenta bancaria ──────────────────────────────────────────

class _FormCuenta extends StatefulWidget {
  final VoidCallback onGuardado;
  const _FormCuenta({required this.onGuardado});
  @override
  State<_FormCuenta> createState() => _FormCuentaState();
}

class _FormCuentaState extends State<_FormCuenta> {
  final _form = GlobalKey<FormState>();
  final _bancoCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  String _moneda = 'PEN';
  List<CuentaContable> _cuentas = [];
  String? _cuentaId;
  bool _cargandoCuentas = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarCuentas();
  }

  Future<void> _cargarCuentas() async {
    final svc = await getFinanzasService();
    final r = await svc.planCuentas(nivel: 'detalle');
    if (!mounted) return;
    setState(() {
      _cargandoCuentas = false;
      if (r.ok) {
        // Prioriza las cuentas de disponible (familia 10: caja y bancos).
        final all = r.data!;
        final bancos = all.where((c) => c.codigo.startsWith('10')).toList();
        _cuentas = bancos.isNotEmpty ? bancos : all;
      }
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  @override
  void dispose() {
    _bancoCtrl.dispose();
    _numeroCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (_cuentaId == null) {
      mostrarError(context, 'Elige la cuenta contable (PCGE) que representa el banco');
      return;
    }
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final r = await svc.crearCuentaBancaria(
      banco: _bancoCtrl.text.trim(),
      numeroCuenta: _numeroCtrl.text.trim(),
      cuentaContableId: _cuentaId!,
      moneda: _moneda,
      alias: _aliasCtrl.text.trim().isEmpty ? null : _aliasCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Cuenta bancaria creada');
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
              Text('Nueva cuenta bancaria', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bancoCtrl,
                decoration: const InputDecoration(labelText: 'Banco', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numeroCtrl,
                decoration: const InputDecoration(
                    labelText: 'Número de cuenta', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _moneda,
                decoration: const InputDecoration(labelText: 'Moneda', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'PEN', child: Text('Soles (PEN)')),
                  DropdownMenuItem(value: 'USD', child: Text('Dólares (USD)')),
                ],
                onChanged: (v) => setState(() => _moneda = v ?? 'PEN'),
              ),
              const SizedBox(height: 12),
              if (_cargandoCuentas)
                const Padding(padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator())
              else
                DropdownButtonFormField<String>(
                  initialValue: _cuentaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Cuenta de Bancos (PCGE)', border: OutlineInputBorder()),
                  items: _cuentas
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.codigo} · ${c.nombre}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _cuentaId = v),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _aliasCtrl,
                decoration: const InputDecoration(
                    labelText: 'Alias (opcional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              const Text(
                'El saldo según libros se toma de los asientos de esa cuenta del PCGE. '
                'La conciliación cuadra ese saldo contra el extracto del banco.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Crear cuenta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Formulario movimiento manual ──────────────────────────────────────────────

class _FormMovimiento extends StatefulWidget {
  final String cuentaId;
  final VoidCallback onGuardado;
  const _FormMovimiento({required this.cuentaId, required this.onGuardado});
  @override
  State<_FormMovimiento> createState() => _FormMovimientoState();
}

class _FormMovimientoState extends State<_FormMovimiento> {
  final _form = GlobalKey<FormState>();
  String _tipo = 'abono';
  final _montoCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _descCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  String get _fechaIso =>
      '${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}';

  Future<void> _pickFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _fecha = d);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final r = await svc.registrarMovimientoBancario(
      cuentaId: widget.cuentaId,
      fecha: _fechaIso,
      descripcion: _descCtrl.text.trim(),
      tipo: _tipo,
      monto: double.tryParse(_montoCtrl.text.trim()) ?? 0,
      referencia: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
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
    final esAbono = _tipo == 'abono';
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
              Text('Movimiento del extracto', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'abono', label: Text('Abono (entró)'), icon: Icon(Icons.arrow_downward)),
                  ButtonSegment(value: 'cargo', label: Text('Cargo (salió)'), icon: Icon(Icons.arrow_upward)),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() => _tipo = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto S/', border: OutlineInputBorder()),
                validator: (v) {
                  final d = double.tryParse(v ?? '');
                  if (d == null || d <= 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _refCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nº operación / referencia (opcional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickFecha,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text('Fecha: $_fechaIso'),
              ),
              const SizedBox(height: 8),
              Text(
                esAbono
                    ? 'Abono: entró dinero. Se conciliará con un asiento que DEBITA la cuenta de bancos.'
                    : 'Cargo: salió dinero. Se conciliará con un asiento que ACREDITA la cuenta de bancos.',
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

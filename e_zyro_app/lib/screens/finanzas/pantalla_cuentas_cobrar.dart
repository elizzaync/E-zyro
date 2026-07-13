import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/finanzas_models.dart';
import '../../utils/app_session.dart';
import '../../utils/api_provider.dart';
import '../../theme/ez_theme.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

// ── CPE (facturación electrónica) — helpers de UI ────────────────────────────
Color colorCpe(String estado) => switch (estado) {
      'aceptado' => Colors.green,
      'pendiente_sunat' => Colors.orange,
      'error' => Colors.red,
      _ => Colors.blueGrey, // no_soportado u otros
    };

/// Hoja con el estado SUNAT del comprobante: PDF oficial y reintento si falló.
Future<void> mostrarDetalleCpe(BuildContext context, Factura f,
    {Future<void> Function()? onReintentar}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.receipt_long_outlined,
                  color: colorCpe(f.cpeEstado ?? ''), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('SUNAT — ${f.numeroDocumento}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              chipEstado(f.cpeEstado ?? '—', context.ez),
            ]),
            const SizedBox(height: 10),
            if ((f.cpeMensaje ?? '').isNotEmpty)
              Text(f.cpeMensaje!,
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
            const SizedBox(height: 14),
            if ((f.cpePdfUrl ?? '').isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44)),
                onPressed: () => launchUrl(Uri.parse(f.cpePdfUrl!),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Ver PDF oficial'),
              ),
            if (f.cpeEstado == 'error' && onReintentar != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await onReintentar();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar emisión a SUNAT'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class PantallaCuentasCobrar extends StatefulWidget {
  const PantallaCuentasCobrar({super.key});
  @override
  State<PantallaCuentasCobrar> createState() => _State();
}

class _State extends State<PantallaCuentasCobrar>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Tab 0 — Comprobantes
  List<Factura> _comprobantes = [];
  bool _loadingComp = true;

  // Tab 1 — Saldos
  List<SaldoTercero> _saldos = [];
  bool _loadingSaldos = true;

  // Tab 2 — Cobros
  List<CobroCliente> _cobros = [];
  bool _loadingCobros = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _cargarTodo();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    _cargarComprobantes();
    _cargarSaldos();
    _cargarCobros();
  }

  Future<void> _cargarComprobantes() async {
    setState(() => _loadingComp = true);
    final svc = await getFinanzasService();
    final r = await svc.facturasCliente();
    if (!mounted) return;
    setState(() {
      _loadingComp = false;
      if (r.ok) _comprobantes = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarSaldos() async {
    setState(() => _loadingSaldos = true);
    final svc = await getFinanzasService();
    final r = await svc.saldosCliente();
    if (!mounted) return;
    setState(() {
      _loadingSaldos = false;
      if (r.ok) _saldos = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarCobros() async {
    setState(() => _loadingCobros = true);
    final svc = await getFinanzasService();
    final r = await svc.listarCobros();
    if (!mounted) return;
    setState(() {
      _loadingCobros = false;
      if (r.ok) _cobros = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _reintentarCpe(Factura f) async {
    final svc = await getFinanzasService();
    final r = await svc.reintentarCpe(f.id);
    if (!mounted) return;
    if (r.ok) {
      final estado = r.data?.cpeEstado ?? '';
      if (estado == 'aceptado' || estado == 'pendiente_sunat') {
        mostrarOk(context, 'Comprobante enviado a SUNAT ($estado)');
      } else {
        mostrarError(context, r.data?.cpeMensaje ?? 'La emisión volvió a fallar');
      }
      _cargarComprobantes();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _anular(Factura f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anular comprobante'),
        content: Text(
            '¿Anular ${f.numeroDocumento}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final svc = await getFinanzasService();
    final r = await svc.anularComprobante(f.id);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Comprobante anulado');
      _cargarComprobantes();
      _cargarSaldos();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  void _abrirFormComprobante() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormComprobante(
        // Comprobantes con saldo, para que una nota de crédito elija a cuál rebaja.
        comprobantesAbiertos: _comprobantes
            .where((f) =>
                (f.estado == 'pendiente' || f.estado == 'cobrada_parcial') &&
                f.tipoDocumento != 'nota_credito' &&
                f.saldoPendiente > 0)
            .toList(),
        onGuardado: () {
          _cargarComprobantes();
          _cargarSaldos();
        },
      ),
    );
  }

  Future<void> _abrirFacturarServicio() async {
    final svc = await getFinanzasService();
    final r = await svc.serviciosFacturables();
    if (!mounted) return;
    if (!r.ok) {
      mostrarError(context, r.errorMessage);
      return;
    }
    final servicios = r.data!;
    if (servicios.isEmpty) {
      mostrarError(
          context, 'No hay servicios completados pendientes de facturar');
      return;
    }
    final elegido = await showModalBottomSheet<ServicioFacturable>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SelectorServicio(servicios: servicios),
    );
    if (elegido == null || !mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormFacturarServicio(
        servicio: elegido,
        onGuardado: () {
          _cargarComprobantes();
          _cargarSaldos();
        },
      ),
    );
  }

  void _abrirFormCobro() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormCobro(
        // El backend marca 'cobrada_parcial' (no 'parcial'): sin este valor los
        // comprobantes con cobro parcial desaparecían y no se podía saldar el resto.
        comprobantesPendientes: _comprobantes
            .where((f) =>
                f.estado == 'pendiente' || f.estado == 'cobrada_parcial')
            .toList(),
        onGuardado: () {
          _cargarComprobantes();
          _cargarSaldos();
          _cargarCobros();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEmitir = AppSession.i.canEmitirComprobante;
    final canCobrar = AppSession.i.canRegistrarCobro;
    final canAnular = AppSession.i.isAdmin;

    FloatingActionButton? fab;
    if (_tabs.index == 0 && canEmitir) {
      fab = FloatingActionButton.extended(
        onPressed: _abrirFormComprobante,
        icon: const Icon(Icons.add),
        label: const Text('Emitir comprobante'),
      );
    } else if (_tabs.index == 2 && canCobrar) {
      fab = FloatingActionButton.extended(
        onPressed: _abrirFormCobro,
        icon: const Icon(Icons.attach_money),
        label: const Text('Registrar cobro'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas por Cobrar'),
        actions: [
          if (_tabs.index == 0 && canEmitir)
            IconButton(
              icon: const Icon(Icons.receipt_long),
              tooltip: 'Facturar servicio',
              onPressed: _abrirFacturarServicio,
            ),
          accionConmutadorFinanzas(context, actual: FinId.cxc),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Comprobantes'),
            Tab(text: 'Saldos'),
            Tab(text: 'Cobros'),
          ],
        ),
      ),
      floatingActionButton: fab,
      body: TabBarView(
        controller: _tabs,
        children: [
          _TabComprobantes(
            comprobantes: _comprobantes,
            loading: _loadingComp,
            canAnular: canAnular,
            onAnular: _anular,
            onRefresh: _cargarComprobantes,
            onReintentarCpe: _reintentarCpe,
          ),
          _TabSaldos(
            saldos: _saldos,
            loading: _loadingSaldos,
            onRefresh: _cargarSaldos,
          ),
          _TabCobros(
            cobros: _cobros,
            loading: _loadingCobros,
            onRefresh: _cargarCobros,
          ),
        ],
      ),
    );
  }
}

// ── Tab Comprobantes ─────────────────────────────────────────────────────────

class _TabComprobantes extends StatelessWidget {
  final List<Factura> comprobantes;
  final bool loading;
  final bool canAnular;
  final void Function(Factura) onAnular;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Factura)? onReintentarCpe;

  const _TabComprobantes({
    required this.comprobantes,
    required this.loading,
    required this.canAnular,
    required this.onAnular,
    required this.onRefresh,
    this.onReintentarCpe,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (comprobantes.isEmpty) {
      return const EstadoVacio(
        icono: Icons.receipt_long,
        titulo: 'Sin comprobantes emitidos',
        subtitulo: 'Emite tu primer comprobante para llevar el control de cuentas por cobrar.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: comprobantes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final f = comprobantes[i];
          return Card(
            child: ListTile(
              // Ícono SUNAT solo cuando la feature CPE está activa (cpe_estado
              // llega null con la feature apagada: la tarjeta no cambia).
              leading: f.cpeEstado == null
                  ? null
                  : Icon(Icons.cloud_done_outlined,
                      color: colorCpe(f.cpeEstado!), size: 22),
              title: Text(f.numeroDocumento +
                  (f.moneda != 'PEN' ? ' · ${f.moneda}' : '')),
              subtitle: Text(
                '${f.tipoDocumento} · Vence ${f.fechaVencimiento}'
                '${f.cpeEstado != null ? ' · SUNAT: ${f.cpeEstado}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: f.cpeEstado == null
                  ? null
                  : () => mostrarDetalleCpe(context, f,
                      onReintentar: onReintentarCpe == null
                          ? null
                          : () => onReintentarCpe!(f)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(money(f.total, f.moneda),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      chipEstado(f.estado, context.ez),
                    ],
                  ),
                  if (canAnular && f.estado == 'pendiente')
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                      tooltip: 'Anular',
                      onPressed: () => onAnular(f),
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

// ── Tab Saldos ───────────────────────────────────────────────────────────────

class _TabSaldos extends StatelessWidget {
  final List<SaldoTercero> saldos;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _TabSaldos({
    required this.saldos,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (saldos.isEmpty) {
      return const EstadoVacio(
        icono: Icons.account_balance_wallet_outlined,
        titulo: 'Sin saldos pendientes',
        subtitulo: 'Aún no hay saldos pendientes de clientes.',
      );
    }
    final total = saldos.fold(0.0, (s, e) => s + e.saldoTotal);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Column(
        children: [
          TarjetaResumen(
            titulo: 'Total por cobrar',
            valor: money(total),
            color: Colors.green.shade700,
            icono: Icons.account_balance_wallet,
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: saldos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = saldos[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(s.nombre),
                    subtitle:
                        Text('${s.facturasAbiertas} comprobante(s) pendiente(s)'),
                    trailing: Text(
                      money(s.saldoTotal),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab Cobros ───────────────────────────────────────────────────────────────

class _TabCobros extends StatelessWidget {
  final List<CobroCliente> cobros;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _TabCobros({
    required this.cobros,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (cobros.isEmpty) {
      return const EstadoVacio(
        icono: Icons.payments_outlined,
        titulo: 'Sin cobros registrados',
        subtitulo: 'Aún no se han registrado cobros de clientes.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: cobros.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c = cobros[i];
          return Card(
            child: ExpansionTile(
              leading: const CircleAvatar(child: Icon(Icons.attach_money)),
              title: Text(money(c.monto, c.moneda),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${c.fechaCobro} · ${c.medioPago}'
                '${c.referencia != null ? ' · ${c.referencia}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              children: c.aplicaciones
                  .map((a) => ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.receipt_outlined, size: 16),
                        title: Text('Comprobante ${a.facturaId}'),
                        trailing: Text(money(a.montoAplicado, c.moneda)),
                      ))
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}

// ── Formulario emitir comprobante ─────────────────────────────────────────────

class _FormComprobante extends StatefulWidget {
  final List<Factura> comprobantesAbiertos;
  final VoidCallback onGuardado;
  const _FormComprobante(
      {required this.comprobantesAbiertos, required this.onGuardado});

  @override
  State<_FormComprobante> createState() => _FormComprobanteState();
}

class _FormComprobanteState extends State<_FormComprobante> {
  final _form = GlobalKey<FormState>();
  List<Tercero> _clientes = [];
  String? _clienteId;
  final _numCtrl = TextEditingController();
  String _tipo = 'factura';
  // Nota de crédito: comprobante del cliente cuyo saldo rebaja.
  String? _documentoAfectadoId;
  DateTime _emision = DateTime.now();
  // Al crédito el vencimiento SIEMPRE viaja: sin default, si el usuario no
  // tocaba el campo se enviaba null y el comprobante quedaba sin vencimiento
  // (invisible para alertas y antigüedad de saldos).
  DateTime? _vencimiento = DateTime.now().add(const Duration(days: 30));
  final _subtotalCtrl = TextEditingController();
  final _igvCtrl = TextEditingController(text: '18');
  bool _alContado = false;
  bool _guardando = false;
  // Multimoneda: el selector USD solo aparece si la empresa la tiene activa.
  bool _multimoneda = false;
  String _moneda = 'PEN';

  static const _tipos = ['factura', 'boleta', 'nota_credito'];

  @override
  void initState() {
    super.initState();
    _cargarClientes();
    _cargarTasaIgv();
    _cargarMultimoneda();
  }

  Future<void> _cargarMultimoneda() async {
    final svc = await getFinanzasService();
    final r = await svc.configContable();
    if (mounted && r.ok) {
      setState(() => _multimoneda = r.data?.multimoneda ?? false);
    }
  }

  /// Tasa de IGV inicial desde la configuración tributaria de la empresa.
  Future<void> _cargarTasaIgv() async {
    final svc = await getFinanzasService();
    final pct = await svc.getTasaIgv(); // porcentaje (18.0)
    if (!mounted) return;
    setState(() =>
        _igvCtrl.text = pct.toStringAsFixed(pct % 1 == 0 ? 0 : 2));
  }

  Future<void> _cargarClientes() async {
    final svc = await getFinanzasService();
    final r = await svc.clientes();
    if (mounted && r.ok) setState(() => _clientes = r.data!);
  }

  bool get _esNotaCredito => _tipo == 'nota_credito';

  List<Factura> get _afectablesDelCliente => widget.comprobantesAbiertos
      .where((f) => f.terceroId == _clienteId)
      .toList();

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (_clienteId == null) {
      mostrarError(context, 'Selecciona un cliente');
      return;
    }
    if (_esNotaCredito && _documentoAfectadoId == null) {
      mostrarError(
          context, 'Selecciona el comprobante que afecta la nota de crédito');
      return;
    }
    setState(() => _guardando = true);
    final subtotal = double.tryParse(_subtotalCtrl.text) ?? 0;
    final igvPct = double.tryParse(_igvCtrl.text) ?? 18;
    final igv = subtotal * igvPct / 100;
    final fmt = DateFormat('yyyy-MM-dd');
    final svc = await getFinanzasService();
    final r = await svc.emitirComprobante(
      clienteId: _clienteId!,
      numeroDocumento: _numCtrl.text.trim(),
      tipoDocumento: _tipo,
      fechaEmision: fmt.format(_emision),
      fechaVencimiento: _esNotaCredito || _vencimiento == null
          ? null
          : fmt.format(_vencimiento!),
      subtotal: subtotal,
      igv: igv,
      alContado: _esNotaCredito ? false : _alContado,
      documentoAfectadoId: _esNotaCredito ? _documentoAfectadoId : null,
      moneda: _moneda == 'PEN' ? null : _moneda,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context,
          _esNotaCredito ? 'Nota de crédito aplicada' : 'Comprobante emitido');
      Navigator.pop(context);
      widget.onGuardado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinFormSheet(
      titulo: 'Emitir comprobante',
      subtitulo: 'Crea la cuenta por cobrar y su asiento contable automáticamente',
      icono: Icons.request_quote_outlined,
      textoBoton: 'Emitir comprobante',
      guardando: _guardando,
      onGuardar: _guardar,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _clienteId,
              decoration: const InputDecoration(labelText: 'Cliente'),
              items: _clientes
                  .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.razonSocial),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _clienteId = v;
                _documentoAfectadoId = null;
              }),
              validator: (v) => v == null ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _numCtrl,
                  decoration:
                      const InputDecoration(labelText: 'N° documento'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: _tipos
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(etiquetaLegible(t))))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _tipo = v!;
                    if (!_esNotaCredito) _documentoAfectadoId = null;
                  }),
                ),
              ),
            ]),
            if (_esNotaCredito) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _documentoAfectadoId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Comprobante que afecta',
                  helperText:
                      'La nota de crédito REBAJA el saldo por cobrar de este comprobante',
                ),
                items: _afectablesDelCliente
                    .map((f) => DropdownMenuItem(
                          value: f.id,
                          child: Text(
                              '${f.numeroDocumento} · saldo ${money(f.saldoPendiente, f.moneda)}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _documentoAfectadoId = v),
                validator: (v) =>
                    _esNotaCredito && v == null ? 'Requerido' : null,
              ),
            ],
            const SizedBox(height: 12),
            _DateField(
              label: 'Fecha emisión',
              value: _emision,
              onChanged: (d) => setState(() => _emision = d),
            ),
            if (_multimoneda && !_esNotaCredito) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _moneda,
                decoration: const InputDecoration(
                  labelText: 'Moneda',
                  helperText:
                      'En USD el asiento se convierte al TC SUNAT del día',
                ),
                items: const [
                  DropdownMenuItem(value: 'PEN', child: Text('S/ Soles')),
                  DropdownMenuItem(value: 'USD', child: Text('US\$ Dólares')),
                ],
                onChanged: (v) => setState(() => _moneda = v ?? 'PEN'),
              ),
            ],
            if (!_esNotaCredito) ...[
              const SizedBox(height: 6),
              SwitchListTile(
                title: const Text('Al contado'),
                subtitle: const Text('El cobro ingresa a caja en el momento',
                    style: TextStyle(fontSize: 11.5)),
                value: _alContado,
                onChanged: (v) => setState(() {
                  _alContado = v;
                  _vencimiento = v
                      ? null
                      : DateTime.now().add(const Duration(days: 30));
                }),
                contentPadding: EdgeInsets.zero,
              ),
              if (!_alContado) ...[
                const SizedBox(height: 6),
                _DateField(
                  label: 'Fecha vencimiento',
                  value: _vencimiento ??
                      DateTime.now().add(const Duration(days: 30)),
                  onChanged: (d) => setState(() => _vencimiento = d),
                ),
              ],
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _subtotalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                        labelText: 'Subtotal (${simboloMoneda(_moneda)})'),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final d = double.tryParse(v ?? '');
                      if (d == null || d <= 0) return 'Monto inválido';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _igvCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(labelText: 'IGV %'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FinTotalesCard(
              subtotal: double.tryParse(_subtotalCtrl.text) ?? 0,
              igvPct: double.tryParse(_igvCtrl.text) ?? 18,
              moneda: _moneda,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Formulario registrar cobro ─────────────────────────────────────────────────

class _FormCobro extends StatefulWidget {
  final List<Factura> comprobantesPendientes;
  final VoidCallback onGuardado;

  const _FormCobro({
    required this.comprobantesPendientes,
    required this.onGuardado,
  });

  @override
  State<_FormCobro> createState() => _FormCobroState();
}

class _FormCobroState extends State<_FormCobro> {
  List<Tercero> _clientes = [];
  String? _clienteId;
  List<Factura> _comprobantesCliente = [];

  final Map<String, TextEditingController> _montos = {};
  final Set<String> _seleccionados = {};

  String _medioPago = 'efectivo';
  final _refCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  static const _medios = ['efectivo', 'transferencia', 'cheque'];

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  @override
  void dispose() {
    for (final c in _montos.values) {
      c.dispose();
    }
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    final svc = await getFinanzasService();
    final r = await svc.clientes();
    if (mounted && r.ok) setState(() => _clientes = r.data!);
  }

  void _seleccionarCliente(String? id) {
    setState(() {
      _clienteId = id;
      _seleccionados.clear();
      for (final c in _montos.values) {
        c.dispose();
      }
      _montos.clear();
      _comprobantesCliente = id == null
          ? []
          : widget.comprobantesPendientes
              .where((f) => f.terceroId == id)
              .toList();
    });
  }

  double get _totalAplicado {
    double t = 0;
    for (final id in _seleccionados) {
      t += double.tryParse(_montos[id]?.text ?? '') ?? 0;
    }
    return t;
  }

  // El backend exige que un cobro aplique a comprobantes de UNA sola moneda;
  // el total se muestra en la moneda del primer seleccionado.
  String get _monedaSeleccion {
    for (final f in _comprobantesCliente) {
      if (_seleccionados.contains(f.id)) return f.moneda;
    }
    return 'PEN';
  }

  Future<void> _guardar() async {
    if (_clienteId == null) {
      mostrarError(context, 'Selecciona un cliente');
      return;
    }
    if (_seleccionados.isEmpty) {
      mostrarError(context, 'Selecciona al menos un comprobante');
      return;
    }
    final aplicaciones = <Map<String, dynamic>>[];
    for (final id in _seleccionados) {
      final m = double.tryParse(_montos[id]?.text ?? '') ?? 0;
      if (m <= 0) {
        mostrarError(
            context, 'Ingresa el monto para cada comprobante seleccionado');
        return;
      }
      aplicaciones.add({'factura_id': id, 'monto_aplicado': m});
    }
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final r = await svc.registrarCobro(
      clienteId: _clienteId!,
      fechaCobro: DateFormat('yyyy-MM-dd').format(_fecha),
      medioPago: _medioPago,
      aplicaciones: aplicaciones,
      referencia:
          _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Cobro registrado');
      Navigator.pop(context);
      widget.onGuardado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinFormSheet(
      titulo: 'Registrar cobro de cliente',
      subtitulo: 'Aplica el cobro a los comprobantes y mueve caja/bancos automáticamente',
      icono: Icons.attach_money_rounded,
      textoBoton: 'Registrar cobro',
      guardando: _guardando,
      onGuardar: _guardar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _clienteId,
            decoration: const InputDecoration(labelText: 'Cliente'),
            items: _clientes
                .map((c) =>
                    DropdownMenuItem(value: c.id, child: Text(c.razonSocial)))
                .toList(),
            onChanged: _seleccionarCliente,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _DateField(
                label: 'Fecha de cobro',
                value: _fecha,
                onChanged: (d) => setState(() => _fecha = d),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _medioPago,
                decoration: const InputDecoration(labelText: 'Medio'),
                items: _medios
                    .map((m) => DropdownMenuItem(
                        value: m, child: Text(etiquetaLegible(m))))
                    .toList(),
                onChanged: (v) => setState(() => _medioPago = v!),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _refCtrl,
            decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
                helperText: 'N° de operación, depósito, etc.'),
          ),
          if (_comprobantesCliente.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Comprobantes pendientes',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ..._comprobantesCliente.map((f) {
              final sel = _seleccionados.contains(f.id);
              _montos.putIfAbsent(
                f.id,
                () => TextEditingController(
                    text: f.saldoPendiente.toStringAsFixed(2)),
              );
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                  side: BorderSide(
                      color: sel
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withValues(alpha: 0.25)),
                ),
                child: CheckboxListTile(
                  value: sel,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _seleccionados.add(f.id);
                    } else {
                      _seleccionados.remove(f.id);
                    }
                  }),
                  title: Text(f.numeroDocumento),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saldo: ${money(f.saldoPendiente, f.moneda)}',
                          style: const TextStyle(fontSize: 12)),
                      if (sel)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextField(
                            controller: _montos[f.id],
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: InputDecoration(
                              labelText:
                                  'Monto a cobrar (${simboloMoneda(f.moneda)})',
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ] else if (_clienteId != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Este cliente no tiene comprobantes pendientes',
              style: TextStyle(color: Colors.grey),
            ),
          ],
          if (_seleccionados.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      '${_seleccionados.length} comprobante${_seleccionados.length == 1 ? '' : 's'} · Total a cobrar',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(money(_totalAplicado, _monedaSeleccion),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Selector de servicio facturable ───────────────────────────────────────────

class _SelectorServicio extends StatelessWidget {
  final List<ServicioFacturable> servicios;
  const _SelectorServicio({required this.servicios});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Elegir servicio a facturar',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: servicios.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = servicios[i];
                final detalle = [
                  if (s.proyectoNombre != null && s.proyectoNombre!.isNotEmpty)
                    s.proyectoNombre,
                  if (s.clienteNombre != null && s.clienteNombre!.isNotEmpty)
                    s.clienteNombre,
                  if (s.nroDocumentoCliente != null &&
                      s.nroDocumentoCliente!.isNotEmpty)
                    'OC ${s.nroDocumentoCliente}',
                ].whereType<String>().join(' · ');
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.build)),
                    title: Text(s.servicioNombre),
                    subtitle: detalle.isEmpty
                        ? null
                        : Text(detalle, style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, s),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Formulario facturar servicio ───────────────────────────────────────────────

class _FormFacturarServicio extends StatefulWidget {
  final ServicioFacturable servicio;
  final VoidCallback onGuardado;
  const _FormFacturarServicio({required this.servicio, required this.onGuardado});

  @override
  State<_FormFacturarServicio> createState() => _FormFacturarServicioState();
}

class _FormFacturarServicioState extends State<_FormFacturarServicio> {
  final _form = GlobalKey<FormState>();
  final _numCtrl = TextEditingController();
  String _tipo = 'factura';
  DateTime _emision = DateTime.now();
  DateTime? _vencimiento;
  final _subtotalCtrl = TextEditingController();
  final _igvCtrl = TextEditingController();
  bool _alContado = false;
  bool _guardando = false;
  bool _igvEditadoManual = false;
  double _tasaIgv = 18.0;
  // Multimoneda: el selector USD solo aparece si la empresa la tiene activa.
  bool _multimoneda = false;
  String _moneda = 'PEN';

  static const _tipos = ['factura', 'boleta', 'nota_credito', 'nota_debito'];

  @override
  void initState() {
    super.initState();
    _cargarTasaIgv();
    _cargarMultimoneda();
  }

  Future<void> _cargarMultimoneda() async {
    final svc = await getFinanzasService();
    final r = await svc.configContable();
    if (mounted && r.ok) {
      setState(() => _multimoneda = r.data?.multimoneda ?? false);
    }
  }

  @override
  void dispose() {
    _numCtrl.dispose();
    _subtotalCtrl.dispose();
    _igvCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarTasaIgv() async {
    final svc = await getFinanzasService();
    final tasa = await svc.getTasaIgv();
    if (!mounted) return;
    setState(() => _tasaIgv = tasa);
    _recalcularIgv();
  }

  /// Pre-llena el IGV = subtotal × tasa/100 salvo que el usuario lo haya editado.
  void _recalcularIgv() {
    if (_igvEditadoManual) return;
    final subtotal = double.tryParse(_subtotalCtrl.text) ?? 0;
    final igv = subtotal * _tasaIgv / 100;
    _igvCtrl.text = igv == 0 ? '' : igv.toStringAsFixed(2);
  }

  double get _subtotal => double.tryParse(_subtotalCtrl.text) ?? 0;
  double get _igv => double.tryParse(_igvCtrl.text) ?? 0;
  double get _total => _subtotal + _igv;

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (!_alContado && _vencimiento == null) {
      mostrarError(context, 'Indica la fecha de vencimiento');
      return;
    }
    if (!_alContado && _vencimiento!.isBefore(DateTime(
        _emision.year, _emision.month, _emision.day))) {
      mostrarError(
          context, 'El vencimiento no puede ser anterior a la emisión');
      return;
    }
    setState(() => _guardando = true);
    final fmt = DateFormat('yyyy-MM-dd');
    final svc = await getFinanzasService();
    final r = await svc.facturarServicio(
      servicioId: widget.servicio.servicioId,
      numeroDocumento: _numCtrl.text.trim(),
      tipoDocumento: _tipo,
      fechaEmision: fmt.format(_emision),
      fechaVencimiento:
          _alContado || _vencimiento == null ? null : fmt.format(_vencimiento!),
      subtotal: _subtotal,
      igv: _igv,
      moneda: _moneda == 'PEN' ? null : _moneda,
      alContado: _alContado,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Servicio facturado');
      Navigator.pop(context);
      widget.onGuardado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.servicio.clienteNombre;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Facturar servicio',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(widget.servicio.servicioNombre,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              TextFormField(
                initialValue:
                    (cliente == null || cliente.isEmpty) ? '—' : cliente,
                readOnly: true,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Cliente',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(
                  labelText: 'Tipo documento',
                  border: OutlineInputBorder(),
                ),
                items: _tipos
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _tipo = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numCtrl,
                decoration: const InputDecoration(
                  labelText: 'N° documento',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              _DateField(
                label: 'Fecha emisión',
                value: _emision,
                onChanged: (d) => setState(() => _emision = d),
              ),
              if (_multimoneda && _tipo != 'nota_credito') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _moneda,
                  decoration: const InputDecoration(
                    labelText: 'Moneda',
                    helperText:
                        'En USD el asiento se convierte al TC SUNAT del día',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'PEN', child: Text('S/ Soles')),
                    DropdownMenuItem(
                        value: 'USD', child: Text('US\$ Dólares')),
                  ],
                  onChanged: (v) => setState(() => _moneda = v ?? 'PEN'),
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Al contado'),
                value: _alContado,
                onChanged: (v) => setState(() {
                  _alContado = v;
                  if (v) _vencimiento = null;
                }),
                contentPadding: EdgeInsets.zero,
              ),
              if (!_alContado) ...[
                const SizedBox(height: 12),
                _DateField(
                  label: 'Fecha vencimiento',
                  value: _vencimiento ??
                      DateTime.now().add(const Duration(days: 30)),
                  onChanged: (d) => setState(() => _vencimiento = d),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _subtotalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Subtotal (${simboloMoneda(_moneda)})',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(_recalcularIgv),
                      validator: (v) {
                        final d = double.tryParse(v ?? '');
                        if (d == null || d <= 0) return 'Monto inválido';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _igvCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: 'IGV (${simboloMoneda(_moneda)})',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _igvEditadoManual = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(money(_total, _moneda),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Facturar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widget reutilizable DateField ─────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(DateFormat('dd/MM/yyyy').format(value)),
      ),
    );
  }
}

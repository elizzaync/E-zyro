import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Tributario / IGV: registro de compras y de ventas del periodo.
class PantallaTributario extends StatefulWidget {
  const PantallaTributario({super.key});

  @override
  State<PantallaTributario> createState() => _PantallaTributarioState();
}

class _PantallaTributarioState extends State<PantallaTributario> {
  FinanzasService? _svc;
  List<RegistroTributarioFila> _compras = [];
  List<RegistroTributarioFila> _ventas = [];
  String _periodo = periodoActual();
  bool _cargando = true;
  String? _error;

  List<RegimenTributario> _regimenes = [];
  ConfiguracionTributaria? _config;
  List<CuentaContable> _cuentas = [];
  bool _cargandoConfig = true;

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
    final c = await _svc!.registroCompras(_periodo);
    final v = await _svc!.registroVentas(_periodo);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (c.ok) {
        _compras = c.data ?? [];
      } else {
        _error = c.errorMessage;
      }
      if (v.ok) _ventas = v.data ?? [];
    });
  }

  Future<void> _cargarConfig() async {
    if (_svc == null) return;
    setState(() => _cargandoConfig = true);
    final r = await _svc!.regimenesTributarios();
    final c = await _svc!.configuracionTributaria();
    final pc = await _svc!.planCuentas(soloActivas: true);
    if (!mounted) return;
    setState(() {
      _cargandoConfig = false;
      _regimenes = r.ok ? (r.data ?? []) : [];
      _config = c.ok ? c.data : null;
      _cuentas = pc.ok ? (pc.data ?? []).where((x) => x.esDetalle).toList() : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tributario / IGV', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Compras'), Tab(text: 'Ventas'), Tab(text: 'Configuración')]),
          actions: [
            accionConmutadorFinanzas(context, actual: FinId.tributario),
            IconButton(
              tooltip: 'Periodo',
              icon: const Icon(Icons.edit_calendar),
              onPressed: () async {
                final parts = _periodo.split('-');
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime(int.parse(parts[0]), int.parse(parts[1]), 1),
                  firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) {
                  setState(() => _periodo = '${d.year}-${d.month.toString().padLeft(2, '0')}');
                  await _cargar();
                }
              },
            ),
            IconButton(onPressed: () async { await _cargar(); await _cargarConfig(); },
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: TabBarView(children: [
          _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _registro(_compras, 'IGV crédito fiscal', Colors.deepOrange, 'Compras'),
          _cargando
              ? const Center(child: CircularProgressIndicator())
              : _registro(_ventas, 'IGV débito fiscal', Colors.teal, 'Ventas'),
          _tabConfiguracion(),
        ]),
      ),
    );
  }

  Widget _tabConfiguracion() {
    if (_cargandoConfig) return const Center(child: CircularProgressIndicator());
    final cfg = _config;
    final puedeConfigurar = AppSession.i.isAdmin || AppSession.i.hasPerm('tributario:configurar');
    String nombreCuenta(String? id) {
      if (id == null) return '— sin asignar —';
      final c = _cuentas.where((x) => x.id == id).toList();
      return c.isEmpty ? id : '${c.first.codigo} — ${c.first.nombre}';
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.account_balance_outlined, color: Colors.indigo),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Configuración tributaria',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                  if (puedeConfigurar)
                    IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _editarConfiguracion),
                ]),
                const Divider(height: 24),
                if (cfg == null)
                  const Text('Sin configuración registrada.', style: TextStyle(color: Colors.grey))
                else ...[
                  _filaConfig('Régimen', '${cfg.regimenCodigo} (${cfg.regimenId})'),
                  _filaConfig('Tasa IGV', '${(cfg.tasaIgv * 100).toStringAsFixed(2)} %'),
                  _filaConfig('Cuenta IGV crédito fiscal', nombreCuenta(cfg.cuentaIgvCreditoFiscalId)),
                  _filaConfig('Cuenta IGV débito fiscal', nombreCuenta(cfg.cuentaIgvDebitoFiscalId)),
                ],
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 16, 8, 4),
          child: Text('REGÍMENES TRIBUTARIOS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
        if (_regimenes.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Sin regímenes registrados.', style: TextStyle(color: Colors.grey)))
        else
          ..._regimenes.map((r) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: r.activo ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
                    child: Icon(Icons.gavel_outlined, color: r.activo ? Colors.green : Colors.grey, size: 20),
                  ),
                  title: Text('${r.codigo} — ${r.nombre}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'IGV ${(r.tasaIgv * 100).toStringAsFixed(2)} %'
                    '${r.tasaRentaReferencial != null ? '  ·  Renta ref. ${(r.tasaRentaReferencial! * 100).toStringAsFixed(2)} %' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: r.activo ? null : const Text('inactivo', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              )),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _filaConfig(String label, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 180, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
        ]),
      );

  Future<void> _editarConfiguracion() async {
    final cfg = _config;
    if (cfg == null || _svc == null) return;
    final actualizado = await showModalBottomSheet<ConfiguracionTributaria>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormConfiguracionTributaria(config: cfg, regimenes: _regimenes, cuentas: _cuentas, svc: _svc!),
    );
    if (actualizado != null && mounted) {
      setState(() => _config = actualizado);
    }
  }

  Widget _registro(List<RegistroTributarioFila> filas, String etiquetaIgv, Color color, String etiquetaChip) {
    final base = filas.fold<double>(0, (a, f) => a + f.baseImponible);
    final igv = filas.fold<double>(0, (a, f) => a + f.igv);
    final total = filas.fold<double>(0, (a, f) => a + f.total);
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.07),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Periodo $_periodo', style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: _mini('Base', money(base), color)),
              const SizedBox(width: 8),
              Expanded(child: _mini(etiquetaIgv, money(igv), color)),
              const SizedBox(width: 8),
              Expanded(child: _mini('Total', money(total), color)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Documentos del periodo',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(etiquetaChip,
                              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filas.isEmpty
                        ? EstadoVacio(
                            icono: Icons.request_quote,
                            titulo: 'Sin documentos en el periodo',
                            subtitulo:
                                'Registra ${etiquetaChip.toLowerCase()} del periodo $_periodo para calcular tu $etiquetaIgv.',
                          )
                        : ListView.separated(
                            itemCount: filas.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final f = filas[i];
                              return ListTile(
                                dense: true,
                                title: Text('${f.tipoDocumento.toUpperCase()} ${f.numeroDocumento}',
                                    style: const TextStyle(fontSize: 13)),
                                subtitle: Text('${f.fecha} · ${f.tercero}${f.ruc != null ? ' · ${f.ruc}' : ''}',
                                    style: const TextStyle(fontSize: 11)),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(money(f.total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    Text('IGV ${money(f.igv)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mini(String label, String valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(valor, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _FormConfiguracionTributaria extends StatefulWidget {
  final ConfiguracionTributaria config;
  final List<RegimenTributario> regimenes;
  final List<CuentaContable> cuentas;
  final FinanzasService svc;
  const _FormConfiguracionTributaria({
    required this.config, required this.regimenes, required this.cuentas, required this.svc,
  });
  @override
  State<_FormConfiguracionTributaria> createState() => _FormConfiguracionTributariaState();
}

class _FormConfiguracionTributariaState extends State<_FormConfiguracionTributaria> {
  String? _regimenId;
  String? _cuentaCreditoId;
  String? _cuentaDebitoId;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _regimenId = widget.config.regimenId;
    _cuentaCreditoId = widget.config.cuentaIgvCreditoFiscalId;
    _cuentaDebitoId = widget.config.cuentaIgvDebitoFiscalId;
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final r = await widget.svc.actualizarConfiguracionTributaria(
      regimenId: _regimenId,
      cuentaIgvCreditoFiscalId: _cuentaCreditoId,
      cuentaIgvDebitoFiscalId: _cuentaDebitoId,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Configuración actualizada');
      Navigator.pop(context, r.data);
    } else {
      mostrarError(context, r.errorMessage);
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
            Text('Editar configuración tributaria', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _regimenId,
              decoration: const InputDecoration(labelText: 'Régimen', border: OutlineInputBorder()),
              items: widget.regimenes
                  .map((r) => DropdownMenuItem(value: r.id, child: Text('${r.codigo} — ${r.nombre}')))
                  .toList(),
              onChanged: (v) => setState(() => _regimenId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cuentaCreditoId,
              decoration: const InputDecoration(labelText: 'Cuenta IGV crédito fiscal', border: OutlineInputBorder()),
              items: cuentaItems,
              onChanged: (v) => setState(() => _cuentaCreditoId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cuentaDebitoId,
              decoration: const InputDecoration(labelText: 'Cuenta IGV débito fiscal', border: OutlineInputBorder()),
              items: cuentaItems,
              onChanged: (v) => setState(() => _cuentaDebitoId = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

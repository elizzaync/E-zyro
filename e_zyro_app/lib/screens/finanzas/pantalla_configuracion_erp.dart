import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Configuración ERP por empresa: features opcionales que cada cliente activa
/// según su operación — facturación electrónica (CPE vía Nubefact) y
/// multimoneda (USD con tipo de cambio SUNAT y diferencia de cambio).
class PantallaConfiguracionErp extends StatefulWidget {
  const PantallaConfiguracionErp({super.key});
  @override
  State<PantallaConfiguracionErp> createState() =>
      _PantallaConfiguracionErpState();
}

class _PantallaConfiguracionErpState extends State<PantallaConfiguracionErp> {
  FinanzasService? _svc;
  ConfigFE? _fe;
  ConfigContable? _contable;
  List<TipoCambioDia> _tc = [];
  bool _cargando = true;
  bool _accion = false;

  bool get _puedeEditar =>
      AppSession.i.isAdmin || AppSession.i.canConfigurarContabilidad;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getFinanzasService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() => _cargando = true);
    final fe = await _svc!.configFE();
    final cc = await _svc!.configContable();
    final tc = await _svc!.tiposCambio(dias: 10);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _fe = fe.data;
      _contable = cc.data;
      _tc = tc.data ?? [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración ERP',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          accionConmutadorFinanzas(context, actual: FinId.configuracionErp),
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _cardFacturacionElectronica(),
                  const SizedBox(height: 12),
                  _cardMultimoneda(),
                ],
              ),
            ),
    );
  }

  // ── Facturación electrónica ─────────────────────────────────────────────────
  Widget _cardFacturacionElectronica() {
    final fe = _fe;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 20, color: Colors.teal),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Facturación electrónica (SUNAT)',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: fe?.habilitado ?? false,
                  onChanged: (!_puedeEditar || _accion)
                      ? null
                      : (v) => _guardarFE(habilitado: v),
                ),
              ],
            ),
            const Text(
              'Al activarla, cada factura o boleta emitida en Cuentas por '
              'Cobrar se envía a SUNAT vía Nubefact (XML firmado + PDF). '
              'Apagada, los comprobantes son solo registros internos.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
            if (fe != null && fe.habilitado) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    fe.tokenConfigurado && (fe.apiUrl ?? '').isNotEmpty
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    size: 16,
                    color: fe.tokenConfigurado && (fe.apiUrl ?? '').isNotEmpty
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      fe.tokenConfigurado && (fe.apiUrl ?? '').isNotEmpty
                          ? 'Conectado a ${fe.proveedor} · series ${fe.serieFactura} / ${fe.serieBoleta}'
                          : 'Falta configurar la URL y el token de Nubefact.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (_puedeEditar)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _accion ? null : _editarCredencialesFE,
                    icon: const Icon(Icons.key_outlined, size: 16),
                    label: const Text('Credenciales y series'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _guardarFE({bool? habilitado, String? apiUrl, String? apiToken,
      String? serieFactura, String? serieBoleta}) async {
    setState(() => _accion = true);
    final r = await _svc!.actualizarConfigFE(
        habilitado: habilitado, apiUrl: apiUrl, apiToken: apiToken,
        serieFactura: serieFactura, serieBoleta: serieBoleta);
    if (!mounted) return;
    setState(() {
      _accion = false;
      if (r.ok) _fe = r.data;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _editarCredencialesFE() async {
    final url = TextEditingController(text: _fe?.apiUrl ?? '');
    final token = TextEditingController();
    final sf = TextEditingController(text: _fe?.serieFactura ?? 'F001');
    final sb = TextEditingController(text: _fe?.serieBoleta ?? 'B001');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Credenciales Nubefact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                decoration: const InputDecoration(
                    labelText: 'URL de la API',
                    hintText: 'https://api.nubefact.com/api/v1/…'),
              ),
              TextField(
                controller: token,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: 'Token',
                    hintText: (_fe?.tokenConfigurado ?? false)
                        ? '(configurado — dejar vacío para no cambiar)'
                        : 'Token de tu cuenta Nubefact'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: sf,
                      decoration:
                          const InputDecoration(labelText: 'Serie factura'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: sb,
                      decoration:
                          const InputDecoration(labelText: 'Serie boleta'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      await _guardarFE(
        apiUrl: url.text.trim(),
        apiToken: token.text.trim().isEmpty ? null : token.text.trim(),
        serieFactura: sf.text.trim(),
        serieBoleta: sb.text.trim(),
      );
    }
  }

  // ── Multimoneda + tipo de cambio ────────────────────────────────────────────
  Widget _cardMultimoneda() {
    final activa = _contable?.multimoneda ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.currency_exchange_outlined,
                    size: 20, color: Colors.indigo),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Multimoneda (USD)',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: activa,
                  onChanged: (!_puedeEditar || _accion)
                      ? null
                      : (v) async {
                          setState(() => _accion = true);
                          final r = await _svc!
                              .actualizarConfigContable(multimoneda: v);
                          if (!mounted) return;
                          setState(() {
                            _accion = false;
                            if (r.ok) _contable = r.data;
                          });
                          if (!r.ok) mostrarError(context, r.errorMessage);
                        },
                ),
              ],
            ),
            const Text(
              'Permite emitir facturas de venta y compra en dólares. Los '
              'asientos se convierten a soles al TC SUNAT del día y los '
              'cobros/pagos generan diferencia de cambio (776/676) automática.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
            if (activa) ...[
              const Divider(height: 22),
              Row(
                children: [
                  const Text('TIPO DE CAMBIO (VENTA)',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _accion ? null : _actualizarTcHoy,
                    icon: const Icon(Icons.cloud_download_outlined, size: 16),
                    label: const Text('Traer de SUNAT'),
                  ),
                  if (_puedeEditar)
                    IconButton(
                      tooltip: 'Registrar manual',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: _accion ? null : _registrarTcManual,
                    ),
                ],
              ),
              if (_tc.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Sin tipos de cambio registrados aún.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                )
              else
                for (final t in _tc.take(7))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(t.fecha, style: const TextStyle(fontSize: 12.5)),
                        const SizedBox(width: 8),
                        Text('(${t.fuente})',
                            style: const TextStyle(
                                fontSize: 10.5, color: Colors.grey)),
                        const Spacer(),
                        Text('S/ ${t.venta.toStringAsFixed(4)}',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _actualizarTcHoy() async {
    setState(() => _accion = true);
    final r = await _svc!.actualizarTipoCambioHoy();
    if (!mounted) return;
    setState(() => _accion = false);
    if (r.ok) {
      mostrarOk(context, 'TC de hoy: S/ ${r.data!.venta.toStringAsFixed(4)}');
      _cargar();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _registrarTcManual() async {
    final venta = TextEditingController();
    final hoy = hoyISO();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('TC venta del $hoy'),
        content: TextField(
          controller: venta,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Venta (S/ por USD)', hintText: '3.7500'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    final v = double.tryParse(venta.text.trim());
    if (ok == true && v != null && v > 0) {
      setState(() => _accion = true);
      final r = await _svc!.registrarTipoCambio(hoy, v);
      if (!mounted) return;
      setState(() => _accion = false);
      if (r.ok) {
        _cargar();
      } else {
        mostrarError(context, r.errorMessage);
      }
    }
  }
}

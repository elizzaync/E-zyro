import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import 'finanzas_comun.dart';

/// Planilla / nómina: cálculo, aprobación (provisión) y pago.
class PantallaPlanilla extends StatefulWidget {
  const PantallaPlanilla({super.key});

  @override
  State<PantallaPlanilla> createState() => _PantallaPlanillaState();
}

class _PantallaPlanillaState extends State<PantallaPlanilla> {
  FinanzasService? _svc;
  List<Planilla> _planillas = [];
  bool _cargando = true;
  String? _error;

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
    setState(() { _cargando = true; _error = null; });
    final res = await _svc!.planillas();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok) {
        _planillas = res.data ?? [];
      } else {
        _error = res.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planilla', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: AppSession.i.canCalcularPlanilla
          ? FloatingActionButton.extended(
              onPressed: _calcular,
              icon: const Icon(Icons.calculate),
              label: const Text('Calcular mes'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _planillas.isEmpty
                  ? const Center(child: Text('Sin planillas procesadas.'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _planillas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _tarjeta(_planillas[i]),
                      ),
                    ),
    );
  }

  Widget _tarjeta(Planilla p) {
    final surface = Theme.of(context).colorScheme.surface;
    final puedeAprobar = AppSession.i.canAprobarPlanilla;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_note, color: Colors.purple),
              const SizedBox(width: 8),
              Expanded(child: Text('Proceso ${p.fechaProceso}',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
              chipEstado(p.estado),
            ],
          ),
          const Divider(height: 18),
          _filaMonto('Ingresos', p.totalIngresos, Colors.green),
          _filaMonto('Descuentos', p.totalDescuentos, Colors.deepOrange),
          _filaMonto('Aportes empleador', p.totalAportes, Colors.blueGrey),
          const Divider(height: 14),
          _filaMonto('Neto a pagar', p.totalNeto, Colors.purple, negrita: true),
          if (puedeAprobar && (p.estado == 'calculada' || p.estado == 'aprobada')) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (p.estado == 'calculada')
                  FilledButton.tonalIcon(
                    onPressed: () => _accion(p, 'aprobar'),
                    icon: const Icon(Icons.verified, size: 18),
                    label: const Text('Aprobar'),
                  ),
                if (p.estado == 'aprobada')
                  FilledButton.icon(
                    onPressed: () => _accion(p, 'pagar'),
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Marcar pagada'),
                  ),
              ],
            ),
          ],
        ],
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

  Future<void> _calcular() async {
    final periodo = periodoActual();
    final res = await _svc!.calcularPlanilla(periodo);
    if (!mounted) return;
    if (res.ok) {
      mostrarOk(context, 'Planilla $periodo calculada (estado: calculada).');
      _cargar();
    } else {
      mostrarError(context, res.errorMessage);
    }
  }

  Future<void> _accion(Planilla p, String accion) async {
    final esAprobar = accion == 'aprobar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esAprobar ? 'Aprobar planilla' : 'Marcar pagada'),
        content: Text(esAprobar
            ? 'Se generará el asiento de provisión (62 → 41/40).'
            : 'Se generará el asiento de pago (41/40 → 10 Caja).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(esAprobar ? 'Aprobar' : 'Pagar')),
        ],
      ),
    );
    if (ok != true) return;
    final res = esAprobar ? await _svc!.aprobarPlanilla(p.id) : await _svc!.pagarPlanilla(p.id);
    if (!mounted) return;
    if (res.ok) {
      mostrarOk(context, esAprobar ? 'Planilla aprobada (provisión contabilizada).'
          : 'Planilla pagada (pago contabilizado).');
      _cargar();
    } else {
      mostrarError(context, res.errorMessage);
    }
  }
}

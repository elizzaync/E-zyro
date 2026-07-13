import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Presupuesto anual por cuenta/grupo PCGE con ejecución en vivo.
class PantallaPresupuesto extends StatefulWidget {
  const PantallaPresupuesto({super.key});
  @override
  State<PantallaPresupuesto> createState() => _PantallaPresupuestoState();
}

class _PantallaPresupuestoState extends State<PantallaPresupuesto> {
  FinanzasService? _svc;
  PresupuestoAnual? _p;
  int _anio = DateTime.now().year;
  bool _cargando = true;
  String? _error;

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
    setState(() { _cargando = true; _error = null; });
    final r = await _svc!.presupuesto(_anio);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _p = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presupuesto',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          accionConmutadorFinanzas(context, actual: FinId.presupuesto),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () { setState(() => _anio--); _cargar(); },
          ),
          Center(child: Text('$_anio',
              style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () { setState(() => _anio++); _cargar(); },
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: (_p?.lineas.isEmpty ?? true)
                      ? ListView(children: [
                          const SizedBox(height: 60),
                          EstadoVacio(
                            icono: Icons.savings_outlined,
                            titulo: 'Sin presupuesto $_anio',
                            subtitulo: _puedeEditar
                                ? 'Agrega líneas por cuenta o grupo PCGE (ej. "63" para servicios de terceros).'
                                : 'Aún no se ha definido el presupuesto de este año.',
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            _resumen(),
                            const SizedBox(height: 8),
                            for (final l in _p!.lineas) _tarjeta(l),
                          ],
                        ),
                ),
      floatingActionButton: _puedeEditar
          ? FloatingActionButton.extended(
              onPressed: _agregarLinea,
              icon: const Icon(Icons.add),
              label: const Text('Línea'),
            )
          : null,
    );
  }

  Widget _resumen() {
    final p = _p!;
    final pct = p.totalPresupuestado > 0
        ? (p.totalEjecutado / p.totalPresupuestado * 100)
        : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(children: [
                    const Text('Presupuestado',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    FittedBox(child: Text(money(p.totalPresupuestado),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700))),
                  ]),
                ),
                Expanded(
                  child: Column(children: [
                    const Text('Ejecutado',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    FittedBox(child: Text(money(p.totalEjecutado),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: pct > 100 ? Colors.red : Colors.teal))),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 8,
                color: pct > 100 ? Colors.red : const Color(0xFF1E9462),
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 4),
            Text('${pct.toStringAsFixed(1)} % del año ejecutado',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(PresupuestoLinea l) {
    final pct = l.ejecucionPct ?? 0;
    final sobre = pct > 100;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${l.cuentaCodigo} — ${l.nombre}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 6,
                color: sobre ? Colors.red : Colors.teal,
                backgroundColor: Colors.grey.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${money(l.ejecutado)} de ${money(l.montoAnual)}'
              '${l.ejecucionPct != null ? ' · ${pct.toStringAsFixed(1)} %' : ''}'
              '${sobre ? ' · SOBREEJECUTADO' : ''}',
              style: TextStyle(
                  fontSize: 11, color: sobre ? Colors.red : Colors.grey),
            ),
          ],
        ),
        trailing: _puedeEditar
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 19),
                onPressed: () => _eliminarLinea(l),
              )
            : null,
      ),
    );
  }

  Future<void> _guardar(List<PresupuestoLinea> lineas) async {
    final r = await _svc!.guardarPresupuesto(_anio, [
      for (final l in lineas)
        {
          'cuenta_codigo': l.cuentaCodigo,
          'monto_anual': l.montoAnual,
          if (l.notas != null) 'notas': l.notas,
        },
    ]);
    if (!mounted) return;
    if (r.ok) {
      setState(() => _p = r.data);
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _agregarLinea() async {
    final codigo = TextEditingController();
    final monto = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nueva línea $_anio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codigo,
              decoration: const InputDecoration(
                  labelText: 'Código PCGE (cuenta o grupo)',
                  hintText: '63, 601, 6311…'),
            ),
            TextField(
              controller: monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Monto anual (S/)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Agregar')),
        ],
      ),
    );
    final m = double.tryParse(monto.text.trim());
    if (ok != true || codigo.text.trim().isEmpty || m == null) return;
    await _guardar([
      ...?_p?.lineas,
      PresupuestoLinea(
          cuentaCodigo: codigo.text.trim(), nombre: '',
          montoAnual: m, ejecutado: 0, disponible: m),
    ]);
  }

  Future<void> _eliminarLinea(PresupuestoLinea l) async {
    await _guardar(
        _p!.lineas.where((x) => x.cuentaCodigo != l.cuentaCodigo).toList());
  }
}

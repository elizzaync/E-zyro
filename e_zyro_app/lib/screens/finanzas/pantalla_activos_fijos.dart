import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import 'finanzas_comun.dart';

/// Activos fijos: catálogo, alta y proceso mensual de depreciación.
class PantallaActivosFijos extends StatefulWidget {
  const PantallaActivosFijos({super.key});

  @override
  State<PantallaActivosFijos> createState() => _PantallaActivosFijosState();
}

class _PantallaActivosFijosState extends State<PantallaActivosFijos> {
  FinanzasService? _svc;
  List<ActivoFijo> _activos = [];
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
    final res = await _svc!.activosFijos();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok) {
        _activos = res.data ?? [];
      } else {
        _error = res.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final puedeGestionar = AppSession.i.canGestionarActivos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activos fijos', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (puedeGestionar)
            IconButton(
              tooltip: 'Procesar depreciación del mes',
              icon: const Icon(Icons.calculate_outlined),
              onPressed: _procesarDepreciacion,
            ),
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: _nuevoActivo,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo activo'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _activos.isEmpty
                  ? const Center(child: Text('Sin activos fijos registrados.'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        itemCount: _activos.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _tile(_activos[i]),
                      ),
                    ),
    );
  }

  Widget _tile(ActivoFijo a) {
    final pct = a.valorAdquisicion == 0 ? 0.0
        : (a.depreciacionAcumulada / a.valorAdquisicion).clamp(0.0, 1.0);
    return ListTile(
      leading: const Icon(Icons.precision_manufacturing_outlined),
      title: Text(a.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Valor ${money(a.valorAdquisicion)} · En libros ${money(a.valorEnLibros)}',
              style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: pct, minHeight: 5,
                color: Colors.brown, backgroundColor: Colors.brown.shade100),
          ),
          const SizedBox(height: 2),
          Text('Depreciado ${(pct * 100).toStringAsFixed(0)}% · ${a.vidaUtilMeses} meses',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
      isThreeLine: true,
      trailing: chipEstado(a.estado),
    );
  }

  Future<void> _procesarDepreciacion() async {
    final periodo = periodoActual();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Procesar depreciación'),
        content: Text('Se generarán los asientos de depreciación del periodo $periodo '
            '(idempotente: no duplica los ya procesados).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Procesar')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _svc!.procesarDepreciacion(periodo);
    if (!mounted) return;
    if (res.ok) {
      final d = res.data!;
      mostrarOk(context, 'Procesados: ${d['procesados']} · Omitidos: ${d['omitidos']} '
          '· Total ${money((d['total_depreciado'] as num?)?.toDouble() ?? 0)}');
      _cargar();
    } else {
      mostrarError(context, res.errorMessage);
    }
  }

  Future<void> _nuevoActivo() async {
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormActivo(svc: _svc!),
    );
    if (creado == true) _cargar();
  }
}

class _FormActivo extends StatefulWidget {
  final FinanzasService svc;
  const _FormActivo({required this.svc});

  @override
  State<_FormActivo> createState() => _FormActivoState();
}

class _FormActivoState extends State<_FormActivo> {
  final _nombreCtrl = TextEditingController();
  final _valorCtrl = TextEditingController();
  final _residualCtrl = TextEditingController(text: '0');
  final _vidaCtrl = TextEditingController(text: '60');
  DateTime _adquisicion = DateTime.now();
  bool _guardando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _valorCtrl.dispose();
    _residualCtrl.dispose();
    _vidaCtrl.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nuevo activo fijo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _adquisicion,
                    firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _adquisicion = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Fecha de adquisición', border: OutlineInputBorder()),
                child: Text(_iso(_adquisicion)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _valorCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Valor adquisición', border: OutlineInputBorder()))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _residualCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Valor residual', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _vidaCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Vida útil (meses)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    final valor = double.tryParse(_valorCtrl.text) ?? 0;
    final vida = int.tryParse(_vidaCtrl.text) ?? 0;
    if (_nombreCtrl.text.trim().isEmpty || valor <= 0 || vida <= 0) {
      mostrarError(context, 'Completa nombre, valor > 0 y vida útil > 0.');
      return;
    }
    setState(() => _guardando = true);
    final res = await widget.svc.crearActivoFijo(
      nombre: _nombreCtrl.text.trim(),
      fechaAdquisicion: _iso(_adquisicion),
      valorAdquisicion: valor,
      vidaUtilMeses: vida,
      valorResidual: double.tryParse(_residualCtrl.text) ?? 0,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      mostrarOk(context, 'Activo fijo registrado.');
      Navigator.pop(context, true);
    } else {
      mostrarError(context, res.errorMessage);
    }
  }
}

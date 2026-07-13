import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import '../../theme/ez_theme.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Controlling: catálogo de centros de costo, costo real y comparativo
/// presupuesto vs. real (calculados en vivo sobre el libro mayor).
class PantallaCentrosCosto extends StatefulWidget {
  const PantallaCentrosCosto({super.key});
  @override
  State<PantallaCentrosCosto> createState() => _PantallaCentrosCostoState();
}

class _PantallaCentrosCostoState extends State<PantallaCentrosCosto> {
  FinanzasService? _svc;
  List<CentroCosto> _centros = [];
  bool _cargando = true;
  String? _error;
  bool _soloActivos = true;

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
    final r = await _svc!.centrosCosto(activo: _soloActivos ? true : null);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _centros = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final puedeGestionar = AppSession.i.isAdmin || AppSession.i.canGestionarCentrosCosto;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centros de costo', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          accionConmutadorFinanzas(context, actual: FinId.centrosCosto),
          IconButton(
            tooltip: _soloActivos ? 'Mostrar todos' : 'Solo activos',
            icon: Icon(_soloActivos ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () { setState(() => _soloActivos = !_soloActivos); _cargar(); },
          ),
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _centros.isEmpty
                  ? const EstadoVacio(
                      icono: Icons.account_tree,
                      titulo: 'Sin centros de costo',
                      subtitulo: 'Crea centros para distribuir ingresos y gastos por área o proyecto.',
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _centros.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _tarjeta(_centros[i]),
                      ),
                    ),
      floatingActionButton: puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: _nuevoCentro,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo centro'),
            )
          : null,
    );
  }

  Widget _tarjeta(CentroCosto c) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (c.activo ? Colors.indigo : Colors.grey).withValues(alpha: 0.15),
          child: Icon(Icons.workspaces_outline, color: c.activo ? Colors.indigo : Colors.grey, size: 20),
        ),
        title: Text('${c.codigo} — ${c.nombre}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(
          'Tipo: ${c.tipoReferencia}'
          '${c.presupuestoReferencial != null ? '  ·  Presupuesto: ${money(c.presupuestoReferencial!)}' : ''}'
          '${c.activo ? '' : '  ·  inactivo'}',
          style: const TextStyle(fontSize: 11),
        ),
        onTap: () async {
          final cambiado = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => _PantallaDetalleCentro(centro: c, svc: _svc!)),
          );
          if (cambiado == true) _cargar();
        },
      ),
    );
  }

  Future<void> _nuevoCentro() async {
    if (_svc == null) return;
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormCentroCosto(svc: _svc!),
    );
    if (creado == true) _cargar();
  }
}

class _FormCentroCosto extends StatefulWidget {
  final FinanzasService svc;
  const _FormCentroCosto({required this.svc});
  @override
  State<_FormCentroCosto> createState() => _FormCentroCostoState();
}

class _FormCentroCostoState extends State<_FormCentroCosto> {
  final _formKey = GlobalKey<FormState>();
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  final _presupuesto = TextEditingController();
  String _tipo = 'libre';
  bool _guardando = false;

  static const _tipos = ['libre', 'proyecto', 'area', 'empleado'];

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _presupuesto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    final presupuesto = _presupuesto.text.trim().isEmpty ? null : double.tryParse(_presupuesto.text.replaceAll(',', '.'));
    final r = await widget.svc.crearCentroCosto(
      codigo: _codigo.text.trim(),
      nombre: _nombre.text.trim(),
      tipoReferencia: _tipo,
      presupuestoReferencial: presupuesto,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Centro de costo creado');
      Navigator.pop(context, true);
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
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nuevo centro de costo', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codigo,
                decoration: const InputDecoration(labelText: 'Código', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo de referencia', border: OutlineInputBorder()),
                items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _tipo = v ?? 'libre'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _presupuesto,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Presupuesto referencial (opcional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Crear'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PantallaDetalleCentro extends StatefulWidget {
  final CentroCosto centro;
  final FinanzasService svc;
  const _PantallaDetalleCentro({required this.centro, required this.svc});
  @override
  State<_PantallaDetalleCentro> createState() => _PantallaDetalleCentroState();
}

class _PantallaDetalleCentroState extends State<_PantallaDetalleCentro> {
  late CentroCosto _centro;
  bool _huboCambios = false;
  ComparativoCentro? _comparativo;
  bool _cargandoComparativo = true;
  DateTime? _desde;
  DateTime? _hasta;

  @override
  void initState() {
    super.initState();
    _centro = widget.centro;
    _cargarComparativo();
  }

  String? _iso(DateTime? d) => d?.toIso8601String().substring(0, 10);

  Future<void> _cargarComparativo() async {
    setState(() => _cargandoComparativo = true);
    final r = await widget.svc.comparativoCentro(_centro.id, desde: _iso(_desde), hasta: _iso(_hasta));
    if (!mounted) return;
    setState(() {
      _cargandoComparativo = false;
      _comparativo = r.ok ? r.data : null;
    });
  }

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _desde != null && _hasta != null ? DateTimeRange(start: _desde!, end: _hasta!) : null,
      helpText: 'Rango de evaluación',
    );
    if (rango != null) {
      setState(() { _desde = rango.start; _hasta = rango.end; });
      await _cargarComparativo();
    } else if (_desde == null) {
      setState(() => _hasta = ahora);
    }
  }

  Future<void> _editar() async {
    final puedeGestionar = AppSession.i.isAdmin || AppSession.i.canGestionarCentrosCosto;
    if (!puedeGestionar) return;
    final actualizado = await showModalBottomSheet<CentroCosto>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormEditarCentro(centro: _centro, svc: widget.svc),
    );
    if (actualizado != null && mounted) {
      setState(() { _centro = actualizado; _huboCambios = true; });
    }
  }

  Future<void> _desactivar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desactivar centro de costo'),
        content: Text('¿Confirma desactivar "${_centro.nombre}"? Se conservará su historial de imputaciones.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Desactivar')),
        ],
      ),
    );
    if (confirmar != true) return;
    final r = await widget.svc.desactivarCentroCosto(_centro.id);
    if (!mounted) return;
    if (r.ok && r.data != null) {
      mostrarOk(context, 'Centro de costo desactivado');
      setState(() { _centro = r.data!; _huboCambios = true; });
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _centro;
    final puedeGestionar = AppSession.i.isAdmin || AppSession.i.canGestionarCentrosCosto;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_huboCambios);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.nombre),
          actions: [
            if (puedeGestionar) IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _editar),
            if (puedeGestionar && c.activo)
              IconButton(icon: const Icon(Icons.block_outlined), onPressed: _desactivar),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [chipEstado(c.activo ? 'activo' : 'inactivo', context.ez), const Spacer(),
                        Text(c.tipoReferencia, style: const TextStyle(fontSize: 12, color: Colors.grey))]),
                    const SizedBox(height: 12),
                    Text('${c.codigo} — ${c.nombre}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (c.presupuestoReferencial != null) ...[
                      const SizedBox(height: 4),
                      Text('Presupuesto referencial: ${money(c.presupuestoReferencial!)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('COMPARATIVO PRESUPUESTO VS. REAL', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(_desde != null && _hasta != null ? '${_iso(_desde)} → ${_iso(_hasta)}' : 'Elegir rango'),
                onPressed: _elegirRango,
              ),
            ]),
            const SizedBox(height: 8),
            if (_cargandoComparativo)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_comparativo == null)
              const Padding(padding: EdgeInsets.all(16), child: Text('Sin datos para el rango seleccionado.', style: TextStyle(color: Colors.grey)))
            else
              _tarjetaComparativo(_comparativo!),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaComparativo(ComparativoCentro c) {
    final desviacionNegativa = (c.desviacion ?? 0) < 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: TarjetaResumen(titulo: 'Costo real', valor: money(c.costoReal),
                  color: Colors.deepOrange, icono: Icons.trending_up)),
              const SizedBox(width: 10),
              Expanded(child: TarjetaResumen(
                  titulo: 'Presupuesto', valor: c.presupuestoReferencial != null ? money(c.presupuestoReferencial!) : '—',
                  color: Colors.indigo, icono: Icons.savings_outlined)),
            ]),
            if (c.desviacion != null) ...[
              const SizedBox(height: 12),
              _filaComparativo('Desviación', money(c.desviacion!), desviacionNegativa ? Colors.red : Colors.green),
            ],
            if (c.ejecucionPct != null)
              _filaComparativo('Ejecución', '${c.ejecucionPct!.toStringAsFixed(1)} %',
                  c.ejecucionPct! > 100 ? Colors.red : Colors.indigo),
          ],
        ),
      ),
    );
  }

  Widget _filaComparativo(String label, String valor, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const Spacer(),
          Text(valor, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ]),
      );
}

class _FormEditarCentro extends StatefulWidget {
  final CentroCosto centro;
  final FinanzasService svc;
  const _FormEditarCentro({required this.centro, required this.svc});
  @override
  State<_FormEditarCentro> createState() => _FormEditarCentroState();
}

class _FormEditarCentroState extends State<_FormEditarCentro> {
  late final TextEditingController _nombre;
  late final TextEditingController _presupuesto;
  late String _tipo;
  bool _guardando = false;

  static const _tipos = ['libre', 'proyecto', 'area', 'empleado'];

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.centro.nombre);
    _presupuesto = TextEditingController(text: widget.centro.presupuestoReferencial?.toString() ?? '');
    _tipo = widget.centro.tipoReferencia;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _presupuesto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final presupuesto = _presupuesto.text.trim().isEmpty ? null : double.tryParse(_presupuesto.text.replaceAll(',', '.'));
    final r = await widget.svc.actualizarCentroCosto(
      id: widget.centro.id,
      nombre: _nombre.text.trim(),
      tipoReferencia: _tipo,
      presupuestoReferencial: presupuesto,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Centro de costo actualizado');
      Navigator.pop(context, r.data);
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Editar centro de costo', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo de referencia', border: OutlineInputBorder()),
              items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _tipo = v ?? _tipo),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _presupuesto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Presupuesto referencial', border: OutlineInputBorder()),
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

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../models/cotizacion_models.dart';
import '../models/finanzas_models.dart' show Tercero;
import '../services/consulta_service.dart';
import '../services/cotizacion_service.dart';
import '../services/finanzas_service.dart';
import '../utils/app_session.dart';

const _kVerde = Color(0xFF1E9462);

Color _colorEstado(String e) => switch (e) {
      'borrador' => Colors.blueGrey,
      'enviada' => Colors.orange,
      'aceptada' => Colors.green,
      'rechazada' => Colors.red,
      'vencida' => Colors.grey,
      'convertida' => Colors.indigo,
      _ => Colors.blueGrey,
    };

Widget _chip(String estado) {
  final c = _colorEstado(estado);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.withValues(alpha: 0.5)),
    ),
    child: Text(estado,
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

String _money(double v, String moneda) =>
    '${moneda == 'PEN' ? 'S/' : moneda} ${v.toStringAsFixed(2)}';

/// Ciclo comercial: cotizaciones (borrador → enviada → aceptada → proyecto).
class PantallaCotizaciones extends StatefulWidget {
  const PantallaCotizaciones({super.key});
  @override
  State<PantallaCotizaciones> createState() => _PantallaCotizacionesState();
}

class _PantallaCotizacionesState extends State<PantallaCotizaciones> {
  CotizacionService? _svc;
  List<Cotizacion> _todas = [];
  bool _cargando = true;
  String? _error;
  String _filtro = 'todas';

  static const _filtros = [
    'todas', 'borrador', 'enviada', 'aceptada', 'convertida', 'rechazada', 'vencida',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = CotizacionService(ApiClient(prefs));
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final r = await _svc!.listar();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _todas = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  List<Cotizacion> get _visibles =>
      _filtro == 'todas' ? _todas : _todas.where((c) => c.estado == _filtro).toList();

  bool get _puedeGestionar =>
      AppSession.i.isAdmin || AppSession.i.hasPerm('cotizaciones:gestionar');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cotizaciones',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final f in _filtros)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f, style: const TextStyle(fontSize: 12)),
                      selected: _filtro == f,
                      onSelected: (_) => setState(() => _filtro = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _visibles.isEmpty
                        ? const Center(
                            child: Text('Sin cotizaciones',
                                style: TextStyle(color: Colors.grey)))
                        : RefreshIndicator(
                            onRefresh: _cargar,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _visibles.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _tarjeta(_visibles[i]),
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: _puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: _nueva,
              backgroundColor: _kVerde,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Nueva', style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }

  Widget _tarjeta(Cotizacion c) {
    return Card(
      child: ListTile(
        title: Text('${c.numero} — ${c.cliente}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text('${c.fechaEmision}  ·  vence ${c.vence}',
            style: const TextStyle(fontSize: 11)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(c.total, c.moneda),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            _chip(c.estado),
          ],
        ),
        onTap: () async {
          final cambio = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => _DetalleCotizacion(id: c.id, svc: _svc!)),
          );
          if (cambio == true) _cargar();
        },
      ),
    );
  }

  Future<void> _nueva() async {
    final creada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _FormCotizacion(svc: _svc!)),
    );
    if (creada == true) _cargar();
  }
}

// ── Detalle ───────────────────────────────────────────────────────────────────
class _DetalleCotizacion extends StatefulWidget {
  final String id;
  final CotizacionService svc;
  const _DetalleCotizacion({required this.id, required this.svc});
  @override
  State<_DetalleCotizacion> createState() => _DetalleCotizacionState();
}

class _DetalleCotizacionState extends State<_DetalleCotizacion> {
  Cotizacion? _c;
  bool _cargando = true;
  bool _accion = false;
  bool _huboCambio = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await widget.svc.obtener(widget.id);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _c = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  bool get _puedeGestionar =>
      AppSession.i.isAdmin || AppSession.i.hasPerm('cotizaciones:gestionar');

  Future<void> _ejecutar(Future<dynamic> Function() fn) async {
    setState(() => _accion = true);
    final r = await fn();
    if (!mounted) return;
    setState(() => _accion = false);
    if (r.ok) {
      _huboCambio = true;
      setState(() => _c = r.data as Cotizacion?);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.errorMessage),
          backgroundColor: Colors.red.shade700));
    }
  }

  Future<void> _verPdf() async {
    setState(() => _accion = true);
    final bytes = await widget.svc.pdf(widget.id);
    if (!mounted) return;
    setState(() => _accion = false);
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo generar el PDF')));
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: '${_c?.numero ?? 'cotizacion'}.pdf');
  }

  Future<void> _convertir() async {
    final lideres = await widget.svc.lideres();
    if (!mounted) return;
    if (lideres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay jefes de operaciones disponibles')));
      return;
    }
    String? jefeId = lideres.first['id'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convertir a proyecto'),
        content: StatefulBuilder(
          builder: (ctx2, setD) => DropdownButtonFormField<String>(
            initialValue: jefeId,
            decoration: const InputDecoration(labelText: 'Jefe de operaciones'),
            items: [
              for (final l in lideres)
                DropdownMenuItem(value: l['id'], child: Text(l['nombre'] ?? '')),
            ],
            onChanged: (v) => setD(() => jefeId = v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Convertir')),
        ],
      ),
    );
    if (ok == true && jefeId != null) {
      await _ejecutar(() => widget.svc.convertir(widget.id,
          jefeOperacionesId: jefeId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _huboCambio);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(c?.numero ?? 'Cotización',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          actions: [
            if (c != null)
              IconButton(
                  tooltip: 'PDF',
                  onPressed: _accion ? null : _verPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined)),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(c!.cliente,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ),
                          _chip(c.estado),
                        ],
                      ),
                      if ((c.ruc ?? '').isNotEmpty)
                        Text('RUC ${c.ruc}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text('Emitida ${c.fechaEmision} · válida hasta ${c.vence}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const Divider(height: 24),
                      for (final it in c.items)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(it.descripcion,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                              '${it.cantidad} ${it.unidad ?? ''} × ${_money(it.precioUnitario, c.moneda)}',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Text(_money(it.total, c.moneda),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      const Divider(height: 20),
                      _totRow('Subtotal', c.subtotal, c.moneda),
                      _totRow('IGV', c.igv, c.moneda),
                      _totRow('TOTAL', c.total, c.moneda, destacado: true),
                      if ((c.condicionesPago ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('Condiciones: ${c.condicionesPago}',
                            style: const TextStyle(fontSize: 12)),
                      ],
                      if ((c.notas ?? '').isNotEmpty)
                        Text('Notas: ${c.notas}',
                            style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 20),
                      if (_puedeGestionar) ..._acciones(c),
                    ],
                  ),
      ),
    );
  }

  List<Widget> _acciones(Cotizacion c) {
    final botones = <Widget>[];
    void agregar(String texto, IconData icono, Color color,
        Future<void> Function() fn) {
      botones.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: color, minimumSize: const Size.fromHeight(44)),
          onPressed: _accion ? null : () => fn(),
          icon: Icon(icono, size: 18),
          label: Text(texto),
        ),
      ));
    }

    switch (c.estado) {
      case 'borrador':
        agregar('Enviar al cliente', Icons.send_outlined, Colors.orange,
            () => _ejecutar(() => widget.svc.enviar(c.id)));
        botones.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44)),
            onPressed: _accion
                ? null
                : () async {
                    final edit = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              _FormCotizacion(svc: widget.svc, editar: c)),
                    );
                    if (edit == true) {
                      _huboCambio = true;
                      _cargar();
                    }
                  },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Editar'),
          ),
        ));
        agregar('Eliminar borrador', Icons.delete_outline, Colors.red,
            () async {
          final ok = await widget.svc.eliminarBorrador(c.id);
          if (!mounted) return;
          if (ok) {
            Navigator.pop(context, true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No se pudo eliminar')));
          }
        });
      case 'enviada':
        agregar('Marcar aceptada', Icons.check_circle_outline, Colors.green,
            () => _ejecutar(() => widget.svc.resolver(c.id, 'aceptada')));
        agregar('Marcar rechazada', Icons.cancel_outlined, Colors.red,
            () => _ejecutar(() => widget.svc.resolver(c.id, 'rechazada')));
      case 'aceptada':
        agregar('Convertir a proyecto', Icons.rocket_launch_outlined,
            Colors.indigo, _convertir);
      case 'convertida':
        botones.add(const Center(
            child: Text('Convertida en proyecto ✅',
                style: TextStyle(color: Colors.grey))));
    }
    return botones;
  }

  Widget _totRow(String t, double v, String mon, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(t,
                  style: TextStyle(
                      fontSize: destacado ? 14 : 12.5,
                      fontWeight:
                          destacado ? FontWeight.w700 : FontWeight.w400))),
          Text(_money(v, mon),
              style: TextStyle(
                  fontSize: destacado ? 15 : 12.5,
                  fontWeight: FontWeight.w700,
                  color: destacado ? _kVerde : null)),
        ],
      ),
    );
  }
}

// ── Formulario crear/editar ───────────────────────────────────────────────────
class _FormCotizacion extends StatefulWidget {
  final CotizacionService svc;
  final Cotizacion? editar;
  const _FormCotizacion({required this.svc, this.editar});
  @override
  State<_FormCotizacion> createState() => _FormCotizacionState();
}

class _FormCotizacionState extends State<_FormCotizacion> {
  // Cliente: existente o nuevo
  List<Tercero> _clientes = [];
  Tercero? _clienteSel;
  bool _clienteNuevo = false;
  final _razonNueva = TextEditingController();
  final _rucNuevo = TextEditingController();
  bool _consultandoRuc = false;

  final List<ItemBorrador> _items = [ItemBorrador()];
  final _validez = TextEditingController(text: '30');
  final _condiciones = TextEditingController();
  final _notas = TextEditingController();
  bool _guardando = false;

  bool get _esEdicion => widget.editar != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editar;
    if (e != null) {
      _validez.text = e.validezDias.toString();
      _condiciones.text = e.condicionesPago ?? '';
      _notas.text = e.notas ?? '';
      _items
        ..clear()
        ..addAll(e.items.map((i) => ItemBorrador(
              descripcion: i.descripcion,
              unidad: i.unidad,
              cantidad: i.cantidad,
              precioUnitario: i.precioUnitario,
            )));
    }
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
    final prefs = await SharedPreferences.getInstance();
    final r = await FinanzasService(ApiClient(prefs)).clientes();
    if (!mounted) return;
    setState(() => _clientes = r.data ?? []);
  }

  @override
  void dispose() {
    _razonNueva.dispose();
    _rucNuevo.dispose();
    _validez.dispose();
    _condiciones.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _buscarRuc() async {
    final ruc = _rucNuevo.text.trim();
    if (ruc.length != 11) return;
    setState(() => _consultandoRuc = true);
    final r = await ConsultaService.ruc(ruc);
    if (!mounted) return;
    setState(() {
      _consultandoRuc = false;
      if (r != null && r.razonSocial.isNotEmpty) _razonNueva.text = r.razonSocial;
    });
  }

  double get _subtotal => _items.fold(0, (a, i) => a + i.total);

  Future<void> _guardar() async {
    if (!_esEdicion) {
      if (!_clienteNuevo && _clienteSel == null) {
        _msg('Selecciona un cliente o crea uno nuevo');
        return;
      }
      if (_clienteNuevo && _razonNueva.text.trim().isEmpty) {
        _msg('Ingresa la razón social del cliente nuevo');
        return;
      }
    }
    final items = _items.where((i) => i.descripcion.trim().isNotEmpty).toList();
    if (items.isEmpty) {
      _msg('Agrega al menos un ítem con descripción');
      return;
    }
    setState(() => _guardando = true);
    final r = _esEdicion
        ? await widget.svc.editar(widget.editar!.id,
            items: items,
            validezDias: int.tryParse(_validez.text) ?? 30,
            condicionesPago: _condiciones.text.trim(),
            notas: _notas.text.trim())
        : await widget.svc.crear(
            clienteId: _clienteNuevo ? null : _clienteSel!.id,
            clienteNuevoRazon: _razonNueva.text.trim(),
            clienteNuevoRuc: _rucNuevo.text.trim(),
            items: items,
            validezDias: int.tryParse(_validez.text) ?? 30,
            condicionesPago: _condiciones.text.trim(),
            notas: _notas.text.trim());
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      _msg(r.errorMessage);
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: Colors.red.shade700));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar cotización' : 'Nueva cotización',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (!_esEdicion) ...[
            const Text('CLIENTE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey)),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Existente')),
                ButtonSegment(value: true, label: Text('Nuevo')),
              ],
              selected: {_clienteNuevo},
              onSelectionChanged: (s) =>
                  setState(() => _clienteNuevo = s.first),
            ),
            const SizedBox(height: 10),
            if (!_clienteNuevo)
              DropdownButtonFormField<Tercero>(
                initialValue: _clienteSel,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Cliente existente'),
                items: [
                  for (final c in _clientes)
                    DropdownMenuItem(
                        value: c,
                        child: Text(c.razonSocial,
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _clienteSel = v),
              )
            else ...[
              TextField(
                controller: _rucNuevo,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'RUC (opcional)',
                  suffixIcon: _consultandoRuc
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          tooltip: 'Buscar en SUNAT',
                          icon: const Icon(Icons.search),
                          onPressed: _buscarRuc),
                ),
                onSubmitted: (_) => _buscarRuc(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _razonNueva,
                decoration:
                    const InputDecoration(labelText: 'Razón social *'),
              ),
            ],
            const SizedBox(height: 18),
          ],
          const Text('ÍTEMS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey)),
          const SizedBox(height: 4),
          for (var i = 0; i < _items.length; i++) _itemCard(i),
          OutlinedButton.icon(
            onPressed: () => setState(() => _items.add(ItemBorrador())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar ítem'),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Subtotal: S/ ${_subtotal.toStringAsFixed(2)}  (+ IGV)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _validez,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Validez (días)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _condiciones,
            decoration: const InputDecoration(
                labelText: 'Condiciones de pago (opcional)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notas,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notas (opcional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _kVerde,
                minimumSize: const Size.fromHeight(48)),
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_esEdicion ? 'Guardar cambios' : 'Crear cotización'),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _itemCard(int i) {
    final it = _items[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextFormField(
              initialValue: it.descripcion,
              decoration: InputDecoration(
                labelText: 'Descripción ${i + 1}',
                suffixIcon: _items.length > 1
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _items.removeAt(i)),
                      )
                    : null,
              ),
              onChanged: (v) => it.descripcion = v,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: it.unidad ?? '',
                    decoration: const InputDecoration(labelText: 'Unidad'),
                    onChanged: (v) => it.unidad = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: it.cantidad.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cant.'),
                    onChanged: (v) => setState(
                        () => it.cantidad = double.tryParse(v) ?? 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: it.precioUnitario == 0
                        ? ''
                        : it.precioUnitario.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'P. Unit.'),
                    onChanged: (v) => setState(
                        () => it.precioUnitario = double.tryParse(v) ?? 0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

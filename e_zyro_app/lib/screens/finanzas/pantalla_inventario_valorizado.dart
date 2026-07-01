import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../models/proyecto_models.dart' show MaterialBusqueda;
import '../../models/requerimiento_models.dart' show AlmacenItem;
import '../../services/finanzas_service.dart';
import '../../services/proyecto_service.dart';
import '../../services/requerimiento_service.dart';
import '../../utils/api_provider.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Inventario valorizado: kardex (saldo valorizado por material/almacén),
/// costo promedio vigente y registro de movimientos (ingreso/salida) que
/// generan asiento contable automático en el backend.
class PantallaInventarioValorizado extends StatefulWidget {
  const PantallaInventarioValorizado({super.key});
  @override
  State<PantallaInventarioValorizado> createState() => _PantallaInventarioValorizadoState();
}

class _PantallaInventarioValorizadoState extends State<PantallaInventarioValorizado> {
  FinanzasService? _svc;
  RequerimientoService? _reqSvc;
  ProyectoService? _proySvc;

  List<KardexFila> _kardex = [];
  List<AlmacenItem> _almacenes = [];
  bool _cargando = true;
  String? _error;
  String? _almacenFiltroId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getFinanzasService();
    _reqSvc = await getRequerimientoService();
    _proySvc = await getProyectoService();
    final almacenes = await _reqSvc!.getAlmacenes();
    if (mounted) setState(() => _almacenes = almacenes);
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final r = await _svc!.kardexValorizado(almacen: _almacenFiltroId);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _kardex = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  String _nombreAlmacen(String? id) {
    if (id == null) return '—';
    final a = _almacenes.where((x) => x.id == id).toList();
    return a.isEmpty ? id : a.first.nombre;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventario valorizado', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Kardex'), Tab(text: 'Costo promedio')]),
          actions: [
            accionConmutadorFinanzas(context, actual: FinId.inventario),
            IconButton(
              tooltip: 'Filtrar por almacén',
              icon: const Icon(Icons.warehouse_outlined),
              onPressed: _filtrarAlmacen,
            ),
            IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
          ],
        ),
        // Solo lectura: el inventario se mueve y valoriza desde Logística.
        body: TabBarView(children: [_tabKardex(), _tabCostoPromedio()]),
      ),
    );
  }

  Future<void> _filtrarAlmacen() async {
    final elegido = await showModalBottomSheet<String?>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Todos los almacenes'),
              onTap: () => Navigator.pop(context, ''),
            ),
            ..._almacenes.map((a) => ListTile(
                  title: Text(a.nombre),
                  subtitle: a.ubicacion != null ? Text(a.ubicacion!) : null,
                  onTap: () => Navigator.pop(context, a.id),
                )),
          ],
        ),
      ),
    );
    if (elegido != null) {
      setState(() => _almacenFiltroId = elegido.isEmpty ? null : elegido);
      await _cargar();
    }
  }

  Widget _tabKardex() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_kardex.isEmpty) {
      return const EstadoVacio(
        icono: Icons.warehouse,
        titulo: 'Sin movimientos valorizados',
        subtitulo: 'Cuando registres entradas y salidas, el Kardex valorizado aparecerá aquí.',
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _kardex.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final f = _kardex[i];
          return ListTile(
            dense: true,
            leading: const CircleAvatar(
              backgroundColor: Color(0x1A3F51B5),
              child: Icon(Icons.inventory_2_outlined, color: Colors.indigo, size: 20),
            ),
            title: Text(
              f.materialNombre ?? f.materialId,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${f.materialCodigo != null && f.materialCodigo!.isNotEmpty ? '${f.materialCodigo} · ' : ''}'
              'Almacén: ${f.almacenNombre ?? _nombreAlmacen(f.almacenId)}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Text(money(f.saldoValorizado), style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        },
      ),
    );
  }

  Widget _tabCostoPromedio() {
    return _BuscadorCostoPromedio(svc: _svc, proySvc: _proySvc, almacenes: _almacenes);
  }
}

/// Búsqueda de material + selección de almacén para consultar costo promedio vigente.
class _BuscadorCostoPromedio extends StatefulWidget {
  final FinanzasService? svc;
  final ProyectoService? proySvc;
  final List<AlmacenItem> almacenes;
  const _BuscadorCostoPromedio({required this.svc, required this.proySvc, required this.almacenes});
  @override
  State<_BuscadorCostoPromedio> createState() => _BuscadorCostoPromedioState();
}

class _BuscadorCostoPromedioState extends State<_BuscadorCostoPromedio> {
  final _busqueda = TextEditingController();
  Timer? _debounce;
  List<MaterialBusqueda> _resultados = [];
  bool _buscando = false;
  MaterialBusqueda? _materialElegido;
  String? _almacenId;
  CostoPromedio? _costo;
  bool _cargandoCosto = false;
  String? _error;

  @override
  void dispose() {
    _busqueda.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (widget.proySvc == null || q.trim().length < 2) {
        setState(() => _resultados = []);
        return;
      }
      setState(() => _buscando = true);
      final r = await widget.proySvc!.buscarMateriales(q);
      if (!mounted) return;
      setState(() { _resultados = r; _buscando = false; });
    });
  }

  Future<void> _consultar() async {
    if (widget.svc == null || _materialElegido == null || _almacenId == null) return;
    setState(() { _cargandoCosto = true; _error = null; });
    final r = await widget.svc!.costoPromedio(_materialElegido!.id, _almacenId!);
    if (!mounted) return;
    setState(() {
      _cargandoCosto = false;
      if (r.ok) {
        _costo = r.data;
      } else {
        _costo = null;
        _error = r.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _busqueda,
          decoration: InputDecoration(
            labelText: 'Buscar material',
            border: const OutlineInputBorder(),
            suffixIcon: _buscando ? const Padding(padding: EdgeInsets.all(12),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
          onChanged: _onChanged,
        ),
        if (_materialElegido != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Chip(
              label: Text('${_materialElegido!.nombre} (${_materialElegido!.unidad})'),
              onDeleted: () => setState(() { _materialElegido = null; _costo = null; }),
            ),
          )
        else if (_resultados.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _resultados.map((m) => ListTile(
                    dense: true,
                    title: Text(m.nombre, style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${m.unidad} · stock ${m.stock}', style: const TextStyle(fontSize: 11)),
                    onTap: () => setState(() {
                      _materialElegido = m;
                      _resultados = [];
                      _busqueda.text = m.nombre;
                      _costo = null;
                    }),
                  )).toList(),
            ),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _almacenId,
          decoration: const InputDecoration(labelText: 'Almacén', border: OutlineInputBorder(), isDense: true),
          items: widget.almacenes.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))).toList(),
          onChanged: (v) => setState(() { _almacenId = v; _costo = null; }),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: (_materialElegido != null && _almacenId != null) ? _consultar : null,
          icon: const Icon(Icons.search),
          label: const Text('Consultar costo promedio'),
        ),
        const SizedBox(height: 16),
        if (_cargandoCosto)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red))
        else if (_costo != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: TarjetaResumen(titulo: 'Cantidad actual', valor: _costo!.cantidadActual.toStringAsFixed(2),
                        color: Colors.indigo, icono: Icons.inventory_outlined)),
                    const SizedBox(width: 10),
                    Expanded(child: TarjetaResumen(titulo: 'Costo promedio', valor: money(_costo!.costoPromedioActual),
                        color: Colors.teal, icono: Icons.calculate_outlined)),
                  ]),
                  const SizedBox(height: 10),
                  TarjetaResumen(titulo: 'Valor actual', valor: money(_costo!.valorActual),
                      color: Colors.green, icono: Icons.account_balance_wallet_outlined),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

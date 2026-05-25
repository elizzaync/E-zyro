import 'dart:async';
import 'package:flutter/material.dart';
import '../models/requerimiento_models.dart';
import '../services/requerimiento_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);
const _kCyan = Color(0xFF06B6D4);

/// Fase 6 — Transferencia de stock entre almacenes.
class PantallaTransferenciasLogistica extends StatefulWidget {
  const PantallaTransferenciasLogistica({super.key});

  @override
  State<PantallaTransferenciasLogistica> createState() =>
      _PantallaTransferenciasLogisticaState();
}

class _PantallaTransferenciasLogisticaState
    extends State<PantallaTransferenciasLogistica> {
  RequerimientoService? _service;
  List<AlmacenItem> _almacenes = [];
  bool _isLoading = true;

  // Form
  CatalogoItem? _material;
  String? _origenId;
  String? _destinoId;
  final _cantidadCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<CatalogoItem> _resultados = [];
  bool _buscando = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cantidadCtrl.dispose();
    _motivoCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getRequerimientoService();
    final alm = await _service!.getAlmacenes();
    if (!mounted) return;
    setState(() {
      _almacenes = alm;
      _isLoading = false;
    });
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _buscar(q));
  }

  Future<void> _buscar(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    final items = await _service!.getCatalogo(q, pageSize: 12);
    if (!mounted) return;
    setState(() {
      _resultados = items;
      _buscando = false;
    });
  }

  void _err(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: _kRed,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _transferir() async {
    final cantidad = int.tryParse(_cantidadCtrl.text.trim());
    if (_material == null) return _err('Selecciona un material');
    if (_origenId == null) return _err('Selecciona el almacén origen');
    if (_destinoId == null) return _err('Selecciona el almacén destino');
    if (_origenId == _destinoId) {
      return _err('El origen y destino deben ser distintos');
    }
    if (cantidad == null || cantidad < 1) return _err('Cantidad inválida');

    setState(() => _guardando = true);
    final res = await _service!.transferirStock(
      materialId: _material!.id,
      almacenOrigenId: _origenId!,
      almacenDestinoId: _destinoId!,
      cantidad: cantidad,
      motivo: _motivoCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Transferencia registrada'),
        backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating,
      ));
      // Limpiar form
      setState(() {
        _material = null;
        _origenId = null;
        _destinoId = null;
        _cantidadCtrl.clear();
        _motivoCtrl.clear();
      });
    } else {
      _err(res.error ?? 'No se pudo transferir');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.4);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Transferencias',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16,
        amp: 9,
        stroke: 0.38,
        speed: 0.45,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _kGreen))
            : _almacenes.length < 2
                ? _buildSinAlmacenes()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Material ─────────────────────────────────────
                        _label('Material'),
                        const SizedBox(height: 6),
                        if (_material != null)
                          _MaterialChip(
                            item: _material!,
                            onClear: () => setState(() => _material = null),
                          )
                        else ...[
                          TextField(
                            controller: _searchCtrl,
                            onChanged: _onSearch,
                            decoration: InputDecoration(
                              hintText: 'Buscar material...',
                              prefixIcon: const Icon(Icons.search,
                                  color: Colors.grey),
                              filled: true,
                              fillColor: fill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          if (_buscando)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                  child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: _kGreen))),
                            )
                          else if (_resultados.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              constraints:
                                  const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _resultados.length,
                                itemBuilder: (_, i) {
                                  final it = _resultados[i];
                                  return ListTile(
                                    dense: true,
                                    title: Text(it.nombre,
                                        style: const TextStyle(fontSize: 14)),
                                    subtitle: Text(
                                        'Stock: ${it.stock} ${it.unidad}',
                                        style: const TextStyle(fontSize: 11)),
                                    onTap: () => setState(() {
                                      _material = it;
                                      _resultados = [];
                                      _searchCtrl.clear();
                                    }),
                                  );
                                },
                              ),
                            ),
                        ],
                        const SizedBox(height: 18),

                        // ── Origen → Destino ─────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Desde'),
                                  const SizedBox(height: 6),
                                  _dropAlmacen(
                                    value: _origenId,
                                    fill: fill,
                                    onChanged: (v) =>
                                        setState(() => _origenId = v),
                                  ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Icon(Icons.arrow_forward_rounded,
                                  color: _kCyan),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Hacia'),
                                  const SizedBox(height: 6),
                                  _dropAlmacen(
                                    value: _destinoId,
                                    fill: fill,
                                    onChanged: (v) =>
                                        setState(() => _destinoId = v),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // ── Cantidad ─────────────────────────────────────
                        _label('Cantidad'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _cantidadCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '0',
                            filled: true,
                            fillColor: fill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // ── Motivo ───────────────────────────────────────
                        _label('Motivo (opcional)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _motivoCtrl,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Ej: reabastecer almacén de obra...',
                            filled: true,
                            fillColor: fill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _guardando ? null : _transferir,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kCyan,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _guardando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.compare_arrows_rounded),
                            label: const Text('Transferir',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _label(String t) =>
      Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));

  Widget _dropAlmacen({
    required String? value,
    required Color fill,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        hintText: 'Almacén',
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: _almacenes
          .map((a) => DropdownMenuItem(
                value: a.id,
                child: Text(a.nombre, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildSinAlmacenes() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warehouse_outlined, size: 52, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            const Text('Se necesitan al menos 2 almacenes',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
                'Las transferencias mueven stock entre dos almacenes distintos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _MaterialChip extends StatelessWidget {
  final CatalogoItem item;
  final VoidCallback onClear;
  const _MaterialChip({required this.item, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kCyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kCyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: _kCyan, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text('Stock total: ${item.stock} ${item.unidad}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

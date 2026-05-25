import 'dart:async';
import 'package:flutter/material.dart';
import '../models/compras_models.dart';
import '../models/requerimiento_models.dart';
import '../services/compras_service.dart';
import '../services/requerimiento_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kBlue = Color(0xFF3B82F6);

/// Fase 5 — Órdenes de compra + recepción de mercadería.
class PantallaComprasLogistica extends StatefulWidget {
  const PantallaComprasLogistica({super.key});

  @override
  State<PantallaComprasLogistica> createState() =>
      _PantallaComprasLogisticaState();
}

class _PantallaComprasLogisticaState extends State<PantallaComprasLogistica> {
  ComprasService? _service;
  RequerimientoService? _reqService;
  List<OrdenCompra> _ordenes = [];
  bool _isLoading = true;
  String _filtro = 'todos';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getComprasService();
    _reqService = await getRequerimientoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final estado = _filtro == 'todos' ? null : _filtro;
    final data = await _service!.getOrdenes(estado: estado);
    if (!mounted) return;
    setState(() {
      _ordenes = data;
      _isLoading = false;
    });
  }

  void _setFiltro(String f) {
    setState(() => _filtro = f);
    _load();
  }

  void _msg(bool ok, String okMsg, String errMsg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? okMsg : errMsg),
      backgroundColor: ok ? _kGreen : _kRed,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _nuevaOrden() async {
    final proveedores = await _service!.getProveedores();
    if (!mounted) return;
    if (proveedores.isEmpty) {
      _msg(false, '', 'Primero registra un proveedor');
      return;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NuevaOrdenSheet(
        service: _service!,
        reqService: _reqService!,
        proveedores: proveedores,
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _abrirDetalle(OrdenCompra orden) async {
    final completa = await _service!.getOrden(orden.id);
    if (!mounted || completa == null) return;
    final accion = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetalleOrdenSheet(orden: completa),
    );
    if (accion == null) return;
    if (accion == 'recibir') {
      await _recibir(orden);
    } else if (accion == 'cancelar') {
      await _cancelar(orden);
    }
  }

  Future<void> _recibir(OrdenCompra orden) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recibir mercadería'),
        content: const Text(
            'Se sumará al stock la cantidad de cada material de la orden. ¿Confirmar recepción?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Recibir', style: TextStyle(color: _kGreen))),
        ],
      ),
    );
    if (confirmar != true) return;
    final ok = await _service!.recibirOrden(orden.id);
    _msg(ok, 'Mercadería recibida y sumada al stock', 'No se pudo recibir');
    if (ok) await _load();
  }

  Future<void> _cancelar(OrdenCompra orden) async {
    final ok = await _service!.cambiarEstadoOrden(orden.id, 'cancelada');
    _msg(ok, 'Orden cancelada', 'No se pudo cancelar');
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Compras',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _service == null ? null : _nuevaOrden,
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('Nueva orden',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16,
        amp: 9,
        stroke: 0.38,
        speed: 0.45,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Chip(
                        label: 'Todos',
                        selected: _filtro == 'todos',
                        onTap: () => _setFiltro('todos')),
                    _Chip(
                        label: 'Enviadas',
                        selected: _filtro == 'enviada',
                        color: _kBlue,
                        onTap: () => _setFiltro('enviada')),
                    _Chip(
                        label: 'En tránsito',
                        selected: _filtro == 'en_transito',
                        color: _kAmber,
                        onTap: () => _setFiltro('en_transito')),
                    _Chip(
                        label: 'Recibidas',
                        selected: _filtro == 'recibida',
                        color: _kGreen,
                        onTap: () => _setFiltro('recibida')),
                    _Chip(
                        label: 'Canceladas',
                        selected: _filtro == 'cancelada',
                        color: _kRed,
                        onTap: () => _setFiltro('cancelada')),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kGreen))
                  : _ordenes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shopping_cart_outlined,
                                  size: 52, color: Colors.grey.shade400),
                              const SizedBox(height: 14),
                              const Text('Sin órdenes de compra',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _kGreen,
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 90),
                            itemCount: _ordenes.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _OrdenCard(
                              orden: _ordenes[i],
                              onTap: () => _abrirDetalle(_ordenes[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── estado helpers ──────────────────────────────────────────────────────────
({Color color, String label}) _estadoCfg(String estado) => switch (estado) {
      'enviada' => (color: _kBlue, label: 'Enviada'),
      'confirmada' => (color: _kBlue, label: 'Confirmada'),
      'en_transito' => (color: _kAmber, label: 'En tránsito'),
      'recibida' => (color: _kGreen, label: 'Recibida'),
      'cancelada' => (color: _kRed, label: 'Cancelada'),
      _ => (color: Colors.grey, label: 'Borrador'),
    };

// ─── Chip de filtro ──────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    this.color = _kGreen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color
                : (isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.grey.shade300),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            )),
      ),
    );
  }
}

// ─── Card de orden ───────────────────────────────────────────────────────────
class _OrdenCard extends StatelessWidget {
  final OrdenCompra orden;
  final VoidCallback onTap;

  const _OrdenCard({required this.orden, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final cfg = _estadoCfg(orden.estado);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(color: cfg.color.withValues(alpha: 0.30))
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(orden.proveedorNombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: cfg.color.withValues(alpha: isDark ? 0.15 : 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(cfg.label,
                      style: TextStyle(
                          color: cfg.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${orden.totalItems} items',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_today_outlined,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(orden.fechaEmision,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const Spacer(),
                if (orden.totalReferencial > 0)
                  Text('S/ ${orden.totalReferencial.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet: detalle de orden ─────────────────────────────────────────────────
class _DetalleOrdenSheet extends StatelessWidget {
  final OrdenCompra orden;
  const _DetalleOrdenSheet({required this.orden});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final cfg = _estadoCfg(orden.estado);
    final puedeRecibir =
        orden.estado != 'recibida' && orden.estado != 'cancelada';

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(orden.proveedorNombre,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: cfg.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(cfg.label,
                      style: TextStyle(
                          color: cfg.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Emitida: ${orden.fechaEmision}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (orden.fechaEntregaEstimada != null)
              Text('Entrega estimada: ${orden.fechaEntregaEstimada}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const Text('Materiales',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...orden.items.map((it) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.fiber_manual_record,
                          size: 7, color: _kGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(it.materialNombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text('${it.cantidad} ${it.unidad}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      if (it.precioUnitario > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                              'S/ ${(it.precioUnitario * it.cantidad).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ),
                    ],
                  ),
                )),
            if (orden.totalReferencial > 0) ...[
              const SizedBox(height: 6),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total referencial',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('S/ ${orden.totalReferencial.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
            const SizedBox(height: 18),
            if (puedeRecibir)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'cancelar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kRed,
                        side: const BorderSide(color: _kRed),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Cancelar OC'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, 'recibir'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.inventory_rounded, size: 16),
                      label: const Text('Recibir'),
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

// ─── Sheet: nueva orden ──────────────────────────────────────────────────────
class _NuevaOrdenSheet extends StatefulWidget {
  final ComprasService service;
  final RequerimientoService reqService;
  final List<Proveedor> proveedores;

  const _NuevaOrdenSheet({
    required this.service,
    required this.reqService,
    required this.proveedores,
  });

  @override
  State<_NuevaOrdenSheet> createState() => _NuevaOrdenSheetState();
}

class _ItemNuevo {
  final CatalogoItem material;
  int cantidad = 1;
  double precio = 0;
  _ItemNuevo({required this.material});
}

class _NuevaOrdenSheetState extends State<_NuevaOrdenSheet> {
  String? _proveedorId;
  final List<_ItemNuevo> _items = [];
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<CatalogoItem> _resultados = [];
  bool _buscando = false;
  bool _guardando = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
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
    final items = await widget.reqService.getCatalogo(q, pageSize: 12);
    if (!mounted) return;
    setState(() {
      _resultados = items;
      _buscando = false;
    });
  }

  void _agregar(CatalogoItem mat) {
    if (_items.any((i) => i.material.id == mat.id)) return;
    setState(() {
      _items.add(_ItemNuevo(material: mat));
      _resultados = [];
      _searchCtrl.clear();
    });
  }

  double get _total =>
      _items.fold(0.0, (s, it) => s + it.precio * it.cantidad);

  Future<void> _guardar() async {
    if (_proveedorId == null) {
      _err('Selecciona un proveedor');
      return;
    }
    if (_items.isEmpty) {
      _err('Agrega al menos un material');
      return;
    }
    setState(() => _guardando = true);
    final ok = await widget.service.crearOrden(
      proveedorId: _proveedorId!,
      items: _items
          .map((it) => {
                'material_id': it.material.id,
                'cantidad': it.cantidad,
                'precio_unitario': it.precio,
              })
          .toList(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      _err('No se pudo crear la orden');
    }
  }

  void _err(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: _kRed,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final fill = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.4);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Nueva orden de compra',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Proveedor',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _proveedorId,
              isExpanded: true,
              decoration: InputDecoration(
                hintText: 'Selecciona...',
                filled: true,
                fillColor: fill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: widget.proveedores
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.razonSocial,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _proveedorId = v),
            ),
            const SizedBox(height: 16),
            const Text('Materiales',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Buscar material para agregar...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _resultados.length,
                  itemBuilder: (_, i) {
                    final it = _resultados[i];
                    return ListTile(
                      dense: true,
                      title: Text(it.nombre,
                          style: const TextStyle(fontSize: 14)),
                      subtitle: Text('Stock: ${it.stock} ${it.unidad}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: const Icon(Icons.add_circle_outline,
                          color: _kGreen, size: 20),
                      onTap: () => _agregar(it),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),

            // ── Items agregados ────────────────────────────────────────────
            ..._items.asMap().entries.map((e) {
              final idx = e.key;
              final it = e.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(it.material.nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              setState(() => _items.removeAt(idx)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Cantidad',
                              isDense: true,
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            controller: TextEditingController(
                                text: it.cantidad.toString()),
                            onChanged: (v) =>
                                it.cantidad = int.tryParse(v) ?? 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Precio unit.',
                              isDense: true,
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            controller: TextEditingController(
                                text: it.precio > 0
                                    ? it.precio.toString()
                                    : ''),
                            onChanged: (v) =>
                                it.precio = double.tryParse(v) ?? 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),

            if (_items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total referencial',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('S/ ${_total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Crear orden',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

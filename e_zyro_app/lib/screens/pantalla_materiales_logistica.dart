import 'dart:async';
import 'package:flutter/material.dart';
import '../models/requerimiento_models.dart';
import '../services/requerimiento_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);

/// Fase 4 — Gestión de materiales: editar / eliminar + administrar categorías.
class PantallaMaterialesLogistica extends StatefulWidget {
  const PantallaMaterialesLogistica({super.key});

  @override
  State<PantallaMaterialesLogistica> createState() =>
      _PantallaMaterialesLogisticaState();
}

class _PantallaMaterialesLogisticaState
    extends State<PantallaMaterialesLogistica> {
  RequerimientoService? _service;
  List<CatalogoItem> _items = [];
  List<CategoriaItem> _categorias = [];
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getRequerimientoService();
    await Future.wait([_loadMateriales(), _loadCategorias()]);
  }

  Future<void> _loadMateriales() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final data = await _service!.getCatalogo(_searchCtrl.text, pageSize: 50);
    if (!mounted) return;
    setState(() {
      _items = data;
      _isLoading = false;
    });
  }

  Future<void> _loadCategorias() async {
    if (_service == null) return;
    final cats = await _service!.getCategorias();
    if (!mounted) return;
    setState(() => _categorias = cats);
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadMateriales);
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

  Future<void> _editar(CatalogoItem item) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditarMaterialSheet(
        service: _service!,
        item: item,
        categorias: _categorias,
      ),
    );
    if (ok == true) await _loadMateriales();
  }

  Future<void> _eliminar(CatalogoItem item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar material'),
        content: Text(
            '¿Eliminar "${item.nombre}" del inventario? Esta acción lo desactiva.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar', style: TextStyle(color: _kRed))),
        ],
      ),
    );
    if (confirmar != true) return;
    final ok = await _service!.eliminarMaterial(item.id);
    _msg(ok, 'Material eliminado', 'No se pudo eliminar');
    if (ok) await _loadMateriales();
  }

  Future<void> _gestionarCategorias() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoriasSheet(
        service: _service!,
        categorias: _categorias,
      ),
    );
    await _loadCategorias();
    await _loadMateriales();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Materiales',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          TextButton.icon(
            onPressed: _service == null ? null : _gestionarCategorias,
            icon: const Icon(Icons.category_outlined, size: 18, color: _kGreen),
            label: const Text('Categorías',
                style: TextStyle(color: _kGreen, fontWeight: FontWeight.w600)),
          ),
        ],
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
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Buscar materiales...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kGreen))
                  : _items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text('Sin materiales',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 14)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadMateriales,
                          color: _kGreen,
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _MaterialRow(
                              item: _items[i],
                              onEditar: () => _editar(_items[i]),
                              onEliminar: () => _eliminar(_items[i]),
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

// ─── Fila de material ────────────────────────────────────────────────────────
class _MaterialRow extends StatelessWidget {
  final CatalogoItem item;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _MaterialRow({
    required this.item,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final bajo = item.stockMinimo > 0 && item.stock <= item.stockMinimo;
    final stockColor =
        item.stock == 0 ? _kRed : (bajo ? _kAmber : _kGreen);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: stockColor),
                    const SizedBox(width: 5),
                    Text('${item.stock} ${item.unidad}',
                        style: TextStyle(
                            color: stockColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    if (item.stockMinimo > 0) ...[
                      const SizedBox(width: 6),
                      Text('· mín ${item.stockMinimo}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                    ],
                    if (item.categoria != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('· ${item.categoria}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: _kGreen),
            onPressed: onEditar,
            tooltip: 'Editar',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: _kRed),
            onPressed: onEliminar,
            tooltip: 'Eliminar',
          ),
        ],
      ),
    );
  }
}

// ─── Sheet: editar material ──────────────────────────────────────────────────
class _EditarMaterialSheet extends StatefulWidget {
  final RequerimientoService service;
  final CatalogoItem item;
  final List<CategoriaItem> categorias;

  const _EditarMaterialSheet({
    required this.service,
    required this.item,
    required this.categorias,
  });

  @override
  State<_EditarMaterialSheet> createState() => _EditarMaterialSheetState();
}

class _EditarMaterialSheetState extends State<_EditarMaterialSheet> {
  late final TextEditingController _nombre;
  late final TextEditingController _codigo;
  late final TextEditingController _unidad;
  late final TextEditingController _descripcion;
  late final TextEditingController _minimo;
  String? _categoriaId;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.item.nombre);
    _codigo = TextEditingController(text: widget.item.codigo ?? '');
    _unidad = TextEditingController(text: widget.item.unidad);
    _descripcion = TextEditingController(text: widget.item.descripcion ?? '');
    _minimo = TextEditingController(
        text: widget.item.stockMinimo > 0
            ? widget.item.stockMinimo.toString()
            : '');
    // Inferir categoría seleccionada por nombre
    final match = widget.categorias
        .where((c) => c.nombre == widget.item.categoria)
        .toList();
    _categoriaId = match.isNotEmpty ? match.first.id : null;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _codigo.dispose();
    _unidad.dispose();
    _descripcion.dispose();
    _minimo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty || _unidad.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nombre y unidad son obligatorios'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _guardando = true);
    final ok = await widget.service.editarMaterial(
      widget.item.id,
      nombre: _nombre.text.trim(),
      codigo: _codigo.text.trim(),
      unidad: _unidad.text.trim(),
      descripcion: _descripcion.text.trim(),
      categoriaId: _categoriaId,
      cantidadMinima: int.tryParse(_minimo.text.trim()),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo guardar'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
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
            const Text('Editar material',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Nombre',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(controller: _nombre, decoration: _dec('Nombre')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Código',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                          controller: _codigo, decoration: _dec('Opcional')),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Unidad',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                          controller: _unidad, decoration: _dec('ej: und')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Categoría',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _categoriaId,
              isExpanded: true,
              decoration: _dec('Sin categoría'),
              items: widget.categorias
                  .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.nombre,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _categoriaId = v),
            ),
            const SizedBox(height: 12),
            const Text('Stock mínimo (alerta de bajo stock)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
                controller: _minimo,
                keyboardType: TextInputType.number,
                decoration: _dec('0 = sin alerta')),
            const SizedBox(height: 12),
            const Text('Descripción',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
                controller: _descripcion,
                maxLines: 2,
                decoration: _dec('Opcional')),
            const SizedBox(height: 20),
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
                    : const Text('Guardar cambios',
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

// ─── Sheet: gestionar categorías ─────────────────────────────────────────────
class _CategoriasSheet extends StatefulWidget {
  final RequerimientoService service;
  final List<CategoriaItem> categorias;

  const _CategoriasSheet({required this.service, required this.categorias});

  @override
  State<_CategoriasSheet> createState() => _CategoriasSheetState();
}

class _CategoriasSheetState extends State<_CategoriasSheet> {
  late List<CategoriaItem> _cats;
  final _nuevaCtrl = TextEditingController();
  bool _creando = false;

  @override
  void initState() {
    super.initState();
    _cats = List.from(widget.categorias);
  }

  @override
  void dispose() {
    _nuevaCtrl.dispose();
    super.dispose();
  }

  Future<void> _refrescar() async {
    final cats = await widget.service.getCategorias();
    if (!mounted) return;
    setState(() => _cats = cats);
  }

  Future<void> _crear() async {
    final nombre = _nuevaCtrl.text.trim();
    if (nombre.isEmpty) return;
    setState(() => _creando = true);
    final ok = await widget.service.crearCategoria(nombre);
    if (!mounted) return;
    setState(() => _creando = false);
    if (ok) {
      _nuevaCtrl.clear();
      await _refrescar();
    } else {
      _err('No se pudo crear la categoría');
    }
  }

  Future<void> _eliminar(CategoriaItem c) async {
    final res = await widget.service.eliminarCategoria(c.id);
    if (!mounted) return;
    if (res.ok) {
      await _refrescar();
    } else {
      _err(res.error ?? 'No se pudo eliminar');
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
          const Text('Categorías',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // Crear nueva
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nuevaCtrl,
                  decoration: InputDecoration(
                    hintText: 'Nueva categoría...',
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _creando ? null : _crear,
                style: IconButton.styleFrom(backgroundColor: _kGreen),
                icon: _creando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_cats.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('Sin categorías',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _cats.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.label_outline, color: _kGreen),
                  title: Text(_cats[i].nombre,
                      style: const TextStyle(fontSize: 14)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: _kRed),
                    onPressed: () => _eliminar(_cats[i]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

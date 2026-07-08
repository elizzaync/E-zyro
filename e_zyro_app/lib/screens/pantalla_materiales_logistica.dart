import 'dart:async';
import 'package:flutter/material.dart';
import '../models/requerimiento_models.dart';
import '../services/requerimiento_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../widgets/topo_background.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);

/// Materiales consumibles — gestión de catálogo.
/// Las herramientas están en PantallaEquiposLogistica (clase='herramienta').
class PantallaMaterialesLogistica extends StatefulWidget {
  const PantallaMaterialesLogistica({super.key});

  @override
  State<PantallaMaterialesLogistica> createState() =>
      _PantallaMaterialesLogisticaState();
}

class _PantallaMaterialesLogisticaState
    extends State<PantallaMaterialesLogistica>
    with TickerProviderStateMixin {
  static const _pageSize = 30;

  RequerimientoService? _service;
  List<CatalogoItem> _materiales = [];
  List<CategoriaItem> _categorias = [];
  CatalogoResumen _resumen = const CatalogoResumen();

  bool _isLoading = true;     // carga inicial / reset
  bool _loadingMore = false;  // paginación incremental
  bool _hasMore = true;
  int _page = 1;

  // ── Filtros activos ────────────────────────────────────────────────────────
  String _estadoStock = 'todos';   // todos | con_stock | bajo | agotado
  String? _categoriaSel;           // null = todas
  String _orden = 'nombre';        // nombre | stock_desc | stock_asc | reciente

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getRequerimientoService();
    await Future.wait([_loadMateriales(reset: true), _loadCategorias()]);
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || _isLoading) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadMateriales({bool reset = false}) async {
    if (_service == null) return;
    if (reset) {
      setState(() {
        _isLoading = true;
        _page = 1;
        _hasMore = true;
      });
    }
    final results = await Future.wait([
      _service!.getCatalogo(
        _searchCtrl.text,
        tipo: 'consumible',
        categoria: _categoriaSel,
        estadoStock: _estadoStock,
        orden: _orden,
        page: 1,
        pageSize: _pageSize,
      ),
      _service!.getCatalogoResumen(
        q: _searchCtrl.text,
        tipo: 'consumible',
        categoria: _categoriaSel,
      ),
    ]);
    if (!mounted) return;
    final items = results[0] as List<CatalogoItem>;
    setState(() {
      _materiales = items;
      _resumen    = results[1] as CatalogoResumen;
      _hasMore    = items.length >= _pageSize;
      _page       = 1;
      _isLoading  = false;
    });
  }

  Future<void> _loadMore() async {
    if (_service == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final items = await _service!.getCatalogo(
      _searchCtrl.text,
      tipo: 'consumible',
      categoria: _categoriaSel,
      estadoStock: _estadoStock,
      orden: _orden,
      page: next,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _materiales.addAll(items);
      _page = next;
      _hasMore = items.length >= _pageSize;
      _loadingMore = false;
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
    _debounce = Timer(const Duration(milliseconds: 350),
        () => _loadMateriales(reset: true));
  }

  void _setEstado(String e) {
    setState(() => _estadoStock = _estadoStock == e ? 'todos' : e);
    _loadMateriales(reset: true);
  }

  void _setCategoria(String? c) {
    setState(() => _categoriaSel = c);
    _loadMateriales(reset: true);
  }

  void _setOrden(String o) {
    setState(() => _orden = o);
    _loadMateriales(reset: true);
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
    if (ok == true) await _loadMateriales(reset: true);
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
    if (ok) await _loadMateriales(reset: true);
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
    await _loadMateriales(reset: true);
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
            // ── Buscador + orden ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearch,
                      decoration: InputDecoration(
                        hintText: 'Buscar por nombre o código...',
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _loadMateriales(reset: true);
                                },
                              )
                            : null,
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
                  const SizedBox(width: 8),
                  _ordenButton(),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ── Chips de estado de stock (con conteos) ─────────────────────
            _estadoChips(),
            // ── Chips de categoría ─────────────────────────────────────────
            if (_categorias.isNotEmpty) _categoriaChips(),
            const SizedBox(height: 4),
            // ── Lista ───────────────────────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _kGreen))
                  : _listaItems(_materiales),
            ),
          ],
        ),
      ),
    );
  }

  // ── Menú de ordenamiento ──────────────────────────────────────────────────
  Widget _ordenButton() {
    const labels = {
      'nombre': 'Nombre (A-Z)',
      'stock_desc': 'Mayor stock',
      'stock_asc': 'Menor stock',
      'reciente': 'Más reciente',
    };
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.sort_rounded, color: _kGreen),
        tooltip: 'Ordenar',
        onSelected: _setOrden,
        itemBuilder: (_) => labels.entries
            .map((e) => PopupMenuItem(
                  value: e.key,
                  child: Row(children: [
                    Icon(
                      _orden == e.key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: _orden == e.key ? _kGreen : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    Text(e.value),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  // ── Chips de estado de stock con conteos (actúan de filtro) ───────────────
  Widget _estadoChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _statChip('Todos', _resumen.total, 'todos', _kGreen),
          _statChip('Con stock', _resumen.conStock, 'con_stock', _kGreen),
          _statChip('Bajo mínimo', _resumen.bajo, 'bajo', _kAmber),
          _statChip('Agotado', _resumen.agotado, 'agotado', _kRed),
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, String value, Color color) {
    final sel = _estadoStock == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _setEstado(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? color : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? color : Colors.grey.shade300),
          ),
          child: Row(children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : null)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: sel
                    ? Colors.white.withValues(alpha: 0.25)
                    : color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : color)),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Chips de categoría ─────────────────────────────────────────────────────
  Widget _categoriaChips() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _catChip('Todas', null),
            ..._categorias.map((c) => _catChip(c.nombre, c.nombre)),
          ],
        ),
      ),
    );
  }

  Widget _catChip(String label, String? value) {
    final sel = _categoriaSel == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _setCategoria(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? _kGreen.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: sel ? _kGreen : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? _kGreen : Colors.grey.shade600)),
        ),
      ),
    );
  }

  Widget _listaItems(List<CatalogoItem> items) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          _searchCtrl.text.isNotEmpty
              ? 'Sin resultados para "${_searchCtrl.text}"'
              : 'Sin registros con estos filtros',
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ]));
    }
    return RefreshIndicator(
      onRefresh: () => _loadMateriales(reset: true),
      color: _kGreen,
      child: ListView.separated(
        controller: _scrollCtrl,
        padding: bottomSafePadding(context, top: 8, extra: 24),
        itemCount: items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == items.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen)),
              ),
            );
          }
          return _MaterialRow(
            item: items[i],
            onEditar: () => _editar(items[i]),
            onEliminar: () => _eliminar(items[i]),
          );
        },
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

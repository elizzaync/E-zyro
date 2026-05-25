import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../models/requerimiento_models.dart';
import '../utils/app_session.dart';
import '../models/proyecto_models.dart';
import '../services/requerimiento_service.dart';
import '../services/proyecto_service.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';
import 'pantalla_inventario_panel.dart';

// ── Private carrito entry ─────────────────────────────────────────────────────
class _CarritoEntry {
  final CatalogoItem item;
  int cantidad;
  _CarritoEntry({required this.item, required this.cantidad});
}

// ── Main Screen ───────────────────────────────────────────────────────────────
class LogisticsScreen extends StatefulWidget {
  const LogisticsScreen({super.key});

  @override
  State<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends State<LogisticsScreen> {
  static const _green = Color(0xFF8FD11B);
  static const _pageSize = 30;

  RequerimientoService? _service;
  ProyectoService? _proyectoService;

  bool _showCatalogo = true;

  List<CatalogoItem> _catalogoItems = [];
  bool _loadingCatalogo = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;

  // HU-15: Filtro por categoría
  String? _selectedCategoria;
  List<String> _categorias = [];

  // HU-16: FCM listener para aviso_logistica
  StreamSubscription<RemoteMessage>? _fcmSub;

  List<MiSolicitud> _solicitudes = [];
  bool _loadingSolicitudes = false;
  bool _solicitudesLoaded = false;

  final Map<String, _CarritoEntry> _carrito = {};

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  List<ProyectoItem> _proyectos = [];
  bool _puedeGestionar = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _checkRol();
    _fcmSub = FcmFlutterService.messageStream.listen((msg) {
      if ((msg.data['tipo'] as String?) == 'aviso_logistica') {
        if (!_showCatalogo) {
          _loadSolicitudes();
        } else {
          _switchTab(false);
        }
      }
    });
    _init();
  }

  Future<void> _checkRol() async {
    await AppSession.load();
    if (mounted) setState(() => _puedeGestionar = AppSession.i.canGestInventario);
  }

  Future<void> _init() async {
    _service = await getRequerimientoService();
    _proyectoService = await getProyectoService();
    await _loadCatalogo();
  }

  void _onScroll() {
    if (!_showCatalogo || _loadingMore || !_hasMore || _loadingCatalogo) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadCatalogo() async {
    if (_service == null) return;
    setState(() {
      _loadingCatalogo = true;
      _currentPage = 1;
      _hasMore = true;
    });
    final items = await _service!.getCatalogo(
      _searchCtrl.text,
      categoria: _selectedCategoria,
      page: 1,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _catalogoItems = items;
      _hasMore = items.length >= _pageSize;
      // Extract categories on initial full load (no filters active)
      if (_selectedCategoria == null &&
          _searchCtrl.text.isEmpty &&
          _categorias.isEmpty) {
        final cats = items
            .map((e) => e.categoria)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
        _categorias = cats;
      }
      _loadingCatalogo = false;
    });
  }

  Future<void> _loadMore() async {
    if (_service == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _currentPage + 1;
    final items = await _service!.getCatalogo(
      _searchCtrl.text,
      categoria: _selectedCategoria,
      page: nextPage,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _catalogoItems.addAll(items);
      _currentPage = nextPage;
      _hasMore = items.length >= _pageSize;
      _loadingMore = false;
    });
  }

  Future<void> _loadSolicitudes() async {
    if (_service == null) return;
    setState(() => _loadingSolicitudes = true);
    final items = await _service!.getMisSolicitudes();
    if (!mounted) return;
    setState(() {
      _solicitudes = items;
      _loadingSolicitudes = false;
      _solicitudesLoaded = true;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _loadCatalogo);
  }

  void _switchTab(bool toCatalogo) {
    setState(() => _showCatalogo = toCatalogo);
    if (!toCatalogo && !_solicitudesLoaded) _loadSolicitudes();
  }

  void _selectCategoria(String? cat) {
    setState(() => _selectedCategoria = cat);
    _loadCatalogo();
  }

  void _addToCarrito(CatalogoItem item, int cantidad) {
    setState(() {
      if (_carrito.containsKey(item.id)) {
        _carrito[item.id]!.cantidad += cantidad;
      } else {
        _carrito[item.id] = _CarritoEntry(item: item, cantidad: cantidad);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.nombre} agregado al pedido'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _green,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  int get _carritoCount => _carrito.length;

  Future<void> _openCarritoSheet() async {
    if (_service == null) return;

    if (_proyectos.isEmpty && _proyectoService != null) {
      final data = await _proyectoService!.getProyectos();
      if (mounted) setState(() => _proyectos = data?.proyectos ?? []);
    }

    if (!mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CarritoSheet(
        initialCarrito: Map.from(_carrito),
        proyectos: _proyectos,
        service: _service!,
        onCartChanged: (updated) {
          if (mounted) {
            setState(() {
              _carrito.clear();
              _carrito.addAll(updated);
            });
          }
        },
      ),
    );

    if (result == true && mounted) {
      setState(() => _carrito.clear());
      _switchTab(false);
      await _loadSolicitudes();
    }
  }

  void _openItemDetail(CatalogoItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemDetailSheet(
        item: item,
        cantidadEnCarrito: _carrito[item.id]?.cantidad ?? 0,
        onAgregar: (cantidad) => _addToCarrito(item, cantidad),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _openNuevoMaterialSheet() async {
    if (_service == null) return;

    List<CategoriaItem> categorias = [];
    List<AlmacenItem> almacenes = [];
    await Future.wait([
      _service!.getCategorias().then((v) => categorias = v),
      _service!.getAlmacenes().then((v) => almacenes = v),
    ]);

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NuevoMaterialSheet(
        categorias: categorias,
        almacenes: almacenes,
        service: _service!,
        onCreado: () {
          _loadCatalogo();
          messenger.showSnackBar(SnackBar(
            content: const Text('Material agregado al inventario'),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final toggleBg = isDark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Colors.grey.shade200;

    return TopoBackground(
      c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
      c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
      base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
      count: 18,
      amp: 10,
      stroke: 0.40,
      speed: 0.5,
      child: SafeArea(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Logística',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        // Acceso al panel del encargado (solo logística/admin)
                        if (_puedeGestionar)
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PantallaInventarioPanel(),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: _green,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: _green.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.dashboard_customize_outlined,
                                      color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text('Panel',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Container(
                      decoration: BoxDecoration(
                        color: toggleBg,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          _ToggleTab(
                            label: 'Catálogo',
                            isSelected: _showCatalogo,
                            onTap: () => _switchTab(true),
                          ),
                          _ToggleTab(
                            label: 'Mis Solicitudes',
                            isSelected: !_showCatalogo,
                            onTap: () => _switchTab(false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_showCatalogo) ...[
                      TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Buscar materiales...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _loadCatalogo();
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                      if (_categorias.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _CategoriaChip(
                                label: 'Todos',
                                selected: _selectedCategoria == null,
                                onTap: () => _selectCategoria(null),
                              ),
                              ..._categorias.map(
                                (cat) => _CategoriaChip(
                                  label: cat,
                                  selected: _selectedCategoria == cat,
                                  onTap: () => _selectCategoria(cat),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              Expanded(
                child: _showCatalogo ? _buildCatalogo() : _buildSolicitudes(),
              ),
            ],
          ),

          // FABs
          Positioned(
            right: 20,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // FAB agregar al inventario (solo logística/admin)
                if (_puedeGestionar && _showCatalogo) ...[
                  FloatingActionButton(
                    heroTag: 'fab_inventario',
                    onPressed: () => _openNuevoMaterialSheet(),
                    backgroundColor: Colors.white,
                    foregroundColor: _green,
                    elevation: 3,
                    mini: true,
                    tooltip: 'Agregar al inventario',
                    child: const Icon(Icons.add_box_outlined),
                  ),
                  const SizedBox(height: 10),
                ],
                // FAB solicitar materiales
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: 'fab_solicitar',
                      onPressed: _openCarritoSheet,
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: const Text('Solicitar',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (_carritoCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          child: Text('$_carritoCount',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildCatalogo() {
    if (_loadingCatalogo) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_catalogoItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isNotEmpty
                  ? 'Sin resultados para "${_searchCtrl.text}"'
                  : 'Sin materiales en el catálogo',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadCatalogo,
      child: ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        itemCount: _catalogoItems.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == _catalogoItems.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _CatalogoItemCard(
            item: _catalogoItems[i],
            cantidadEnCarrito: _carrito[_catalogoItems[i].id]?.cantidad ?? 0,
            onTap: () => _openItemDetail(_catalogoItems[i]),
          );
        },
      ),
    );
  }

  Widget _buildSolicitudes() {
    if (_loadingSolicitudes || !_solicitudesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_solicitudes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'Sin solicitudes registradas',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text(
              'Usa el catálogo para crear una solicitud',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSolicitudes,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        itemCount: _solicitudes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _MiSolicitudCard(item: _solicitudes[i]),
      ),
    );
  }
}

// ── Chip de categoría ─────────────────────────────────────────────────────────
class _CategoriaChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoriaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF8FD11B);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? green : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? green : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

// ── Toggle tab ────────────────────────────────────────────────────────────────
class _ToggleTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF8FD11B) : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tarjeta de catálogo ───────────────────────────────────────────────────────
class _CatalogoItemCard extends StatelessWidget {
  final CatalogoItem item;
  final int cantidadEnCarrito;
  final VoidCallback onTap;

  const _CatalogoItemCard({
    required this.item,
    required this.cantidadEnCarrito,
    required this.onTap,
  });

  Color get _stockColor {
    if (item.stock == 0) return Colors.red;
    if (item.stock <= 10) return const Color(0xFFF59E0B);
    return const Color(0xFF8FD11B);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    final stockColor = _stockColor;
    final isLow = item.stock <= 10 && item.stock > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(color: green.withValues(alpha: 0.35), width: 1.0)
              : null,
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: green.withValues(alpha: 0.08),
                    blurRadius: 10,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? green.withValues(alpha: 0.12)
                    : const Color(0xFFEFFAE0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: green,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (item.categoria != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.categoria!,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: stockColor.withValues(
                            alpha: isDark ? 0.15 : 0.10,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: stockColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isLow) ...[
                              Icon(
                                Icons.warning_amber_outlined,
                                size: 10,
                                color: stockColor,
                              ),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              'Stock: ${item.stock} ${item.unidad}',
                              style: TextStyle(
                                color: stockColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (cantidadEnCarrito > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(
                              alpha: isDark ? 0.15 : 0.10,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            'En pedido: $cantidadEnCarrito',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Tarjeta de solicitud ──────────────────────────────────────────────────────
class _MiSolicitudCard extends StatelessWidget {
  final MiSolicitud item;
  const _MiSolicitudCard({required this.item});

  Color get _estadoColor => switch (item.estado) {
    'aprobado' => const Color(0xFF8FD11B),
    'entregado' => Colors.blue,
    'rechazado' => Colors.red,
    _ => Colors.orange,
  };

  String get _estadoLabel => switch (item.estado) {
    'aprobado' => 'Aprobado',
    'entregado' => 'Entregado',
    'rechazado' => 'Rechazado',
    _ => 'Pendiente',
  };

  IconData get _estadoIcon => switch (item.estado) {
    'aprobado' => Icons.check_circle_outline,
    'entregado' => Icons.local_shipping_outlined,
    'rechazado' => Icons.cancel_outlined,
    _ => Icons.hourglass_empty_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    final color = _estadoColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? Border.all(color: green.withValues(alpha: 0.35))
            : null,
        boxShadow: isDark
            ? [BoxShadow(color: green.withValues(alpha: 0.08), blurRadius: 10)]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_estadoIcon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.proyectoNombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 11,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.fecha,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.layers_outlined,
                          size: 11,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.items.length} material${item.items.length != 1 ? 'es' : ''}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _estadoLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (item.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            ...item.items.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 5, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d.nombre,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      '${d.cantidad} ${d.unidad}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (d.cantidadAprobada != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(aprobado: ${d.cantidadAprobada})',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF8FD11B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (item.observacion != null && item.observacion!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.notes_outlined,
                    size: 12,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item.observacion!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            // HU-16: Observación del logístico (aprobación/rechazo)
            if (item.observacionLogistico != null &&
                item.observacionLogistico!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: item.estado == 'rechazado'
                      ? Colors.red.withValues(alpha: 0.08)
                      : const Color(0xFF8FD11B).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: item.estado == 'rechazado'
                        ? Colors.red.withValues(alpha: 0.25)
                        : const Color(0xFF8FD11B).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.estado == 'rechazado'
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                      size: 12,
                      color: item.estado == 'rechazado'
                          ? Colors.red
                          : const Color(0xFF8FD11B),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        item.observacionLogistico!,
                        style: TextStyle(
                          fontSize: 11,
                          color: item.estado == 'rechazado'
                              ? Colors.red.shade700
                              : const Color(0xFF5A8A00),
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Bottom sheet: detalle de item ─────────────────────────────────────────────
class _ItemDetailSheet extends StatefulWidget {
  final CatalogoItem item;
  final int cantidadEnCarrito;
  final void Function(int cantidad) onAgregar;

  const _ItemDetailSheet({
    required this.item,
    required this.cantidadEnCarrito,
    required this.onAgregar,
  });

  @override
  State<_ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<_ItemDetailSheet> {
  int _cantidad = 1;

  Color get _stockColor {
    if (widget.item.stock == 0) return Colors.red;
    if (widget.item.stock <= 10) return const Color(0xFFF59E0B);
    return const Color(0xFF8FD11B);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    final stockColor = _stockColor;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? green.withValues(alpha: 0.12)
                        : const Color(0xFFEFFAE0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: green,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.nombre,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.item.categoria != null)
                        Text(
                          widget.item.categoria!,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      if (widget.item.codigo != null)
                        Text(
                          'Cód: ${widget.item.codigo}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Stock card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: stockColor.withValues(alpha: isDark ? 0.08 : 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: stockColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stock disponible',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${widget.item.stock} ',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            TextSpan(
                              text: widget.item.unidad,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.cantidadEnCarrito > 0)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'En pedido',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.cantidadEnCarrito} ${widget.item.unidad}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Quantity picker
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Cantidad:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 16),
                _QtyButton(
                  icon: Icons.remove,
                  onTap: () {
                    if (_cantidad > 1) setState(() => _cantidad--);
                  },
                ),
                const SizedBox(width: 16),
                Text(
                  '$_cantidad',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 16),
                _QtyButton(
                  icon: Icons.add,
                  onTap: () => setState(() => _cantidad++),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.item.unidad,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Add to cart button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: widget.item.stock == 0
                    ? null
                    : () {
                        widget.onAgregar(_cantidad);
                        Navigator.pop(context);
                      },
                icon: const Icon(Icons.add_shopping_cart_outlined),
                label: Text(
                  widget.cantidadEnCarrito > 0
                      ? 'Agregar más al Pedido'
                      : 'Agregar al Pedido',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

// ── Bottom sheet: carrito / nueva solicitud ───────────────────────────────────
class _CarritoSheet extends StatefulWidget {
  final Map<String, _CarritoEntry> initialCarrito;
  final List<ProyectoItem> proyectos;
  final RequerimientoService service;
  final void Function(Map<String, _CarritoEntry>) onCartChanged;

  const _CarritoSheet({
    required this.initialCarrito,
    required this.proyectos,
    required this.service,
    required this.onCartChanged,
  });

  @override
  State<_CarritoSheet> createState() => _CarritoSheetState();
}

class _CarritoSheetState extends State<_CarritoSheet> {
  static const _green = Color(0xFF8FD11B);

  late Map<String, _CarritoEntry> _carrito;
  String? _proyectoId;
  final _obsCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _carrito = {
      for (final e in widget.initialCarrito.entries)
        e.key: _CarritoEntry(item: e.value.item, cantidad: e.value.cantidad),
    };
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  void _updateCantidad(String materialId, int delta) {
    setState(() {
      final entry = _carrito[materialId];
      if (entry == null) return;
      final next = entry.cantidad + delta;
      if (next <= 0) {
        _carrito.remove(materialId);
      } else {
        entry.cantidad = next;
      }
    });
    widget.onCartChanged(Map.from(_carrito));
  }

  void _removeItem(String materialId) {
    setState(() => _carrito.remove(materialId));
    widget.onCartChanged(Map.from(_carrito));
  }

  Future<void> _enviar() async {
    if (_proyectoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un proyecto para la solicitud'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_carrito.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un material al pedido'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _sending = true);

    final items = _carrito.values
        .map((e) => {'material_id': e.item.id, 'cantidad': e.cantidad})
        .toList();

    final ok = await widget.service.crearSolicitud(
      proyectoId: _proyectoId!,
      items: items,
      observacion: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al enviar la solicitud. Intenta nuevamente.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.70,
      minChildSize: 0.40,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          children: [
            // Handle + header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? _green.withValues(alpha: 0.12)
                              : const Color(0xFFEFFAE0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          color: _green,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nueva Solicitud',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Pedido de materiales',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                ],
              ),
            ),

            // Carrito vacío
            if (_carrito.isEmpty) ...[
              const SizedBox(height: 16),
              _buildEmptyCarrito(),
            ],

            // Items del carrito
            if (_carrito.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Materiales seleccionados',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._carrito.values.map(
                      (e) => _CarritoItemRow(
                        entry: e,
                        isDark: isDark,
                        onDecrement: () => _updateCantidad(e.item.id, -1),
                        onIncrement: () => _updateCantidad(e.item.id, 1),
                        onRemove: () => _removeItem(e.item.id),
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 20),

                    // Proyecto
                    const Text(
                      'Proyecto',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    widget.proyectos.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Cargando proyectos...',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: _proyectoId,
                            hint: const Text('Selecciona un proyecto'),
                            isExpanded: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            items: widget.proyectos
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(
                                      p.nombreProyecto.isNotEmpty
                                          ? p.nombreProyecto
                                          : p.ordenTrabajo,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _proyectoId = v),
                          ),

                    const SizedBox(height: 16),

                    // Observación
                    const Text(
                      'Observación (opcional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _obsCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Notas o instrucciones adicionales...',
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Enviar
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _sending ? null : _enviar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Enviar Pedido',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCarrito() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 56,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            const Text(
              'Tu pedido está vacío',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Regresa al catálogo y agrega materiales para crear una solicitud.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Volver al catálogo',
                style: TextStyle(color: _green),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarritoItemRow extends StatelessWidget {
  final _CarritoEntry entry;
  final bool isDark;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onRemove;

  const _CarritoItemRow({
    required this.entry,
    required this.isDark,
    required this.onDecrement,
    required this.onIncrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF8FD11B);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? green.withValues(alpha: 0.06) : const Color(0xFFF9FDF0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.item.nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.item.categoria != null)
                  Text(
                    entry.item.categoria!,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: onDecrement,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.remove, size: 14),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '${entry.cantidad}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onIncrement,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.add, size: 14),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                entry.item.unidad,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ── Sheet: Nuevo material en inventario ───────────────────────────────────────
class _NuevoMaterialSheet extends StatefulWidget {
  final List<CategoriaItem> categorias;
  final List<AlmacenItem> almacenes;
  final RequerimientoService service;
  final VoidCallback onCreado;

  const _NuevoMaterialSheet({
    required this.categorias,
    required this.almacenes,
    required this.service,
    required this.onCreado,
  });

  @override
  State<_NuevoMaterialSheet> createState() => _NuevoMaterialSheetState();
}

class _NuevoMaterialSheetState extends State<_NuevoMaterialSheet> {
  static const _green = Color(0xFF8FD11B);

  final _nombreCtrl   = TextEditingController();
  final _codigoCtrl   = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '0');

  String? _categoriaId;
  String? _almacenId;
  String _unidad = 'Unidades';
  bool _sending = false;

  static const _unidades = [
    'Unidades', 'Metros', 'Rollos', 'Barras', 'Pares',
    'Sets', 'Litros', 'Kilogramos', 'Cajas',
  ];

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _codigoCtrl.dispose();
    _descCtrl.dispose();
    _cantidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) { _snack('Ingresa el nombre del material'); return; }
    if (_categoriaId == null) { _snack('Selecciona una categoría'); return; }
    final cantidad = int.tryParse(_cantidadCtrl.text) ?? 0;

    setState(() => _sending = true);
    final ok = await widget.service.crearMaterial(
      nombre: nombre,
      codigo: _codigoCtrl.text.trim().isEmpty ? null : _codigoCtrl.text.trim(),
      unidad: _unidad,
      categoriaId: _categoriaId!,
      descripcion: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      cantidadInicial: cantidad,
      almacenId: _almacenId,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      Navigator.pop(context);
      widget.onCreado();
    } else {
      _snack('Error al guardar. Verifica permisos.');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final inputBg = Theme.of(context).colorScheme.surfaceContainerHighest;
    final inputDec = InputDecoration(
      filled: true, fillColor: inputBg,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.add_box_outlined, color: _green, size: 22),
              ),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nuevo Material',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text('Agregar al inventario',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 24),
            _label('Nombre *'),
            TextField(controller: _nombreCtrl,
                decoration: inputDec.copyWith(hintText: 'Ej: Cable THW 12 AWG')),
            const SizedBox(height: 14),
            _label('Código (opcional)'),
            TextField(controller: _codigoCtrl,
                decoration: inputDec.copyWith(hintText: 'Ej: CBL-THW-12')),
            const SizedBox(height: 14),
            _label('Categoría *'),
            DropdownButtonFormField<String>(
              value: _categoriaId,
              hint: const Text('Selecciona categoría'),
              decoration: inputDec,
              items: widget.categorias.map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(c.nombre, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setState(() => _categoriaId = v),
            ),
            const SizedBox(height: 14),
            _label('Unidad de medida'),
            DropdownButtonFormField<String>(
              value: _unidad,
              decoration: inputDec,
              items: _unidades.map((u) => DropdownMenuItem(
                  value: u, child: Text(u, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setState(() => _unidad = v ?? 'Unidades'),
            ),
            const SizedBox(height: 14),
            _label('Descripción (opcional)'),
            TextField(controller: _descCtrl, maxLines: 2,
                decoration: inputDec.copyWith(hintText: 'Especificaciones técnicas...')),
            const SizedBox(height: 14),
            _label('Cantidad inicial en stock'),
            TextField(controller: _cantidadCtrl,
                keyboardType: TextInputType.number,
                decoration: inputDec.copyWith(hintText: '0')),
            const SizedBox(height: 14),
            if (widget.almacenes.isNotEmpty) ...[
              _label('Almacén (opcional)'),
              DropdownButtonFormField<String>(
                value: _almacenId,
                hint: const Text('Almacén principal por defecto'),
                decoration: inputDec,
                items: widget.almacenes.map((a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      a.ubicacion != null ? '${a.nombre} — ${a.ubicacion}' : a.nombre,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ))).toList(),
                onChanged: (v) => setState(() => _almacenId = v),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _sending ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green, foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _sending
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar en Inventario',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
  );
}

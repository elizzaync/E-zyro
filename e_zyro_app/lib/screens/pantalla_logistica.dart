import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../models/requerimiento_models.dart';
import '../utils/app_session.dart';
import '../services/requerimiento_service.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';
import 'pantalla_inventario_panel.dart';

part 'logistica/cards.dart';
part 'logistica/sheets.dart';

// Nota: el flujo de "Solicitar materiales" se trasladó al detalle de servicio
// (pantalla_detalle_servicio.dart, borrador). Esta pantalla queda restringida
// a logística/admin y solo expone catálogo + panel del encargado.
//
// -- Main Screen ---------------------------------------------------------------
class LogisticsScreen extends StatefulWidget {
  const LogisticsScreen({super.key});

  @override
  State<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends State<LogisticsScreen> {
  static const _green = Color(0xFF8FD11B);
  static const _pageSize = 30;

  RequerimientoService? _service;

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

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

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
    if (mounted) {
      setState(() => _puedeGestionar = AppSession.i.canGestInventario);
    }
  }

  Future<void> _init() async {
    _service = await getRequerimientoService();
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
        final cats =
            items.map((e) => e.categoria).whereType<String>().toSet().toList()
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

  void _openItemDetail(CatalogoItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemDetailSheet(item: item),
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
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Material agregado al inventario'),
              backgroundColor: _green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
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
                                  builder: (_) =>
                                      const PantallaInventarioPanel(),
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
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
                                    Icon(
                                      Icons.dashboard_customize_outlined,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Panel',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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

            // FAB único: agregar material al inventario (solo logística/admin
            // en la pestaña Catálogo). El antiguo FAB "Solicitar" se eliminó �?"
            // las solicitudes ahora se crean desde el detalle del servicio.
            if (_puedeGestionar && _showCatalogo)
              Positioned(
                right: 20,
                bottom: 20,
                child: FloatingActionButton.extended(
                  heroTag: 'fab_inventario',
                  onPressed: _openNuevoMaterialSheet,
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text(
                    'Nuevo material',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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


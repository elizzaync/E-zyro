import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/seguridad_models.dart';
import '../services/seguridad_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';
import 'pantalla_mis_sesiones.dart' show SesionCard;

const _kGreen = Color(0xFF8FD11B);
const _kRed   = Color(0xFFEF4444);

class PantallaPersonal extends StatefulWidget {
  const PantallaPersonal({super.key});

  @override
  State<PantallaPersonal> createState() => _PantallaPersonalState();
}

class _PantallaPersonalState extends State<PantallaPersonal> {
  SeguridadService? _service;
  List<PersonalItem> _items = [];
  bool _loading = true;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getSeguridadService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _loading = true);
    final data = await _service!.getUsuarios(q: _searchCtrl.text);
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activos = _items.where((u) => u.activo).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Personal',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            if (!_loading)
              Text('$activos activo${activos == 1 ? '' : 's'} de ${_items.length}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16, amp: 9, stroke: 0.38, speed: 0.45,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o email...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                          onPressed: () { _searchCtrl.clear(); _load(); },
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _kGreen))
                  : _items.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _kGreen,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _items.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _PersonalCard(
                              item: _items[i],
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _PantallaSesionesUsuario(usuario: _items[i]),
                                ),
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_off_outlined, size: 52, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            const Text('Sin resultados',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey)),
          ],
        ),
      );
}

// ─── Tarjeta de un usuario ────────────────────────────────────────────────────

class _PersonalCard extends StatelessWidget {
  final PersonalItem item;
  final VoidCallback onTap;
  const _PersonalCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.08))
              : null,
          boxShadow: isDark ? null : [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            _Avatar(fotoUrl: item.fotoUrl, nombre: item.nombre),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(item.nombreCompleto,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    if (!item.activo)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Inactivo',
                            style: TextStyle(fontSize: 10, color: _kRed,
                                fontWeight: FontWeight.w600)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(item.rol,
                      style: const TextStyle(fontSize: 11, color: _kGreen,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(item.email,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 6),
                  Row(children: [
                    if (item.sesionesActivas > 0) ...[
                      const Icon(Icons.fiber_manual_record, size: 8, color: _kGreen),
                      const SizedBox(width: 3),
                      Text('${item.sesionesActivas} sesión${item.sesionesActivas == 1 ? '' : 'es'} activa${item.sesionesActivas == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 10, color: _kGreen,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                    ],
                    if (item.ultimoAcceso != null) ...[
                      const Icon(Icons.access_time_rounded, size: 10, color: Colors.grey),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text('Último: ${item.ultimoAcceso}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? fotoUrl;
  final String nombre;
  const _Avatar({this.fotoUrl, required this.nombre});

  @override
  Widget build(BuildContext context) {
    if (fotoUrl != null && fotoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: fotoUrl!,
          width: 44, height: 44, fit: BoxFit.cover,
          placeholder: (_, _) => _initials(),
          errorWidget: (_, _, _) => _initials(),
        ),
      );
    }
    return _initials();
  }

  Widget _initials() {
    final letter = nombre.isEmpty ? '?' : nombre[0].toUpperCase();
    return Container(
      width: 44, height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFEFFAE0),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(letter,
          style: const TextStyle(
              color: _kGreen, fontWeight: FontWeight.bold, fontSize: 18)),
    );
  }
}

// ─── Detalle: sesiones de un usuario ──────────────────────────────────────────

class _PantallaSesionesUsuario extends StatefulWidget {
  final PersonalItem usuario;
  const _PantallaSesionesUsuario({required this.usuario});

  @override
  State<_PantallaSesionesUsuario> createState() => _PantallaSesionesUsuarioState();
}

class _PantallaSesionesUsuarioState extends State<_PantallaSesionesUsuario> {
  SeguridadService? _service;
  List<SesionConexion> _sesiones = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getSeguridadService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _loading = true);
    final data = await _service!.getSesionesDeUsuario(widget.usuario.id);
    if (!mounted) return;
    setState(() {
      _sesiones = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activas = _sesiones.where((s) => s.activa).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.usuario.nombreCompleto,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (!_loading)
              Text('$activas activa${activas == 1 ? '' : 's'} · ${_sesiones.length} total',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16, amp: 9, stroke: 0.38, speed: 0.45,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kGreen))
            : _sesiones.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.devices_other_rounded, size: 52, color: Colors.grey.shade400),
                        const SizedBox(height: 14),
                        const Text('Sin sesiones registradas',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                                color: Colors.grey)),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: _kGreen,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      itemCount: _sesiones.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => SesionCard(item: _sesiones[i]),
                    ),
                  ),
      ),
    );
  }
}

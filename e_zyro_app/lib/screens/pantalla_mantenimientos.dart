import 'package:flutter/material.dart';
import '../models/mantenimiento_models.dart';
import '../services/mantenimiento_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_notifiers.dart';
import '../widgets/topo_background.dart';

const _kGreen  = Color(0xFF8FD11B);
const _kRed    = Color(0xFFEF4444);
const _kAmber  = Color(0xFFF59E0B);

class PantallaMantenimientos extends StatefulWidget {
  const PantallaMantenimientos({super.key});

  @override
  State<PantallaMantenimientos> createState() =>
      _PantallaMantenimientosState();
}

class _PantallaMantenimientosState extends State<PantallaMantenimientos> {
  MantenimientoService? _service;
  List<MantenimientoGeneral> _todos = [];
  List<MantenimientoGeneral> _filtrados = [];
  bool _isLoading = true;
  String _filtro = 'todos'; // 'todos' | 'vigente' | 'vencido' | 'proximo'
  DateTime? _lastLoad;

  @override
  void initState() {
    super.initState();
    _init();
    syncCompletedNotifier.addListener(_onSyncCompleted);
  }

  @override
  void dispose() {
    syncCompletedNotifier.removeListener(_onSyncCompleted);
    super.dispose();
  }

  void _onSyncCompleted() {
    if (!mounted) return;
    final ahora = DateTime.now();
    if (_lastLoad != null &&
        ahora.difference(_lastLoad!) < const Duration(seconds: 60)) {
      return;
    }
    _lastLoad = ahora;
    _load();
  }

  Future<void> _init() async {
    _service = await getMantenimientoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final data = await _service!.getMantenimientosGenerales();
    if (!mounted) return;
    setState(() {
      _todos = data;
      _aplicarFiltro(_filtro);
      _isLoading = false;
    });
  }

  void _aplicarFiltro(String f) {
    setState(() {
      _filtro = f;
      _filtrados = f == 'todos'
          ? List.from(_todos)
          : _todos.where((m) => m.estado == f).toList();
    });
  }

  // Contadores para los chips
  int _count(String estado) =>
      estado == 'todos'
          ? _todos.length
          : _todos.where((m) => m.estado == estado).length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vencidos = _count('vencido');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mantenimientos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            if (!_isLoading && vencidos > 0)
              Text(
                '$vencidos vencido${vencidos > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 10, color: _kRed),
              ),
          ],
        ),
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
        child: Column(
          children: [
            // ── Chips de filtro ───────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Chip(
                      label: 'Todos (${_count('todos')})',
                      isSelected: _filtro == 'todos',
                      onTap: () => _aplicarFiltro('todos'),
                    ),
                    _Chip(
                      label: 'Vigente (${_count('vigente')})',
                      isSelected: _filtro == 'vigente',
                      color: _kGreen,
                      onTap: () => _aplicarFiltro('vigente'),
                    ),
                    _Chip(
                      label: 'Próximo (${_count('proximo')})',
                      isSelected: _filtro == 'proximo',
                      color: _kAmber,
                      onTap: () => _aplicarFiltro('proximo'),
                    ),
                    _Chip(
                      label: 'Vencido (${_count('vencido')})',
                      isSelected: _filtro == 'vencido',
                      color: _kRed,
                      onTap: () => _aplicarFiltro('vencido'),
                    ),
                  ],
                ),
              ),
            ),

            // ── Lista ─────────────────────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kGreen))
                  : _filtrados.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _kGreen,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                                16, 8, 16, 24),
                            itemCount: _filtrados.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) =>
                                _MantenimientoCard(item: _filtrados[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.build_circle_outlined,
              size: 52,
              color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            _filtro == 'todos'
                ? 'Sin registros de mantenimiento'
                : 'No hay mantenimientos en\neste estado',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey),
          ),
          const SizedBox(height: 6),
          const Text(
            'Los mantenimientos se generan al\nfinalizar servicios completados.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _load,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _kGreen),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.refresh_rounded,
                color: _kGreen, size: 16),
            label: const Text('Actualizar',
                style: TextStyle(color: _kGreen)),
          ),
        ],
      ),
    );
  }
}

// ─── Chip de filtro ───────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.isSelected,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color : surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ─── Tarjeta de mantenimiento ─────────────────────────────────────────────────

class _MantenimientoCard extends StatelessWidget {
  final MantenimientoGeneral item;

  const _MantenimientoCard({required this.item});

  Color get _estadoColor => switch (item.estado) {
        'vencido' => _kRed,
        'proximo' => _kAmber,
        _ => _kGreen, // vigente
      };

  Color get _estadoBg => switch (item.estado) {
        'vencido' => const Color(0xFFFFEBEB),
        'proximo' => const Color(0xFFFFF3CD),
        _ => const Color(0xFFEFFAE0),
      };

  String get _estadoLabel => switch (item.estado) {
        'vencido' => 'Vencido',
        'proximo' => 'Próximo',
        _ => 'Vigente',
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? Border.all(
                color: _estadoColor.withValues(alpha: 0.30))
            : null,
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: _estadoColor.withValues(alpha: 0.08),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── OT + estado ─────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.ot.isNotEmpty ? item.ot : 'Sin OT',
                style: const TextStyle(
                  fontSize: 11,
                  color: _kGreen,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? _estadoColor.withValues(alpha: 0.15)
                      : _estadoBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _estadoLabel,
                  style: TextStyle(
                    color: _estadoColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),

          // ── Cliente ──────────────────────────────────────────────────────
          Text(
            item.cliente,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),

          // ── Tipo + zona ──────────────────────────────────────────────────
          Text(
            item.tipo +
                (item.zona.isNotEmpty ? '  ·  Zona ${item.zona}' : ''),
            style:
                const TextStyle(color: Colors.grey, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // ── Técnico ──────────────────────────────────────────────────────
          if (item.tecnicoNombre.isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  item.tecnicoNombre,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ── Fechas ───────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Realizado',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.fechaRealizado.isNotEmpty
                          ? item.fechaRealizado
                          : '—',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Próximo',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.fechaProximo.isNotEmpty
                          ? item.fechaProximo
                          : '—',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: item.estado == 'vencido'
                            ? _kRed
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Colors.grey, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

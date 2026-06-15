import 'dart:async';
import 'package:flutter/material.dart';
import '../models/requerimiento_models.dart';
import '../services/requerimiento_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../widgets/topo_background.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_preview_screen.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF3B82F6);
const _kAmber = Color(0xFFF59E0B);

/// Fase 3 — Movimientos de inventario: historial + registrar ajuste de stock.
class PantallaMovimientosLogistica extends StatefulWidget {
  const PantallaMovimientosLogistica({super.key});

  @override
  State<PantallaMovimientosLogistica> createState() =>
      _PantallaMovimientosLogisticaState();
}

class _PantallaMovimientosLogisticaState
    extends State<PantallaMovimientosLogistica> {
  RequerimientoService? _service;
  List<MovimientoStock> _movimientos = [];
  List<ReposicionItem> _reposicion = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getRequerimientoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final data = await _service!.getMovimientos();
    final repo = await _service!.getReposicion();
    if (!mounted) return;
    setState(() {
      _movimientos = data;
      _reposicion = repo;
      _isLoading = false;
    });
  }

  Future<void> _abrirReposicion() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReposicionSheet(items: _reposicion),
    );
  }

  Future<void> _exportarSalidasPdf() async {
    final bytes = await PdfService.salidasLogistica(_movimientos);
    if (!mounted) return;
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo: 'salidas_almacen_${DateTime.now().millisecondsSinceEpoch}.pdf',
      titulo: 'Reporte de Salidas',
    );
  }

  Future<void> _abrirAjuste() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AjusteSheet(service: _service!),
    );
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Movimientos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          _BadgeAccion(
            count: _reposicion.length,
            tooltip: 'Reposición (stock bajo el mínimo)',
            icon: Icons.warning_amber_rounded,
            onPressed: _reposicion.isEmpty ? null : _abrirReposicion,
          ),
          IconButton(
            tooltip: 'Exportar salidas (PDF)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _movimientos.isEmpty ? null : _exportarSalidasPdf,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _service == null ? null : _abrirAjuste,
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.tune_rounded),
        label: const Text('Ajustar stock',
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _kGreen))
            : _movimientos.isEmpty
                ? _buildEmpty()
                : RefreshIndicator(
                    onRefresh: _load,
                    color: _kGreen,
                    child: ListView.separated(
                      padding: bottomSafePadding(context, extra: 90),
                      itemCount: _movimientos.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          _MovimientoCard(mov: _movimientos[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_vert_rounded, size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          const Text('Sin movimientos registrados',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Registra una entrada o salida de stock',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Card de movimiento ──────────────────────────────────────────────────────
class _MovimientoCard extends StatelessWidget {
  final MovimientoStock mov;
  const _MovimientoCard({required this.mov});

  ({Color color, IconData icon, String label}) get _cfg => switch (mov.tipo) {
        'entrada' => (color: _kGreen, icon: Icons.arrow_downward_rounded, label: 'Entrada'),
        'salida' => (color: _kRed, icon: Icons.arrow_upward_rounded, label: 'Salida'),
        'ajuste' => (color: _kBlue, icon: Icons.tune_rounded, label: 'Ajuste'),
        'requerimiento' => (color: _kAmber, icon: Icons.outbox_rounded, label: 'Entrega'),
        'transferencia' => (color: const Color(0xFF06B6D4), icon: Icons.compare_arrows_rounded, label: 'Transferencia'),
        'compra' => (color: const Color(0xFF8B5CF6), icon: Icons.shopping_cart_rounded, label: 'Compra'),
        _ => (color: Colors.grey, icon: Icons.swap_vert_rounded, label: mov.tipo),
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final cfg = _cfg;
    final signo = mov.tipo == 'salida' ? '-' : (mov.tipo == 'entrada' ? '+' : '');

    return Container(
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
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cfg.color.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(cfg.icon, color: cfg.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mov.materialNombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${cfg.label}${mov.almacenNombre != null ? ' · ${mov.almacenNombre}' : ''}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                if (mov.motivo != null && mov.motivo!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(mov.motivo!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 2),
                Text(
                  '${mov.fecha}${mov.responsableNombre != null ? ' · ${mov.responsableNombre}' : ''}',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            mov.tipo == 'ajuste'
                ? '=${mov.cantidad} ${mov.unidad}'
                : '$signo${mov.cantidad} ${mov.unidad}',
            style: TextStyle(
                color: cfg.color, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─── Sheet de ajuste de stock ────────────────────────────────────────────────
class _AjusteSheet extends StatefulWidget {
  final RequerimientoService service;
  const _AjusteSheet({required this.service});

  @override
  State<_AjusteSheet> createState() => _AjusteSheetState();
}

class _AjusteSheetState extends State<_AjusteSheet> {
  final _searchCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();
  final _costoCtrl = TextEditingController();
  Timer? _debounce;

  List<CatalogoItem> _resultados = [];
  CatalogoItem? _seleccionado;
  bool _buscando = false;
  bool _guardando = false;
  String _tipo = 'entrada'; // entrada | salida | ajuste

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _cantidadCtrl.dispose();
    _motivoCtrl.dispose();
    _costoCtrl.dispose();
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
    final items = await widget.service.getCatalogo(q, pageSize: 15);
    if (!mounted) return;
    setState(() {
      _resultados = items;
      _buscando = false;
    });
  }

  Future<void> _guardar() async {
    final mat = _seleccionado;
    final cantidad = int.tryParse(_cantidadCtrl.text.trim());
    if (mat == null) {
      _err('Selecciona un material');
      return;
    }
    if (cantidad == null || cantidad < 0) {
      _err('Cantidad inválida');
      return;
    }
    if (_tipo != 'ajuste' && cantidad < 1) {
      _err('La cantidad debe ser mayor a 0');
      return;
    }
    final costo = _tipo == 'entrada'
        ? double.tryParse(_costoCtrl.text.trim().replaceAll(',', '.'))
        : null;
    setState(() => _guardando = true);
    final ok = await widget.service.ajustarStock(
      materialId: mat.id,
      tipo: _tipo,
      cantidad: cantidad,
      motivo: _motivoCtrl.text.trim(),
      costoUnitario: costo,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      _err('No se pudo registrar el ajuste (¿stock insuficiente?)');
    }
  }

  void _err(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            const Text('Ajustar stock',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // ── Material seleccionado o buscador ───────────────────────────
            if (_seleccionado != null)
              _MaterialChip(
                item: _seleccionado!,
                onClear: () => setState(() {
                  _seleccionado = null;
                  _resultados = [];
                  _searchCtrl.clear();
                }),
              )
            else ...[
              TextField(
                controller: _searchCtrl,
                onChanged: _onSearch,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar material...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_buscando)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _kGreen))),
                )
              else if (_resultados.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 220),
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
                          'Stock: ${it.stock} ${it.unidad}'
                          '${it.categoria != null ? ' · ${it.categoria}' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => setState(() {
                          _seleccionado = it;
                          _resultados = [];
                        }),
                      );
                    },
                  ),
                ),
            ],
            const SizedBox(height: 16),

            // ── Tipo de movimiento ─────────────────────────────────────────
            const Text('Tipo de movimiento',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _TipoBtn(
                    label: 'Entrada',
                    icon: Icons.arrow_downward_rounded,
                    color: _kGreen,
                    selected: _tipo == 'entrada',
                    onTap: () => setState(() => _tipo = 'entrada')),
                const SizedBox(width: 8),
                _TipoBtn(
                    label: 'Salida',
                    icon: Icons.arrow_upward_rounded,
                    color: _kRed,
                    selected: _tipo == 'salida',
                    onTap: () => setState(() => _tipo = 'salida')),
                const SizedBox(width: 8),
                _TipoBtn(
                    label: 'Ajuste',
                    icon: Icons.tune_rounded,
                    color: _kBlue,
                    selected: _tipo == 'ajuste',
                    onTap: () => setState(() => _tipo = 'ajuste')),
              ],
            ),
            const SizedBox(height: 16),

            // ── Cantidad ───────────────────────────────────────────────────
            Text(
              _tipo == 'ajuste'
                  ? 'Cantidad final (valor exacto)'
                  : 'Cantidad',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cantidadCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '0',
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Costo unitario (solo entrada; alimenta el kardex/promedio) ──
            if (_tipo == 'entrada') ...[
              const Text('Costo unitario',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _costoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: 'Costo al que entra (opcional)',
                  helperText: 'Si lo dejas vacío se usa el precio del material',
                  prefixText: 'S/ ',
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Motivo ─────────────────────────────────────────────────────
            const Text('Motivo (opcional)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _motivoCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Ej: compra, merma, conteo físico...',
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
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
                    : const Text('Registrar',
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

class _MaterialChip extends StatelessWidget {
  final CatalogoItem item;
  final VoidCallback onClear;
  const _MaterialChip({required this.item, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGreen.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: _kGreen, size: 20),
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
                Text('Stock actual: ${item.stock} ${item.unidad}',
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

class _TipoBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TipoBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color : surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? color : Colors.transparent, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 18, color: selected ? Colors.white : color),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Acción de AppBar con badge numérico ─────────────────────────────────────
class _BadgeAccion extends StatelessWidget {
  final int count;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  const _BadgeAccion({
    required this.count,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed),
        if (count > 0)
          Positioned(
            top: 8,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _kRed,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Hoja de reposición: materiales en/bajo el stock mínimo ──────────────────
class _ReposicionSheet extends StatelessWidget {
  final List<ReposicionItem> items;
  const _ReposicionSheet({required this.items});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: _kAmber),
                const SizedBox(width: 8),
                Text('Reposición (${items.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Materiales en o por debajo de su stock mínimo',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = items[i];
                  return ListTile(
                    dense: true,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x1AF59E0B),
                      child: Icon(Icons.inventory_2_outlined,
                          color: _kAmber, size: 20),
                    ),
                    title: Text(it.materialNombre,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${it.almacenNombre} · ${it.cantidad}/${it.stockMinimo} ${it.unidad}',
                        style: const TextStyle(fontSize: 11)),
                    trailing: Text('faltan ${it.faltante}',
                        style: const TextStyle(
                            color: _kRed,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

// ── Modelo de solicitud ───────────────────────────────────────────────────────
class _SolicitudItem {
  final String item;
  final int cantidad;
  final String unidad;
  final String status;
  final String fecha;
  final String solicitante;

  const _SolicitudItem({
    required this.item,
    required this.cantidad,
    required this.unidad,
    required this.status,
    required this.fecha,
    required this.solicitante,
  });
}

const _solicitudes = [
  _SolicitudItem(
    item: 'Cable de Red CAT6',
    cantidad: 100,
    unidad: 'metros',
    status: 'Pendiente',
    fecha: 'Hoy',
    solicitante: 'Carlos M.',
  ),
  _SolicitudItem(
    item: 'Conectores RJ45',
    cantidad: 200,
    unidad: 'piezas',
    status: 'Aprobada',
    fecha: 'Ayer',
    solicitante: 'Ana L.',
  ),
  _SolicitudItem(
    item: 'Switch 24 puertos',
    cantidad: 2,
    unidad: 'unidades',
    status: 'En proceso',
    fecha: '25/04/2025',
    solicitante: 'Luis R.',
  ),
  _SolicitudItem(
    item: 'Cable de Fibra Óptica',
    cantidad: 50,
    unidad: 'metros',
    status: 'Rechazada',
    fecha: '22/04/2025',
    solicitante: 'María C.',
  ),
];

// ── Modelo de inventario ──────────────────────────────────────────────────────
class _InventoryData {
  final String name;
  final int quantity;
  final String unit;
  final int minimum;
  final int percentage;
  final bool isLow;
  final String category;

  const _InventoryData({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.minimum,
    required this.percentage,
    required this.isLow,
    required this.category,
  });
}

const _inventory = [
  _InventoryData(
    name: 'Cable de Red CAT6',
    quantity: 450,
    unit: 'metros',
    minimum: 200,
    percentage: 113,
    isLow: false,
    category: 'Cables',
  ),
  _InventoryData(
    name: 'Conectores RJ45',
    quantity: 85,
    unit: 'piezas',
    minimum: 100,
    percentage: 43,
    isLow: true,
    category: 'Conectores',
  ),
  _InventoryData(
    name: 'Switches de Red (24 puertos)',
    quantity: 12,
    unit: 'unidades',
    minimum: 5,
    percentage: 120,
    isLow: false,
    category: 'Equipos',
  ),
  _InventoryData(
    name: 'Cable de Fibra Óptica',
    quantity: 150,
    unit: 'metros',
    minimum: 100,
    percentage: 75,
    isLow: false,
    category: 'Cables',
  ),
];

class LogisticsScreen extends StatefulWidget {
  const LogisticsScreen({super.key});

  @override
  State<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends State<LogisticsScreen> {
  bool _showInventory = true;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_InventoryData> get _filteredInventory {
    if (_query.isEmpty) return _inventory;
    return _inventory
        .where((i) => i.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  void _openInventoryDetail(_InventoryData item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InventoryDetailSheet(item: item),
    );
  }

  void _showNewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewItemSheet(isInventory: _showInventory),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final toggleBg = isDark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Colors.grey.shade200;

    return SafeArea(
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
                    // ── Encabezado ─────────────────────────────────────
                    const Text('Logística',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // ── Toggle ─────────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: toggleBg,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          _ToggleTab(
                            label: 'Inventario',
                            isSelected: _showInventory,
                            onTap: () => setState(() {
                              _showInventory = true;
                              _query = '';
                              _searchCtrl.clear();
                            }),
                          ),
                          _ToggleTab(
                            label: 'Solicitudes',
                            isSelected: !_showInventory,
                            onTap: () => setState(() => _showInventory = false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Buscador (solo en inventario) ──────────────────
                    if (_showInventory)
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar materiales...',
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
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
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // ── Contenido ──────────────────────────────────────────────
              Expanded(
                child: _showInventory
                    ? _buildInventoryList()
                    : _buildSolicitudesList(),
              ),
            ],
          ),

          // ── FAB ────────────────────────────────────────────────────────
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton.extended(
              onPressed: _showNewSheet,
              backgroundColor: const Color(0xFF8FD11B),
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add),
              label: Text(
                _showInventory ? 'Agregar' : 'Solicitar',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryList() {
    final items = _filteredInventory;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Sin resultados',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _InventoryItemCard(
        item: items[i],
        onTap: () => _openInventoryDetail(items[i]),
      ),
    );
  }

  Widget _buildSolicitudesList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: _solicitudes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _SolicitudCard(item: _solicitudes[i]),
    );
  }
}

// ─── Tab de toggle ────────────────────────────────────────────────────────────
class _ToggleTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleTab({required this.label, required this.isSelected, required this.onTap});

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
              color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tarjeta de inventario ────────────────────────────────────────────────────
class _InventoryItemCard extends StatelessWidget {
  final _InventoryData item;
  final VoidCallback onTap;

  const _InventoryItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final barColor = item.isLow ? Colors.red : const Color(0xFF8FD11B);
    const green = Color(0xFF8FD11B);
    final clampedPercent = (item.percentage / 120).clamp(0.0, 1.0);
    final borderColor = item.isLow ? Colors.red : green;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(color: borderColor.withValues(alpha: 0.45), width: 1.0)
              : null,
          boxShadow: isDark
              ? [BoxShadow(color: borderColor.withValues(alpha: 0.10), blurRadius: 12, spreadRadius: 1)]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(item.category,
                          style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.isLow)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: isDark ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_outlined, size: 11, color: Colors.red),
                            SizedBox(width: 3),
                            Text('Bajo', style: TextStyle(color: Colors.red, fontSize: 10)),
                          ],
                        ),
                      ),
                    const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${item.quantity} ',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: item.unit,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: clampedPercent,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                color: barColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mín: ${item.minimum} ${item.unit}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text('${item.percentage}%',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tarjeta de solicitud ─────────────────────────────────────────────────────
class _SolicitudCard extends StatelessWidget {
  final _SolicitudItem item;
  const _SolicitudCard({required this.item});

  Color get _statusColor => switch (item.status) {
        'Aprobada' => const Color(0xFF8FD11B),
        'En proceso' => Colors.blue,
        'Rechazada' => Colors.red,
        _ => Colors.orange,
      };

  IconData get _statusIcon => switch (item.status) {
        'Aprobada' => Icons.check_circle_outline,
        'En proceso' => Icons.sync_outlined,
        'Rechazada' => Icons.cancel_outlined,
        _ => Icons.hourglass_empty_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: green.withValues(alpha: 0.35)) : null,
        boxShadow: isDark
            ? [BoxShadow(color: green.withValues(alpha: 0.08), blurRadius: 10)]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_statusIcon, color: _statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.item,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 3),
                Text(
                  '${item.cantidad} ${item.unidad}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(item.solicitante,
                        style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(width: 10),
                    const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(item.fecha,
                        style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              item.status,
              style: TextStyle(
                color: _statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom sheet: Detalle de inventario ─────────────────────────────────────
class _InventoryDetailSheet extends StatelessWidget {
  final _InventoryData item;
  const _InventoryDetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    final barColor = item.isLow ? Colors.red : green;
    final clampedPercent = (item.percentage / 120).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
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
                    color: isDark ? green.withValues(alpha: 0.12) : const Color(0xFFEFFAE0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_outlined, color: green, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(item.category,
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                if (item.isLow)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: const Text('Stock Bajo',
                        style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Stock
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? barColor.withValues(alpha: 0.08) : barColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: barColor.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Stock actual',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('${item.percentage}% del objetivo',
                          style: TextStyle(
                            color: barColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${item.quantity} ',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        TextSpan(
                          text: item.unit,
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: clampedPercent,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      color: barColor,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mínimo requerido: ${item.minimum} ${item.unit}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Acciones
            Row(
              children: [
                Expanded(
                  child: _SheetAction(
                    icon: Icons.add_circle_outline,
                    label: 'Solicitar',
                    color: green,
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Solicitud de ${item.name} enviada'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetAction(
                    icon: Icons.history_outlined,
                    label: 'Historial',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('Historial disponible próximamente'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ));
                    },
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

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom sheet: Nuevo item / solicitud ─────────────────────────────────────
class _NewItemSheet extends StatelessWidget {
  final bool isInventory;
  const _NewItemSheet({required this.isInventory});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? green.withValues(alpha: 0.12) : const Color(0xFFEFFAE0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isInventory ? Icons.add_box_outlined : Icons.request_page_outlined,
                    color: green,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isInventory ? 'Agregar al Inventario' : 'Nueva Solicitud',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      isInventory
                          ? 'Registro de nuevo material'
                          : 'Solicitud de materiales',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? green.withValues(alpha: 0.06) : const Color(0xFFF9FDF0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: green.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF8FD11B), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Esta funcionalidad estará disponible con integración al sistema central en la próxima versión.',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class LogisticsScreen extends StatefulWidget {
  const LogisticsScreen({super.key});

  @override
  State<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends State<LogisticsScreen> {
  // TODO: Reemplazar con estado real
  bool _showInventory = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Encabezado ────────────────────────────────────────
                const Text(
                  'Logística',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // ── Toggle Inventario / Solicitudes ────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _ToggleTab(
                        label: 'Inventario',
                        isSelected: _showInventory,
                        onTap: () => setState(() => _showInventory = true),
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

                // ── Buscador ──────────────────────────────────────────
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar materiales...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  // TODO: Conectar con lógica de búsqueda
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // ── Lista de materiales ──────────────────────────────────────
          Expanded(
            child: _showInventory
                ? _buildInventoryList()
                : _buildSolicitudesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryList() {
    // TODO: Reemplazar con ListView.builder + datos reales desde repositorio
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: const [
        _InventoryItemCard(
          name: 'Cable de Red CAT6',
          quantity: 450,
          unit: 'metros',
          minimum: 200,
          percentage: 113,
          isLow: false,
        ),
        SizedBox(height: 10),
        _InventoryItemCard(
          name: 'Conectores RJ45',
          quantity: 85,
          unit: 'piezas',
          minimum: 100,
          percentage: 43,
          isLow: true,
        ),
        SizedBox(height: 10),
        _InventoryItemCard(
          name: 'Switches de Red (24 puertos)',
          quantity: 12,
          unit: 'unidades',
          minimum: 5,
          percentage: 120,
          isLow: false,
        ),
        SizedBox(height: 10),
        _InventoryItemCard(
          name: 'Cable de Fibra Óptica',
          quantity: 150,
          unit: 'metros',
          minimum: 100,
          percentage: 75,
          isLow: false,
        ),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSolicitudesList() {
    // TODO: Conectar con lista real de solicitudes
    return const Center(
      child: Text(
        'Lista de solicitudes\n(conectar con datos reales)',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}

// ─── Tab de toggle ────────────────────────────────────────────────────────────
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
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tarjeta de item de inventario ───────────────────────────────────────────
class _InventoryItemCard extends StatelessWidget {
  final String name;
  final int quantity;
  final String unit;
  final int minimum;
  final int percentage;
  final bool isLow;

  const _InventoryItemCard({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.minimum,
    required this.percentage,
    required this.isLow,
  });

  @override
  Widget build(BuildContext context) {
    final barColor = isLow ? Colors.red : const Color(0xFF8FD11B);
    final clampedPercent = (percentage / 120).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre + badge "Bajo"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (isLow)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 12,
                        color: Colors.red,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Bajo',
                        style: TextStyle(color: Colors.red, fontSize: 11),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Cantidad
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$quantity ',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                TextSpan(
                  text: unit,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Barra de progreso
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clampedPercent,
              backgroundColor: Colors.grey.shade200,
              color: barColor,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mín: $minimum',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                '$percentage%',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

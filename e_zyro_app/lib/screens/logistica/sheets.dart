// Bottom sheets: detalle de item y nuevo material.
part of '../pantalla_logistica.dart';

// -- Bottom sheet: detalle de item (solo lectura) ------------------------------
// Sin selector de cantidad ni botón "Agregar al Pedido": esa funcionalidad se
// trasladó al detalle del servicio (donde la solicitud se vincula al servicio).
class _ItemDetailSheet extends StatelessWidget {
  final CatalogoItem item;
  const _ItemDetailSheet({required this.item});

  Color _stockColor() {
    if (item.stock == 0) return Colors.red;
    if (item.stock <= 10) return const Color(0xFFF59E0B);
    return const Color(0xFF8FD11B);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    final stockColor = _stockColor();

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
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? green.withValues(alpha: 0.12)
                      : const Color(0xFFEFFAE0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombre,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    if (item.categoria != null)
                      Text(item.categoria!,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    if (item.codigo != null)
                      Text('Cód: ${item.codigo}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // Stock card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: stockColor.withValues(alpha: isDark ? 0.08 : 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: stockColor.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Stock disponible',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(text: '${item.stock} ',
                        style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface)),
                      TextSpan(text: item.unidad,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.grey)),
                    ]),
                  ),
                ],
              ),
            ),
            if (item.descripcion != null && item.descripcion!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(item.descripcion!,
                  style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

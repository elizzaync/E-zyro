// Materiales: título de sección + card de material.
// (La solicitud de materiales se unificó en la pantalla de Préstamos:
//  ver _SolicitarPrestamoSheet en pantalla_prestamos_servicio.dart.)
part of '../pantalla_detalle_servicio.dart';

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionTitle(this.title, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final ItemMaterial item;
  final VoidCallback? onEdit;
  const _MaterialCard({required this.item, this.onEdit});

  // No se edita lo ya entregado o aprobado por Logística.
  bool get _editable =>
      item.estadoReq != 'entregado' && item.estadoReq != 'aprobado';

  Color _estadoColor() => switch (item.estadoReq) {
        'entregado' => _green,
        'aprobado' => const Color(0xFF3E80C0),
        'rechazado' => _danger,
        _ => _amber,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final tappable = _editable && onEdit != null;

    return InkWell(
      onTap: tappable ? onEdit : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isDark
                  ? Colors.grey.withValues(alpha: 0.20)
                  : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.nombre,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(item.estadoReq,
                      style: TextStyle(
                          color: _estadoColor(),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Text('${item.cantidad} ${item.unidad}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (tappable) ...[
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
            ],
          ],
        ),
      ),
    );
  }
}

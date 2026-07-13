// Cards/chips del catalogo y solicitudes.
part of '../pantalla_logistica.dart';

// -- Chip de categoría ---------------------------------------------------------
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
          border: Border.all(color: selected ? green : Colors.grey.shade300),
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

// -- Toggle tab ----------------------------------------------------------------
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

// -- Tarjeta de catálogo -------------------------------------------------------
class _CatalogoItemCard extends StatelessWidget {
  final CatalogoItem item;
  final VoidCallback onTap;

  const _CatalogoItemCard({
    required this.item,
    required this.onTap,
  });

  Color get _stockColor {
    if (item.stock == 0) return Colors.red;
    if (item.stock <= 10) return const Color(0xFFD98A16);
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

// -- Tarjeta de solicitud ------------------------------------------------------
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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


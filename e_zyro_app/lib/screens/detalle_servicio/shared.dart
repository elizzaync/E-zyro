// Widgets compartidos: estado vacio y vista de error.
part of '../pantalla_detalle_servicio.dart';

// ─── Banner: servicio cerrado (solo lectura) ──────────────────────────────────

class _ClosedBanner extends StatelessWidget {
  final String estado;
  const _ClosedBanner({required this.estado});

  @override
  Widget build(BuildContext context) {
    // Terminado: el backend usa 'Completado', pero puede llegar
    // 'finalizado'/'terminado' (comparación case-insensitive).
    final isTerminado = const {'completado', 'finalizado', 'terminado'}
        .contains(estado.trim().toLowerCase());
    final color = isTerminado ? _green : _danger;
    final icon = isTerminado ? Icons.task_alt : Icons.cancel_outlined;
    final label = isTerminado
        ? 'Servicio terminado — solo lectura'
        : 'Servicio cancelado — solo lectura';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ─── Estado vacío genérico ────────────────────────────────────────────────────

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─── Botón Equipos Intervenidos (aparece sobre la barra de tabs) ──────────────

class _EquiposIntervenidosButton extends StatelessWidget {
  final String servicioId;
  final String? ubicacionId;
  final String? zonaId;
  final bool isClosed;

  const _EquiposIntervenidosButton({
    required this.servicioId,
    this.ubicacionId,
    this.zonaId,
    this.isClosed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _EquiposIntervenidosSheet(
            servicioId: servicioId,
            ubicacionId: ubicacionId,
            zonaId: zonaId,
            isClosed: isClosed,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _green.withValues(alpha: 0.40)),
          ),
          child: Row(
            children: [
              const Icon(Icons.electrical_services_outlined, size: 16, color: _green),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Equipos Intervenidos',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _green),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: _green),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sheet: lista de equipos intervenidos ────────────────────────────────────

class _EquiposIntervenidosSheet extends StatelessWidget {
  final String servicioId;
  final String? ubicacionId;
  final String? zonaId;
  final bool isClosed;

  const _EquiposIntervenidosSheet({
    required this.servicioId,
    this.ubicacionId,
    this.zonaId,
    this.isClosed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.electrical_services_outlined, size: 18, color: _green),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Equipos Intervenidos',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _EquiposIntervenidosTab(
                servicioId: servicioId,
                ubicacionId: ubicacionId,
                zonaId: zonaId,
                isClosed: isClosed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No se pudo cargar el servicio',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _green),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Reintentar', style: TextStyle(color: _green)),
          ),
        ],
      ),
    );
  }
}


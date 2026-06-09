// Tab Procedimientos: lista, card, sheet de evidencias, thumb.
part of '../pantalla_detalle_servicio.dart';

// ─── Tab: Procedimientos (interactivo) ────────────────────────────────────────

class _ProcedimientosTab extends StatelessWidget {
  final List<ProcedimientoDetalle> procedimientos;
  final ProyectoService service;
  final Future<void> Function() onChanged;
  final void Function(ProcedimientoDetalle) onToggle;
  final bool isClosed;

  const _ProcedimientosTab({
    required this.procedimientos,
    required this.service,
    required this.onChanged,
    required this.onToggle,
    this.isClosed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (procedimientos.isEmpty) {
      return _EmptyTab(
        icon: Icons.checklist_outlined,
        label: 'Sin procedimientos registrados\nSe cargan desde la plantilla del tipo de trabajo',
      );
    }
    return ListView.separated(
      padding: bottomSafePadding(context),
      itemCount: procedimientos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ProcedimientoCard(
        proc: procedimientos[i],
        service: service,
        onChanged: onChanged,
        onToggle: onToggle,
        isClosed: isClosed,
      ),
    );
  }
}

class _ProcedimientoCard extends StatelessWidget {
  final ProcedimientoDetalle proc;
  final ProyectoService service;
  final Future<void> Function() onChanged;
  final void Function(ProcedimientoDetalle) onToggle;
  final bool isClosed;

  const _ProcedimientoCard({
    required this.proc,
    required this.service,
    required this.onChanged,
    required this.onToggle,
    this.isClosed = false,
  });

  Color get _color => switch (proc.estado) {
        'completado' => _green,
        'en_proceso' => const Color(0xFF3B82F6),
        'bloqueado' => _danger,
        _ => _amber,
      };

  IconData get _icon => switch (proc.estado) {
        'completado' => Icons.check_circle,
        'en_proceso' => Icons.play_circle_outline,
        'bloqueado' => Icons.block,
        _ => Icons.radio_button_unchecked,
      };

  void _abrirEvidencia(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EvidenciaSheet(
        proc: proc,
        service: service,
        onUploaded: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _color.withValues(alpha: isDark ? 0.30 : 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => onToggle(proc),
                child: Icon(_icon, color: _color, size: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${proc.orden}. ${proc.nombre}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              // Subir evidencia: oculto si el servicio está cerrado
              // (las evidencias ya subidas siguen visibles abajo).
              if (!isClosed)
                TextButton.icon(
                  onPressed: () => _abrirEvidencia(context),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                  label: const Text('Evidencia',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: _green,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                ),
            ],
          ),
          if (proc.descripcion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(proc.descripcion,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ],
          if (proc.evidencias.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    proc.evidencias.map((e) => _EvidenciaThumb(ev: e)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Sheet de subida de evidencia por etapa ───────────────────────────────────

class _EvidenciaSheet extends StatefulWidget {
  final ProcedimientoDetalle proc;
  final ProyectoService service;
  final Future<void> Function() onUploaded;

  const _EvidenciaSheet({
    required this.proc,
    required this.service,
    required this.onUploaded,
  });

  @override
  State<_EvidenciaSheet> createState() => _EvidenciaSheetState();
}

class _EvidenciaSheetState extends State<_EvidenciaSheet> {
  static const _etapas = ['antes', 'durante', 'despues'];
  static const _labels = {
    'antes': 'Antes',
    'durante': 'Durante',
    'despues': 'Después',
  };
  String? _subiendo; // etapa en curso
  final Set<String> _encoladas = {}; // etapas guardadas offline (pendientes)

  bool _tieneEtapa(String etapa) =>
      widget.proc.evidencias.any((e) => e.etapaLower == etapa) ||
      _encoladas.contains(etapa);

  Future<void> _capturar(String etapa) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: _green),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: _green),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 70);
    if (picked == null) return;

    setState(() => _subiendo = etapa);
    final subida = await widget.service.encolarEvidencia(
      procedimientoId: widget.proc.id,
      etapa: etapa,
      fotoPath: picked.path,
    );
    if (!mounted) return;
    setState(() {
      _subiendo = null;
      if (!subida) _encoladas.add(etapa);
    });
    if (subida) {
      // Subida directa (con conexión).
      await widget.onUploaded();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Evidencia "${_labels[etapa]}" subida', style: const TextStyle(color: Colors.white)),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } else {
      // Sin conexión: guardada en cola, se enviará al reconectar.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Evidencia "${_labels[etapa]}" guardada · se subirá al reconectar',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.amber.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
          Text('Evidencia: ${widget.proc.nombre}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Registra una foto por cada etapa del paso',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),
          ..._etapas.map((etapa) {
            final hecho = _tieneEtapa(etapa);
            final cargando = _subiendo == etapa;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    hecho ? Icons.check_circle : Icons.circle_outlined,
                    color: hecho ? _green : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_labels[etapa]!,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                  ElevatedButton(
                    onPressed: cargando ? null : () => _capturar(etapa),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hecho ? Colors.grey.shade300 : _green,
                      foregroundColor: hecho ? Colors.black54 : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: cargando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(hecho ? 'Reemplazar' : 'Capturar',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _EvidenciaThumb extends StatelessWidget {
  final EvidenciaDetalle ev;
  const _EvidenciaThumb({required this.ev});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: ev.urlCloudinary,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => Container(
            width: 64,
            height: 64,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            CachedNetworkImage(imageUrl: ev.urlCloudinary, fit: BoxFit.contain),
            if (ev.descripcion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(ev.descripcion,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}


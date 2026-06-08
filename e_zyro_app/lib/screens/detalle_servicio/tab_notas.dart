// Tab Notas: CRUD de notas del servicio.
part of '../pantalla_detalle_servicio.dart';

// ─── Tab: Notas (CRUD) ────────────────────────────────────────────────────────

class _NotasTab extends StatefulWidget {
  final String servicioId;
  final List<NotaSeguimiento> notasIniciales;
  final ProyectoService service;
  final bool isClosed;

  const _NotasTab({
    required this.servicioId,
    required this.notasIniciales,
    required this.service,
    this.isClosed = false,
  });

  @override
  State<_NotasTab> createState() => _NotasTabState();
}

class _NotasTabState extends State<_NotasTab> {
  final _nuevaCtrl = TextEditingController();
  List<NotaServicio> _notas = [];
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // Semilla inmediata desde el detalle (sin permisos), luego refresco real.
    _notas = widget.notasIniciales
        .map((n) => NotaServicio(
              id: n.id,
              descripcion: n.texto,
              autor: n.autor,
              fecha: n.fecha,
              puedeEditar: false,
            ))
        .toList();
    _cargar();
  }

  @override
  void dispose() {
    _nuevaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final data = await widget.service.getNotasServicio(widget.servicioId);
    if (!mounted) return;
    setState(() {
      _notas = data;
      _cargando = false;
    });
  }

  Future<void> _agregar() async {
    final texto = _nuevaCtrl.text.trim();
    if (texto.isEmpty || _guardando) return;
    setState(() => _guardando = true);
    final res = await widget.service.agregarNota(widget.servicioId, texto);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      _nuevaCtrl.clear();
      FocusScope.of(context).unfocus();
      if (res.queued) {
        _snack('Nota guardada · se enviará al reconectar', _amber);
      } else {
        await _cargar();
      }
    } else {
      _snack(res.errorMessage.isEmpty ? 'No se pudo agregar la nota' : res.errorMessage, _danger);
    }
  }

  Future<void> _editar(NotaServicio n) async {
    final ctrl = TextEditingController(text: n.descripcion);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar nota'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Texto de la nota…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final texto = ctrl.text.trim();
    if (texto.isEmpty) return;
    final res = await widget.service.actualizarNota(n.id, texto);
    if (!mounted) return;
    if (res.ok) {
      if (res.queued) {
        _snack('Edición guardada · se enviará al reconectar', _amber);
      } else {
        await _cargar();
      }
    } else {
      _snack(res.errorMessage.isEmpty ? 'No se pudo actualizar la nota' : res.errorMessage, _danger);
    }
  }

  Future<void> _eliminar(NotaServicio n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar nota'),
        content: const Text('¿Seguro que deseas eliminar esta nota?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _danger),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.service.eliminarNota(n.id);
    if (!mounted) return;
    if (res.ok) {
      if (res.queued) {
        setState(() => _notas.removeWhere((x) => x.id == n.id));
        _snack('Nota eliminada · se sincronizará al reconectar', _amber);
      } else {
        await _cargar();
      }
    } else {
      _snack(res.errorMessage.isEmpty ? 'No se pudo eliminar la nota' : res.errorMessage, _danger);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Column(
      children: [
        if (!widget.isClosed)
          // Campo de nueva nota
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nuevaCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Observación, mejora o recordatorio…',
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _agregar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(_green)))
              : _notas.isEmpty
                  ? _EmptyTab(
                      icon: Icons.notes_outlined,
                      label: 'Sin notas de seguimiento')
                  : RefreshIndicator(
                      color: _green,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: bottomSafePadding(context),
                        itemCount: _notas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _NotaCard(
                          nota: _notas[i],
                          surface: surface,
                          onEdit: () => _editar(_notas[i]),
                          onDelete: () => _eliminar(_notas[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _NotaCard extends StatelessWidget {
  final NotaServicio nota;
  final Color surface;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NotaCard({
    required this.nota,
    required this.surface,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? Border.all(color: _green.withValues(alpha: 0.20)) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? _green.withValues(alpha: 0.15)
                      : const Color(0xFFEFFAE0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_outline, size: 14, color: _green),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nota.autor,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(nota.fecha,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
              if (nota.puedeEditar) ...[
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.edit_outlined,
                        size: 18, color: Colors.grey),
                  ),
                ),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline, size: 18, color: _danger),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(nota.descripcion,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }
}


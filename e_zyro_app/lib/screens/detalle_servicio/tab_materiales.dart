// Tab Materiales: borrador, solicitar, recepcion+firma, cards.
part of '../pantalla_detalle_servicio.dart';

// ─── Tab: Materiales (con borrador interactivo) ───────────────────────────────

class _MaterialesTab extends StatefulWidget {
  final String servicioId;
  final List<ItemMaterial> asignados;
  final List<ItemMaterial> solicitados;
  final Borrador borrador;
  final List<ReqRecepcion> reqsRecepcion;
  final ProyectoService service;
  final Future<void> Function() onChanged;

  const _MaterialesTab({
    required this.servicioId,
    required this.asignados,
    required this.solicitados,
    required this.borrador,
    required this.reqsRecepcion,
    required this.service,
    required this.onChanged,
  });

  @override
  State<_MaterialesTab> createState() => _MaterialesTabState();
}

class _MaterialesTabState extends State<_MaterialesTab> {
  bool _enviando = false;
  bool _consenso = false;
  String? _firmandoReqId;

  // Préstamos del servicio (chip de aviso si hay devoluciones sin confirmar)
  int _avisosPrestamoCount = 0;
  PrestamoService? _prestamoService;

  @override
  void initState() {
    super.initState();
    _initPrestamos();
  }

  Future<void> _initPrestamos() async {
    _prestamoService = await getPrestamoService();
    await _refrescarAvisosPrestamo();
  }

  Future<void> _refrescarAvisosPrestamo() async {
    if (_prestamoService == null) return;
    final avisos =
        await _prestamoService!.getAvisosServicio(widget.servicioId);
    if (!mounted) return;
    setState(() => _avisosPrestamoCount = avisos.length);
  }

  Future<void> _abrirPrestamos() async {
    // El nombre del servicio no viene en _MaterialesTab; usamos uno genérico.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPrestamosServicio(
          servicioId: widget.servicioId,
          servicioNombre: 'Servicio',
        ),
      ),
    );
    if (mounted) await _refrescarAvisosPrestamo();
  }

  Future<void> _abrirSolicitar() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SolicitarMaterialSheet(
        servicioId: widget.servicioId,
        service: widget.service,
        onAgregado: widget.onChanged,
      ),
    );
  }

  Future<void> _enviarBorrador() async {
    if (widget.borrador.items.isEmpty) return;
    setState(() => _enviando = true);
    final res = await widget.service.enviarBorrador(widget.servicioId);
    if (!mounted) return;
    setState(() => _enviando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            res.ok
                ? 'Solicitud enviada a Logística'
                : (res.errorMessage.isEmpty ? 'Error al enviar' : res.errorMessage),
            style: const TextStyle(color: Colors.white)),
        backgroundColor: res.ok ? _green : _danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (res.ok) {
      _consenso = false;
      await widget.onChanged();
    }
  }

  Future<void> _quitar(BorradorItem item) async {
    final res = await widget.service.removerItemBorrador(item.id);
    if (!mounted) return;
    if (res.ok) {
      await widget.onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              res.errorMessage.isEmpty ? 'No se pudo quitar el ítem' : res.errorMessage,
              style: const TextStyle(color: Colors.white)),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Firma de recepción de materiales (HU-16, modelo híbrido) ───────────────
  // Cinema-seat: bloqueamos el lock ANTES de abrir la sheet para que ningún
  // otro técnico del equipo pueda firmar a la vez (los demás verán el banner
  // "X está firmando" en tiempo real por WS). Liberamos el lock si cancela o
  // si la firma falla. Si todo va bien, el endpoint /firmar libera el lock
  // automáticamente al hacer commit del nuevo estado 'aprobado'.
  Future<void> _firmarRecepcion(ReqRecepcion req) async {
    // 1) Tomar el lock
    final lock = await widget.service.bloquearFirmaRequerimiento(req.id);
    if (!mounted) return;
    if (!lock.ok) {
      // El backend devuelve detail='firmando_por:Juan Pérez' cuando otro tiene el lock.
      final quien = (lock.error ?? '').startsWith('firmando_por:')
          ? lock.error!.substring('firmando_por:'.length)
          : null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          quien != null
              ? '$quien está firmando ahora. Espera unos segundos…'
              : 'No se pudo iniciar la firma. Reintenta en unos segundos.',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: _amber,
        behavior: SnackBarBehavior.floating,
      ));
      // Refrescar para que la UI pinte el banner "X está firmando"
      await widget.onChanged();
      return;
    }

    // 2) Abrir la sheet de firma (con el lock tomado)
    final firmaUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FirmaRecepcionSheet(req: req),
    );

    // 3) Si canceló (no devolvió firma), liberar el lock y salir
    if (firmaUrl == null || firmaUrl.isEmpty) {
      await widget.service.liberarFirmaRequerimiento(req.id);
      return;
    }

    // 4) Enviar la firma — el backend libera el lock al hacer commit
    setState(() => _firmandoReqId = req.id);
    final res = await widget.service
        .firmarRequerimiento(req.id, firmaUrl, servicioId: widget.servicioId);
    if (!mounted) return;
    setState(() => _firmandoReqId = null);

    // 5) Si el POST online falló, liberamos el lock manualmente (offline
    // queda encolado: NO liberamos para no soltar el "asiento" durante la
    // ventana hasta el reintento).
    if (!res.ok && !res.queued) {
      await widget.service.liberarFirmaRequerimiento(req.id);
      if (!mounted) return;
    }

    final String msg;
    final Color color;
    if (res.queued) {
      msg = 'Firma guardada · se enviará a Logística al reconectar';
      color = _amber;
    } else if (res.ok) {
      msg = 'Recepción firmada · Logística fue notificada';
      color = _green;
    } else {
      msg = res.errorMessage.isEmpty ? 'No se pudo registrar la firma' : res.errorMessage;
      color = _danger;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Solo recargar si se confirmó online (offline el servidor aún no cambió).
    if (res.ok && !res.queued) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final borrador = widget.borrador;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            // ── Equipos y herramientas (préstamos FASE 5) ─────────────────────
            _EquiposHerramientasCard(
              avisosCount: _avisosPrestamoCount,
              onTap: _abrirPrestamos,
            ),
            const SizedBox(height: 16),

            // ── Recepción de materiales (firma HU-16) ─────────────────────────
            if (widget.reqsRecepcion.isNotEmpty) ...[
              const _SectionTitle('Recepción de Materiales',
                  Icons.assignment_turned_in_outlined, _green),
              const SizedBox(height: 8),
              ...widget.reqsRecepcion.map((req) => _RecepcionCard(
                    req: req,
                    firmando: _firmandoReqId == req.id,
                    onFirmar: () => _firmarRecepcion(req),
                  )),
              const SizedBox(height: 20),
            ],

            // ── Borrador en construcción ─────────────────────────────────────
            if (borrador.items.isNotEmpty) ...[
              Row(
                children: [
                  const _SectionTitle(
                      'Borrador de Solicitud', Icons.edit_note, _amber),
                  const Spacer(),
                  Text('${borrador.items.length} ítem(s)',
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 8),
              ...borrador.items.map((it) => _BorradorCard(
                    item: it,
                    onRemove: () => _quitar(it),
                    onEdit: () => _editar(it),
                  )),
              const SizedBox(height: 10),
              // Aviso anti-duplicidad: solo un técnico debe consolidar y enviar.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _amber.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 18, color: _amber),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '¡Atención equipo! Solo un técnico debe consolidar y enviar '
                        'la solicitud para evitar pedidos duplicados. Verifiquen entre '
                        'todos antes de confirmar.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _consenso = !_consenso),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _consenso,
                        onChanged: (v) => setState(() => _consenso = v ?? false),
                        activeColor: _green,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const Expanded(
                        child: Text(
                          'Confirmo que el equipo está de acuerdo con esta solicitud en lote',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_enviando || !_consenso) ? null : _enviarBorrador,
                  icon: _enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_outlined, size: 16),
                  label: Text(_enviando ? 'Enviando...' : 'Enviar a Logística',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _amber,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (widget.asignados.isEmpty &&
                widget.solicitados.isEmpty &&
                borrador.items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: _EmptyTab(
                  icon: Icons.inventory_2_outlined,
                  label: 'Sin materiales registrados',
                ),
              ),

            if (widget.asignados.isNotEmpty) ...[
              const _SectionTitle(
                  'Materiales Asignados', Icons.check_circle_outline, _green),
              const SizedBox(height: 8),
              ...widget.asignados.map((m) =>
                  _MaterialCard(item: m, onEdit: () => _editarMaterial(m))),
              const SizedBox(height: 16),
            ],
            if (widget.solicitados.isNotEmpty) ...[
              const _SectionTitle(
                  'Materiales Solicitados', Icons.pending_outlined, _amber),
              const SizedBox(height: 8),
              ...widget.solicitados.map((m) =>
                  _MaterialCard(item: m, onEdit: () => _editarMaterial(m))),
            ],
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'fab_solicitar_${widget.servicioId}',
            onPressed: _abrirSolicitar,
            backgroundColor: _green,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_shopping_cart_outlined),
            label: const Text('Solicitar',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // Editar cantidad de un material ya asignado/solicitado (si aún es editable).
  Future<void> _editarMaterial(ItemMaterial m) async {
    if (m.estadoReq == 'entregado' || m.estadoReq == 'aprobado') {
      _snack('Este ítem ya fue ${m.estadoReq} y no se puede editar.', _amber);
      return;
    }
    final cantCtrl = TextEditingController(text: '${m.cantidad}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m.nombre),
        content: TextField(
          controller: cantCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Cantidad'),
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
    final cant = int.tryParse(cantCtrl.text.trim()) ?? m.cantidad;
    final res = await widget.service
        .actualizarReqDetalle(m.id, cantidad: cant < 1 ? 1 : cant);
    if (!mounted) return;
    if (res.ok) {
      await widget.onChanged();
    } else {
      _snack(res.errorMessage.isEmpty ? 'No se pudo editar' : res.errorMessage, _danger);
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

  Future<void> _editar(BorradorItem item) async {
    final cantCtrl = TextEditingController(text: '${item.cantidad}');
    final nombreCtrl = TextEditingController(text: item.nombre);
    final especCtrl = TextEditingController(text: item.especificacion ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar ítem'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.esNuevo) ...[
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: especCtrl,
                decoration: const InputDecoration(labelText: 'Especificación'),
              ),
            ],
            TextField(
              controller: cantCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad'),
            ),
          ],
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
    final cant = int.tryParse(cantCtrl.text.trim()) ?? item.cantidad;
    final res = await widget.service.actualizarReqDetalle(
      item.id,
      cantidad: cant < 1 ? 1 : cant,
      nombre: item.esNuevo ? nombreCtrl.text.trim() : null,
      especificacion: item.esNuevo ? especCtrl.text.trim() : null,
    );
    if (!mounted) return;
    if (res.ok) {
      await widget.onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              res.errorMessage.isEmpty ? 'No se pudo editar el ítem' : res.errorMessage,
              style: const TextStyle(color: Colors.white)),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _BorradorCard extends StatelessWidget {
  final BorradorItem item;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const _BorradorCard({
    required this.item,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _amber.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(item.esNuevo ? Icons.shopping_bag_outlined : Icons.inventory_2_outlined,
              size: 16, color: _amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Text('${item.cantidad} ${item.unidad}${item.esNuevo ? ' · Compra externa' : ''}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: _danger),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}


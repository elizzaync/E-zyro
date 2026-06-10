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
  final bool isClosed;

  const _MaterialesTab({
    required this.servicioId,
    required this.asignados,
    required this.solicitados,
    required this.borrador,
    required this.reqsRecepcion,
    required this.service,
    required this.onChanged,
    this.isClosed = false,
  });

  @override
  State<_MaterialesTab> createState() => _MaterialesTabState();
}

class _MaterialesTabState extends State<_MaterialesTab> {
  bool _enviando = false;
  bool _consenso = false;
  bool _firmandoLote = false;

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
          isClosed: widget.isClosed,
        ),
      ),
    );
    if (mounted) await _refrescarAvisosPrestamo();
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
  /// Agrupa las solicitudes de recepción por etapa y devuelve una tarjeta por
  /// grupo. La etapa "listo para recibir" se firma toda con una sola firma.
  List<Widget> _buildRecepcionGrupos() {
    final reqs = widget.reqsRecepcion;
    final listo = reqs.where((r) => r.porFirmar).toList();
    final compra = reqs.where((r) => r.enCompra).toList();
    final recibido = reqs.where((r) => r.recibido).toList();
    final cerrado = reqs.where((r) => r.cerrado).toList();
    return [
      if (listo.isNotEmpty)
        _RecepcionGrupoCard(
          bucket: 'listo',
          reqs: listo,
          firmando: _firmandoLote,
          onFirmar: () => _firmarRecepcionLote(listo),
        ),
      if (compra.isNotEmpty)
        _RecepcionGrupoCard(bucket: 'compra', reqs: compra),
      if (recibido.isNotEmpty)
        _RecepcionGrupoCard(bucket: 'recibido', reqs: recibido),
      if (cerrado.isNotEmpty)
        _RecepcionGrupoCard(bucket: 'cerrado', reqs: cerrado),
    ];
  }

  /// Firma de recepción en lote: una sola firma recibe todas las solicitudes
  /// "listo para recibir". Se toma el lock por requerimiento antes de firmar
  /// cada uno (mantiene la anti-duplicidad por solicitud).
  Future<void> _firmarRecepcionLote(List<ReqRecepcion> reqs) async {
    if (widget.isClosed) {
      _snack('Servicio terminado — solo lectura', _amber);
      return;
    }
    final firmables =
        reqs.where((r) => r.porFirmar && !r.hayAlguienFirmando).toList();
    if (firmables.isEmpty) {
      _snack('No hay recepciones disponibles para firmar ahora.', _amber);
      return;
    }
    final totalItems =
        firmables.fold<int>(0, (a, r) => a + r.itemsValidos.length);

    // 1) Capturar UNA firma para todo el lote.
    final firmaUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FirmaRecepcionSheet(itemsCount: totalItems),
    );
    if (firmaUrl == null || firmaUrl.isEmpty || !mounted) return;

    // 2) Por cada requerimiento: lock → firmar (el backend libera el lock).
    setState(() => _firmandoLote = true);
    int ok = 0, encolados = 0, fallidos = 0;
    for (final req in firmables) {
      final lock = await widget.service.bloquearFirmaRequerimiento(req.id);
      if (!lock.ok) {
        fallidos++;
        continue;
      }
      final res = await widget.service
          .firmarRequerimiento(req.id, firmaUrl, servicioId: widget.servicioId);
      if (res.queued) {
        encolados++;
      } else if (res.ok) {
        ok++;
      } else {
        fallidos++;
        await widget.service.liberarFirmaRequerimiento(req.id);
      }
    }
    if (!mounted) return;
    setState(() => _firmandoLote = false);

    final partes = <String>[];
    if (ok > 0) partes.add('$ok firmada(s)');
    if (encolados > 0) partes.add('$encolados en cola');
    if (fallidos > 0) partes.add('$fallidos no disponible(s)');
    final color = fallidos > 0 && ok == 0 && encolados == 0
        ? _danger
        : (encolados > 0 ? _amber : _green);
    _snack('Recepción: ${partes.join(' · ')}', color);

    if (ok > 0) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final borrador = widget.borrador;
    return ListView(
      padding: bottomSafePadding(context, extra: 24),
      children: [
            // ── Equipos y herramientas (préstamos FASE 5) ─────────────────────
            _EquiposHerramientasCard(
              avisosCount: _avisosPrestamoCount,
              onTap: _abrirPrestamos,
            ),
            const SizedBox(height: 16),

            // ── Recepción de materiales (firma HU-16, agrupada por etapa) ─────
            if (widget.reqsRecepcion.isNotEmpty) ...[
              const _SectionTitle('Recepción de Materiales',
                  Icons.assignment_turned_in_outlined, _green),
              const SizedBox(height: 8),
              ..._buildRecepcionGrupos(),
              const SizedBox(height: 20),
            ],

            // ── Borrador en construcción (oculto si el servicio está cerrado) ──
            if (!widget.isClosed && borrador.items.isNotEmpty) ...[
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
    );
  }

  // Editar cantidad de un material ya asignado/solicitado (si aún es editable).
  Future<void> _editarMaterial(ItemMaterial m) async {
    if (widget.isClosed) {
      _snack('Servicio terminado — solo lectura', _amber);
      return;
    }
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


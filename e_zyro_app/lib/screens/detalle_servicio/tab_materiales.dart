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

// ─── Sheet: Solicitar material (catálogo + compra externa) ────────────────────

class _SolicitarMaterialSheet extends StatefulWidget {
  final String servicioId;
  final ProyectoService service;
  final Future<void> Function() onAgregado;

  const _SolicitarMaterialSheet({
    required this.servicioId,
    required this.service,
    required this.onAgregado,
  });

  @override
  State<_SolicitarMaterialSheet> createState() =>
      _SolicitarMaterialSheetState();
}

class _SolicitarMaterialSheetState extends State<_SolicitarMaterialSheet> {
  int _modo = 0; // 0 = catálogo · 1 = equipos/herramientas · 2 = compra externa
  bool _guardando = false;

  // Catálogo
  final _busquedaCtrl = TextEditingController();
  List<MaterialBusqueda> _resultados = [];
  MaterialBusqueda? _elegido;
  int _cantidad = 1;
  Timer? _debounce;

  // Equipos / Herramientas
  final _busquedaEqCtrl = TextEditingController();
  List<EquipoBusqueda> _resultadosEq = [];
  EquipoBusqueda? _equipoElegido;
  int _cantEquipo = 1;
  Timer? _debounceEq;

  // Compra externa
  final _nombreCtrl = TextEditingController();
  final _especCtrl = TextEditingController();
  String _unidad = 'Unidades';
  int _cantExterno = 1;

  @override
  void dispose() {
    _debounce?.cancel();
    _debounceEq?.cancel();
    _busquedaCtrl.dispose();
    _busquedaEqCtrl.dispose();
    _nombreCtrl.dispose();
    _especCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await widget.service.buscarMateriales(q);
      if (mounted) setState(() => _resultados = r);
    });
  }

  void _onSearchEq(String q) {
    _debounceEq?.cancel();
    _debounceEq = Timer(const Duration(milliseconds: 350), () async {
      final r = await widget.service.buscarEquipos(q);
      if (mounted) setState(() => _resultadosEq = r);
    });
  }

  Future<void> _agregarEquipo() async {
    final eq = _equipoElegido;
    if (eq == null) return;
    setState(() => _guardando = true);
    final etiqueta = eq.esHerramienta ? 'Herramienta' : 'Equipo';
    final res = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: null,
      nombre: eq.nombre,
      unidad: 'Unidades',
      cantidad: _cantEquipo,
      especificacion: '[$etiqueta] ${eq.nombre} del inventario',
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    } else {
      _snackError(res.errorMessage.isEmpty ? 'No se pudo agregar' : res.errorMessage);
    }
  }

  void _snackError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: _danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _agregarCatalogo() async {
    if (_elegido == null) return;
    setState(() => _guardando = true);
    final res = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: _elegido!.id,
      nombre: _elegido!.nombre,
      unidad: _elegido!.unidad,
      cantidad: _cantidad,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    } else {
      _snackError(res.errorMessage.isEmpty ? 'No se pudo agregar' : res.errorMessage);
    }
  }

  Future<void> _agregarExterno() async {
    final nombre = _nombreCtrl.text.trim();
    final espec = _especCtrl.text.trim();
    if (nombre.isEmpty || espec.isEmpty) return;
    setState(() => _guardando = true);
    final res = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: null,
      nombre: nombre,
      unidad: _unidad,
      cantidad: _cantExterno,
      especificacion: espec,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    } else {
      _snackError(res.errorMessage.isEmpty ? 'No se pudo agregar' : res.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
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
          const Text('Solicitar al Requerimiento',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Toggle: catálogo / equipos-herramientas / compra externa
          Row(
            children: [
              _ToggleChip(
                label: 'Material',
                selected: _modo == 0,
                onTap: () => setState(() => _modo = 0),
              ),
              const SizedBox(width: 6),
              _ToggleChip(
                label: 'Equipo/Herr.',
                selected: _modo == 1,
                onTap: () => setState(() => _modo = 1),
              ),
              const SizedBox(width: 6),
              _ToggleChip(
                label: 'Compra ext.',
                selected: _modo == 2,
                onTap: () => setState(() => _modo = 2),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_modo == 0)
            ..._buildCatalogo()
          else if (_modo == 1)
            ..._buildEquipos()
          else
            ..._buildExterno(),
        ],
      ),
    );
  }

  List<Widget> _buildCatalogo() {
    return [
      TextField(
        controller: _busquedaCtrl,
        onChanged: _onSearch,
        decoration: InputDecoration(
          hintText: 'Buscar material (mín. 2 letras)...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      if (_elegido == null && _resultados.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView(
            shrinkWrap: true,
            children: _resultados
                .map((m) => ListTile(
                      dense: true,
                      title: Text(m.nombre),
                      subtitle: Text('Stock: ${m.stock} ${m.unidad}'),
                      onTap: () => setState(() {
                        _elegido = m;
                        _busquedaCtrl.text = m.nombre;
                        _resultados = [];
                      }),
                    ))
                .toList(),
          ),
        ),
      if (_elegido != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _green.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_elegido!.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              _QtyStepper(
                value: _cantidad,
                onChanged: (v) => setState(() => _cantidad = v),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_elegido == null || _guardando) ? null : _agregarCatalogo,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Agregar al Borrador',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  List<Widget> _buildEquipos() {
    return [
      TextField(
        controller: _busquedaEqCtrl,
        onChanged: _onSearchEq,
        decoration: InputDecoration(
          hintText: 'Buscar equipo o herramienta (mín. 2 letras)...',
          prefixIcon: const Icon(Icons.handyman_outlined),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      if (_equipoElegido == null && _resultadosEq.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView(
            shrinkWrap: true,
            children: _resultadosEq
                .map((e) => ListTile(
                      dense: true,
                      title: Text(e.nombre),
                      subtitle: Text(
                          '${e.esHerramienta ? 'Herramienta' : 'Equipo'} · Disponibles: ${e.cantidad}'),
                      onTap: () => setState(() {
                        _equipoElegido = e;
                        _busquedaEqCtrl.text = e.nombre;
                        _resultadosEq = [];
                        _cantEquipo = 1;
                      }),
                    ))
                .toList(),
          ),
        ),
      if (_equipoElegido != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _green.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_equipoElegido!.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '${_equipoElegido!.esHerramienta ? 'Herramienta' : 'Equipo'} · Disp.: ${_equipoElegido!.cantidad}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              _QtyStepper(
                value: _cantEquipo,
                onChanged: (v) => setState(() => _cantEquipo = v),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed:
              (_equipoElegido == null || _guardando) ? null : _agregarEquipo,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Añadir al Borrador',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  List<Widget> _buildExterno() {
    return [
      TextField(
        controller: _nombreCtrl,
        decoration: InputDecoration(
          labelText: 'Nombre del material',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _especCtrl,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Especificación (obligatoria)',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _unidad,
              decoration: InputDecoration(
                labelText: 'Unidad',
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              items: const ['Unidades', 'Metros', 'Kilogramos', 'Litros', 'Cajas']
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => setState(() => _unidad = v ?? 'Unidades'),
            ),
          ),
          const SizedBox(width: 12),
          _QtyStepper(
            value: _cantExterno,
            onChanged: (v) => setState(() => _cantExterno = v),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _guardando ? null : _agregarExterno,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Agregar al Borrador',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _green : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? _green : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _QtyStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: _green),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          visualDensity: VisualDensity.compact,
        ),
        Text('$value',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: _green),
          onPressed: () => onChanged(value + 1),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

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
        'aprobado' => const Color(0xFF3B82F6),
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

// ─── Recepción de materiales: tarjeta + firma (HU-16) ─────────────────────────

class _RecepcionCard extends StatelessWidget {
  final ReqRecepcion req;
  final bool firmando;
  final VoidCallback onFirmar;

  const _RecepcionCard({
    required this.req,
    required this.firmando,
    required this.onFirmar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    // MODELO HÍBRIDO — flujo: comprando → listo → aprobado → entregado.
    //   'comprando'  ámbar  → sin stock, en proceso de compra
    //   'listo'      verde  → disponible, técnico puede firmar
    //   'aprobado'   azul   → técnico firmó, pendiente cierre administrativo
    //   'entregado'  verde  → logística cerró contablemente (final completo)
    const kBlueRecepcion = Color(0xFF3B82F6);
    final (String titulo, Color colorEstado, IconData iconoEstado) =
        req.cerrado
            ? ('Cerrado por logística', _green, Icons.verified_outlined)
            : req.recibido
                ? ('Recibido · pendiente cierre log', kBlueRecepcion,
                   Icons.assignment_turned_in_outlined)
                : req.enCompra
                    ? ('En compra · llegará pronto', _amber,
                       Icons.shopping_cart_outlined)
                    : ('Listo para recibir', _green,
                       Icons.inventory_2_outlined);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorEstado.withValues(alpha: isDark ? 0.30 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconoEstado, size: 16, color: colorEstado),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colorEstado.withValues(alpha: isDark ? 1 : 0.9)),
                ),
              ),
              Text('REQ ${req.id.substring(0, req.id.length >= 6 ? 6 : req.id.length).toUpperCase()}',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: req.itemsValidos
                .map((it) => Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${it.nombre} × ${it.cantidadEfectiva} ${it.unidad}'
                        '${it.esCompra ? ' (compra)' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text('Solicitado por ${req.solicitanteNombre}${req.fecha != null ? ' · ${req.fecha}' : ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 12),
          if (req.cerrado)
            Row(
              children: const [
                Icon(Icons.verified, size: 16, color: _green),
                SizedBox(width: 6),
                Text('Cerrado · doble firma archivada',
                    style: TextStyle(
                        color: _green, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            )
          else if (req.recibido)
            Row(
              children: const [
                Icon(Icons.check_circle, size: 16, color: kBlueRecepcion),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Firmado por el equipo · esperando cierre de logística',
                    style: TextStyle(
                        color: kBlueRecepcion,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          else if (req.enCompra)
            Row(
              children: const [
                Icon(Icons.schedule, size: 16, color: _amber),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Sin stock · en proceso de compra',
                      style: TextStyle(
                          color: _amber,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            )
          else ...[
            // Banner "X está firmando ahora" — actualizado en tiempo real por WS.
            if (req.hayAlguienFirmando && !firmando) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _amber.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.draw_outlined, size: 14, color: _amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${req.firmandoPorNombre} está firmando ahora…',
                      style: const TextStyle(
                          fontSize: 11.5, color: _amber, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (firmando || req.hayAlguienFirmando) ? null : onFirmar,
                icon: firmando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.draw_outlined, size: 16),
                label: Text(
                    firmando
                        ? 'Firmando...'
                        : (req.hayAlguienFirmando
                            ? 'Otro técnico está firmando'
                            : 'Firmar recepción'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet de firma de recepción. Reutiliza el patrón de firma de
/// Trámites/Permisos: dibujar con el dedo, usar la firma guardada en la nube,
/// o subir una imagen. Devuelve la firma como URL (nube) o data-url base64.
class _FirmaRecepcionSheet extends StatefulWidget {
  final ReqRecepcion req;
  const _FirmaRecepcionSheet({required this.req});

  @override
  State<_FirmaRecepcionSheet> createState() => _FirmaRecepcionSheetState();
}

class _FirmaRecepcionSheetState extends State<_FirmaRecepcionSheet> {
  late final SignatureController _controller;
  String? _firmaGuardadaUrl;
  bool _usarGuardada = false;
  bool _cargandoGuardada = true;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penColor: Colors.black,
      penStrokeWidth: 3.0,
      exportBackgroundColor: Colors.white,
    );
    _cargarFirmaGuardada();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cargarFirmaGuardada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final r = await http.get(
        Uri.parse('${AppConstants.baseUrl}/permisos/mi-firma'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final url = data['data']?['url_firma'] as String?;
        if (url != null && url.isNotEmpty && mounted) {
          setState(() {
            _firmaGuardadaUrl = url;
            _usarGuardada = true;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoGuardada = false);
    }
  }

  Future<void> _confirmar() async {
    // Usar la firma guardada en la nube → enviar esa URL.
    if (_usarGuardada && _firmaGuardadaUrl != null) {
      Navigator.pop(context, _firmaGuardadaUrl);
      return;
    }
    // Firma dibujada → exportar PNG como data-url base64.
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dibuja tu firma o usa la guardada'),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (bytes == null || !mounted) return;
    final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
    Navigator.pop(context, dataUrl);
  }

  Future<void> _subirGaleria() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    final Uint8List bytes = await image.readAsBytes();
    final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
    if (mounted) Navigator.pop(context, dataUrl);
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final usandoGuardada = _usarGuardada && _firmaGuardadaUrl != null;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
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
            Row(
              children: [
                const Icon(Icons.draw_outlined, color: _green, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Firmar recepción de materiales',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: muted, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Recibe: los ${widget.req.itemsValidos.length} ítem(s) aprobados',
                style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 14),

            // Toggle: usar guardada / dibujar nueva (si hay guardada)
            if (_cargandoGuardada)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                ),
              )
            else if (_firmaGuardadaUrl != null) ...[
              Row(
                children: [
                  _firmaTab('Usar guardada', _usarGuardada,
                      () => setState(() => _usarGuardada = true)),
                  const SizedBox(width: 8),
                  _firmaTab('Dibujar nueva', !_usarGuardada,
                      () => setState(() => _usarGuardada = false)),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Lienzo o preview de firma guardada
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: usandoGuardada
                    ? Image.network(_firmaGuardadaUrl!, fit: BoxFit.contain)
                    : Signature(
                        controller: _controller,
                        backgroundColor: Colors.white,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            if (!usandoGuardada)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Firma en el recuadro con tu dedo',
                      style: TextStyle(color: muted, fontSize: 12)),
                  TextButton.icon(
                    onPressed: () => _controller.clear(),
                    icon: Icon(Icons.refresh, size: 15, color: muted),
                    label: Text('Limpiar',
                        style: TextStyle(color: muted, fontSize: 13)),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _subirGaleria,
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Galería'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: muted,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _confirmar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Confirmar firma y notificar',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _firmaTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? _green : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}


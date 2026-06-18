// Tab Equipos Intervenidos: activos de la sede del servicio + inspección.
// Réplica de la lógica del componente Angular `equipos-intervenidos`:
// filtro multi-campo, selección masiva (informe general / carta de garantía),
// edición de "Referencia", alta de equipo en catálogo y navegación a la
// inspección del equipo.
part of '../pantalla_detalle_servicio.dart';

// ─── Helpers de documento (.docx) ─────────────────────────────────────────────

/// Guarda bytes de un documento generado (p. ej. .docx) con diálogo del
/// sistema y avisa el resultado. Devuelve true si se guardó.
Future<bool> _guardarDocumentoBytes(
  BuildContext context,
  Uint8List bytes,
  String nombreArchivo,
) async {
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar documento',
      fileName: nombreArchivo,
      bytes: bytes,
    );
    if (!context.mounted) return false;
    if (path == null) return false; // cancelado por el usuario
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Documento guardado: $nombreArchivo',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo guardar el documento'),
        backgroundColor: _danger,
      ));
    }
    return false;
  }
}

String _sanearArchivo(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

/// Lee una imagen y la convierte a data-url base64 (firmas de los documentos).
Future<String?> _imagenADataUrl() async {
  final picker = ImagePicker();
  final file = await picker.pickImage(source: ImageSource.gallery);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final ext = file.path.split('.').last.toLowerCase();
  final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/png';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

// ─── Tab: Equipos Intervenidos ────────────────────────────────────────────────

class _EquiposIntervenidosTab extends StatefulWidget {
  final String servicioId;
  final bool isClosed;
  final String? ubicacionId;
  final String? zonaId;

  const _EquiposIntervenidosTab({
    required this.servicioId,
    this.isClosed = false,
    this.ubicacionId,
    this.zonaId,
  });

  @override
  State<_EquiposIntervenidosTab> createState() =>
      _EquiposIntervenidosTabState();
}

class _EquiposIntervenidosTabState extends State<_EquiposIntervenidosTab> {
  IntervencionService? _svc;
  bool _cargando = true;
  bool _error = false;
  List<EquipoIntervenidoServicio> _equipos = [];
  List<CatalogoItemSimple> _tiposDisp = [];
  String _filtro = '';
  final Set<String> _seleccionados = {};
  final _filtroCtrl = TextEditingController();
  // "Otros equipos de la sede" arranca plegado: el foco es el servicio actual.
  bool _otrosExpandido = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = IntervencionService(ApiClient(prefs));
    await _cargar();
    // Tipos de equipo del catálogo (tabla tipo_equipo), no derivados de la lista.
    final tipos = await _svc!.getTiposEquipo();
    if (mounted) setState(() => _tiposDisp = tipos);
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = false;
      _seleccionados.clear();
    });
    final res = await _svc!.getEquiposIntervenidos(
      widget.servicioId,
      ubicacionId: widget.ubicacionId,
      zonaId: widget.zonaId,
    );
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok) {
        _equipos = res.data ?? [];
      } else {
        _error = true;
      }
    });
  }

  // ── Filtro (mismos 6 campos que el frontend) ───────────────────────────────
  List<EquipoIntervenidoServicio> get _filtrados {
    final q = _filtro.toLowerCase().trim();
    if (q.isEmpty) return _equipos;
    return _equipos
        .where((e) =>
            e.nombre.toLowerCase().contains(q) ||
            (e.tipoNombre ?? '').toLowerCase().contains(q) ||
            (e.ubicacion ?? '').toLowerCase().contains(q) ||
            (e.zona ?? '').toLowerCase().contains(q) ||
            (e.ubicacionReferencia ?? '').toLowerCase().contains(q) ||
            (e.codigo ?? '').toLowerCase().contains(q))
        .toList();
  }

  List<EquipoIntervenidoServicio> get _seleccion =>
      _equipos.where((e) => _seleccionados.contains(e.id)).toList();

  bool get _todosSeleccionados {
    final vis = _filtrados;
    return vis.isNotEmpty && vis.every((e) => _seleccionados.contains(e.id));
  }

  void _toggleTodos() {
    final vis = _filtrados;
    setState(() {
      if (_todosSeleccionados) {
        for (final e in vis) {
          _seleccionados.remove(e.id);
        }
      } else {
        for (final e in vis) {
          _seleccionados.add(e.id);
        }
      }
    });
  }

  void _snackTab(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Acción: Generar Informe General ────────────────────────────────────────
  // Regla estricta (igual que la web): solo se agrupa el MISMO tipo de equipo.
  void _generarInforme() {
    final sel = _seleccion;
    if (sel.isEmpty) {
      _snackTab('Selecciona al menos un equipo para generar el informe.', _amber);
      return;
    }
    final tipos = sel.map((e) => e.tipoEquipoId ?? e.tipoNombre ?? '∅').toSet();
    if (tipos.length > 1) {
      _snackTab('El informe general solo permite agrupar equipos del mismo tipo.',
          _danger);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InformeGeneralSheet(
        servicioId: widget.servicioId,
        equipos: sel,
        service: _svc!,
      ),
    );
  }

  // ── Acción: Carta de Garantía (solo equipos TABLERO) ───────────────────────
  void _cartaGarantia() {
    final sel = _seleccion;
    if (sel.isEmpty) {
      _snackTab('Selecciona al menos un equipo para emitir la garantía.', _amber);
      return;
    }
    final noTablero = sel
        .where((e) => !((e.tipoNombre ?? '').toUpperCase().contains('TABLERO')))
        .toList();
    if (noTablero.isNotEmpty) {
      _snackTab('La carta de garantía solo puede generarse para Tableros Eléctricos.',
          _danger);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CartaGarantiaSheet(
        servicioId: widget.servicioId,
        equipos: sel,
        service: _svc!,
      ),
    );
  }

  // ── Editar "Referencia" (indicaciones físicas) ─────────────────────────────
  Future<void> _editarReferencia(EquipoIntervenidoServicio eq) async {
    final ctrl = TextEditingController(text: eq.ubicacionReferencia ?? '');
    final valor = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar referencia'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Indicaciones físicas de dónde está el equipo',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              child: const Text('Guardar',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (valor == null || !mounted) return;
    final limpio = valor.trim();
    if (limpio == (eq.ubicacionReferencia ?? '')) return;
    final res = await _svc!.actualizarEquipo(
        widget.servicioId, eq.id, {'ubicacion_referencia': limpio});
    if (!mounted) return;
    if (res.ok) {
      setState(() => eq.ubicacionReferencia =
          res.data?['ubicacion_referencia'] as String? ??
              (limpio.isEmpty ? null : limpio));
      _snackTab('Referencia actualizada.', _green);
    } else {
      _snackTab(
          res.errorMessage.isEmpty
              ? 'No se pudo guardar la referencia.'
              : res.errorMessage,
          _danger);
    }
  }

  // ── Agregar equipo al catálogo ─────────────────────────────────────────────
  Future<void> _abrirFormNuevo() async {
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgregarEquipoSheet(
        servicioId: widget.servicioId,
        tipos: _tiposDisp,
        service: _svc!,
      ),
    );
    if (creado == true) await _cargar();
  }

  // ── Inspeccionar (navega a la pantalla de inspección) ──────────────────────
  Future<void> _inspeccionar(EquipoIntervenidoServicio eq) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaIntervencionEquipo(
          servicioId: widget.servicioId,
          eiId: eq.id,
          nombreEquipo: eq.nombre,
        ),
      ),
    );
    if (mounted) await _cargar();
  }

  static String _estadoIntervencionLabel(String e) => switch (e) {
        'sin_inspeccion' => 'Sin inspección',
        'en_proceso' => 'En Proceso',
        'completado' => 'Completado',
        _ => e,
      };

  static Color _estadoIntervencionColor(String e) => switch (e) {
        'en_proceso' => const Color(0xFF3B82F6),
        'completado' => _green,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_green),
        ),
      );
    }
    if (_error) return _ErrorView(onRetry: _cargar);

    final filtrados = _filtrados;
    // Separar lo que se interviene en ESTE servicio (protagonista) del resto
    // de equipos de la sede (contexto, plegado por defecto).
    final delServicio = filtrados.where((e) => e.delServicioActual).toList();
    final otros = filtrados.where((e) => !e.delServicioActual).toList();
    return Column(
      children: [
        // Banner: equipos filtrados por ubicación/zona del servicio
        if (widget.ubicacionId != null || widget.zonaId != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _green.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: _green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Equipos de la ubicación y zona de este servicio.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        // Buscador + acciones
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filtroCtrl,
                  onChanged: (v) => setState(() => _filtro = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar equipo, tipo, zona, código…',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (!widget.isClosed) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _abrirFormNuevo,
                  style: IconButton.styleFrom(backgroundColor: _green),
                  tooltip: 'Agregar equipo',
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ],
            ],
          ),
        ),
        // Barra de selección masiva (informe / garantía)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              InkWell(
                onTap: _toggleTodos,
                child: Row(
                  children: [
                    Icon(
                      _todosSeleccionados
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: _todosSeleccionados ? _green : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _seleccionados.isEmpty
                          ? 'Seleccionar'
                          : '${_seleccionados.length} seleccionado(s)',
                      style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_seleccionados.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: _generarInforme,
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Informe', style: TextStyle(fontSize: 12)),
                ),
                TextButton.icon(
                  onPressed: _cartaGarantia,
                  icon: const Icon(Icons.verified_outlined, size: 16),
                  label: const Text('Garantía', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: filtrados.isEmpty
              ? const _EmptyTab(
                  icon: Icons.electrical_services_outlined,
                  label: 'No hay equipos para esta sede')
              : RefreshIndicator(
                  onRefresh: _cargar,
                  color: _green,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      // ── Sección protagonista: equipos de ESTE servicio ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.play_circle_outline,
                                size: 18, color: _green),
                            const SizedBox(width: 6),
                            Text('En este servicio (${delServicio.length})',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: _green)),
                          ],
                        ),
                      ),
                      if (delServicio.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                          child: Text(
                            'Aún no abriste ningún equipo en este servicio. '
                            'Elige uno de la sede para empezar a registrar fotos.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        )
                      else
                        for (final eq in delServicio) _equipoCard(eq),
                      // ── Sección secundaria: otros equipos (plegable) ────
                      if (otros.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(
                              () => _otrosExpandido = !_otrosExpandido),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  _otrosExpandido
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 20,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Otros equipos de la sede (${otros.length})',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_otrosExpandido)
                          for (final eq in otros) _equipoCard(eq),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // Tarjeta de un equipo, reutilizada en ambas secciones del listado.
  Widget _equipoCard(EquipoIntervenidoServicio eq) {
    final sel = _seleccionados.contains(eq.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: sel
              ? _green.withValues(alpha: 0.6)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _inspeccionar(eq),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () => setState(() => sel
                        ? _seleccionados.remove(eq.id)
                        : _seleccionados.add(eq.id)),
                    child: Icon(
                      sel
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: sel ? _green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(eq.nombre,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5)),
                        if ((eq.codigo ?? '').isNotEmpty)
                          Text(eq.codigo!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _estadoIntervencionColor(eq.estadoIntervencion)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _estadoIntervencionLabel(eq.estadoIntervencion),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _estadoIntervencionColor(eq.estadoIntervencion),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  if ((eq.tipoNombre ?? '').isNotEmpty)
                    _InfoMini(
                        icon: Icons.category_outlined, text: eq.tipoNombre!),
                  if ((eq.ubicacion ?? '').isNotEmpty)
                    _InfoMini(
                        icon: Icons.place_outlined,
                        text: eq.zona == null
                            ? eq.ubicacion!
                            : '${eq.ubicacion} / ${eq.zona}'),
                  if ((eq.ultimoMantenimiento ?? '').isNotEmpty)
                    _InfoMini(
                        icon: Icons.history,
                        text: 'Últ.: ${eq.ultimoMantenimiento}'),
                  if ((eq.proximoMantenimiento ?? '').isNotEmpty)
                    _InfoMini(
                        icon: Icons.event_outlined,
                        text: 'Próx.: ${eq.proximoMantenimiento}'),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.push_pin_outlined,
                      size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      (eq.ubicacionReferencia ?? '').isEmpty
                          ? 'Sin referencia'
                          : eq.ubicacionReferencia!,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                          fontStyle: (eq.ubicacionReferencia ?? '').isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!widget.isClosed)
                    InkWell(
                      onTap: () => _editarReferencia(eq),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.edit_outlined,
                            size: 15, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoMini extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoMini({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}

// ─── Sheet: Agregar equipo al catálogo ────────────────────────────────────────
// Ubicación y Zona NO se envían: el backend las hereda de la sede del servicio.

class _AgregarEquipoSheet extends StatefulWidget {
  final String servicioId;
  final List<CatalogoItemSimple> tipos;
  final IntervencionService service;

  const _AgregarEquipoSheet({
    required this.servicioId,
    required this.tipos,
    required this.service,
  });

  @override
  State<_AgregarEquipoSheet> createState() => _AgregarEquipoSheetState();
}

class _AgregarEquipoSheetState extends State<_AgregarEquipoSheet> {
  final _nombreCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _tipoId;
  String _estado = 'operativo';
  bool _guardando = false;

  static const _estadosDisp = [
    ('operativo', 'Operativo'),
    ('inoperativo', 'Inoperativo'),
    ('mantenimiento', 'En mantenimiento'),
    ('en_revision', 'En revisión'),
  ];

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _refCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa el nombre del equipo'),
          backgroundColor: _danger));
      return;
    }
    setState(() => _guardando = true);
    final res = await widget.service.crearEquipo(
      widget.servicioId,
      nombre: nombre,
      tipoEquipoId: _tipoId,
      ubicacionReferencia: _refCtrl.text.trim(),
      estado: _estado,
      descripcion: _descCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.errorMessage.isEmpty
              ? 'Error al crear el equipo.'
              : res.errorMessage),
          backgroundColor: _danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Agregar equipo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('La ubicación y zona se heredan de la sede del servicio.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 14),
            TextField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nombre del equipo *',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _tipoId,
              decoration: const InputDecoration(
                  labelText: 'Tipo de equipo', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('— Sin tipo —')),
                for (final t in widget.tipos)
                  DropdownMenuItem(value: t.id, child: Text(t.nombre)),
              ],
              onChanged: (v) => setState(() => _tipoId = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                  labelText: 'Referencia (dónde está el equipo)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _estado,
              decoration: const InputDecoration(
                  labelText: 'Estado', border: OutlineInputBorder()),
              items: [
                for (final (v, label) in _estadosDisp)
                  DropdownMenuItem(value: v, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _estado = v ?? 'operativo'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Descripción', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
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
                    : const Text('Agregar al catálogo',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet: Generar Informe General (.docx) ───────────────────────────────────
// Precarga: EPPs por tipo + catálogo BD; materiales/herramientas defaults por
// tipo + lo real del servicio (merge sin duplicados por nombre); personal del
// proyecto auto-poblado con rol sugerido. La OC es obligatoria.

class _InformeGeneralSheet extends StatefulWidget {
  final String servicioId;
  final List<EquipoIntervenidoServicio> equipos;
  final IntervencionService service;

  const _InformeGeneralSheet({
    required this.servicioId,
    required this.equipos,
    required this.service,
  });

  @override
  State<_InformeGeneralSheet> createState() => _InformeGeneralSheetState();
}

class _InformeGeneralSheetState extends State<_InformeGeneralSheet> {
  bool _cargando = true;
  bool _enviando = false;

  late TipoBaseInforme _tipoBase;
  String _servicioNombre = '(servicio actual)';
  final _ocCtrl = TextEditingController();

  List<String> _epps = [];
  List<MaterialInforme> _materiales = [];
  List<HerramientaInforme> _herramientas = [];
  List<PersonalInforme> _personalDisp = [];
  List<({String id, String nombre, String rol})> _personalAsignado = [];
  List<CatalogoItemSimple> _catalogoEpps = [];
  String? _eppSel;
  String? _personalSel;

  @override
  void initState() {
    super.initState();
    _tipoBase = determinarTipoBase(widget.equipos.map((e) => e.tipoNombre));
    _epps = [...kEppsConfig[_tipoBase]!];
    _materiales = [...kMaterialesConfig[_tipoBase]!];
    _herramientas = [...kHerramientasConfig[_tipoBase]!];
    _precargar();
  }

  @override
  void dispose() {
    _ocCtrl.dispose();
    super.dispose();
  }

  /// Rol auto-sugerido: Supervisor si el rol del proyecto sugiere liderazgo.
  static String _rolDe(String rolSugerido) =>
      RegExp(r'supervis|jefe|lider|líder', caseSensitive: false)
              .hasMatch(rolSugerido)
          ? 'Supervisor'
          : 'Técnico';

  Future<void> _precargar() async {
    final resultados = await Future.wait([
      widget.service.getPrecargaInforme(widget.servicioId),
      widget.service.getEppCatalogo(),
    ]);
    if (!mounted) return;

    final pre = resultados[0] as ApiResult<PrecargaInforme>;
    final epps = resultados[1] as List<CatalogoItemSimple>;

    setState(() {
      _catalogoEpps = [
        for (final e in epps)
          CatalogoItemSimple(id: e.id, nombre: e.nombre.toUpperCase()),
      ];
      if (pre.ok && pre.data != null) {
        final p = pre.data!;
        _servicioNombre = p.servicioNombre.isEmpty
            ? '(servicio actual)'
            : '${p.servicioNombre}${p.proyectoNombre != null ? ' — ${p.proyectoNombre}' : ''}';
        // Auto-rellenar OC si el servicio tiene una Orden de Compra registrada
        if (p.tipoDocumento == 'OC' && p.nroDocumento.isNotEmpty) {
          _ocCtrl.text = p.nroDocumento;
        }
        _materiales = _mergePorNombre(
            _materiales, p.materialesSolicitados, (m) => m.nombre);
        _herramientas = _mergePorNombre(
            _herramientas, p.herramientasSolicitadas, (h) => h.nombre);
        _personalDisp = p.personal;
        _personalAsignado = [
          for (final emp in p.personal)
            (id: emp.id, nombre: emp.nombre, rol: _rolDe(emp.rolSugerido)),
        ];
      }
      _cargando = false;
    });
  }

  /// Une base + extra omitiendo duplicados exactos por nombre (case-insensitive).
  static List<T> _mergePorNombre<T>(
      List<T> base, List<T> extra, String Function(T) key) {
    final vistos = base.map((x) => key(x).trim().toUpperCase()).toSet();
    final out = [...base];
    for (final e in extra) {
      final k = key(e).trim().toUpperCase();
      if (k.isEmpty || vistos.contains(k)) continue;
      vistos.add(k);
      out.add(e);
    }
    return out;
  }

  List<CatalogoItemSimple> get _eppsDisponibles {
    final usados = _epps.map((e) => e.toUpperCase()).toSet();
    return _catalogoEpps.where((e) => !usados.contains(e.nombre)).toList();
  }

  List<PersonalInforme> get _personalNoAsignado {
    final ids = _personalAsignado.map((p) => p.id).toSet();
    return _personalDisp.where((p) => !ids.contains(p.id)).toList();
  }

  Future<void> _generar() async {
    final oc = _ocCtrl.text.trim();
    if (oc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa el número de OC antes de generar el informe.'),
          backgroundColor: _danger));
      return;
    }
    setState(() => _enviando = true);
    // Payload exacto del frontend (onSubmitInforme).
    final payload = {
      'oc': oc,
      'servicio_id': widget.servicioId,
      'tipo_base': _tipoBase.api,
      'equipos': [
        for (final e in widget.equipos)
          {
            'id': e.id,
            'tipo': e.tipoNombre,
            'nombre': e.nombre,
            'provincia': e.ubicacion,
            'zona': e.zona,
          },
      ],
      'epps': _epps,
      'materiales': [for (final m in _materiales) m.toJson()],
      'herramientas': [for (final h in _herramientas) h.toJson()],
      'personal': [
        for (final p in _personalAsignado)
          {'id': p.id, 'nombre': p.nombre, 'rol': p.rol},
      ],
    };
    final res =
        await widget.service.generarInformeGeneral(widget.servicioId, payload);
    if (!mounted) return;
    setState(() => _enviando = false);
    if (res.ok && res.data != null) {
      final ok = await _guardarDocumentoBytes(context, res.data!,
          'INFORME_MTTO_${_tipoBase.api}_OC_${_sanearArchivo(oc)}.docx');
      if (ok && mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.errorMessage.isEmpty
              ? 'Error al generar el informe.'
              : res.errorMessage),
          backgroundColor: _danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: _cargando
          ? const SizedBox(
              height: 200,
              child: Center(
                  child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_green))))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Generar Informe General',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(_servicioNombre,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Text(
                      '${widget.equipos.length} equipo(s) · tipo ${_tipoBase.api}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ocCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Nº de OC *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  _SeccionTitulo('EPPs (${_epps.length})'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < _epps.length; i++)
                        Chip(
                          label: Text(_epps[i],
                              style: const TextStyle(fontSize: 10.5)),
                          visualDensity: VisualDensity.compact,
                          onDeleted: () => setState(() => _epps.removeAt(i)),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _eppSel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Agregar EPP del catálogo',
                              isDense: true,
                              border: OutlineInputBorder()),
                          items: [
                            for (final e in _eppsDisponibles)
                              DropdownMenuItem(
                                  value: e.nombre,
                                  child: Text(e.nombre,
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _eppSel = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: _green),
                        onPressed: () {
                          final v = _eppSel?.trim().toUpperCase() ?? '';
                          if (v.isEmpty) return;
                          if (_epps.any((e) => e.toUpperCase() == v)) return;
                          setState(() {
                            _epps.add(v);
                            _eppSel = null;
                          });
                        },
                        icon: const Icon(Icons.add,
                            size: 18, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SeccionTitulo('Materiales (${_materiales.length})'),
                  for (var i = 0; i < _materiales.length; i++)
                    _FilaEliminable(
                      texto:
                          '${_materiales[i].nombre} · ${_materiales[i].unidad}',
                      onDelete: () => setState(() => _materiales.removeAt(i)),
                    ),
                  const SizedBox(height: 14),
                  _SeccionTitulo('Herramientas (${_herramientas.length})'),
                  for (var i = 0; i < _herramientas.length; i++)
                    _FilaEliminable(
                      texto: _herramientas[i].marca == '-'
                          ? _herramientas[i].nombre
                          : '${_herramientas[i].nombre} · ${_herramientas[i].marca}',
                      onDelete: () => setState(() => _herramientas.removeAt(i)),
                    ),
                  const SizedBox(height: 14),
                  _SeccionTitulo('Personal (${_personalAsignado.length})'),
                  for (var i = 0; i < _personalAsignado.length; i++)
                    _FilaEliminable(
                      texto:
                          '${_personalAsignado[i].nombre} — ${_personalAsignado[i].rol}',
                      onDelete: () =>
                          setState(() => _personalAsignado.removeAt(i)),
                    ),
                  if (_personalNoAsignado.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _personalSel,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Agregar personal',
                                isDense: true,
                                border: OutlineInputBorder()),
                            items: [
                              for (final p in _personalNoAsignado)
                                DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.nombre,
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setState(() => _personalSel = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: _green),
                          onPressed: () {
                            final emp = _personalDisp
                                .where((p) => p.id == _personalSel)
                                .firstOrNull;
                            if (emp == null) return;
                            setState(() {
                              _personalAsignado.add((
                                id: emp.id,
                                nombre: emp.nombre,
                                rol: _rolDe(emp.rolSugerido),
                              ));
                              _personalSel = null;
                            });
                          },
                          icon: const Icon(Icons.add,
                              size: 18, color: Colors.white),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _enviando ? null : _generar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _enviando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.description_outlined,
                              size: 18, color: Colors.white),
                      label: Text(
                          _enviando ? 'Generando…' : 'Generar informe (.docx)',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SeccionTitulo extends StatelessWidget {
  final String texto;
  const _SeccionTitulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

class _FilaEliminable extends StatelessWidget {
  final String texto;
  final VoidCallback onDelete;
  const _FilaEliminable({required this.texto, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(texto,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          InkWell(
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sheet: Carta de Garantía (solo Tableros Eléctricos) ──────────────────────

class _CartaGarantiaSheet extends StatefulWidget {
  final String servicioId;
  final List<EquipoIntervenidoServicio> equipos;
  final IntervencionService service;

  const _CartaGarantiaSheet({
    required this.servicioId,
    required this.equipos,
    required this.service,
  });

  @override
  State<_CartaGarantiaSheet> createState() => _CartaGarantiaSheetState();
}

class _CartaGarantiaSheetState extends State<_CartaGarantiaSheet> {
  final _razonCtrl = TextEditingController();
  final _lugarCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  String _fechaOp = '';
  String _vigencia = '';
  String _firmaVerB64 = '';
  String _firmaGerB64 = '';
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    // Fechas: hoy + 1 año (mismo default que el frontend).
    final hoy = DateTime.now();
    _fechaOp = hoy.toIso8601String().split('T').first;
    _vigencia = DateTime(hoy.year + 1, hoy.month, hoy.day)
        .toIso8601String()
        .split('T')
        .first;
    // Lugar: primer equipo con ubicación; dirección desde el mapa de aeropuertos.
    final lugar = (widget.equipos
                .map((e) => e.ubicacion)
                .firstWhere((u) => (u ?? '').isNotEmpty, orElse: () => '') ??
            '')
        .toUpperCase();
    _lugarCtrl.text = lugar;
    _direccionCtrl.text = kAeropuertos[lugar] ?? '';
    // Razón social desde la precarga (cliente del proyecto).
    widget.service.getPrecargaInforme(widget.servicioId).then((res) {
      if (mounted && res.ok && (res.data?.clienteNombre ?? '').isNotEmpty) {
        setState(() => _razonCtrl.text = res.data!.clienteNombre!);
      }
    });
  }

  @override
  void dispose() {
    _razonCtrl.dispose();
    _lugarCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFecha() async {
    final actual = DateTime.tryParse(_fechaOp) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(actual.year - 2),
      lastDate: DateTime(actual.year + 3),
    );
    if (d == null) return;
    setState(() {
      _fechaOp = d.toIso8601String().split('T').first;
      // Vigencia = fecha de operatividad + 1 año (recalcularVigencia).
      _vigencia = DateTime(d.year + 1, d.month, d.day)
          .toIso8601String()
          .split('T')
          .first;
    });
  }

  void _onLugarChange(String v) {
    final key = v.toUpperCase().trim();
    setState(() => _direccionCtrl.text = kAeropuertos[key] ?? '');
  }

  Future<void> _firmar(bool verificador) async {
    final b64 = await _imagenADataUrl();
    if (b64 == null || !mounted) return;
    setState(() {
      if (verificador) {
        _firmaVerB64 = b64;
      } else {
        _firmaGerB64 = b64;
      }
    });
  }

  Future<void> _generar() async {
    if (_razonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa la Razón Social antes de generar.'),
          backgroundColor: _danger));
      return;
    }
    if (_fechaOp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La Fecha de Operatividad es requerida.'),
          backgroundColor: _danger));
      return;
    }
    setState(() => _enviando = true);
    // Payload exacto del frontend (onSubmitGarantia).
    final payload = {
      'equipos': [
        for (final e in widget.equipos)
          {
            'id': e.id,
            'nombre': e.nombre,
            'tipo': e.tipoNombre,
            'provincia': e.ubicacion,
            'zona': e.zona,
          },
      ],
      'razonSocial': _razonCtrl.text.trim(),
      'fechaOperatividad': _fechaOp,
      'vigenciaGarantia': _vigencia,
      'lugar': _lugarCtrl.text.trim(),
      'direccion': _direccionCtrl.text.trim(),
      'firmaVerificadorBase64': _firmaVerB64,
      'firmaGerenteBase64': _firmaGerB64,
    };
    final res =
        await widget.service.generarCartaGarantia(widget.servicioId, payload);
    if (!mounted) return;
    setState(() => _enviando = false);
    if (res.ok && res.data != null) {
      final lugarSafe = _sanearArchivo(_lugarCtrl.text.toUpperCase());
      final ok = await _guardarDocumentoBytes(context, res.data!,
          'CARTA_GARANTIA_${lugarSafe.isEmpty ? 'LUGAR' : lugarSafe}.docx');
      if (ok && mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.errorMessage.isEmpty
              ? 'Error al generar la carta de garantía.'
              : res.errorMessage),
          backgroundColor: _danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Carta de Garantía',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('${widget.equipos.length} tablero(s) seleccionado(s)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            TextField(
              controller: _razonCtrl,
              decoration: const InputDecoration(
                  labelText: 'Razón Social *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickFecha,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Fecha de Operatividad *',
                          border: OutlineInputBorder()),
                      child: Text(_fechaOp,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Vigencia (auto +1 año)',
                        border: OutlineInputBorder()),
                    child:
                        Text(_vigencia, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _lugarCtrl,
              onChanged: _onLugarChange,
              decoration: const InputDecoration(
                  labelText: 'Lugar', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _direccionCtrl,
              decoration: const InputDecoration(
                  labelText: 'Dirección (auto por lugar)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _firmar(true),
                    icon: Icon(
                        _firmaVerB64.isEmpty
                            ? Icons.draw_outlined
                            : Icons.check_circle,
                        size: 16,
                        color: _firmaVerB64.isEmpty ? null : _green),
                    label: const Text('Firma verificador',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _firmar(false),
                    icon: Icon(
                        _firmaGerB64.isEmpty
                            ? Icons.draw_outlined
                            : Icons.check_circle,
                        size: 16,
                        color: _firmaGerB64.isEmpty ? null : _green),
                    label: const Text('Firma gerente',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _enviando ? null : _generar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_outlined,
                        size: 18, color: Colors.white),
                label: Text(_enviando ? 'Generando…' : 'Generar carta (.docx)',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

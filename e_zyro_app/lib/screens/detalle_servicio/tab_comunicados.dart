// Tab Comunicados del proyecto (HU-13).
part of '../pantalla_detalle_servicio.dart';

// ─── Tab: Comunicados del Proyecto (HU-13) ────────────────────────────────────

class _ComunicadosTab extends StatefulWidget {
  final String proyectoId;
  const _ComunicadosTab({required this.proyectoId});

  @override
  State<_ComunicadosTab> createState() => _ComunicadosTabState();
}

class _ComunicadosTabState extends State<_ComunicadosTab>
    with AutomaticKeepAliveClientMixin {
  ComunicadoService? _service;
  List<ComunicadoProyecto> _comunicados = [];
  bool _loading = true;
  bool _puedeEnviar = false;
  bool _sessionExpired = false;
  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
    _fcmSub = FcmFlutterService.messageStream.listen((msg) {
      if ((msg.data['tipo'] as String?) == 'comunicado_proyecto' &&
          (msg.data['proyecto_id'] as String?) == widget.proyectoId) {
        _load();
      }
    });
    _checkPermiso();
  }

  Future<void> _checkPermiso() async {
    await AppSession.load();
    if (mounted) setState(() => _puedeEnviar = AppSession.i.canEnviarComunicado);
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getComunicadoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() {
      _loading = true;
      _sessionExpired = false;
    });
    try {
      final data = await _service!.getComunicadosProyecto(widget.proyectoId);
      if (!mounted) return;
      setState(() {
        _comunicados = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final expired =
          e.toString().contains('expirada') || e.toString().contains('Sesión');
      setState(() {
        _loading = false;
        _sessionExpired = expired;
      });
    }
  }

  Future<void> _marcarLeido(ComunicadoProyecto c) async {
    if (c.leido) return;
    await _service?.marcarLeidoProyecto(c.id);
    if (!mounted) return;
    setState(() {
      final idx = _comunicados.indexWhere((e) => e.id == c.id);
      if (idx != -1) _comunicados[idx] = _comunicados[idx].markRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_green)),
      );
    }

    if (_sessionExpired) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_clock_outlined, size: 44, color: Colors.orange),
            const SizedBox(height: 10),
            const Text('Sesión expirada',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            const Text('Cierra sesión e inicia nuevamente.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false),
              child: const Text('Ir al Login',
                  style:
                      TextStyle(color: _green, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    if (_comunicados.isEmpty) {
      return _EmptyTab(
          icon: Icons.campaign_outlined, label: 'Sin comunicados del proyecto');
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          color: _green,
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(16, 16, 16, _puedeEnviar ? 90 : 16),
            itemCount: _comunicados.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ComunicadoCard(
              comunicado: _comunicados[i],
              onTap: () => _marcarLeido(_comunicados[i]),
            ),
          ),
        ),
        if (_puedeEnviar)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'fab_comunicado_${widget.proyectoId}',
              onPressed: _openNuevoComunicado,
              backgroundColor: _green,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Nuevo',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  void _openNuevoComunicado() {
    final tituloCtrl = TextEditingController();
    final mensajeCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          bool sending = false;
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.campaign_outlined,
                        color: _amber, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nuevo Comunicado',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('Enviar al proyecto',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ]),
                const SizedBox(height: 20),
                const Text('Título',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: tituloCtrl,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: 'Título del comunicado...',
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Mensaje',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: mensajeCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Escribe el comunicado...',
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 24),
                StatefulBuilder(
                  builder: (_, setSend) => SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: sending
                          ? null
                          : () async {
                              final titulo = tituloCtrl.text.trim();
                              final mensaje = mensajeCtrl.text.trim();
                              if (titulo.isEmpty || mensaje.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Completa el título y el mensaje'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }
                              setSend(() => sending = true);
                              final messenger = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(ctx);
                              final ok = await _service?.crearComunicado(
                                    proyectoId: widget.proyectoId,
                                    titulo: titulo,
                                    mensaje: mensaje,
                                  ) ??
                                  false;
                              if (!mounted) return;
                              navigator.pop();
                              if (ok) {
                                _load();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text('Comunicado enviado'),
                                    backgroundColor: _green,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                );
                              } else {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Error al enviar. Intenta nuevamente.'),
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Enviar Comunicado',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ComunicadoCard extends StatelessWidget {
  final ComunicadoProyecto comunicado;
  final VoidCallback onTap;

  const _ComunicadoCard({required this.comunicado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final isUnread = !comunicado.leido;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnread
              ? _amber.withValues(alpha: isDark ? 0.08 : 0.05)
              : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnread
                ? _amber.withValues(alpha: 0.35)
                : isDark
                    ? _green.withValues(alpha: 0.15)
                    : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? _amber.withValues(alpha: 0.15)
                        : const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.campaign_outlined,
                      color: _amber, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comunicado.titulo,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 11, color: Colors.grey),
                          const SizedBox(width: 3),
                          Text(comunicado.autor,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                          const SizedBox(width: 8),
                          const Icon(Icons.access_time_outlined,
                              size: 11, color: Colors.grey),
                          const SizedBox(width: 3),
                          Text(comunicado.fecha,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: const BoxDecoration(
                        color: _amber, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(comunicado.mensaje,
                style: const TextStyle(
                    fontSize: 12, color: Colors.grey, height: 1.5),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            if (comunicado.adjuntoUrl != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.attach_file_outlined,
                      size: 13, color: _green.withValues(alpha: 0.8)),
                  const SizedBox(width: 4),
                  const Text('Archivo adjunto disponible',
                      style: TextStyle(
                          fontSize: 11,
                          color: _green,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


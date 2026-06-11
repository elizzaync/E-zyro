import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../models/comunicado_models.dart';
import '../services/comunicado_service.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../widgets/topo_background.dart';

// Paleta
const _kRed   = Color(0xFFE53935);
const _kGreen = Color(0xFF8FD11B);

class ComunicadosScreen extends StatefulWidget {
  const ComunicadosScreen({super.key});

  @override
  State<ComunicadosScreen> createState() => _ComunicadosScreenState();
}

class _ComunicadosScreenState extends State<ComunicadosScreen> {
  ComunicadoService? _service;
  List<Comunicado> _comunicados = [];
  bool _isLoading = true;
  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  void initState() {
    super.initState();
    _init();
    _fcmSub = FcmFlutterService.messageStream.listen(_onFcmMessage);
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  void _onFcmMessage(RemoteMessage msg) {
    final tipo = msg.data['tipo'] as String? ?? '';
    if (tipo == 'comunicado' || tipo == 'comunicado_proyecto') _load();
  }

  Future<void> _init() async {
    _service = await getComunicadoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final data = await _service!.getComunicados();
    if (!mounted) return;
    setState(() {
      _comunicados = data;
      _isLoading = false;
    });
  }

  Future<void> _marcarLeido(int index) async {
    final item = _comunicados[index];
    if (item.leido) return;
    setState(() {
      _comunicados[index] = item.markRead();
    });
    await _service?.marcarLeido(item.id);
  }

  Future<void> _marcarTodosLeidos() async {
    for (var i = 0; i < _comunicados.length; i++) {
      if (!_comunicados[i].leido) await _marcarLeido(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final noLeidos = _comunicados.where((c) => !c.leido).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign_rounded,
                  size: 18, color: _kRed),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tablón de Comunicados',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (!_isLoading && noLeidos > 0)
                  Text(
                    '$noLeidos sin leer',
                    style: const TextStyle(fontSize: 10, color: _kRed),
                  ),
              ],
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (!_isLoading && _comunicados.any((c) => !c.leido))
            TextButton(
              onPressed: _marcarTodosLeidos,
              child: const Text(
                'Leer todos',
                style: TextStyle(
                    color: _kGreen, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 14,
        amp: 8,
        stroke: 0.35,
        speed: 0.4,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: _kRed),
              )
            : _comunicados.isEmpty
                ? _buildEmpty()
                : RefreshIndicator(
                    onRefresh: _load,
                    color: _kRed,
                    child: ListView.separated(
                      padding: bottomSafePadding(context, top: 12, extra: 24),
                      itemCount: _comunicados.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 12),
                      itemBuilder: (_, i) => _ComunicadoBulletinCard(
                        comunicado: _comunicados[i],
                        onMarcarLeido: () => _marcarLeido(i),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _kRed.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.campaign_outlined,
                size: 40, color: _kRed),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sin comunicados',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aquí aparecerán los comunicados\nobligatorios de tu empresa.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _load,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _kRed),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded,
                color: _kRed, size: 16),
            label: const Text(
              'Actualizar',
              style: TextStyle(color: _kRed),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tarjeta de comunicado tipo tablón de anuncios ────────────────────────────

class _ComunicadoBulletinCard extends StatelessWidget {
  final Comunicado comunicado;
  final VoidCallback onMarcarLeido;

  const _ComunicadoBulletinCard({
    required this.comunicado,
    required this.onMarcarLeido,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final leido = comunicado.leido;

    // Tarjetas no leídas tienen acento rojo (urgencia), leídas pasan a gris
    final accentColor = leido ? Colors.grey.shade400 : _kRed;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: accentColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: leido
                ? Colors.black.withValues(alpha: 0.04)
                : _kRed.withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner superior ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: leido
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.grey.withValues(alpha: 0.06))
                  : (isDark
                      ? _kRed.withValues(alpha: 0.12)
                      : _kRed.withValues(alpha: 0.06)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  leido
                      ? Icons.check_circle_outline_rounded
                      : Icons.campaign_rounded,
                  size: 18,
                  color: accentColor,
                ),
                const SizedBox(width: 8),
                if (!leido) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kRed,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'COMUNICADO',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    leido ? 'Comunicado' : 'AVISO OBLIGATORIO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          leido ? FontWeight.w400 : FontWeight.w700,
                      color: accentColor,
                      letterSpacing: leido ? 0 : 0.3,
                    ),
                  ),
                ),
                // Punto indicador no leído
                if (!leido)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: _kRed, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),

          // ── Cuerpo del comunicado ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título
                Text(
                  comunicado.titulo,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        leido ? FontWeight.w600 : FontWeight.bold,
                    color: leido
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.75)
                        : null,
                  ),
                ),
                const SizedBox(height: 8),

                // Contenido
                Text(
                  comunicado.contenido,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: leido ? 0.55 : 0.80),
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Pie: autor + fecha + acción ───────────────────────────
                Row(
                  children: [
                    // Autor (si existe)
                    if (comunicado.autor.isNotEmpty) ...[
                      CircleAvatar(
                        radius: 11,
                        backgroundColor:
                            accentColor.withValues(alpha: 0.15),
                        child: Text(
                          comunicado.autor[0].toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              color: accentColor,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        comunicado.autor,
                        style: TextStyle(
                            fontSize: 11,
                            color: accentColor,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                    ],

                    // Fecha
                    const Icon(Icons.schedule_outlined,
                        size: 11, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text(
                      comunicado.fecha,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),

                    const Spacer(),

                    // Botón marcar leído
                    if (!leido)
                      GestureDetector(
                        onTap: onMarcarLeido,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _kRed.withValues(
                                alpha: isDark ? 0.15 : 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color:
                                    _kRed.withValues(alpha: 0.40)),
                          ),
                          child: const Text(
                            'Recibido ✓',
                            style: TextStyle(
                              color: _kRed,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.done_all_rounded,
                              size: 14, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Text(
                            'Recibido',
                            style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 11),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

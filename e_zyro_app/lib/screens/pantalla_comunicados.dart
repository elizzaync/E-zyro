import 'package:flutter/material.dart';
import '../models/comunicado_models.dart';
import '../services/comunicado_service.dart';
import '../utils/api_provider.dart';

class ComunicadosScreen extends StatefulWidget {
  const ComunicadosScreen({super.key});

  @override
  State<ComunicadosScreen> createState() => _ComunicadosScreenState();
}

class _ComunicadosScreenState extends State<ComunicadosScreen> {
  ComunicadoService? _service;
  List<Comunicado> _comunicados = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
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
    const green = Color(0xFF8FD11B);
    final noLeidos = _comunicados.where((c) => !c.leido).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Comunicados',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (!_isLoading && noLeidos > 0)
              Text(
                '$noLeidos sin leer',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
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
                style: TextStyle(color: green, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(green),
              ),
            )
          : _comunicados.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mark_email_read_outlined,
                        size: 60,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Sin comunicados',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Aquí aparecerán los comunicados\nde tu empresa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: _load,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: green),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Actualizar',
                          style: TextStyle(color: green),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: green,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: _comunicados.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ComunicadoCard(
                      comunicado: _comunicados[i],
                      onMarcarLeido: () => _marcarLeido(i),
                    ),
                  ),
                ),
    );
  }
}

class _ComunicadoCard extends StatelessWidget {
  final Comunicado comunicado;
  final VoidCallback onMarcarLeido;

  const _ComunicadoCard({
    required this.comunicado,
    required this.onMarcarLeido,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    final leido = comunicado.leido;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: !leido
            ? Border.all(color: green.withValues(alpha: isDark ? 0.5 : 0.4), width: 1.5)
            : isDark
                ? Border.all(color: green.withValues(alpha: 0.15))
                : null,
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: green.withValues(alpha: leido ? 0.05 : 0.12),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Encabezado ────────────────────────────────────────
          Row(
            children: [
              if (!leido)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8, top: 1),
                  decoration: const BoxDecoration(
                    color: green,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  comunicado.titulo,
                  style: TextStyle(
                    fontWeight: leido ? FontWeight.w500 : FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Contenido ─────────────────────────────────────────
          Text(
            comunicado.contenido,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),

          // ── Footer ────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.schedule_outlined, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                comunicado.fecha,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const Spacer(),
              if (!leido)
                GestureDetector(
                  onTap: onMarcarLeido,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? green.withValues(alpha: 0.12)
                          : const Color(0xFFEFFAE0),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: green.withValues(alpha: 0.35)),
                    ),
                    child: const Text(
                      'Marcar como Leído',
                      style: TextStyle(
                        color: green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      'Leído',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

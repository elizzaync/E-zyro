import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mantenimiento_models.dart';
import '../services/mantenimiento_service.dart';
import '../services/sync_service.dart';
import '../utils/api_provider.dart';
import 'pantalla_camara_evidencia.dart';

class ChecklistScreen extends StatefulWidget {
  final EquipoItem equipo;

  const ChecklistScreen({super.key, required this.equipo});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  ChecklistEquipo? _checklist;
  Map<String, FotosMaquina> _progress = {}; // pasoId → FotosMaquina
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isFinalizing = false;
  int _pendingCount = 0;
  MantenimientoService? _service;
  final _sync = SyncService();

  String get _progressKey => 'checklist_${widget.equipo.id}';

  static const _green = Color(0xFF8FD11B);
  static const _amber = Color(0xFFF59E0B);
  static const _blue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getMantenimientoService();
    await _loadProgress();
    await _fetchChecklist();
    await _refreshPendingCount();
  }

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        setState(() {
          _progress = map.map((k, v) =>
              MapEntry(k, FotosMaquina.fromJson(v as Map<String, dynamic>)));
        });
      } catch (_) {}
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _progress.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_progressKey, jsonEncode(map));
  }

  Future<void> _fetchChecklist() async {
    setState(() => _isLoading = true);
    final data = await _service!.getChecklist(widget.equipo.id);
    if (!mounted) return;
    setState(() {
      _checklist = data;
      _isLoading = false;
    });
    // Ensure progress map has entries for all pasos
    if (data != null) {
      for (final paso in data.pasos) {
        _progress.putIfAbsent(paso.id, () => FotosMaquina());
      }
    }
  }

  Future<void> _refreshPendingCount() async {
    final queue = await _sync.getQueue();
    if (mounted) setState(() => _pendingCount = queue.length);
  }

  Future<void> _syncNow() async {
    if (_service == null || _isSyncing) return;
    setState(() => _isSyncing = true);
    final uploaded = await _sync.processQueue(_service!);
    await _refreshPendingCount();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    if (uploaded > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$uploaded evidencia(s) sincronizada(s)'),
          backgroundColor: _green,
        ),
      );
    } else if (_pendingCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todo sincronizado')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sin conexión — se sincronizará después')),
      );
    }
  }

  Future<void> _capturePhoto(PasoChecklist paso, FotoTipo tipo) async {
    final fotos = _progress[paso.id] ?? FotosMaquina();
    if (!fotos.canCapture(tipo)) return;

    final capturedPaths = <FotoTipo, String?>{
      FotoTipo.antes: fotos.antes,
      FotoTipo.durante: fotos.durante,
      FotoTipo.despues: fotos.despues,
    };

    final result = await CameraEvidenciaScreen.open(
      context,
      pasoNombre: paso.nombre,
      tipo: tipo,
      capturedPaths: capturedPaths,
    );

    if (result == null || !mounted) return;

    setState(() {
      fotos.set(tipo, result.path);
      _progress[paso.id] = fotos;
    });
    await _saveProgress();

    // Enqueue for sync with geolocation metadata
    final ev = EvidenciaPendiente(
      id: '${paso.id}_${tipo.apiValue}_${DateTime.now().millisecondsSinceEpoch}',
      pasoId: paso.id,
      tipo: tipo,
      filePath: result.path,
      createdAt: DateTime.now(),
      lat: result.lat,
      lng: result.lng,
      accuracy: result.accuracy,
    );
    await _sync.enqueue(ev);
    await _refreshPendingCount();

    // Try immediate upload
    _syncNow();

    // Notify backend when all steps are complete
    final total = _checklist!.pasos.length;
    if (total > 0 && _completedCount() == total) {
      await _service!.patchMantenimiento(widget.equipo.id, 'completado');
    }
  }

  int _completedCount() {
    if (_checklist == null) return 0;
    return _checklist!.pasos
        .where((p) => (_progress[p.id] ?? FotosMaquina()).isComplete)
        .length;
  }

  // HU-18: Finalizar mantenimiento y generar informe PDF
  Future<void> _finalizar() async {
    if (_isFinalizing || _service == null) return;
    setState(() => _isFinalizing = true);
    try {
      final ok = await _service!.finalizarMantenimiento(widget.equipo.id);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mantenimiento finalizado. Informe en generación.'),
            backgroundColor: _green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        setState(() => _isFinalizing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al finalizar. Intenta nuevamente.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFinalizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = _checklist?.pasos.length ?? 0;
    final completed = _completedCount();
    final progress = total == 0 ? 0.0 : completed / total;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.equipo.nombre,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          if (_pendingCount > 0)
            Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton(
                  tooltip: 'Sincronizar evidencias',
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(_green)),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  onPressed: _syncNow,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_green),
              ),
            )
          : _checklist == null
              ? _EmptyState(onRetry: _fetchChecklist)
              : Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: () async {
                        await _fetchChecklist();
                        await _syncNow();
                      },
                      color: _green,
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: _ProgressHeader(
                              completed: completed,
                              total: total,
                              progress: progress,
                              isDark: isDark,
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) {
                                final paso = _checklist!.pasos[i];
                                final fotos =
                                    _progress[paso.id] ?? FotosMaquina();
                                final isBlocked = i > 0 &&
                                    !(_progress[_checklist!.pasos[i - 1].id] ??
                                            FotosMaquina())
                                        .isComplete;
                                return _PasoCard(
                                  paso: paso,
                                  fotos: fotos,
                                  isDark: isDark,
                                  isBlocked: isBlocked,
                                  onCapture: (tipo) =>
                                      _capturePhoto(paso, tipo),
                                );
                              },
                              childCount: _checklist!.pasos.length,
                            ),
                          ),
                          SliverPadding(
                            padding: EdgeInsets.only(
                              bottom: progress >= 1.0 ? 88 : 32,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // HU-18: Botón visible solo cuando todo el checklist está completo
                    if (progress >= 1.0)
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 20,
                        child: FilledButton.icon(
                          onPressed: _isFinalizing ? null : _finalizar,
                          icon: _isFinalizing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(
                            _isFinalizing
                                ? 'Finalizando...'
                                : 'Finalizar y Generar Informe',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ─── Progress header ──────────────────────────────────────────────────────────

class _ProgressHeader extends StatelessWidget {
  final int completed;
  final int total;
  final double progress;
  final bool isDark;

  const _ProgressHeader({
    required this.completed,
    required this.total,
    required this.progress,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF8FD11B);
    const amber = Color(0xFFF59E0B);
    final color = progress >= 1.0 ? green : amber;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: green.withValues(alpha: 0.25)) : null,
        boxShadow: isDark
            ? null
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progreso del checklist',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                '$completed / $total pasos',
                style: TextStyle(color: color, fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor:
                  isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
          if (progress >= 1.0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle, color: green, size: 14),
                const SizedBox(width: 6),
                const Text(
                  '¡Checklist completado!',
                  style: TextStyle(
                      color: green, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Paso card ────────────────────────────────────────────────────────────────

class _PasoCard extends StatelessWidget {
  final PasoChecklist paso;
  final FotosMaquina fotos;
  final bool isDark;
  final bool isBlocked;
  final void Function(FotoTipo) onCapture;

  const _PasoCard({
    required this.paso,
    required this.fotos,
    required this.isDark,
    required this.isBlocked,
    required this.onCapture,
  });

  static const _green = Color(0xFF8FD11B);
  static const _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final isComplete = fotos.isComplete;

    return Opacity(
      opacity: isBlocked ? 0.45 : 1.0,
      child: AbsorbPointer(
        absorbing: isBlocked,
        child: _buildCard(context, isComplete),
      ),
    );
  }

  Widget _buildCard(BuildContext context, bool isComplete) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? Border.all(
                color: isComplete
                    ? _green.withValues(alpha: 0.5)
                    : _green.withValues(alpha: 0.2),
              )
            : null,
        boxShadow: isDark
            ? null
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
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isComplete
                      ? _green.withValues(alpha: 0.15)
                      : _amber.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isComplete
                      ? const Icon(Icons.check, color: _green, size: 14)
                      : Text(
                          '${paso.orden}',
                          style: const TextStyle(
                              color: _amber,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paso.nombre,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (paso.descripcion.isNotEmpty)
                      Text(
                        paso.descripcion,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Botones ANTES / DURANTE / DESPUÉS ────────────────────────
          Row(
            children: FotoTipo.values.map((tipo) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: tipo != FotoTipo.despues ? 6 : 0,
                  ),
                  child: _FotoButton(
                    tipo: tipo,
                    fotos: fotos,
                    isDark: isDark,
                    onTap: fotos.canCapture(tipo) ? () => onCapture(tipo) : null,
                  ),
                ),
              );
            }).toList(),
          ),

          // ── Thumbnails ───────────────────────────────────────────────
          _ThumbnailRow(fotos: fotos),
        ],
      ),
    );
  }
}

// ─── Foto button ──────────────────────────────────────────────────────────────

class _FotoButton extends StatelessWidget {
  final FotoTipo tipo;
  final FotosMaquina fotos;
  final bool isDark;
  final VoidCallback? onTap;

  const _FotoButton({
    required this.tipo,
    required this.fotos,
    required this.isDark,
    this.onTap,
  });

  static const _green = Color(0xFF8FD11B);
  static const _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final captured = fotos.pathFor(tipo) != null;
    final canCapture = fotos.canCapture(tipo);
    final isLocked = !captured && !canCapture;

    Color bgColor;
    Color textColor;
    IconData icon;

    if (captured) {
      bgColor = _green.withValues(alpha: isDark ? 0.20 : 0.12);
      textColor = _green;
      icon = Icons.check_circle_outline;
    } else if (canCapture) {
      bgColor = _amber.withValues(alpha: isDark ? 0.18 : 0.10);
      textColor = _amber;
      icon = Icons.camera_alt_outlined;
    } else {
      bgColor = Colors.grey.withValues(alpha: 0.10);
      textColor = Colors.grey.shade400;
      icon = Icons.lock_outline;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: captured
                ? _green.withValues(alpha: 0.40)
                : canCapture
                    ? _amber.withValues(alpha: 0.35)
                    : Colors.grey.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: textColor, size: 16),
            const SizedBox(height: 3),
            Text(
              tipo.label,
              style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Thumbnail row ────────────────────────────────────────────────────────────

class _ThumbnailRow extends StatelessWidget {
  final FotosMaquina fotos;

  const _ThumbnailRow({required this.fotos});

  @override
  Widget build(BuildContext context) {
    final paths = [fotos.antes, fotos.durante, fotos.despues]
        .whereType<String>()
        .toList();

    if (paths.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: paths.map((p) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(p),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.grey, size: 20),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;

  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_outlined,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No se pudo cargar el checklist',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

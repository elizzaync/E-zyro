import 'package:flutter/material.dart';
import '../core/sync_logger.dart';
import '../services/asistencia_service.dart';
import '../services/proyecto_service.dart';
import '../core/api_client.dart';
import '../core/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Panel bottom-sheet que muestra los últimos intentos de sincronización
/// de asistencia con su estado, error exacto y código HTTP.
/// Útil para diagnosticar fallos sin necesitar cable USB ni Android Studio.
class SyncLogPanel extends StatefulWidget {
  const SyncLogPanel({super.key});

  @override
  State<SyncLogPanel> createState() => _SyncLogPanelState();
}

class _SyncLogPanelState extends State<SyncLogPanel> {
  List<SyncLogEntry> _logs          = [];
  bool              _loading         = true;
  bool              _syncing         = false;
  String?           _syncResult;
  int               _pendientes      = 0;
  int               _abandonados     = 0;
  int               _permanentes     = 0;
  int               _evidPendientes  = 0;
  int               _evidAbandonadas = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final svc   = AsistenciaService(ApiClient(prefs));
    final proy  = ProyectoService(ApiClient(prefs));
    final results = await Future.wait([
      SyncLogger.getLogs(),
      svc.contarPendientes(),
      svc.contarAbandonados(),
      svc.contarErroresPermanentes(),
      proy.contarEvidenciasPendientes(),
      proy.contarEvidenciasAbandonadas(),
    ]);
    if (mounted) {
      setState(() {
        _logs            = results[0] as List<SyncLogEntry>;
        _pendientes      = results[1] as int;
        _abandonados     = results[2] as int;
        _permanentes     = results[3] as int;
        _evidPendientes  = results[4] as int;
        _evidAbandonadas = results[5] as int;
        _loading         = false;
      });
    }
  }

  Future<void> _clearLogs() async {
    await SyncLogger.clear();
    if (mounted) setState(() => _logs = []);
  }

  Future<void> _descartarPermanentes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Descartar registros?'),
        content: Text(
          'Se eliminarán $_permanentes registro${_permanentes == 1 ? "" : "s"} '
          'que el servidor rechazó permanentemente (ej: empleado inactivo, '
          'datos inválidos).\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final prefs = await SharedPreferences.getInstance();
    final svc   = AsistenciaService(ApiClient(prefs));
    await svc.descartarErroresPermanentes();
    await _loadAll();
  }

  Future<void> _descartarEvidencias() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Descartar evidencias?'),
        content: Text(
          'Se eliminarán $_evidAbandonadas evidencia${_evidAbandonadas == 1 ? "" : "s"} '
          'que no se pudieron subir tras varios intentos.\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final prefs = await SharedPreferences.getInstance();
    final proy  = ProyectoService(ApiClient(prefs));
    await proy.descartarEvidenciasAbandonadas();
    await _loadAll();
  }

  Future<void> _reintentarPermanentes() async {
    if (_syncing) return;
    setState(() { _syncing = true; _syncResult = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final svc   = AsistenciaService(ApiClient(prefs));

      final reseteados = await svc.resetErroresPermanentes();
      if (reseteados == 0) {
        if (mounted) setState(() => _syncResult = '⚠️ No hay errores permanentes para reintentar');
        return;
      }

      final alcanzable = await svc.canReachServer();
      if (!alcanzable) {
        if (mounted) {
          setState(() => _syncResult = '❌ Servidor no alcanzable. Verifica tu conexión.');
        }
        return;
      }

      final n = await svc.sincronizarPendientes();
      if (mounted) {
        setState(() => _syncResult = n > 0
            ? '✅ $n registro${n == 1 ? "" : "s"} recuperado${n == 1 ? "" : "s"}'
            : '⚠️ Se reintentaron $reseteados, pero el servidor sigue rechazándolos — revisa los logs');
      }
    } catch (e) {
      if (mounted) setState(() => _syncResult = '❌ ${e.toString().replaceAll("Exception: ", "")}');
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _loadAll();
    }
  }

  Future<void> _forceSync() async {
    if (_syncing) return;
    setState(() { _syncing = true; _syncResult = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final svc   = AsistenciaService(ApiClient(prefs));
      final proy  = ProyectoService(ApiClient(prefs));

      // 1. Resetear abandonados (asistencia + evidencias) antes de sincronizar
      if (_abandonados > 0) {
        await svc.resetParaReintentar();
      }
      if (_evidAbandonadas > 0) {
        await proy.resetEvidenciasParaReintentar();
      }

      // 2. Verificar conectividad con el servidor (sin token)
      final alcanzable = await svc.canReachServer();
      if (!alcanzable) {
        if (mounted) {
          setState(() => _syncResult = '❌ Servidor no alcanzable. Verifica tu conexión.');
        }
        return;
      }

      // 3. Sincronizar ambas colas
      final n  = await svc.sincronizarPendientes();
      final ev = await proy.sincronizarEvidencias();
      if (mounted) {
        final partes = <String>[];
        if (n > 0)  partes.add('$n asistencia${n == 1 ? "" : "s"}');
        if (ev > 0) partes.add('$ev evidencia${ev == 1 ? "" : "s"}');
        setState(() => _syncResult = partes.isNotEmpty
            ? '✅ Enviado: ${partes.join(" · ")}'
            : '⚠️ Sin pendientes enviados — revisa los logs abajo');
      }
    } catch (e) {
      if (mounted) setState(() => _syncResult = '❌ ${e.toString().replaceAll("Exception: ", "")}');
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _loadAll(); // Refrescar todo después del sync
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green   = Color(0xFF8FD11B);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // ── Header ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: isDark ? 0.15 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.terminal_rounded, color: Color(0xFF8FD11B), size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Logs de Sincronización',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Últimos 50 intentos de envío',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                // Botón limpiar
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  color: Colors.grey,
                  tooltip: 'Limpiar logs',
                  onPressed: _logs.isEmpty ? null : _clearLogs,
                ),
              ],
            ),
          ),

          // ── Resumen de estado ────────────────────────────────────────────────
          if (!_loading) Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip(
                  label: 'Pendientes',
                  count: _pendientes,
                  color: _pendientes > 0 ? Colors.amber.shade700 : Colors.grey,
                  icon: Icons.cloud_sync_outlined,
                ),
                _StatChip(
                  label: 'Abandonados',
                  count: _abandonados,
                  color: _abandonados > 0 ? Colors.orange : Colors.grey,
                  icon: Icons.replay_circle_filled_outlined,
                  tooltip: _abandonados > 0
                      ? 'Superaron 5 reintentos. "Forzar sync" los recupera.'
                      : null,
                ),
                _StatChip(
                  label: 'Error perm.',
                  count: _permanentes,
                  color: _permanentes > 0 ? Colors.red : Colors.grey,
                  icon: Icons.block_rounded,
                  tooltip: _permanentes > 0
                      ? 'El servidor los rechazó (4xx). Si corregiste la causa, usa "Reintentar".'
                      : null,
                ),
                _StatChip(
                  label: 'Evidencias',
                  count: _evidPendientes,
                  color: _evidPendientes > 0 ? Colors.blue : Colors.grey,
                  icon: Icons.photo_camera_back_outlined,
                  tooltip: _evidPendientes > 0
                      ? 'Fotos de pasos pendientes de subir. "Forzar sync" las envía.'
                      : null,
                ),
              ],
            ),
          ),

          // ── Alerta de abandonados (reintentos) ───────────────────────────────
          if (_abandonados > 0 && !_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.replay_circle_filled_outlined,
                        color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_abandonados registro${_abandonados == 1 ? "" : "s"} '
                        'con reintentos agotados. Toca "Forzar sync" para recuperarlos.',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.orange, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Alerta de errores permanentes ────────────────────────────────────
          if (_permanentes > 0 && !_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.block_rounded, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$_permanentes registro${_permanentes == 1 ? "" : "s"} '
                            'rechazado${_permanentes == 1 ? "" : "s"} por el servidor (4xx). '
                            'Si ya corregiste la causa, reintenta; si no, descártalos.',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.red, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _syncing ? null : _reintentarPermanentes,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: green.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: green.withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'Reintentar',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF1E9462),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _descartarPermanentes,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'Descartar',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ── Alerta de evidencias abandonadas ─────────────────────────────────
          if (_evidAbandonadas > 0 && !_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.photo_camera_back_outlined,
                            color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$_evidAbandonadas evidencia${_evidAbandonadas == 1 ? "" : "s"} '
                            'no se pudo subir tras varios intentos. Reintenta o descártala.',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.blue, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _syncing ? null : _forceSync,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.blue.withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'Reintentar',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _descartarEvidencias,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'Descartar',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ── Conectividad actual ──────────────────────────────────────────────
          ValueListenableBuilder<bool>(
            valueListenable: isOnlineNotifier,
            builder: (_, online, _) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: online ? green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    online ? 'Conectado a internet' : 'Sin conexión a internet',
                    style: TextStyle(
                      fontSize: 12,
                      color: online ? green : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Botón forzar sync ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _syncing ? null : _forceSync,
                    icon: _syncing
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: Text(
                      _syncing ? 'Sincronizando...' : 'Forzar sync ahora',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: isDark ? const Color(0xFF0C1506) : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (_syncResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _syncResult!.startsWith('✅')
                          ? green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _syncResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _syncResult!.startsWith('✅') ? green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Lista de logs ────────────────────────────────────────────────────
          Flexible(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
                      ),
                    ),
                  )
                : _logs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text('Sin registros de sync',
                                  style: TextStyle(color: Colors.grey, fontSize: 14)),
                              const SizedBox(height: 4),
                              const Text(
                                'Los intentos de envío aparecerán aquí',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _logs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) =>
                            _SyncLogTile(entry: _logs[i], isDark: isDark),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Tile individual de log ────────────────────────────────────────────────────

class _SyncLogTile extends StatelessWidget {
  final SyncLogEntry entry;
  final bool isDark;

  const _SyncLogTile({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cfg = _config(entry.status);

    // Formatear hora
    final t = entry.timestamp.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    final timeStr = '${pad(t.day)}/${pad(t.month)}  ${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cfg.bg.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cfg.bg.withValues(alpha: isDark ? 0.30 : 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ícono de estado
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cfg.bg.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(cfg.icon, color: cfg.bg, size: 14),
          ),
          const SizedBox(width: 10),

          // Contenido
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Tipo marcación
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (entry.tipoMarcacion == 'entrada'
                                ? const Color(0xFF8FD11B)
                                : Colors.blue)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.tipoMarcacion.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: entry.tipoMarcacion == 'entrada'
                              ? const Color(0xFF8FD11B)
                              : Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Badge de estado
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: cfg.bg.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.status.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cfg.bg,
                        ),
                      ),
                    ),
                    if (entry.httpCode != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        'HTTP ${entry.httpCode}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      timeStr,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                if (entry.errorMessage != null && entry.errorMessage!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    entry.errorMessage!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // UUID abreviado (útil para correlacionar con backend)
                const SizedBox(height: 3),
                Text(
                  'id: ${entry.uuid.substring(0, 8)}…',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.grey,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _TileConfig _config(SyncLogStatus s) {
    switch (s) {
      case SyncLogStatus.enviado:
        return _TileConfig(const Color(0xFF8FD11B), Icons.check_circle_rounded);
      case SyncLogStatus.falloRed:
        return _TileConfig(Colors.orange, Icons.wifi_off_rounded);
      case SyncLogStatus.falloServidor:
        return _TileConfig(Colors.red, Icons.cloud_off_rounded);
      case SyncLogStatus.sesionVencida:
        return _TileConfig(Colors.purple, Icons.lock_outline_rounded);
      case SyncLogStatus.iniciando:
        return _TileConfig(Colors.grey, Icons.pending_outlined);
    }
  }
}

class _TileConfig {
  final Color  bg;
  final IconData icon;
  const _TileConfig(this.bg, this.icon);
}

// ── Chip de estadística ───────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String   label;
  final int      count;
  final Color    color;
  final IconData icon;
  final String?  tooltip;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: chip);
    }
    return chip;
  }
}

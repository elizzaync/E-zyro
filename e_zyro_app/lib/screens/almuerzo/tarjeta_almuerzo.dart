import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/asistencia_models.dart';
import '../../services/asistencia_service.dart';
import '../../services/notification_service.dart';
import '../../utils/api_provider.dart';

/// Tarjeta de marcación de almuerzo (v1 PYME) para la pantalla principal.
/// Un toque, sin selfie: captura GPS + hora y marca inicio/fin de almuerzo.
/// Reutiliza el flujo offline-first de [AsistenciaService].
class TarjetaAlmuerzo extends StatefulWidget {
  const TarjetaAlmuerzo({super.key});

  @override
  State<TarjetaAlmuerzo> createState() => _TarjetaAlmuerzoState();
}

class _TarjetaAlmuerzoState extends State<TarjetaAlmuerzo> {
  static const _green = Color(0xFF8FD11B);
  static const _amber = Color(0xFFD98A16);

  // Config v1 PYME (futuro: por empresa en backend).
  static const _duracionMin = 60;        // duración del descanso
  static const _alertaAntesMin = 5;      // alerta 5 min antes del fin (→ min 55)
  static const _horaRecordatorio = 12;   // recordatorio "es hora de almorzar"

  AsistenciaService? _svc;
  EstadoHoy _estado = EstadoHoy.empty();
  bool _cargando = true;
  bool _marcando = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getAsistenciaService();
    await _refrescar();
    _programarRecordatorioMediodia();
  }

  Future<void> _refrescar() async {
    final e = await _svc!.getEstadoHoy();
    if (!mounted) return;
    setState(() {
      _estado = e;
      _cargando = false;
    });
  }

  // ── Captura de GPS (best-effort: si falla, marca sin coordenadas) ──────────
  Future<Position?> _capturarGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }

  Future<void> _marcar(String tipo) async {
    if (_marcando || _svc == null) return;
    setState(() => _marcando = true);
    final pos = await _capturarGps();
    try {
      final res = await _svc!.marcarAlmuerzo(
        tipo: tipo,
        latitud: pos?.latitude,
        longitud: pos?.longitude,
        precisionM: pos?.accuracy,
        altitud: pos?.altitude,
      );
      if (!mounted) return;

      if (tipo == 'entrada_almuerzo') {
        // Programar la alerta de fin del descanso.
        await NotificationService.scheduleAt(
          id: NotificationService.idAlmuerzoFin,
          title: 'Tu descanso está por terminar',
          body: 'Faltan $_alertaAntesMin min para volver. No olvides marcar tu regreso.',
          when: DateTime.now()
              .add(const Duration(minutes: _duracionMin - _alertaAntesMin)),
        );
      } else if (tipo == 'salida_almuerzo') {
        await NotificationService.cancel(NotificationService.idAlmuerzoFin);
      }

      _snack(res.motivo.isNotEmpty ? res.motivo : 'Registrado', _green);
      await _refrescar();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceAll('Exception: ', ''), Colors.red);
      await _refrescar();
    } finally {
      if (mounted) setState(() => _marcando = false);
    }
  }

  /// Si aún no almorzó y todavía no es mediodía, recuerda salir a las 12:00.
  void _programarRecordatorioMediodia() {
    if (_estado.tieneInicioAlmuerzo || !_estado.tieneEntrada) return;
    final now = DateTime.now();
    final hoy12 = DateTime(now.year, now.month, now.day, _horaRecordatorio);
    if (now.isBefore(hoy12)) {
      NotificationService.scheduleAt(
        id: NotificationService.idAlmuerzoRecordatorio,
        title: 'Hora de almorzar',
        body: 'Recuerda marcar el inicio de tu almuerzo cuando salgas.',
        when: hoy12,
      );
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final estado = _estado.estadoAlmuerzo;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: _green.withValues(alpha: 0.25)) : null,
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
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: (estado == 'en_curso' ? _amber : _green).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.restaurant_rounded,
                color: estado == 'en_curso' ? _amber : _green, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: _cargando ? _skeleton() : _contenido(estado)),
        ],
      ),
    );
  }

  Widget _skeleton() => const SizedBox(
        height: 40,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _green),
          ),
        ),
      );

  Widget _contenido(String estado) {
    switch (estado) {
      case 'bloqueado':
        final motivo = _estado.tieneSalida
            ? 'Jornada cerrada'
            : 'Marca tu entrada para habilitar el almuerzo';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Almuerzo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(motivo,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        );

      case 'en_curso':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('En almuerzo',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                _CronometroAlmuerzo(inicioIso: _estado.inicioAlmuerzoIso),
              ],
            ),
            const SizedBox(height: 2),
            Text('Inició ${_estado.inicioAlmuerzoHora ?? ''} · descanso $_duracionMin min',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            _boton('Finalizar almuerzo', _amber, () => _marcar('salida_almuerzo')),
          ],
        );

      case 'completado':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Text('Almuerzo',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                SizedBox(width: 6),
                Icon(Icons.check_circle, size: 16, color: _green),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${_estado.inicioAlmuerzoHora ?? '--'} – ${_estado.finAlmuerzoHora ?? '--'}'
              '${_estado.duracionAlmuerzoMin != null ? ' · ${_estado.duracionAlmuerzoMin} min' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        );

      default: // disponible
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Almuerzo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            const Text('Marca el inicio de tu descanso',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            _boton('Iniciar almuerzo', _green, () => _marcar('entrada_almuerzo')),
          ],
        );
    }
  }

  Widget _boton(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton.icon(
        onPressed: _marcando ? null : onTap,
        icon: _marcando
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(label.startsWith('Iniciar')
                ? Icons.play_arrow_rounded
                : Icons.stop_rounded, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

/// Cronómetro del almuerzo en curso. Tiene su propio Timer de 1 s y se repinta
/// AISLADO: así el tick por segundo no reconstruye toda la TarjetaAlmuerzo
/// (que vive en el Home, siempre visible), solo este texto.
class _CronometroAlmuerzo extends StatefulWidget {
  final String? inicioIso;
  const _CronometroAlmuerzo({required this.inicioIso});

  @override
  State<_CronometroAlmuerzo> createState() => _CronometroAlmuerzoState();
}

class _CronometroAlmuerzoState extends State<_CronometroAlmuerzo> {
  static const _amber = Color(0xFFD98A16);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _texto() {
    final iso = widget.inicioIso;
    if (iso == null) return '00:00';
    final ini = DateTime.tryParse(iso);
    if (ini == null) return '00:00';
    final d = DateTime.now().difference(ini);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h}h ${m}m' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _texto(),
      style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: _amber),
    );
  }
}

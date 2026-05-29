// Reloj en vivo (chip autocontenido).
part of '../pantalla_asistencia.dart';

// ── Reloj en vivo (chip autocontenido) ──────────────────────────────────────
// Maneja su propio Timer y solo se repinta a sí mismo cada segundo, evitando
// reconstruir toda la pantalla de asistencia.
class _LiveClockChip extends StatefulWidget {
  const _LiveClockChip();

  @override
  State<_LiveClockChip> createState() => _LiveClockChipState();
}

class _LiveClockChipState extends State<_LiveClockChip> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() => _now = DateTime.now());
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final hora = '${_pad(_now.hour)}:${_pad(_now.minute)}:${_pad(_now.second)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(hora, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

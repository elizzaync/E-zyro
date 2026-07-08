import 'package:flutter/material.dart';
import '../models/equipo_intervenido_models.dart';
import '../utils/peru_geo.dart';
import 'detalle_equipo_intervenido.dart';

// ─── Colores ──────────────────────────────────────────────────────────────────
const _kGreen = Color(0xFF8FD11B);
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFE53935);
const _kBg = Color(0xFF0B1220); // fondo "tecnológico" oscuro
const _kSinEquipos = Color(0xFF243044);

/// Mapa del Perú por departamentos con el parque de equipos intervenidos.
/// Semáforo por departamento (rojo = vencidos, ámbar = próximos ≤30 días,
/// verde = al día, gris = sin equipos) y drill-down al tocar.
class PantallaMapaParque extends StatefulWidget {
  final List<EquipoIntervenido> equipos;

  const PantallaMapaParque({super.key, required this.equipos});

  @override
  State<PantallaMapaParque> createState() => _PantallaMapaParqueState();
}

// Estado agregado de un departamento.
class _DepEstado {
  final List<EquipoIntervenido> equipos = [];
  int vencidos = 0;
  int proximos = 0; // 0–30 días

  Color get color {
    if (equipos.isEmpty) return _kSinEquipos;
    if (vencidos > 0) return _kRed;
    if (proximos > 0) return _kAmber;
    return _kGreen;
  }
}

class _PantallaMapaParqueState extends State<PantallaMapaParque>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulso;
  final Map<String, _DepEstado> _porDep = {};
  final List<EquipoIntervenido> _sinUbicar = [];
  String? _seleccionado;

  // Ciudades/provincias conocidas → departamento (nombres ya normalizados).
  // ponytail: cubre capitales y ciudades frecuentes; ampliar si aparece una
  // ubicación real que no matchee (cae en "sin ubicar", no se pierde).
  static const _ciudadADep = {
    'CHACHAPOYAS': 'AMAZONAS', 'BAGUA': 'AMAZONAS',
    'HUARAZ': 'ANCASH', 'CHIMBOTE': 'ANCASH',
    'ABANCAY': 'APURIMAC',
    'HUAMANGA': 'AYACUCHO',
    'CUZCO': 'CUSCO',
    'CHINCHA': 'ICA', 'PISCO': 'ICA', 'NAZCA': 'ICA',
    'HUANCAYO': 'JUNIN', 'TARMA': 'JUNIN', 'SATIPO': 'JUNIN',
    'LA OROYA': 'JUNIN',
    'TRUJILLO': 'LA LIBERTAD', 'CHEPEN': 'LA LIBERTAD',
    'CHICLAYO': 'LAMBAYEQUE',
    'HUACHO': 'LIMA', 'CANETE': 'LIMA', 'BARRANCA': 'LIMA',
    'IQUITOS': 'LORETO', 'YURIMAGUAS': 'LORETO',
    'PUERTO MALDONADO': 'MADRE DE DIOS',
    'ILO': 'MOQUEGUA',
    'CERRO DE PASCO': 'PASCO',
    'SULLANA': 'PIURA', 'TALARA': 'PIURA', 'PAITA': 'PIURA',
    'JULIACA': 'PUNO',
    'MOYOBAMBA': 'SAN MARTIN', 'TARAPOTO': 'SAN MARTIN',
    'PUCALLPA': 'UCAYALI',
  };

  @override
  void initState() {
    super.initState();
    _pulso = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _agrupar();
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  static String _normalizar(String s) {
    const acentos = 'ÁÉÍÓÚÜÑáéíóúüñ';
    const planos = 'AEIOUUNaeiouun';
    final sb = StringBuffer();
    for (final ch in s.characters) {
      final i = acentos.indexOf(ch);
      sb.write(i >= 0 ? planos[i] : ch);
    }
    return sb.toString().toUpperCase().trim();
  }

  /// Resuelve el departamento de una ubicación por nombre.
  String? _depDe(String? ubicacion) {
    if (ubicacion == null || ubicacion.isEmpty) return null;
    final u = _normalizar(ubicacion);
    for (final d in kPeruDepartamentos) {
      if (u == d.nombre || u.contains(d.nombre)) return d.nombre;
    }
    for (final e in _ciudadADep.entries) {
      if (u.contains(e.key)) return e.value;
    }
    return null;
  }

  void _agrupar() {
    for (final d in kPeruDepartamentos) {
      _porDep[d.nombre] = _DepEstado();
    }
    for (final e in widget.equipos) {
      final dep = _depDe(e.ubicacionNombre);
      if (dep == null) {
        _sinUbicar.add(e);
        continue;
      }
      final est = _porDep[dep]!;
      est.equipos.add(e);
      final dias = e.diasParaMantenimiento;
      if (dias != null) {
        if (dias < 0) {
          est.vencidos++;
        } else if (dias <= 30) {
          est.proximos++;
        }
      }
    }
    // Dentro de cada departamento: lo más urgente primero.
    for (final est in _porDep.values) {
      est.equipos.sort((a, b) => (a.diasParaMantenimiento ?? 99999)
          .compareTo(b.diasParaMantenimiento ?? 99999));
    }
  }

  void _onTapMapa(Offset geoPunto) {
    // Al revés para que los departamentos chicos (Callao) ganen sobre Lima.
    for (final d in kPeruDepartamentos.reversed) {
      if (_contiene(d, geoPunto)) {
        setState(() =>
            _seleccionado = _seleccionado == d.nombre ? null : d.nombre);
        return;
      }
    }
    setState(() => _seleccionado = null);
  }

  static bool _contiene(DepartamentoGeo d, Offset p) {
    for (final anillo in d.anillos) {
      var dentro = false;
      final n = anillo.length ~/ 2;
      for (var i = 0, j = n - 1; i < n; j = i++) {
        final xi = anillo[i * 2], yi = anillo[i * 2 + 1];
        final xj = anillo[j * 2], yj = anillo[j * 2 + 1];
        if ((yi > p.dy) != (yj > p.dy) &&
            p.dx < (xj - xi) * (p.dy - yi) / (yj - yi) + xi) {
          dentro = !dentro;
        }
      }
      if (dentro) return true;
    }
    return false;
  }

  void _verSinUbicar() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141D2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('Equipos sin ubicar en el mapa',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Su ubicación no coincide con ningún departamento. '
                'Revisa el nombre de la ubicación en el catálogo.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in _sinUbicar) _itemEquipo(e),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sel = _seleccionado;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Parque nacional de equipos',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_sinUbicar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                backgroundColor: _kAmber.withValues(alpha: 0.15),
                side: const BorderSide(color: _kAmber),
                label: Text('${_sinUbicar.length} sin ubicar',
                    style: const TextStyle(color: _kAmber, fontSize: 11)),
                onPressed: _verSinUbicar,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _leyenda(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // Encajar el lienzo geo (kPeruGeoAncho x kPeruGeoAlto).
                final escala = (box.maxWidth / kPeruGeoAncho)
                    .clamp(0.0, box.maxHeight / kPeruGeoAlto)
                    .toDouble();
                final w = kPeruGeoAncho * escala;
                final h = kPeruGeoAlto * escala;
                return InteractiveViewer(
                  maxScale: 8,
                  child: Center(
                    child: GestureDetector(
                      onTapUp: (d) =>
                          _onTapMapa(d.localPosition / escala),
                      child: CustomPaint(
                        size: Size(w, h),
                        painter: _MapaPeruPainter(
                          porDep: _porDep,
                          seleccionado: sel,
                          pulso: _pulso,
                          escala: escala,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (sel != null) _panelDep(sel),
        ],
      ),
    );
  }

  Widget _leyenda() {
    Widget item(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          item(_kRed, 'Vencidos'),
          item(_kAmber, 'Próximos ≤30 días'),
          item(_kGreen, 'Al día'),
          item(_kSinEquipos, 'Sin equipos'),
        ],
      ),
    );
  }

  Widget _panelDep(String dep) {
    final est = _porDep[dep]!;
    final total = est.equipos.length;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.42),
      decoration: const BoxDecoration(
        color: Color(0xFF141D2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration:
                        BoxDecoration(color: est.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(dep,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white54, size: 20),
                    onPressed: () => setState(() => _seleccionado = null),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                total == 0
                    ? 'Sin equipos en este departamento'
                    : '$total equipo${total == 1 ? '' : 's'} · '
                        '${est.vencidos} vencido${est.vencidos == 1 ? '' : 's'} · '
                        '${est.proximos} próximo${est.proximos == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            if (total > 0)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [for (final e in est.equipos) _itemEquipo(e)],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _itemEquipo(EquipoIntervenido e) {
    final dias = e.diasParaMantenimiento;
    final Color c;
    final String estadoTxt;
    if (dias == null) {
      c = Colors.white38;
      estadoTxt = 'Sin plan';
    } else if (dias < 0) {
      c = _kRed;
      estadoTxt = 'Vencido hace ${-dias} d';
    } else if (dias <= 30) {
      c = _kAmber;
      estadoTxt = dias == 0 ? 'Hoy' : 'En $dias d';
    } else {
      c = _kGreen;
      estadoTxt = 'En $dias d';
    }
    final sede = [
      if (e.zonaNombre != null && e.zonaNombre!.isNotEmpty) e.zonaNombre!,
      if (e.clienteNombre != null && e.clienteNombre!.isNotEmpty)
        e.clienteNombre!,
    ].join(' · ');
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetalleEquipoIntervenido(equipo: e)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.settings_input_component, color: c, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.nombre,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                  if (sede.isNotEmpty)
                    Text(sede,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11.5)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.withValues(alpha: 0.6)),
              ),
              child: Text(estadoTxt,
                  style: TextStyle(
                      color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Painter del mapa ─────────────────────────────────────────────────────────

class _MapaPeruPainter extends CustomPainter {
  final Map<String, _DepEstado> porDep;
  final String? seleccionado;
  final Animation<double> pulso;
  final double escala;

  _MapaPeruPainter({
    required this.porDep,
    required this.seleccionado,
    required this.pulso,
    required this.escala,
  }) : super(repaint: pulso);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(escala);

    for (final d in kPeruDepartamentos) {
      final est = porDep[d.nombre];
      final color = est?.color ?? _kSinEquipos;
      final esSel = d.nombre == seleccionado;
      final conVencidos = (est?.vencidos ?? 0) > 0;

      final path = Path();
      for (final anillo in d.anillos) {
        path.moveTo(anillo[0], anillo[1]);
        for (var i = 2; i < anillo.length; i += 2) {
          path.lineTo(anillo[i], anillo[i + 1]);
        }
        path.close();
      }

      // Relleno: alerta pulsa; seleccionado más intenso.
      final baseAlpha = est == null || est.equipos.isEmpty
          ? 0.55
          : (esSel ? 0.60 : 0.35);
      final alpha = conVencidos
          ? baseAlpha + 0.25 * pulso.value
          : baseAlpha;
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)));

      // Halo exterior en departamentos con equipos (efecto "glow").
      if (est != null && est.equipos.isNotEmpty) {
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = (esSel ? 6 : 4) / escala
              ..maskFilter =
                  const MaskFilter.blur(BlurStyle.normal, 3)
              ..color = color.withValues(
                  alpha: conVencidos ? 0.35 + 0.35 * pulso.value : 0.45));
      }

      // Borde
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (esSel ? 2.4 : 1.0) / escala
            ..color = esSel
                ? Colors.white
                : const Color(0xFF3D4C66));
    }

    // Contadores sobre departamentos con equipos.
    for (final d in kPeruDepartamentos) {
      final est = porDep[d.nombre];
      if (est == null || est.equipos.isEmpty) continue;
      final c = _centro(d);
      final r = 11.0 / escala;
      canvas.drawCircle(
          c,
          r,
          Paint()..color = const Color(0xE60B1220));
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 / escala
            ..color = est.color);
      final tp = TextPainter(
        text: TextSpan(
          text: '${est.equipos.length}',
          style: TextStyle(
            color: est.color,
            fontSize: 12.0 / escala,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// Centro del bounding box del anillo más grande (suficiente para el badge).
  static Offset _centro(DepartamentoGeo d) {
    List<double> mayor = d.anillos.first;
    for (final a in d.anillos) {
      if (a.length > mayor.length) mayor = a;
    }
    var minX = mayor[0], maxX = mayor[0], minY = mayor[1], maxY = mayor[1];
    for (var i = 2; i < mayor.length; i += 2) {
      if (mayor[i] < minX) minX = mayor[i];
      if (mayor[i] > maxX) maxX = mayor[i];
      if (mayor[i + 1] < minY) minY = mayor[i + 1];
      if (mayor[i + 1] > maxY) maxY = mayor[i + 1];
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  @override
  bool shouldRepaint(_MapaPeruPainter old) =>
      old.seleccionado != seleccionado || old.escala != escala;
}

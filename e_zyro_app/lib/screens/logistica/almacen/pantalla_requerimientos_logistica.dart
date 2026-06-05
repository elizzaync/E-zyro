// pantalla_requerimientos_logistica.dart — Fase 2: bandeja UNIFICADA de
// requerimientos (materiales + equipos/herramientas) en una sola pantalla.
//
// Reemplaza visualmente a pantalla_solicitudes_logistica + pantalla_prestamos_
// logistica. Carga AMBOS servicios en paralelo y los une con ReqUnificado;
// el detalle de cada tarjeta porta la lógica real (aprobar/entregar/rechazar/
// devolución/firma) sin perder funciones.

import 'package:flutter/material.dart';
import '../../../services/requerimiento_service.dart';
import '../../../services/prestamo_service.dart';
import '../../../utils/api_provider.dart';
import 'es_tokens.dart';
import 'es_widgets.dart';
import 'req_unificado.dart';
import 'detalle_material_almacen.dart';
import 'detalle_equipo_almacen.dart';

class PantallaRequerimientosLogistica extends StatefulWidget {
  const PantallaRequerimientosLogistica({super.key});

  @override
  State<PantallaRequerimientosLogistica> createState() =>
      _PantallaRequerimientosLogisticaState();
}

class _PantallaRequerimientosLogisticaState
    extends State<PantallaRequerimientosLogistica> {
  RequerimientoService? _reqService;
  PrestamoService? _prestamoService;

  List<ReqUnificado> _all = [];
  bool _loading = true;

  int _tipo = 0;   // 0 Todos · 1 Materiales · 2 Equipos
  int _estado = 0; // 0 Todos · 1 Pendientes · 2 Aprobadas · 3 Entregadas · 4 Devueltos · 5 Rechazados

  static const _estadoTabs = ['Todos', 'Pendientes', 'Aprobadas', 'Entregadas', 'Devueltos', 'Rechazados'];
  static const _estadoNorm = ['', 'pendiente', 'aprobado', 'entregado', 'devuelto', 'rechazado'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _reqService = await getRequerimientoService();
    _prestamoService = await getPrestamoService();
    await _load();
  }

  Future<void> _load() async {
    if (_reqService == null || _prestamoService == null) return;
    setState(() => _loading = true);
    // Tres peticiones en paralelo (se crean antes de await).
    final matsF = _reqService!.getSolicitudesPendientes(estado: null);
    final eqsF = _prestamoService!.getPrestamos(estado: 'todos');
    // Catálogo de consumibles para el StockChip (materialId → stock disponible).
    final catF = _reqService!.getCatalogo('', tipo: 'consumible', pageSize: 300);
    final mats = await matsF;
    final eqs = await eqsF;
    final cat = await catF;
    if (!mounted) return;
    final stockPorMaterial = {for (final c in cat) c.id: c.stock};
    setState(() {
      _all = [
        ...mats.map((s) => ReqUnificado.fromSolicitud(s, stockPorMaterial: stockPorMaterial)),
        ...eqs.map(ReqUnificado.fromPrestamo),
      ];
      _loading = false;
    });
  }

  // Filtro por estado (tab) aplicado primero; el tipo se aplica para la lista.
  List<ReqUnificado> get _porEstado {
    final norm = _estadoNorm[_estado];
    if (norm.isEmpty) return _all;
    return _all.where((r) => r.estadoNorm == norm).toList();
  }

  List<ReqUnificado> get _visibles {
    final base = _porEstado;
    if (_tipo == 1) return base.where((r) => r.esMaterial).toList();
    if (_tipo == 2) return base.where((r) => r.esEquipo).toList();
    return base;
  }

  Future<void> _abrir(ReqUnificado r) async {
    bool? changed;
    if (r.esMaterial && r.solicitud != null && _reqService != null) {
      changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DetalleMaterialAlmacen(
              solicitud: r.solicitud!, service: _reqService!),
        ),
      );
    } else if (r.esEquipo && r.prestamo != null && _prestamoService != null) {
      changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DetalleEquipoAlmacen(
              prestamo: r.prestamo!, service: _prestamoService!),
        ),
      );
    }
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final base = _porEstado;
    final nMat = base.where((r) => r.esMaterial).length;
    final nEq = base.where((r) => r.esEquipo).length;
    final visibles = _visibles;

    return Scaffold(
      backgroundColor: ESC.bg,
      body: Column(children: [
        ESPanelBar(
          title: 'Requerimientos',
          subtitle: 'Materiales y equipos de campo',
          trailing: ESBarIcon(Icons.refresh_rounded, onTap: _load),
        ),
        Expanded(
          child: RefreshIndicator(
            color: ESC.brand,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ESSegmented(
                  selected: _tipo,
                  onChanged: (i) => setState(() => _tipo = i),
                  items: [
                    ESSeg('Todos', count: base.length),
                    ESSeg('Materiales', icon: ESIcons.box, count: nMat, color: ESC.brandDeep),
                    ESSeg('Equipos', icon: ESIcons.wrench, count: nEq, color: ESC.equip),
                  ],
                ),
                const SizedBox(height: 12),
                ESPills(
                  selected: _estado,
                  onChanged: (i) => setState(() => _estado = i),
                  items: _estadoTabs,
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator(color: ESC.brand)),
                  )
                else if (visibles.isEmpty)
                  _vacio()
                else
                  for (final r in visibles) ...[
                    _ReqCard(req: r, onTap: () => _abrir(r)),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _vacio() => Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(children: [
          Icon(ESIcons.box, size: 44, color: ESC.inkFaint),
          const SizedBox(height: 12),
          Text('Sin requerimientos en este filtro',
              style: pj(size: 14, weight: FontWeight.w600, color: ESC.inkSub)),
        ]),
      );
}

class _ReqCard extends StatelessWidget {
  final ReqUnificado req;
  final VoidCallback onTap;
  const _ReqCard({required this.req, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEq = req.esEquipo;
    final accent = isEq ? ESC.equip : ESC.brand;
    return GestureDetector(
      onTap: onTap,
      child: ESCard(
        accent: accent,
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            TypeBadge(isEq ? 'Equipo' : 'Material'),
            const SizedBox(width: 9),
            Text(req.codigoCorto, style: pj(size: 12, weight: FontWeight.w700, color: ESC.inkFaint)),
            const Spacer(),
            StatusPill(req.estadoLabel),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            ESAvatar(req.solicitante.isNotEmpty ? req.solicitante[0] : '?',
                color: isEq ? ESC.equip : ESC.brandDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(req.solicitante, style: pj(size: 13, weight: FontWeight.w700)),
                Text(req.proyecto, maxLines: 1, overflow: TextOverflow.ellipsis, style: pj(size: 11, color: ESC.inkFaint)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Container(height: 1, color: ESC.line),
          const SizedBox(height: 10),
          for (final it in req.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                Container(width: 5, height: 5, margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                Expanded(child: Text(it.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: pj(size: 13, color: ESC.ink))),
                const SizedBox(width: 8),
                Text(it.cantidadLabel, style: pj(size: 12.5, weight: FontWeight.w700, color: ESC.inkSub)),
                if (!isEq && it.enStock != null) ...[const SizedBox(width: 8), StockChip(it.enStock!)],
              ]),
            ),
          if (req.dueText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Icon(ESIcons.clock, size: 14, color: ESC.equip),
                const SizedBox(width: 6),
                Text(req.dueText!, style: pj(size: 12, weight: FontWeight.w700, color: ESC.equip)),
              ]),
            ),
        ]),
      ),
    );
  }
}

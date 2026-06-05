// detalle_material_almacen.dart — Fase 2: detalle de una solicitud de MATERIAL.
// Porta 1:1 la lógica real de pantalla_solicitudes_logistica (aprobar / rechazar
// / entregar con doble firma), reusando el MISMO servicio y endpoints.

import 'package:flutter/material.dart';
import '../../../models/requerimiento_models.dart';
import '../../../services/requerimiento_service.dart';
import '../../../widgets/firma_sheet.dart';
import 'es_tokens.dart';
import 'es_widgets.dart';

class DetalleMaterialAlmacen extends StatefulWidget {
  final SolicitudGestion solicitud;
  final RequerimientoService service;
  const DetalleMaterialAlmacen({
    super.key,
    required this.solicitud,
    required this.service,
  });

  @override
  State<DetalleMaterialAlmacen> createState() => _DetalleMaterialAlmacenState();
}

class _DetalleMaterialAlmacenState extends State<DetalleMaterialAlmacen> {
  late SolicitudGestion s = widget.solicitud;
  bool _busy = false;

  bool get _esPendiente =>
      s.estado == 'pendiente' || s.estado == 'listo' || s.estado == 'comprando';
  bool get _esAprobado => s.estado == 'aprobado';

  void _snack(bool ok, String okMsg, String errMsg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? okMsg : errMsg),
      backgroundColor: ok ? ESC.brand : ESC.vencido,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Aprobar ────────────────────────────────────────────────────────────────
  Future<void> _aprobar() async {
    setState(() => _busy = true);
    final ok = await widget.service.gestionarSolicitud(s.id, 'aprobar');
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok, 'Solicitud aprobada', 'No se pudo aprobar');
    if (ok) Navigator.pop(context, true);
  }

  // ── Rechazar ─────────────────────────────────────────────────────────────--
  Future<void> _rechazar() async {
    final ctrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Indica el motivo del rechazo (opcional):',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
                hintText: 'Motivo...', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Rechazar', style: TextStyle(color: ESC.vencido))),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _busy = true);
    final ok = await widget.service
        .gestionarSolicitud(s.id, 'rechazar', observacion: ctrl.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok, 'Solicitud rechazada', 'No se pudo rechazar');
    if (ok) Navigator.pop(context, true);
  }

  // ── Entregar (doble firma) ───────────────────────────────────────────────--
  Future<void> _entregar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar entrega'),
        content: const Text(
            'Se descontará el stock de los materiales aprobados. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Entregar', style: TextStyle(color: ESC.brandDeep))),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final firma = await FirmaSheet.mostrar(
      context,
      titulo: 'Firma de entrega',
      subtitulo: 'Firma del encargado de logística que entrega los materiales.',
      textoBoton: 'Confirmar entrega',
    );
    if (firma == null || firma.isEmpty) return;

    setState(() => _busy = true);
    final ok = await widget.service.entregarSolicitud(s.id, firma);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok, 'Materiales entregados', 'No se pudo entregar');
    if (ok) Navigator.pop(context, true);
  }

  String get _estadoLabel {
    switch (s.estado) {
      case 'aprobado':
        return 'Aprobada';
      case 'entregado':
        return 'Entregada';
      case 'rechazado':
        return 'Rechazado';
      default:
        return 'Pendiente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = s.items;
    return Scaffold(
      backgroundColor: ESC.bg,
      body: Column(children: [
        ESPanelBar(
          title: 'Solicitud de material',
          subtitle: s.proyectoNombre,
          trailing: const TypeBadge('Material'),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            ESCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ESAvatar(s.solicitanteNombre.isNotEmpty ? s.solicitanteNombre[0] : '?',
                      color: ESC.brandDeep, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(s.solicitanteNombre, style: pj(size: 15, weight: FontWeight.w700)),
                      Text(s.fecha, style: pj(size: 12, color: ESC.inkSub)),
                    ]),
                  ),
                  StatusPill(_estadoLabel),
                ]),
                if ((s.observacionLogistico ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: ESC.bg, borderRadius: BorderRadius.circular(12)),
                    child: Text(s.observacionLogistico!, style: pj(size: 13, color: ESC.inkSub)),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            ESSectionLabel('Ítems solicitados · ${items.length}'),
            const SizedBox(height: 10),
            for (final it in items) ...[
              ESCard(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(color: ESC.matBg, borderRadius: BorderRadius.circular(9)),
                    child: Icon(ESIcons.box, size: 18, color: ESC.brandDeep),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.nombre, style: pj(size: 14, weight: FontWeight.w700, height: 1.3)),
                      const SizedBox(height: 6),
                      Text('${it.cantidad} ${it.unidad}'
                          '${it.cantidadAprobada != null ? '  ·  aprob: ${it.cantidadAprobada}' : ''}',
                          style: pj(size: 13, weight: FontWeight.w700, color: ESC.inkSub)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
          ]),
        ),
        if (_esPendiente || _esAprobado) _actionBar(),
      ]),
    );
  }

  Widget _actionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
          color: ESC.surface, border: Border(top: BorderSide(color: ESC.line))),
      child: SafeArea(
        top: false,
        child: _busy
            ? const SizedBox(
                height: 52,
                child: Center(child: CircularProgressIndicator(color: ESC.brand)))
            : Row(children: [
                Expanded(
                  child: ESButton('Rechazar',
                      kind: ESBtnKind.danger, expand: true, onTap: _rechazar),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _esPendiente
                      ? ESButton('Aprobar',
                          icon: ESIcons.check, expand: true, onTap: _aprobar)
                      : ESButton('Aprobar y entregar',
                          icon: ESIcons.truck, expand: true, onTap: _entregar),
                ),
              ]),
      ),
    );
  }
}

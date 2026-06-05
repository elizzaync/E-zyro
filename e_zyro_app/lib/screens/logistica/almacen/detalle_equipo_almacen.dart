// detalle_equipo_almacen.dart — Fase 2: detalle de un PRÉSTAMO de equipo/herram.
// Porta 1:1 la lógica real de pantalla_prestamos_logistica (entregar con firma /
// rechazar / confirmar devolución), reusando el MISMO servicio y endpoints.

import 'package:flutter/material.dart';
import '../../../models/prestamo_models.dart';
import '../../../services/prestamo_service.dart';
import '../../../widgets/firma_sheet.dart';
import 'es_tokens.dart';
import 'es_widgets.dart';

class DetalleEquipoAlmacen extends StatefulWidget {
  final Prestamo prestamo;
  final PrestamoService service;
  const DetalleEquipoAlmacen({
    super.key,
    required this.prestamo,
    required this.service,
  });

  @override
  State<DetalleEquipoAlmacen> createState() => _DetalleEquipoAlmacenState();
}

class _DetalleEquipoAlmacenState extends State<DetalleEquipoAlmacen> {
  late Prestamo p = widget.prestamo;
  bool _busy = false;

  bool get _esSolicitado => p.estado == 'solicitado';
  bool get _esDevuelto => p.estado == 'devuelto';

  void _snack(bool ok, String okMsg, String errMsg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? okMsg : errMsg),
      backgroundColor: ok ? ESC.brand : ESC.vencido,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Entregar (firma del entregador → queda 'por_recibir') ─────────────────
  Future<void> _entregar() async {
    final firma = await FirmaSheet.mostrar(
      context,
      titulo: 'Firma de entrega (logística)',
      subtitulo:
          'Despachas ${p.items.length} equipo(s)/herramienta(s) a ${p.solicitanteNombre}',
      textoBoton: 'Confirmar despacho',
    );
    if (firma == null || firma.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final res = await widget.service.entregar(p.id, firmaEntregadorUrl: firma);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(res.ok, 'Despachado · espera la firma de recepción del equipo',
        res.error ?? 'No se pudo entregar');
    if (res.ok) Navigator.pop(context, true);
  }

  // ── Rechazar ─────────────────────────────────────────────────────────────--
  Future<void> _rechazar() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar préstamo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Indica el motivo del rechazo:', style: TextStyle(fontSize: 13)),
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
    if (ok != true) return;
    final motivo = ctrl.text.trim();
    if (motivo.isEmpty) return;
    setState(() => _busy = true);
    final res = await widget.service.rechazar(p.id, observacion: motivo);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(res.ok, 'Préstamo rechazado', res.error ?? 'No se pudo rechazar');
    if (res.ok) Navigator.pop(context, true);
  }

  // ── Confirmar devolución (aceptar / observar) ─────────────────────────────
  Future<void> _confirmar() async {
    final perdidasTotales = p.items.fold<int>(0, (a, it) => a + it.cantidadPerdida);
    final ctrl = TextEditingController();
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar devolución'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solicitante: ${p.solicitanteNombre}', style: const TextStyle(fontSize: 12)),
            if (perdidasTotales > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ESC.vencido.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ESC.vencido.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: ESC.vencido, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$perdidasTotales unidad${perdidasTotales == 1 ? '' : 'es'} faltante${perdidasTotales == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 12, color: ESC.vencido, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  hintText: 'Observación (opcional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Observar', style: TextStyle(color: ESC.compra))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Confirmar', style: TextStyle(color: ESC.brandDeep))),
        ],
      ),
    );
    if (aceptar == null) return;
    setState(() => _busy = true);
    final res = await widget.service.confirmarDevolucion(
      p.id,
      aceptar: aceptar,
      observacion: ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(res.ok, aceptar ? 'Devolución confirmada' : 'Devolución observada',
        res.error ?? 'No se pudo procesar');
    if (res.ok) Navigator.pop(context, true);
  }

  String get _estadoLabel {
    switch (p.estado) {
      case 'por_recibir':
        return 'Aprobada';
      case 'entregado':
        return 'En préstamo';
      case 'devuelto':
      case 'confirmado':
        return 'Devuelto';
      case 'rechazado':
        return 'Rechazado';
      default:
        return 'Pendiente';
    }
  }

  // Pasos del ciclo construidos desde las fechas reales del préstamo.
  List<_Paso> get _pasos {
    final pasos = <_Paso>[
      _Paso('Solicitado', p.fechaSolicitud, done: p.fechaSolicitud.isNotEmpty),
      _Paso('Entregado', p.fechaEntrega ?? '—', done: p.fechaEntrega != null),
      _Paso('Devuelto', p.fechaDevolucion ?? '—', done: p.fechaDevolucion != null),
      _Paso('Confirmado', p.fechaConfirmacion ?? '—', done: p.fechaConfirmacion != null),
    ];
    final idx = pasos.indexWhere((s) => !s.done);
    if (idx >= 0) pasos[idx] = pasos[idx].copyNow();
    return pasos;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ESC.bg,
      body: Column(children: [
        ESPanelBar(
          title: 'Préstamo de equipo',
          subtitle: p.proyectoNombre ?? p.servicioNombre ?? 'Servicio',
          trailing: const TypeBadge('Equipo'),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            ESCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ESAvatar(p.solicitanteNombre.isNotEmpty ? p.solicitanteNombre[0] : '?',
                      color: ESC.equip, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(p.solicitanteNombre, style: pj(size: 15, weight: FontWeight.w700)),
                      Text(p.fechaSolicitud, style: pj(size: 12, color: ESC.inkSub)),
                    ]),
                  ),
                  StatusPill(_estadoLabel),
                ]),
                if (p.porRecibir) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: ESC.equipBg, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(ESIcons.clock, size: 18, color: ESC.equip),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Despachado · espera la firma de recepción del equipo',
                            style: pj(size: 12.5, weight: FontWeight.w600, color: ESC.equip)),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            ESSectionLabel('Ciclo de devolución'),
            const SizedBox(height: 10),
            ESCard(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                for (int i = 0; i < _pasos.length; i++)
                  _stepRow(_pasos[i], i == _pasos.length - 1),
              ]),
            ),
            const SizedBox(height: 12),
            ESSectionLabel('Equipos en préstamo · ${p.items.length}'),
            const SizedBox(height: 10),
            for (final e in p.items) ...[
              ESCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: ESC.equipBg, borderRadius: BorderRadius.circular(10)),
                    child: Icon(ESIcons.wrench, size: 20, color: ESC.equip),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(e.equipoNombre, style: pj(size: 14, weight: FontWeight.w700)),
                      Text('${e.equipoCodigo ?? e.clase} · ${e.cantidadSolicitada} u',
                          style: pj(size: 12, color: ESC.inkFaint)),
                    ]),
                  ),
                  if (e.cantidadPerdida > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: ESC.vencidoBg, borderRadius: BorderRadius.circular(7)),
                      child: Text('${e.cantidadPerdida} falta',
                          style: pj(size: 11.5, weight: FontWeight.w700, color: ESC.vencido)),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
          ]),
        ),
        if (_esSolicitado || _esDevuelto) _actionBar(),
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
            : _esSolicitado
                ? Row(children: [
                    Expanded(
                      child: ESButton('Rechazar',
                          kind: ESBtnKind.danger, expand: true, onTap: _rechazar),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ESButton('Entregar',
                          icon: ESIcons.truck, color: ESC.equip, expand: true, onTap: _entregar),
                    ),
                  ])
                : ESButton('Confirmar devolución',
                    icon: ESIcons.undo, color: ESC.equip, expand: true, onTap: _confirmar),
      ),
    );
  }

  Widget _stepRow(_Paso s, bool last) {
    final c = s.done ? ESC.entreg : s.now ? ESC.equip : ESC.lineStrong;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
                color: s.done ? ESC.entreg : ESC.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c, width: 2)),
            child: s.done
                ? const Icon(ESIcons.check, size: 13, color: Colors.white)
                : s.now
                    ? Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: ESC.equip, shape: BoxShape.circle)))
                    : null,
          ),
          if (!last) Expanded(child: Container(width: 2, color: s.done ? ESC.entreg : ESC.line)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(s.label,
                  style: pj(size: 14, weight: s.now ? FontWeight.w800 : FontWeight.w700,
                      color: s.now ? ESC.equip : s.done ? ESC.ink : ESC.inkFaint)),
              Text(s.when, style: pj(size: 12, color: ESC.inkFaint)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Paso {
  final String label, when;
  final bool done, now;
  const _Paso(this.label, this.when, {this.done = false, this.now = false});
  _Paso copyNow() => _Paso(label, when, done: done, now: true);
}

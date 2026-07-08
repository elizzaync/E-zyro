import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/prestamo_models.dart';
import '../models/proyecto_models.dart';
import '../services/prestamo_service.dart';
import '../services/proyecto_service.dart';
import '../services/chat_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../widgets/topo_background.dart';
import '../widgets/firma_sheet.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed   = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kBlue  = Color(0xFF3B82F6);
const _kPurple = Color(0xFF8B5CF6);
const _kGray  = Color(0xFF6B7280);

/// Pantalla del técnico: gestiona préstamos de equipos/herramientas para un
/// servicio específico. Permite solicitar, ver estado y registrar devolución.
class PantallaPrestamosServicio extends StatefulWidget {
  final String servicioId;
  final String servicioNombre;
  final bool isClosed;

  const PantallaPrestamosServicio({
    super.key,
    required this.servicioId,
    required this.servicioNombre,
    this.isClosed = false,
  });

  @override
  State<PantallaPrestamosServicio> createState() =>
      _PantallaPrestamosServicioState();
}

class _PantallaPrestamosServicioState extends State<PantallaPrestamosServicio> {
  PrestamoService? _service;
  List<Prestamo> _prestamos = [];
  List<PrestamoBorradorItem> _borrador = [];
  bool _loading = true;
  bool _enviandoBorrador = false;

  // WS en vivo: refresca cuando otro técnico toma/suelta el lock de firma o
  // cuando logística despacha (banner "X está firmando" sin recargar).
  ChatService? _eventosWs;
  Timer? _eventDebounce;

  @override
  void initState() {
    super.initState();
    _init();
    _conectarEventos();
  }

  @override
  void dispose() {
    _eventDebounce?.cancel();
    _eventosWs?.dispose();
    super.dispose();
  }

  Future<void> _conectarEventos() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    if (token.isEmpty || !mounted) return;
    final ws = ChatService();
    ws.connect('servicio/${widget.servicioId}', token);
    ws.eventos.listen((_) {
      // Coalescer ráfagas de eventos en una sola recarga.
      _eventDebounce?.cancel();
      _eventDebounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) _load();
      });
    });
    _eventosWs = ws;
  }

  Future<void> _init() async {
    _service = await getPrestamoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _loading = true);
    final data = await _service!.getPorServicio(widget.servicioId);
    final borr = await _service!.getBorrador(widget.servicioId);
    if (!mounted) return;
    setState(() {
      _prestamos = data;
      _borrador = borr;
      _loading = false;
    });
  }

  Future<void> _quitarBorradorItem(PrestamoBorradorItem it) async {
    if (_service == null) return;
    final ok = await _service!.quitarItemBorrador(it.id);
    if (ok) {
      await _load();
    } else {
      _snack('No se pudo quitar el ítem', _kRed);
    }
  }

  Future<void> _enviarBorrador() async {
    if (_service == null || _borrador.isEmpty) return;
    final firma = await FirmaSheet.mostrar(
      context,
      titulo: 'Firmar solicitud',
      subtitulo: 'Firma para confirmar y enviar el lote de equipos/herramientas',
      textoBoton: 'Firmar y enviar',
    );
    if (firma == null || firma.isEmpty || !mounted) return;
    setState(() => _enviandoBorrador = true);
    final res = await _service!
        .enviarBorrador(widget.servicioId, firmaSolicitanteUrl: firma);
    if (!mounted) return;
    setState(() => _enviandoBorrador = false);
    if (res.ok) {
      final msg = res.faltanteCount > 0
          ? 'Solicitud enviada. ${res.faltanteCount} ítem(s) sin stock se enviaron a compra a Logística.'
          : 'Solicitud de equipos enviada';
      _snack(msg, res.faltanteCount > 0 ? _kAmber : _kGreen);
      await _load();
    } else {
      _snack(res.error ?? 'Error al enviar', _kRed);
    }
  }

  Future<void> _abrirSolicitarSheet() async {
    if (_service == null) return;
    final cambios = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SolicitarPrestamoSheet(
        servicioId: widget.servicioId,
        service: _service!,
      ),
    );
    if (cambios == true) await _load();
  }

  Future<void> _abrirDevolverSheet(Prestamo p) async {
    if (_service == null) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DevolverSheet(prestamo: p, service: _service!),
    );
    if (ok == true) await _load();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Firma de recepción del préstamo (consenso cinema-seat + firma del equipo).
  /// Toma el lock ANTES de abrir la firma para que ningún otro técnico firme a
  /// la vez (los demás ven "X está firmando"). Libera el lock si cancela/falla.
  Future<void> _firmarRecepcion(Prestamo p) async {
    if (_service == null) return;
    if (p.hayAlguienFirmando) {
      _snack('${p.firmandoPorNombre} está firmando la recepción ahora.', _kAmber);
      return;
    }
    final lock = await _service!.bloquearFirmaPrestamo(p.id);
    if (!lock.ok) {
      // 409 → detalle 'firmando_por:<nombre>'
      final det = lock.error ?? '';
      final quien = det.startsWith('firmando_por:') ? det.substring(13) : 'Otro técnico';
      if (mounted) _snack('$quien está firmando la recepción ahora.', _kAmber);
      await _load();
      return;
    }
    if (!mounted) return;
    final firma = await FirmaSheet.mostrar(
      context,
      titulo: 'Firmar recepción del equipo',
      subtitulo:
          'Confirmas recibir ${p.items.length} equipo(s)/herramienta(s) de ${p.solicitanteNombre}',
      textoBoton: 'Confirmar recepción',
    );
    if (firma == null || firma.isEmpty) {
      await _service!.liberarFirmaPrestamo(p.id);
      if (mounted) await _load();
      return;
    }
    final res = await _service!.firmarRecepcion(p.id, firmaReceptorUrl: firma);
    if (!mounted) return;
    if (res.ok) {
      _snack('Recepción firmada. El préstamo quedó recibido.', _kGreen);
      await _load();
    } else {
      await _service!.liberarFirmaPrestamo(p.id);
      _snack(res.error ?? 'No se pudo firmar la recepción', _kRed);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pendienteConfirm = _prestamos.where((p) => p.estado == 'devuelto').length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Equipos y herramientas',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(widget.servicioNombre,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        elevation: 0,
      ),
      floatingActionButton: widget.isClosed
          ? null
          : FloatingActionButton.extended(
        onPressed: _abrirSolicitarSheet,
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.build_outlined),
        label: const Text('Solicitar',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16, amp: 9, stroke: 0.38, speed: 0.45,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kGreen))
            : Column(
                children: [
                  if (pendienteConfirm > 0)
                    _PendienteConfirmacionBanner(count: pendienteConfirm),
                  if (!widget.isClosed && _borrador.isNotEmpty)
                    _buildBorradorSection(),
                  Expanded(
                    child: _prestamos.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: _kGreen,
                            child: ListView.separated(
                              padding: bottomSafePadding(context, extra: 96),
                              itemCount: _prestamos.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => PrestamoCard(
                                prestamo: _prestamos[i],
                                onDevolver: _prestamos[i].estado == 'entregado'
                                    ? () => _abrirDevolverSheet(_prestamos[i])
                                    : null,
                                onFirmarRecepcion: _prestamos[i].porRecibir
                                    ? () => _firmarRecepcion(_prestamos[i])
                                    : null,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBorradorSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kAmber.withValues(alpha: 0.5), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.edit_note, color: _kAmber, size: 20),
            const SizedBox(width: 6),
            const Text('Borrador de solicitud',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${_borrador.length} ítem(s)',
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          ..._borrador.map((it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(
                      it.clase == 'herramienta'
                          ? Icons.handyman_outlined
                          : Icons.precision_manufacturing_outlined,
                      size: 18, color: _kGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(it.nombre,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text('x${it.cantidad}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  if (it.disponible < it.cantidad)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text('(${it.disponible} disp.)',
                          style: const TextStyle(
                              color: _kAmber, fontSize: 10.5)),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16, color: _kRed),
                    onPressed: () => _quitarBorradorItem(it),
                  ),
                ]),
              )),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enviandoBorrador ? null : _enviarBorrador,
              icon: _enviandoBorrador
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.draw_outlined, size: 16),
              label: Text(
                  _enviandoBorrador ? 'Enviando...' : 'Firmar y enviar a Logística',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAmber,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.handyman_outlined, size: 52, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            const Text('Sin equipos solicitados',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 6),
            const Text('Usa el botón "Solicitar" para pedir equipos o herramientas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
}

// ─── Banner de devoluciones pendientes de confirmar ───────────────────────────

class _PendienteConfirmacionBanner extends StatelessWidget {
  final int count;
  const _PendienteConfirmacionBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kAmber.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: _kAmber, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$count devolución${count == 1 ? '' : 'es'} esperando confirmación de Logística.',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

// ─── Card de un préstamo (reusable: técnico y logística) ──────────────────────

class PrestamoCard extends StatelessWidget {
  final Prestamo prestamo;
  final VoidCallback? onDevolver;
  final VoidCallback? onEntregar;
  final VoidCallback? onConfirmar;
  final VoidCallback? onRechazar;
  final VoidCallback? onFirmarRecepcion;
  final bool mostrarServicio;

  const PrestamoCard({
    super.key,
    required this.prestamo,
    this.onDevolver,
    this.onEntregar,
    this.onConfirmar,
    this.onRechazar,
    this.onFirmarRecepcion,
    this.mostrarServicio = false,
  });

  ({Color color, IconData icon, String label}) get _estado {
    switch (prestamo.estado) {
      case 'solicitado':  return (color: _kAmber,  icon: Icons.hourglass_top_rounded,    label: 'Solicitado');
      case 'por_recibir': return (color: _kBlue,   icon: Icons.inventory_2_outlined,     label: 'Por recibir');
      case 'entregado':   return (color: _kBlue,   icon: Icons.local_shipping_outlined,  label: 'Entregado');
      case 'devuelto':    return (color: _kPurple, icon: Icons.assignment_return_outlined,label: 'Pendiente confirmar');
      case 'confirmado':  return (color: _kGreen,  icon: Icons.check_circle_outline,     label: 'Confirmado');
      case 'rechazado':   return (color: _kRed,    icon: Icons.cancel_outlined,          label: 'Rechazado');
      default:            return (color: _kGray,   icon: Icons.help_outline,             label: prestamo.estado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final est = _estado;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: est.color.withValues(alpha: 0.3)) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: est.color.withValues(alpha: isDark ? 0.15 : 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(est.icon, color: est.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (mostrarServicio && prestamo.servicioNombre != null)
                    Text(prestamo.servicioNombre!,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(prestamo.solicitanteNombre,
                      style: TextStyle(
                          fontSize: mostrarServicio ? 11 : 13,
                          color: mostrarServicio ? Colors.grey : null,
                          fontWeight:
                              mostrarServicio ? FontWeight.normal : FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(prestamo.fechaSolicitud,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: est.color.withValues(alpha: isDark ? 0.15 : 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(est.label,
                  style: TextStyle(
                      color: est.color, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ),
          ]),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Items
          ...prestamo.items.map((it) => _itemRow(it, isDark)),

          // Préstamo auto-generado al recibir una compra de faltante: mostramos
          // una nota legible en vez de la marca técnica interna.
          if (prestamo.esAutoCompra) ...[
            const SizedBox(height: 8),
            _notaBox('Origen', 'Generado por compra de faltante de stock',
                _kBlue),
          ] else if (prestamo.observacion != null &&
              prestamo.observacion!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _notaBox('Solicitante', prestamo.observacion!, _kGray),
          ],
          if (prestamo.observacionLogistico != null &&
              prestamo.observacionLogistico!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _notaBox('Logística', prestamo.observacionLogistico!,
                prestamo.estado == 'rechazado' ? _kRed : _kGreen),
          ],

          // Banner cinema-seat: otro técnico está firmando la recepción ahora.
          if (prestamo.porRecibir && prestamo.hayAlguienFirmando) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _kAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kAmber.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.draw_outlined, size: 15, color: _kAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${prestamo.firmandoPorNombre} está firmando la recepción…',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: _kAmber)),
                ),
              ]),
            ),
          ],

          if (onFirmarRecepcion != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    prestamo.hayAlguienFirmando ? null : onFirmarRecepcion,
                icon: const Icon(Icons.draw_outlined, size: 16),
                label: const Text('Firmar recepción'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],

          if (onDevolver != null || onEntregar != null ||
              onConfirmar != null || onRechazar != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              if (onRechazar != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRechazar,
                    icon: const Icon(Icons.close, size: 16, color: _kRed),
                    label: const Text('Rechazar', style: TextStyle(color: _kRed)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kRed),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (onRechazar != null && onEntregar != null) const SizedBox(width: 8),
              if (onEntregar != null)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onEntregar,
                    icon: const Icon(Icons.local_shipping_outlined, size: 16),
                    label: const Text('Entregar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (onDevolver != null)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onDevolver,
                    icon: const Icon(Icons.assignment_return_outlined, size: 16),
                    label: const Text('Devolver'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (onConfirmar != null)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onConfirmar,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Confirmar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(PrestamoItem it, bool isDark) {
    final partes = <String>[];
    partes.add('Sol: ${it.cantidadSolicitada}');
    if (it.cantidadEntregada != null) partes.add('Ent: ${it.cantidadEntregada}');
    if (it.cantidadDevuelta != null)  partes.add('Dev: ${it.cantidadDevuelta}');
    if (it.cantidadPerdida > 0)       partes.add('Perd: ${it.cantidadPerdida}');

    final perdida = it.cantidadPerdida > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: (it.clase == 'herramienta' ? _kAmber : _kBlue)
                .withValues(alpha: isDark ? 0.15 : 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
              it.clase == 'herramienta'
                  ? Icons.handyman_outlined
                  : Icons.precision_manufacturing_outlined,
              size: 12,
              color: it.clase == 'herramienta' ? _kAmber : _kBlue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.equipoNombre,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            Text(partes.join('  ·  '),
                style: TextStyle(
                    fontSize: 10.5,
                    color: perdida ? _kRed : Colors.grey,
                    fontWeight: perdida ? FontWeight.w600 : FontWeight.normal)),
          ]),
        ),
      ]),
    );
  }

  Widget _notaBox(String etiqueta, String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$etiqueta: ',
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(texto,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontStyle: FontStyle.italic),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

// ─── Sheet: Solicitar préstamo (catálogo + carrito) ───────────────────────────

class _SolicitarPrestamoSheet extends StatefulWidget {
  final String servicioId;
  final PrestamoService service;
  const _SolicitarPrestamoSheet({
    required this.servicioId,
    required this.service,
  });

  @override
  State<_SolicitarPrestamoSheet> createState() =>
      _SolicitarPrestamoSheetState();
}

class _SolicitarPrestamoSheetState extends State<_SolicitarPrestamoSheet> {
  // Modo: 0 = Equipos/Herramientas (préstamo) · 1 = Materiales (borrador req.)
  int _modo = 0;

  List<EquipoCatalogo> _catalogo = [];
  bool _loading = true;
  bool _sending = false;
  String _claseFiltro = ''; // '' | 'equipo' | 'herramienta'
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  final _obsCtrl = TextEditingController();

  // Carrito local de equipos: equipo_id → cantidad
  final Map<String, int> _carrito = {};

  // ── Materiales (catálogo → borrador de requerimiento) ──────────────────────
  ProyectoService? _proyectoService;
  final _searchMatCtrl = TextEditingController();
  Timer? _debounceMat;
  List<MaterialBusqueda> _resultadosMat = [];
  bool _loadingMat = false;
  // Carrito de materiales: material_id → (material, cantidad)
  final Map<String, ({MaterialBusqueda mat, int cant})> _carritoMat = {};

  @override
  void initState() {
    super.initState();
    _load();
    _initProyectoService();
  }

  Future<void> _initProyectoService() async {
    final s = await getProyectoService();
    if (mounted) setState(() => _proyectoService = s);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _obsCtrl.dispose();
    _debounce?.cancel();
    _searchMatCtrl.dispose();
    _debounceMat?.cancel();
    super.dispose();
  }

  void _onSearchMatChanged(String q) {
    _debounceMat?.cancel();
    _debounceMat = Timer(const Duration(milliseconds: 400), () async {
      final svc = _proyectoService;
      if (svc == null) return;
      setState(() => _loadingMat = true);
      final r = await svc.buscarMateriales(q);
      if (!mounted) return;
      setState(() {
        _resultadosMat = r;
        _loadingMat = false;
      });
    });
  }

  Future<void> _enviarMateriales() async {
    final svc = _proyectoService;
    if (svc == null || _carritoMat.isEmpty) return;
    setState(() => _sending = true);
    var fallo = false;
    for (final e in _carritoMat.values) {
      final res = await svc.agregarItemBorrador(
        widget.servicioId,
        materialId: e.mat.id,
        nombre: e.mat.nombre,
        unidad: e.mat.unidad,
        cantidad: e.cant,
      );
      if (!res.ok) fallo = true;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (!fallo) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Algunos materiales no se pudieron agregar'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.service.getCatalogo(
      q: _searchCtrl.text,
      clase: _claseFiltro,
    );
    if (!mounted) return;
    setState(() {
      _catalogo = data;
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _enviar() async {
    if (_carrito.isEmpty) return;
    // Agrega al BORRADOR (no crea el préstamo todavía). La firma se hace al
    // confirmar y enviar el borrador, igual que en materiales.
    setState(() => _sending = true);
    var ok = 0;
    for (final e in _carrito.entries) {
      if (await widget.service
          .agregarItemBorrador(widget.servicioId, e.key, e.value)) {
        ok++;
      }
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok > 0) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$ok ítem(s) agregados al borrador'),
        backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo agregar al borrador'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final esEquipos = _modo == 0;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Center(
            child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(esEquipos ? Icons.build_outlined : Icons.inventory_2_outlined,
                    color: _kGreen, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Solicitar Recursos',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  Text(esEquipos
                      ? 'Préstamo de equipos para este servicio'
                      : 'Materiales al borrador de Logística',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ),
              if ((esEquipos ? _carrito : _carritoMat).isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: _kGreen, borderRadius: BorderRadius.circular(20)),
                  child: Text('${(esEquipos ? _carrito : _carritoMat).length}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          // Selector de modo: Equipos/Herramientas · Materiales
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _modoChip('Equipos/Herram.', 0),
              const SizedBox(width: 8),
              _modoChip('Materiales', 1),
            ]),
          ),
          const SizedBox(height: 12),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: esEquipos ? _searchCtrl : _searchMatCtrl,
              onChanged: esEquipos ? _onSearchChanged : _onSearchMatChanged,
              decoration: InputDecoration(
                hintText: esEquipos
                    ? 'Buscar equipo / herramienta...'
                    : 'Buscar material (mín. 2 letras)...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          // Filtro de clase: solo para equipos
          if (esEquipos) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _claseChip('Todos',     ''),
                  _claseChip('Equipos',   'equipo'),
                  _claseChip('Herramientas', 'herramienta'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Expanded(
            child: esEquipos
                ? _buildListaEquipos(scrollCtrl)
                : _buildListaMateriales(scrollCtrl),
          ),
          // Observación (solo equipos) + Enviar
          Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(children: [
              if (esEquipos)
                TextField(
                  controller: _obsCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Observación (opcional)',
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              if (esEquipos) const SizedBox(height: 10),
              SizedBox(
                width: double.infinity, height: 48,
                child: esEquipos
                    ? ElevatedButton(
                        onPressed: _carrito.isEmpty || _sending ? null : _enviar,
                        style: _btnStyle(),
                        child: _sending
                            ? const _BtnSpinner()
                            : Text(_carrito.isEmpty
                                ? 'Selecciona equipos'
                                : 'Enviar solicitud (${_carrito.values.fold<int>(0, (a, b) => a + b)} unidades)',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                      )
                    : ElevatedButton(
                        onPressed:
                            _carritoMat.isEmpty || _sending ? null : _enviarMateriales,
                        style: _btnStyle(),
                        child: _sending
                            ? const _BtnSpinner()
                            : Text(_carritoMat.isEmpty
                                ? 'Selecciona materiales'
                                : 'Agregar al borrador (${_carritoMat.values.fold<int>(0, (a, b) => a + b.cant)} ítem(s))',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  ButtonStyle _btnStyle() => ElevatedButton.styleFrom(
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _buildListaEquipos(ScrollController scrollCtrl) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kGreen));
    }
    if (_catalogo.isEmpty) {
      return const Center(
          child: Text('Sin resultados', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      itemCount: _catalogo.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = _catalogo[i];
        final actual = _carrito[e.id] ?? 0;
        return _EquipoRow(
          equipo: e,
          cantidad: actual,
          onChange: (n) {
            setState(() {
              if (n <= 0) {
                _carrito.remove(e.id);
              } else {
                _carrito[e.id] = n;
              }
            });
          },
        );
      },
    );
  }

  Widget _buildListaMateriales(ScrollController scrollCtrl) {
    if (_loadingMat) {
      return const Center(child: CircularProgressIndicator(color: _kGreen));
    }
    if (_searchMatCtrl.text.trim().length < 2) {
      return const Center(
          child: Text('Escribe para buscar materiales',
              style: TextStyle(color: Colors.grey)));
    }
    if (_resultadosMat.isEmpty) {
      return const Center(
          child: Text('Sin resultados', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      itemCount: _resultadosMat.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final m = _resultadosMat[i];
        final actual = _carritoMat[m.id]?.cant ?? 0;
        return _MaterialRow(
          material: m,
          cantidad: actual,
          onChange: (n) {
            setState(() {
              if (n <= 0) {
                _carritoMat.remove(m.id);
              } else {
                _carritoMat[m.id] = (mat: m, cant: n);
              }
            });
          },
        );
      },
    );
  }

  Widget _modoChip(String label, int value) {
    final sel = _modo == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _modo = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? _kGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? _kGreen : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                  color: sel ? Colors.white : Colors.grey.shade700,
                  fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _claseChip(String label, String value) {
    final sel = _claseFiltro == value;
    return GestureDetector(
      onTap: () { setState(() => _claseFiltro = value); _load(); },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? _kGreen : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _kGreen : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : Colors.grey.shade700,
                fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }
}

class _EquipoRow extends StatelessWidget {
  final EquipoCatalogo equipo;
  final int cantidad;
  final ValueChanged<int> onChange;

  const _EquipoRow({
    required this.equipo,
    required this.cantidad,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final isHerr = equipo.clase == 'herramienta';
    final color = isHerr ? _kAmber : _kBlue;
    final disponible = equipo.cantidadDisponible;
    final sinStock = disponible <= 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: sinStock
                ? Colors.grey.shade300
                : color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.15 : 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
              isHerr
                  ? Icons.handyman_outlined
                  : Icons.precision_manufacturing_outlined,
              color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(equipo.nombre,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Row(children: [
              Text(isHerr ? 'Herramienta' : 'Equipo',
                  style: TextStyle(fontSize: 10, color: color,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('Disp: $disponible/${equipo.cantidadTotal}',
                  style: TextStyle(
                      fontSize: 10,
                      color: sinStock ? _kRed : Colors.grey,
                      fontWeight: sinStock ? FontWeight.w600 : FontWeight.normal)),
              if (equipo.almacenNombre != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text('· ${equipo.almacenNombre}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ),
              ],
            ]),
            // Desglose préstamo / compra cuando se pide más de lo disponible.
            if (cantidad > disponible) ...[
              const SizedBox(height: 3),
              Text(
                  disponible > 0
                      ? '$disponible en préstamo · ${cantidad - disponible} a compra'
                      : '${cantidad - disponible} a compra (sin stock)',
                  style: const TextStyle(
                      fontSize: 10,
                      color: _kAmber,
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        // Sin tope al stock: el excedente se solicita a compra a Logística.
        _Stepper(
          value: cantidad,
          max: 9999,
          onChanged: onChange,
        ),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  const _Stepper({required this.value, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _btn(Icons.remove, value > 0, () => onChanged(value - 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text('$value',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ),
      _btn(Icons.add, value < max, () => onChanged(value + 1)),
    ]);
  }

  Widget _btn(IconData icon, bool enabled, VoidCallback onTap) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            border: Border.all(
                color: enabled ? Colors.grey.shade400 : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14,
              color: enabled ? null : Colors.grey.shade400),
        ),
      );
}

// ─── Sheet: Devolver préstamo ─────────────────────────────────────────────────

class _DevolverSheet extends StatefulWidget {
  final Prestamo prestamo;
  final PrestamoService service;
  const _DevolverSheet({required this.prestamo, required this.service});

  @override
  State<_DevolverSheet> createState() => _DevolverSheetState();
}

class _DevolverSheetState extends State<_DevolverSheet> {
  late final Map<String, int> _devueltas; // item_id → cantidad devuelta (default: entregada)
  final _obsCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _devueltas = {
      for (final it in widget.prestamo.items)
        it.id: (it.cantidadEntregada ?? it.cantidadSolicitada),
    };
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() => _sending = true);
    final items = widget.prestamo.items.map((it) {
      return {
        'item_id': it.id,
        'cantidad_devuelta': _devueltas[it.id] ?? 0,
      };
    }).toList();
    final res = await widget.service.devolver(
      widget.prestamo.id,
      items: items,
      observacion: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error ?? 'Error al registrar la devolución'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          children: [
            Center(
              child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _kPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.assignment_return_outlined,
                    color: _kPurple, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Devolver Préstamo',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  Text('Indica cuántas unidades devuelves de cada equipo',
                      style: TextStyle(color: Colors.grey, fontSize: 11.5)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            ...widget.prestamo.items.map((it) => _itemBox(it)),
            const SizedBox(height: 12),
            TextField(
              controller: _obsCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Observación (motivo de faltantes, daños, etc.)',
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _sending ? null : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _sending
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Registrar devolución',
                        style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemBox(PrestamoItem it) {
    final entregada = it.cantidadEntregada ?? it.cantidadSolicitada;
    final devuelta = _devueltas[it.id] ?? entregada;
    final perdida = entregada - devuelta;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(it.equipoNombre,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Text('Entregadas: $entregada',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Text('Devuelves:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const Spacer(),
          _Stepper(
            value: devuelta,
            max: entregada,
            onChanged: (n) => setState(() => _devueltas[it.id] = n),
          ),
        ]),
        if (perdida > 0) ...[
          const SizedBox(height: 6),
          Text('Faltante: $perdida unidad${perdida == 1 ? '' : 'es'}',
              style: const TextStyle(
                  color: _kRed, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

// ─── Spinner pequeño para botones ─────────────────────────────────────────────

class _BtnSpinner extends StatelessWidget {
  const _BtnSpinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
}

// ─── Fila de material del catálogo (modo Materiales del sheet) ────────────────

class _MaterialRow extends StatelessWidget {
  final MaterialBusqueda material;
  final int cantidad;
  final ValueChanged<int> onChange;

  const _MaterialRow({
    required this.material,
    required this.cantidad,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final sinStock = material.stock <= 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGreen.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: isDark ? 0.15 : 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.inventory_2_outlined, color: _kGreen, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(material.nombre,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Text('Stock: ${material.stock} ${material.unidad}',
                style: TextStyle(
                    fontSize: 10,
                    color: sinStock ? _kAmber : Colors.grey,
                    fontWeight: sinStock ? FontWeight.w600 : FontWeight.normal)),
          ]),
        ),
        const SizedBox(width: 8),
        // Sin tope por stock: se puede solicitar más (compra a Logística).
        _Stepper(value: cantidad, max: 99999, onChanged: onChange),
      ]),
    );
  }
}

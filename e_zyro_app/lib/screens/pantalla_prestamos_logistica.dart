import 'package:flutter/material.dart';
import '../models/prestamo_models.dart';
import '../services/prestamo_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';
import '../widgets/firma_sheet.dart';
import 'pantalla_prestamos_servicio.dart' show PrestamoCard;

const _kGreen  = Color(0xFF8FD11B);
const _kRed    = Color(0xFFEF4444);
const _kAmber  = Color(0xFFF59E0B);
const _kPurple = Color(0xFF8B5CF6);
const _kBlue   = Color(0xFF3B82F6);

/// Bandeja del encargado de logística para gestionar préstamos:
/// entregar (cuando un técnico solicita) y confirmar devoluciones.
class PantallaPrestamosLogistica extends StatefulWidget {
  const PantallaPrestamosLogistica({super.key});

  @override
  State<PantallaPrestamosLogistica> createState() =>
      _PantallaPrestamosLogisticaState();
}

class _PantallaPrestamosLogisticaState extends State<PantallaPrestamosLogistica>
    with SingleTickerProviderStateMixin {
  PrestamoService? _service;
  List<Prestamo> _items = [];
  bool _loading = true;
  String _filtro = 'solicitado'; // solicitado | devuelto | confirmado | rechazado | todos

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getPrestamoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _loading = true);
    final data = await _service!.getPrestamos(estado: _filtro);
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  void _setFiltro(String f) {
    setState(() => _filtro = f);
    _load();
  }

  Future<void> _entregar(Prestamo p) async {
    // Firma de logística como ENTREGADOR. El préstamo queda 'por_recibir':
    // el equipo técnico debe firmar la recepción para completar la doble firma.
    final firma = await FirmaSheet.mostrar(
      context,
      titulo: 'Firma de entrega (logística)',
      subtitulo:
          'Despachas ${p.items.length} equipo(s)/herramienta(s) a ${p.solicitanteNombre}',
      textoBoton: 'Confirmar despacho',
    );
    if (firma == null || firma.isEmpty || !mounted) return;

    final res = await _service!.entregar(p.id, firmaEntregadorUrl: firma);
    if (!mounted) return;
    _msg(res.ok, 'Despachado · espera la firma de recepción del equipo',
        res.error ?? 'No se pudo entregar');
    if (res.ok) await _load();
  }

  Future<void> _rechazar(Prestamo p) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar préstamo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Indica el motivo del rechazo:',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Motivo...',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rechazar', style: TextStyle(color: _kRed))),
        ],
      ),
    );
    if (ok != true) return;
    final motivo = ctrl.text.trim();
    if (motivo.isEmpty) return;
    final res = await _service!.rechazar(p.id, observacion: motivo);
    if (!mounted) return;
    _msg(res.ok, 'Préstamo rechazado', res.error ?? 'No se pudo rechazar');
    if (res.ok) await _load();
  }

  Future<void> _confirmar(Prestamo p) async {
    final perdidasTotales =
        p.items.fold<int>(0, (a, it) => a + it.cantidadPerdida);
    final ctrl = TextEditingController();
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar devolución'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solicitante: ${p.solicitanteNombre}',
                style: const TextStyle(fontSize: 12)),
            if (perdidasTotales > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kRed.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: _kRed, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$perdidasTotales unidad${perdidasTotales == 1 ? '' : 'es'} faltante${perdidasTotales == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: _kRed,
                            fontWeight: FontWeight.w600),
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
                hintText: 'Observación (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Observar', style: TextStyle(color: _kAmber))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Confirmar', style: TextStyle(color: _kGreen))),
        ],
      ),
    );
    if (aceptar == null) return;
    final res = await _service!.confirmarDevolucion(
      p.id,
      aceptar: aceptar,
      observacion: ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
    );
    if (!mounted) return;
    _msg(
      res.ok,
      aceptar ? 'Devolución confirmada' : 'Devolución observada',
      res.error ?? 'No se pudo procesar',
    );
    if (res.ok) await _load();
  }

  void _msg(bool ok, String okMsg, String errMsg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? okMsg : errMsg),
      backgroundColor: ok ? _kGreen : _kRed,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Bandeja de Préstamos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _load),
        ],
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16, amp: 9, stroke: 0.38, speed: 0.45,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _Chip(label: 'Solicitados', value: 'solicitado',
                      sel: _filtro, color: _kAmber, onTap: _setFiltro),
                  _Chip(label: 'Por recibir', value: 'por_recibir',
                      sel: _filtro, color: _kBlue, onTap: _setFiltro),
                  _Chip(label: 'Por confirmar', value: 'devuelto',
                      sel: _filtro, color: _kPurple, onTap: _setFiltro),
                  _Chip(label: 'Entregados', value: 'entregado',
                      sel: _filtro, color: _kBlue, onTap: _setFiltro),
                  _Chip(label: 'Confirmados', value: 'confirmado',
                      sel: _filtro, color: _kGreen, onTap: _setFiltro),
                  _Chip(label: 'Rechazados', value: 'rechazado',
                      sel: _filtro, color: _kRed, onTap: _setFiltro),
                  _Chip(label: 'Todos', value: 'todos',
                      sel: _filtro, color: _kGreen, onTap: _setFiltro),
                ]),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _kGreen))
                  : _items.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _kGreen,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final p = _items[i];
                              return PrestamoCard(
                                prestamo: p,
                                mostrarServicio: true,
                                onEntregar: p.estado == 'solicitado'
                                    ? () => _entregar(p)
                                    : null,
                                onRechazar: p.estado == 'solicitado'
                                    ? () => _rechazar(p)
                                    : null,
                                onConfirmar: p.estado == 'devuelto'
                                    ? () => _confirmar(p)
                                    : null,
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_rounded, size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          const Text('Sin préstamos en este estado',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey)),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final String sel;
  final Color color;
  final ValueChanged<String> onTap;
  const _Chip({
    required this.label,
    required this.value,
    required this.sel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSel = sel == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSel ? color : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSel ? color : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: isSel
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
      ),
    );
  }
}

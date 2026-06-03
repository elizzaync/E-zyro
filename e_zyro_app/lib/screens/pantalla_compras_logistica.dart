import 'dart:async';
import 'package:flutter/material.dart';
import '../models/compras_models.dart';
import '../services/compras_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kBlue = Color(0xFF3B82F6);
const _kPurple = Color(0xFF8B5CF6);

/// Gestión de tickets de compra (flujo Logística). Espejo móvil del módulo
/// de Compras del frontend web: pestañas por estado, KPIs, procesar compra
/// (modo unificado/por-ítem), ingreso al inventario, vinculación de ítems
/// nuevos y cancelación.
class PantallaComprasLogistica extends StatefulWidget {
  const PantallaComprasLogistica({super.key});

  @override
  State<PantallaComprasLogistica> createState() =>
      _PantallaComprasLogisticaState();
}

class _PantallaComprasLogisticaState extends State<PantallaComprasLogistica>
    with SingleTickerProviderStateMixin {
  ComprasService? _service;
  late TabController _tabController;

  static const _estados = ['pendiente', 'en_proceso', 'completado', 'cancelado'];

  List<TicketCompra> _tickets = [];
  List<Proveedor> _proveedores = [];
  ComprasResumen _kpis = const ComprasResumen();
  bool _isLoading = true;
  String _busqueda = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) _load();
      });
    _init();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  String get _estadoActual => _estados[_tabController.index];

  Future<void> _init() async {
    _service = await getComprasService();
    _proveedores = await _service!.getProveedores();
    await Future.wait([_loadResumen(), _load()]);
  }

  Future<void> _loadResumen() async {
    if (_service == null) return;
    final r = await _service!.getComprasResumen();
    if (mounted) setState(() => _kpis = r);
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final data = await _service!.getTicketsCompra(
      estado: _estadoActual,
      q: _busqueda,
    );
    if (!mounted) return;
    setState(() {
      _tickets = data;
      _isLoading = false;
    });
  }

  void _onSearch(String q) {
    _busqueda = q;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _msg(String texto, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Acciones ────────────────────────────────────────────────────────────────

  Future<void> _abrirProceso(TicketCompra t) async {
    // Cargar versión fresca con ítems completos.
    final fresco = await _service!.getTicketCompra(t.id) ?? t;
    if (!mounted) return;
    final cambio = await showModalBottomSheet<_ResultadoProceso>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProcesarSheet(
        ticket: fresco,
        proveedores: _proveedores,
        service: _service!,
      ),
    );
    if (cambio == null) return;
    await _loadResumen();
    await _load();
    if (cambio.completado && cambio.ticket != null) {
      // Tras completar: registrar ingreso / vincular ítems nuevos.
      await _flujoIngreso(cambio.ticket!);
    }
  }

  Future<void> _abrirCancelar(TicketCompra t) async {
    final motivo = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CancelarSheet(ticket: t),
    );
    if (motivo == null) return; // cerró sin confirmar
    final res = await _service!.cancelarCompra(t.id, motivo: motivo.isEmpty ? null : motivo);
    if (!mounted) return;
    if (res.ok) {
      _msg('Ticket cancelado', _kGreen);
      await _loadResumen();
      await _load();
    } else {
      _msg(res.errorMessage, _kRed);
    }
  }

  Future<void> _verDetalle(TicketCompra t) async {
    final fresco = await _service!.getTicketCompra(t.id) ?? t;
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetalleSheet(ticket: fresco),
    );
  }

  /// Flujo posterior a completar (o botón "Ingresar"): vincula ítems nuevos
  /// y, si no hay ninguno pendiente, asegura el registro del ingreso.
  Future<void> _flujoIngreso(TicketCompra ticket) async {
    final fresco = await _service!.getTicketCompra(ticket.id) ?? ticket;
    if (!mounted) return;

    final sinVincular = fresco.items.where((i) => i.sinVincular).toList();

    if (sinVincular.isNotEmpty) {
      // Cola de vinculación: un modal por cada ítem nuevo.
      for (final item in sinVincular) {
        if (!mounted) return;
        final ok = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          isDismissible: false,
          builder: (_) => _VincularSheet(
            ticketId: fresco.id,
            item: item,
            service: _service!,
          ),
        );
        if (ok != true) break; // el usuario omitió el resto
      }
      if (mounted) _msg('Ítems nuevos registrados en inventario', _kGreen);
    } else if (!fresco.ingresoRegistrado) {
      // No hay ítems nuevos pero el ingreso no se aplicó: forzarlo.
      final res = await _service!.registrarIngreso(
        fresco.id,
        items: fresco.items
            .where((i) => (i.cantidadComprada ?? 0) > 0)
            .map((i) => {'itemId': i.id, 'cantidad': i.cantidadComprada})
            .toList(),
      );
      if (mounted) {
        _msg(res.ok ? 'Materiales ingresados al inventario'
            : res.errorMessage, res.ok ? _kGreen : _kRed);
      }
    } else {
      if (mounted) _msg('Materiales ingresados al inventario', _kGreen);
    }
    await _loadResumen();
    await _load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Compras',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Tickets de compra y proveedores',
                style: TextStyle(
                    fontSize: 10.5, color: Colors.grey.shade500)),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: _kGreen,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _kGreen,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Pendientes'),
            Tab(text: 'En proceso'),
            Tab(text: 'Completados'),
            Tab(text: 'Cancelados'),
          ],
        ),
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16,
        amp: 9,
        stroke: 0.38,
        speed: 0.45,
        child: Column(
          children: [
            // KPIs
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _KpiCard(
                      valor: _kpis.pendiente,
                      label: 'Pendientes',
                      color: _kAmber),
                  const SizedBox(width: 10),
                  _KpiCard(
                      valor: _kpis.enProceso,
                      label: 'En proceso',
                      color: _kBlue),
                  const SizedBox(width: 10),
                  _KpiCard(
                      valor: _kpis.completado,
                      label: 'Completados',
                      color: _kGreen),
                ],
              ),
            ),
            // Búsqueda
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Buscar por código, proyecto, servicio, ítem…',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _kGreen))
                  : _tickets.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: () async {
                            await _loadResumen();
                            await _load();
                          },
                          color: _kGreen,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                            itemCount: _tickets.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _TicketCard(
                              ticket: _tickets[i],
                              onProcesar: () => _abrirProceso(_tickets[i]),
                              onCancelar: () => _abrirCancelar(_tickets[i]),
                              onIngresar: () => _flujoIngreso(_tickets[i]),
                              onDetalle: () => _verDetalle(_tickets[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined,
                size: 52, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            const Text('Sin tickets en esta categoría',
                style: TextStyle(
                    color: Colors.grey, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// Helpers de presentación
// ════════════════════════════════════════════════════════════════════════════

({Color color, String label}) _estadoCfg(String e) => switch (e) {
      'pendiente' => (color: _kAmber, label: 'Pendiente'),
      'en_proceso' => (color: _kBlue, label: 'En proceso'),
      'completado' => (color: _kGreen, label: 'Completado'),
      'cancelado' => (color: _kRed, label: 'Cancelado'),
      _ => (color: Colors.grey, label: e),
    };

({Color color, String label}) _tipoCfg(String t) => switch (t) {
      'equipo' => (color: _kGreen, label: 'EQP'),
      'herramienta' => (color: _kAmber, label: 'HRR'),
      _ => (color: _kBlue, label: 'MAT'),
    };

class _KpiCard extends StatelessWidget {
  final int valor;
  final String label;
  final Color color;
  const _KpiCard({required this.valor, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          children: [
            Text('$valor',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _TipoBadge extends StatelessWidget {
  final String tipo;
  const _TipoBadge({required this.tipo});

  @override
  Widget build(BuildContext context) {
    final cfg = _tipoCfg(tipo);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: cfg.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(cfg.label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w800, color: cfg.color)),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Card de un ticket
// ════════════════════════════════════════════════════════════════════════════

class _TicketCard extends StatelessWidget {
  final TicketCompra ticket;
  final VoidCallback onProcesar;
  final VoidCallback onCancelar;
  final VoidCallback onIngresar;
  final VoidCallback onDetalle;

  const _TicketCard({
    required this.ticket,
    required this.onProcesar,
    required this.onCancelar,
    required this.onIngresar,
    required this.onDetalle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final cfg = _estadoCfg(ticket.estado);
    final total = ticket.items.length;
    final hechos = ticket.itemsHechosCount;
    final progreso = total == 0 ? 0.0 : hechos / total;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: cfg.color, width: 4)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado: código + estado + total
            Row(
              children: [
                Text(ticket.codigo,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _kPurple)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cfg.color.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(cfg.label,
                      style: TextStyle(
                          color: cfg.color,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                if (ticket.totalReal != null)
                  Text('S/ ${ticket.totalReal!.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold))
                else if (ticket.totalEstimado != null)
                  Text('≈ S/ ${ticket.totalEstimado!.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 6),
            // Proyecto / servicio / solicitante
            Text(ticket.proyectoNombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Row(
              children: [
                if (ticket.servicioNombre != null) ...[
                  Flexible(
                    child: Text(ticket.servicioNombre!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                  const Text(' · ',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
                const Icon(Icons.person_outline, size: 11, color: Colors.grey),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(ticket.solicitanteNombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              ],
            ),
            // Proveedor unificado / canal (hint)
            if (ticket.modoUnificado == true && ticket.proveedorUnicoNombre != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Proveedor: ${ticket.proveedorUnicoNombre}',
                    style: const TextStyle(
                        fontSize: 11, color: _kBlue, fontWeight: FontWeight.w500)),
              )
            else if (ticket.canalUnico != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Canal: ${ticket.canalUnico}',
                    style: const TextStyle(
                        fontSize: 11, color: _kBlue, fontWeight: FontWeight.w500)),
              ),
            const SizedBox(height: 8),
            // Ítems (primeros 3)
            ...ticket.items.take(3).map((it) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      _TipoBadge(tipo: it.tipoItem),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(it.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                decoration: it.estadoItem == 'comprado'
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: it.estadoItem == 'comprado'
                                    ? Colors.grey
                                    : null)),
                      ),
                      Text('×${it.cantidad}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            if (total > 3)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Text('+${total - 3} más',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600)),
              ),
            // Progreso
            if (total > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progreso,
                        minHeight: 5,
                        backgroundColor: Colors.grey.withValues(alpha: 0.20),
                        valueColor: const AlwaysStoppedAnimation(_kGreen),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$hechos/$total',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ],
            const SizedBox(height: 10),
            // Acciones según estado
            _buildAcciones(),
          ],
        ),
      ),
    );
  }

  Widget _buildAcciones() {
    if (ticket.estado == 'pendiente' || ticket.estado == 'en_proceso') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onProcesar,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(ticket.estado == 'pendiente' ? 'Procesar' : 'Continuar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onCancelar,
            style: OutlinedButton.styleFrom(
              foregroundColor: _kRed,
              side: const BorderSide(color: _kRed),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cancelar'),
          ),
        ],
      );
    }
    if (ticket.estado == 'completado') {
      return Row(
        children: [
          if (!ticket.ingresoRegistrado) ...[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onIngresar,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Ingresar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onDetalle,
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Ver detalle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kGreen,
                side: BorderSide(color: _kGreen.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      );
    }
    // cancelado
    return const Align(
      alignment: Alignment.centerLeft,
      child: Text('Cancelado',
          style: TextStyle(color: _kRed, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Resultado del modal de proceso
// ════════════════════════════════════════════════════════════════════════════

class _ResultadoProceso {
  final bool completado;
  final TicketCompra? ticket;
  const _ResultadoProceso({required this.completado, this.ticket});
}

// ════════════════════════════════════════════════════════════════════════════
// Modal: Procesar compra
// ════════════════════════════════════════════════════════════════════════════

class _ItemForm {
  final String itemId;
  final String nombre;
  final int cantidad;
  final String unidad;
  final String tipoItem;
  int cantidadComprada;
  double? precioUnitario;
  bool modoCustom; // canal propio por ítem (modo por-ítem)
  String? proveedorId;
  String? proveedorNombre;
  String canalCustom;
  String factura;
  String nota;

  _ItemForm.fromItem(TicketCompraItem it)
      : itemId = it.id,
        nombre = it.nombre,
        cantidad = it.cantidad,
        unidad = it.unidad,
        tipoItem = it.tipoItem,
        cantidadComprada = it.cantidadComprada ?? it.cantidad,
        precioUnitario = it.precioUnitario,
        modoCustom = (it.canalPersonalizado ?? '').isNotEmpty,
        proveedorId = it.proveedorId,
        proveedorNombre = it.proveedorNombre,
        canalCustom = it.canalPersonalizado ?? '',
        factura = it.factura ?? '',
        nota = it.nota ?? '';
}

class _ProcesarSheet extends StatefulWidget {
  final TicketCompra ticket;
  final List<Proveedor> proveedores;
  final ComprasService service;

  const _ProcesarSheet({
    required this.ticket,
    required this.proveedores,
    required this.service,
  });

  @override
  State<_ProcesarSheet> createState() => _ProcesarSheetState();
}

class _ProcesarSheetState extends State<_ProcesarSheet> {
  late bool _modoUnificado;
  String? _proveedorUnicoId;
  String? _proveedorUnicoNombre;
  bool _canalUnicoCustom = false;
  final _canalUnicoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  late List<_ItemForm> _items;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    final t = widget.ticket;
    _modoUnificado = t.modoUnificado ?? true;
    _proveedorUnicoId = t.proveedorUnicoId;
    _proveedorUnicoNombre = t.proveedorUnicoNombre;
    _canalUnicoCustom = (t.canalUnico ?? '').isNotEmpty;
    _canalUnicoCtrl.text = t.canalUnico ?? '';
    _notaCtrl.text = t.nota ?? '';
    _items = t.items.map((it) => _ItemForm.fromItem(it)).toList();
  }

  @override
  void dispose() {
    _canalUnicoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  int get _itemsIngresados =>
      _items.where((f) => f.cantidadComprada > 0).length;

  double get _totalEstimado => _items.fold(
      0.0, (s, f) => s + f.cantidadComprada * (f.precioUnitario ?? 0));

  bool get _puedeCompletar {
    if (_modoUnificado) {
      if (!_canalUnicoCustom && _proveedorUnicoId == null) return false;
      if (_canalUnicoCustom && _canalUnicoCtrl.text.trim().isEmpty) return false;
    }
    return _itemsIngresados > 0;
  }

  List<Map<String, dynamic>> _buildItems() {
    return _items.map((f) {
      return {
        'itemId': f.itemId,
        'cantidadComprada': f.cantidadComprada,
        'precioUnitario': f.precioUnitario,
        'proveedorId': _modoUnificado
            ? (_canalUnicoCustom ? null : _proveedorUnicoId)
            : (f.modoCustom ? null : f.proveedorId),
        'proveedorNombre': _modoUnificado
            ? (_canalUnicoCustom ? null : _proveedorUnicoNombre)
            : (f.modoCustom ? null : f.proveedorNombre),
        'canalPersonalizado': _modoUnificado
            ? (_canalUnicoCustom ? _canalUnicoCtrl.text.trim() : null)
            : (f.modoCustom ? f.canalCustom.trim() : null),
        'factura': f.factura.trim().isEmpty ? null : f.factura.trim(),
        'nota': f.nota.trim().isEmpty ? null : f.nota.trim(),
      };
    }).toList();
  }

  Future<void> _enviar({required bool completado}) async {
    if (completado && !_puedeCompletar) return;
    setState(() => _enviando = true);
    final res = await widget.service.procesarCompra(
      widget.ticket.id,
      modoUnificado: _modoUnificado,
      proveedorUnicoId:
          _modoUnificado && !_canalUnicoCustom ? _proveedorUnicoId : null,
      proveedorUnicoNombre:
          _modoUnificado && !_canalUnicoCustom ? _proveedorUnicoNombre : null,
      canalUnico: _modoUnificado && _canalUnicoCustom
          ? _canalUnicoCtrl.text.trim()
          : null,
      nota: _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
      completado: completado,
      items: _buildItems(),
    );
    if (!mounted) return;
    setState(() => _enviando = false);
    if (res.ok) {
      Navigator.pop(context,
          _ResultadoProceso(completado: completado, ticket: res.data));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.errorMessage),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Registrar compra',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.ticket.codigo} · ${widget.ticket.proyectoNombre}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Toggle de modo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _modoBtn('Un proveedor', true),
                  const SizedBox(width: 8),
                  _modoBtn('Por ítem', false),
                ],
              ),
            ),
            // Proveedor unificado
            if (_modoUnificado)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _buildProveedorUnico(fill),
              ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            // Lista de ítems
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _buildItemCard(_items[i], i, fill),
              ),
            ),
            // Footer
            _buildFooter(fill),
          ],
        ),
      ),
    );
  }

  Widget _modoBtn(String label, bool value) {
    final sel = _modoUnificado == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _modoUnificado = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? _kPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? _kPurple : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                  color: sel ? Colors.white : Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5)),
        ),
      ),
    );
  }

  Widget _buildProveedorUnico(Color fill) {
    if (_canalUnicoCustom) {
      return Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            onPressed: () => setState(() => _canalUnicoCustom = false),
          ),
          Expanded(
            child: TextField(
              controller: _canalUnicoCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Ej: Mercado libre, ferretería local…',
                filled: true,
                fillColor: fill,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final p in widget.proveedores)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      if (_proveedorUnicoId == p.id) {
                        _proveedorUnicoId = null;
                        _proveedorUnicoNombre = null;
                      } else {
                        _proveedorUnicoId = p.id;
                        _proveedorUnicoNombre = p.nombre;
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _proveedorUnicoId == p.id
                            ? _kBlue
                            : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _proveedorUnicoId == p.id
                                ? _kBlue
                                : Colors.grey.shade300),
                      ),
                      child: Text(p.nombre,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _proveedorUnicoId == p.id
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() {
            _canalUnicoCustom = true;
            _proveedorUnicoId = null;
            _proveedorUnicoNombre = null;
          }),
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Otro canal de compra',
              style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
              foregroundColor: _kPurple,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 28)),
        ),
      ],
    );
  }

  Widget _buildItemCard(_ItemForm f, int idx, Color fill) {
    final hecho = f.cantidadComprada > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hecho ? _kGreen.withValues(alpha: 0.06) : fill.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: hecho
                ? _kGreen.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TipoBadge(tipo: f.tipoItem),
              const SizedBox(width: 6),
              Expanded(
                child: Text(f.nombre,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text('Pedido: ${f.cantidad} ${f.unidad}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _numField(
                  label: 'Comprando',
                  initial: f.cantidadComprada == 0 ? '' : '${f.cantidadComprada}',
                  onChanged: (v) =>
                      setState(() => f.cantidadComprada = int.tryParse(v) ?? 0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _numField(
                  label: 'S/ Unitario',
                  decimal: true,
                  initial: f.precioUnitario == null ? '' : '${f.precioUnitario}',
                  onChanged: (v) =>
                      setState(() => f.precioUnitario = double.tryParse(v)),
                ),
              ),
            ],
          ),
          // Proveedor / canal por ítem (modo por-ítem)
          if (!_modoUnificado) ...[
            const SizedBox(height: 8),
            if (!f.modoCustom)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: f.proveedorId,
                      isExpanded: true,
                      decoration: _fieldDeco('Proveedor', fill),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— Sin asignar —')),
                        ...widget.proveedores.map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.nombre,
                                overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => setState(() {
                        f.proveedorId = v;
                        f.proveedorNombre = widget.proveedores
                            .where((p) => p.id == v)
                            .map((p) => p.nombre)
                            .firstOrNull;
                      }),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Usar canal propio',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => setState(() {
                      f.modoCustom = true;
                      f.proveedorId = null;
                      f.proveedorNombre = null;
                    }),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: f.canalCustom),
                      onChanged: (v) => f.canalCustom = v,
                      decoration: _fieldDeco('Canal / medio', fill),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: () =>
                        setState(() => f.modoCustom = false),
                  ),
                ],
              ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: f.factura),
                  onChanged: (v) => f.factura = v,
                  decoration: _fieldDeco('Factura / ref.', fill),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: f.nota),
                  onChanged: (v) => f.nota = v,
                  decoration: _fieldDeco('Nota', fill),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numField({
    required String label,
    required String initial,
    required ValueChanged<String> onChanged,
    bool decimal = false,
  }) {
    return TextField(
      controller: TextEditingController(text: initial),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      onChanged: onChanged,
      decoration: _fieldDeco(label,
          Theme.of(context).colorScheme.surfaceContainerHighest),
    );
  }

  InputDecoration _fieldDeco(String label, Color fill) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: fill,
        labelStyle: const TextStyle(fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      );

  Widget _buildFooter(Color fill) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('$_itemsIngresados/${_items.length} ítems',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Spacer(),
              if (_totalEstimado > 0)
                Text('Total: S/ ${_totalEstimado.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notaCtrl,
            decoration: InputDecoration(
              hintText: 'Nota interna del ticket (opcional)…',
              isDense: true,
              filled: true,
              fillColor: fill,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (_enviando || _itemsIngresados == 0)
                      ? null
                      : () => _enviar(completado: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kPurple,
                    side: BorderSide(color: _kPurple.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Guardar progreso'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: (_enviando || !_puedeCompletar)
                      ? null
                      : () => _enviar(completado: true),
                  icon: _enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Completar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Modal: Vincular ítem nuevo a inventario
// ════════════════════════════════════════════════════════════════════════════

class _VincularSheet extends StatefulWidget {
  final String ticketId;
  final TicketCompraItem item;
  final ComprasService service;

  const _VincularSheet({
    required this.ticketId,
    required this.item,
    required this.service,
  });

  @override
  State<_VincularSheet> createState() => _VincularSheetState();
}

class _VincularSheetState extends State<_VincularSheet> {
  late final TextEditingController _nombre;
  final _descripcion = TextEditingController();
  // material
  String _unidad = 'Unidades';
  final _stockMin = TextEditingController(text: '0');
  final _precio = TextEditingController();
  // equipo / herramienta
  final _marca = TextEditingController();
  final _modelo = TextEditingController();
  final _serie = TextEditingController();
  bool _enviando = false;

  bool get _esMaterial => widget.item.tipoItem == 'material';

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.item.nombre);
    _unidad = widget.item.unidad.isEmpty ? 'Unidades' : widget.item.unidad;
    if (widget.item.precioUnitario != null) {
      _precio.text = '${widget.item.precioUnitario}';
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _stockMin.dispose();
    _precio.dispose();
    _marca.dispose();
    _modelo.dispose();
    _serie.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_nombre.text.trim().isEmpty) return;
    setState(() => _enviando = true);
    final body = <String, dynamic>{
      'nombre': _nombre.text.trim(),
      'descripcion':
          _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
      'precioUnitario': double.tryParse(_precio.text.trim()),
    };
    if (_esMaterial) {
      body['unidad'] = _unidad;
      body['stockMinimo'] = int.tryParse(_stockMin.text.trim()) ?? 0;
    } else {
      body['marca'] = _marca.text.trim().isEmpty ? null : _marca.text.trim();
      body['modelo'] = _modelo.text.trim().isEmpty ? null : _modelo.text.trim();
      body['numeroSerie'] = _serie.text.trim().isEmpty ? null : _serie.text.trim();
    }
    final res = await widget.service.vincularInventario(
        widget.ticketId, widget.item.id, body);
    if (!mounted) return;
    setState(() => _enviando = false);
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.errorMessage),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    final cfg = _tipoCfg(widget.item.tipoItem);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cfg.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.add_box_outlined, color: cfg.color, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Nuevo ítem en inventario',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                'Este ${_esMaterial ? 'material' : widget.item.tipoItem} no existe en el inventario. Completa los datos para registrarlo.',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            _campo('Nombre *', _nombre, fill),
            const SizedBox(height: 10),
            if (_esMaterial) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unidad,
                      decoration: _deco('Unidad *', fill),
                      items: const [
                        'Unidades', 'Metros', 'Kilogramos', 'Litros',
                        'Cajas', 'Rollos', 'Juego'
                      ].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                      onChanged: (v) => setState(() => _unidad = v ?? 'Unidades'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _campo('Stock mínimo', _stockMin, fill,
                        keyboard: TextInputType.number),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _campo('Precio unitario (S/)', _precio, fill,
                  keyboard: const TextInputType.numberWithOptions(decimal: true)),
            ] else ...[
              Row(
                children: [
                  Expanded(child: _campo('Marca', _marca, fill)),
                  const SizedBox(width: 10),
                  Expanded(child: _campo('Modelo', _modelo, fill)),
                ],
              ),
              const SizedBox(height: 10),
              _campo('N° de serie', _serie, fill),
              const SizedBox(height: 10),
              _campo('Precio unitario (S/)', _precio, fill,
                  keyboard: const TextInputType.numberWithOptions(decimal: true)),
            ],
            const SizedBox(height: 10),
            _campo('Descripción / Notas', _descripcion, fill, maxLines: 2),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _enviando ? null : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Omitir'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_enviando || _nombre.text.trim().isEmpty)
                        ? null
                        : _confirmar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Registrar en inventario'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(String label, TextEditingController ctrl, Color fill,
      {int maxLines = 1, TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      onChanged: (_) => setState(() {}),
      decoration: _deco(label, fill),
    );
  }

  InputDecoration _deco(String label, Color fill) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// Modal: Cancelar ticket
// ════════════════════════════════════════════════════════════════════════════

class _CancelarSheet extends StatefulWidget {
  final TicketCompra ticket;
  const _CancelarSheet({required this.ticket});

  @override
  State<_CancelarSheet> createState() => _CancelarSheetState();
}

class _CancelarSheetState extends State<_CancelarSheet> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const Text('Cancelar ticket',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('${widget.ticket.codigo} · ${widget.ticket.proyectoNombre}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 14),
          TextField(
            controller: _motivo,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Motivo (opcional)',
              hintText: 'Ej: Compra ya no requerida…',
              filled: true,
              fillColor: fill,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    side: BorderSide(color: Colors.grey.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Volver'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _motivo.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirmar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Modal: Detalle (read-only)
// ════════════════════════════════════════════════════════════════════════════

class _DetalleSheet extends StatelessWidget {
  final TicketCompra ticket;
  const _DetalleSheet({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Detalle de compra',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('${ticket.codigo} · ${ticket.proyectoNombre}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (ticket.modoUnificado == true)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Proveedor único: ${ticket.proveedorUnicoNombre ?? ticket.canalUnico ?? '—'}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: _kBlue),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                itemCount: ticket.items.length,
                separatorBuilder: (_, _) => const Divider(height: 16),
                itemBuilder: (_, i) {
                  final it = ticket.items[i];
                  final totalItem =
                      (it.cantidadComprada != null && it.precioUnitario != null)
                          ? it.cantidadComprada! * it.precioUnitario!
                          : null;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _TipoBadge(tipo: it.tipoItem),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(it.nombre,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          if (it.estadoItem == 'comprado')
                            const Icon(Icons.check_circle,
                                size: 16, color: _kGreen),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 14,
                        runSpacing: 2,
                        children: [
                          _kv('Pedido', '${it.cantidad} ${it.unidad}'),
                          _kv('Comprado', '${it.cantidadComprada ?? '—'}'),
                          _kv(
                              'S/ Unit.',
                              it.precioUnitario != null
                                  ? it.precioUnitario!.toStringAsFixed(2)
                                  : '—'),
                          _kv(
                              'Total',
                              totalItem != null
                                  ? 'S/ ${totalItem.toStringAsFixed(2)}'
                                  : '—'),
                          if (it.proveedorNombre != null ||
                              it.canalPersonalizado != null)
                            _kv('Proveedor',
                                it.proveedorNombre ?? it.canalPersonalizado!),
                          if (it.factura != null) _kv('Factura', it.factura!),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            // Total general
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 10, 20, MediaQuery.of(context).padding.bottom + 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                    top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('S/ ${ticket.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11.5, color: Colors.grey),
          children: [
            TextSpan(text: '$k: '),
            TextSpan(
                text: v,
                style: TextStyle(
                    color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

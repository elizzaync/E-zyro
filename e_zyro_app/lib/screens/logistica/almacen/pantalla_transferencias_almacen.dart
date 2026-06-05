// pantalla_transferencias_almacen.dart — Transferencias entre almacenes mejoradas.
// Cualquier ítem (material/equipo/herramienta) se puede mover de un almacén a
// otro. Flujo: elegir DESDE/HACIA → se carga lo que hay en el origen → se arma
// una lista (carrito) de 1 o varios ítems con cantidad → transferir en lote.

import 'package:flutter/material.dart';
import '../../../models/requerimiento_models.dart';
import '../../../services/requerimiento_service.dart';
import '../../../utils/api_provider.dart';
import 'es_tokens.dart';
import 'es_widgets.dart';

class _Linea {
  final ContenidoAlmacen item;
  int cantidad;
  _Linea(this.item, this.cantidad);
}

class PantallaTransferenciasAlmacen extends StatefulWidget {
  const PantallaTransferenciasAlmacen({super.key});

  @override
  State<PantallaTransferenciasAlmacen> createState() =>
      _PantallaTransferenciasAlmacenState();
}

class _PantallaTransferenciasAlmacenState
    extends State<PantallaTransferenciasAlmacen> {
  RequerimientoService? _service;
  List<AlmacenItem> _almacenes = [];
  bool _loading = true;

  String? _origenId;
  String? _destinoId;

  List<ContenidoAlmacen> _contenido = [];
  bool _cargandoContenido = false;
  String _query = '';

  // Carrito: clave 'fuente:id' → línea.
  final Map<String, _Linea> _carrito = {};
  bool _transfiriendo = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getRequerimientoService();
    final alm = await _service!.getAlmacenes();
    if (!mounted) return;
    // Origen por defecto: el predeterminado (Oficina). Destino: el otro.
    AlmacenItem? pred;
    for (final a in alm) {
      if (a.predeterminado) {
        pred = a;
        break;
      }
    }
    final origen = pred ?? (alm.isNotEmpty ? alm.first : null);
    AlmacenItem? destino;
    for (final a in alm) {
      if (a.id != origen?.id) {
        destino = a;
        break;
      }
    }
    setState(() {
      _almacenes = alm;
      _origenId = origen?.id;
      _destinoId = destino?.id;
      _loading = false;
    });
    if (_origenId != null) _cargarContenido();
  }

  Future<void> _cargarContenido() async {
    if (_origenId == null) return;
    setState(() {
      _cargandoContenido = true;
      _contenido = [];
      _carrito.clear();
    });
    final data = await _service!.getContenidoAlmacen(_origenId!);
    if (!mounted) return;
    setState(() {
      _contenido = data;
      _cargandoContenido = false;
    });
  }

  void _swap() {
    setState(() {
      final t = _origenId;
      _origenId = _destinoId;
      _destinoId = t;
    });
    _cargarContenido();
  }

  String _key(ContenidoAlmacen c) => '${c.fuente}:${c.id}';

  void _agregar(ContenidoAlmacen c) {
    final k = _key(c);
    setState(() {
      final l = _carrito[k];
      if (l == null) {
        _carrito[k] = _Linea(c, 1);
      } else if (l.cantidad < c.disponible) {
        l.cantidad++;
      }
    });
  }

  void _setCantidad(String k, int v) {
    setState(() {
      final l = _carrito[k];
      if (l == null) return;
      if (v <= 0) {
        _carrito.remove(k);
      } else {
        l.cantidad = v.clamp(1, l.item.disponible);
      }
    });
  }

  int get _totalUnidades => _carrito.values.fold(0, (a, l) => a + l.cantidad);

  void _msg(bool ok, String okMsg, String errMsg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? okMsg : errMsg),
      backgroundColor: ok ? ESC.brand : ESC.vencido,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _transferir() async {
    if (_origenId == null || _destinoId == null) return;
    if (_origenId == _destinoId) return _msg(false, '', 'Origen y destino deben ser distintos');
    if (_carrito.isEmpty) return _msg(false, '', 'Agrega al menos un ítem');

    setState(() => _transfiriendo = true);
    final items = _carrito.values
        .map((l) => {'fuente': l.item.fuente, 'id': l.item.id, 'cantidad': l.cantidad})
        .toList();
    final res = await _service!.transferirLote(
      almacenOrigenId: _origenId!,
      almacenDestinoId: _destinoId!,
      items: items,
    );
    if (!mounted) return;
    setState(() => _transfiriendo = false);
    if (res.ok) {
      if (mounted) Navigator.maybePop(context); // cierra el sheet del carrito si está abierto
      _msg(true, 'Transferencia registrada (${_carrito.length} ítem(s))', '');
      await _cargarContenido();
    } else {
      _msg(false, '', res.error ?? 'No se pudo transferir');
    }
  }

  String _nombreAlmacen(String? id) {
    for (final a in _almacenes) {
      if (a.id == id) return a.nombre;
    }
    return '—';
  }

  List<ContenidoAlmacen> get _filtrado {
    if (_query.trim().isEmpty) return _contenido;
    final q = _query.toLowerCase();
    return _contenido
        .where((c) => c.nombre.toLowerCase().contains(q) ||
            (c.codigo ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ESC.bg,
      body: Column(children: [
        ESPanelBar(
          title: 'Transferencias',
          subtitle: 'Mover material o equipos entre almacenes',
          trailing: ESBarIcon(Icons.refresh_rounded, onTap: _cargarContenido),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: ESC.brand))
              : _almacenes.length < 2
                  ? _sinAlmacenes()
                  : _cuerpo(),
        ),
      ]),
      bottomNavigationBar: _loading || _almacenes.length < 2 ? null : _barraCarrito(),
    );
  }

  Widget _cuerpo() {
    final items = _filtrado;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // ── Selector Desde / Hacia ──────────────────────────────────────────
      ESCard(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          _dropAlmacen('Desde', _origenId, (v) {
            setState(() => _origenId = v);
            _cargarContenido();
          }),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Expanded(child: Divider()),
              GestureDetector(
                onTap: _swap,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: ESC.brand, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.swap_vert_rounded, color: Colors.white, size: 20),
                ),
              ),
              const Expanded(child: Divider()),
            ]),
          ),
          _dropAlmacen('Hacia', _destinoId, (v) => setState(() => _destinoId = v)),
        ]),
      ),
      const SizedBox(height: 12),

      // ── Buscador ────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: ESC.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ESC.line),
        ),
        child: Row(children: [
          Icon(ESIcons.search, size: 19, color: ESC.inkFaint),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Buscar en ${_nombreAlmacen(_origenId)}…',
                hintStyle: pj(size: 13.5, color: ESC.inkFaint),
              ),
              style: pj(size: 14),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),

      ESSectionLabel('Disponible · ${items.length} ítem(s)'),
      const SizedBox(height: 10),

      if (_cargandoContenido)
        const Padding(padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator(color: ESC.brand)))
      else if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 30),
          child: Center(child: Text('Este almacén no tiene ítems disponibles',
              style: pj(size: 13.5, color: ESC.inkSub))),
        )
      else
        for (final c in items) ...[
          _itemDisponible(c),
          const SizedBox(height: 10),
        ],
      const SizedBox(height: 80), // espacio para la barra del carrito
    ]);
  }

  Widget _dropAlmacen(String label, String? value, ValueChanged<String?> onChanged) {
    return Row(children: [
      SizedBox(
        width: 54,
        child: Text(label, style: pj(size: 12.5, weight: FontWeight.w700, color: ESC.inkFaint)),
      ),
      Expanded(
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            hint: Text('Selecciona…', style: pj(size: 14, color: ESC.inkFaint)),
            items: _almacenes
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Row(children: [
                        Flexible(child: Text(a.nombre, overflow: TextOverflow.ellipsis,
                            style: pj(size: 14, weight: FontWeight.w600))),
                        if (a.predeterminado) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: ESC.matBg, borderRadius: BorderRadius.circular(5)),
                            child: Text('Predet.', style: pj(size: 9.5, weight: FontWeight.w700, color: ESC.brandDeep)),
                          ),
                        ],
                      ]),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    ]);
  }

  Widget _itemDisponible(ContenidoAlmacen c) {
    final enCarrito = _carrito[_key(c)];
    final esEquipo = c.fuente == 'equipo';
    final accent = esEquipo ? ESC.equip : ESC.brand;
    return GestureDetector(
      onTap: () => _agregar(c),
      child: ESCard(
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: esEquipo ? ESC.equipBg : ESC.matBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(esEquipo ? ESIcons.wrench : ESIcons.box,
                size: 19, color: esEquipo ? ESC.equip : ESC.brandDeep),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(c.nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: pj(size: 14, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${c.codigo != null ? '${c.codigo} · ' : ''}Disp: ${c.disponible} ${c.unidad}',
                  style: pj(size: 11.5, color: ESC.inkFaint)),
            ]),
          ),
          const SizedBox(width: 8),
          if (enCarrito != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: esTint(accent, 0.14), borderRadius: BorderRadius.circular(8)),
              child: Text('×${enCarrito.cantidad}', style: pj(size: 12.5, weight: FontWeight.w800, color: accent)),
            )
          else
            Icon(Icons.add_circle, color: accent, size: 26),
        ]),
      ),
    );
  }

  // ── Barra inferior con resumen del carrito ────────────────────────────────
  Widget _barraCarrito() {
    final vacio = _carrito.isEmpty;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
            color: ESC.surface, border: Border(top: BorderSide(color: ESC.line))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: ESC.matBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.local_shipping_outlined, color: ESC.brandDeep, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(vacio ? 'Sin ítems seleccionados' : '${_carrito.length} ítem(s) · $_totalUnidades unidad(es)',
                  style: pj(size: 13.5, weight: FontWeight.w800)),
              Text('${_nombreAlmacen(_origenId)} → ${_nombreAlmacen(_destinoId)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: pj(size: 11, color: ESC.inkFaint)),
            ]),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: vacio ? null : _abrirCarrito,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: vacio ? ESC.line : ESC.brand,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('Revisar', style: pj(size: 14, weight: FontWeight.w800,
                  color: vacio ? ESC.inkFaint : Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Hoja del carrito: la lista destacada de ítems a transferir ────────────
  void _abrirCarrito() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void refresh() => setSheet(() => setState(() {}));
          return Container(
            decoration: const BoxDecoration(
              color: ESC.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 10),
                Container(width: 40, height: 4, decoration: BoxDecoration(
                    color: ESC.lineStrong, borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Row(children: [
                    Icon(Icons.local_shipping_outlined, color: ESC.brandDeep, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('Ítems a transferir', style: pj(size: 16, weight: FontWeight.w800)),
                        Text('${_nombreAlmacen(_origenId)}  →  ${_nombreAlmacen(_destinoId)}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: pj(size: 12, color: ESC.inkSub)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(color: ESC.matBg, borderRadius: BorderRadius.circular(999)),
                      child: Text('${_carrito.length}', style: pj(size: 13, weight: FontWeight.w800, color: ESC.brandDeep)),
                    ),
                  ]),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    children: [
                      for (final entry in _carrito.entries.toList())
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _lineaCarrito(entry.key, entry.value, refresh),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: _transfiriendo
                      ? const SizedBox(height: 52, child: Center(child: CircularProgressIndicator(color: ESC.brand)))
                      : ESButton('Transferir ${_carrito.length} ítem(s) · $_totalUnidades u',
                          icon: ESIcons.check, expand: true, onTap: _transferir),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _lineaCarrito(String k, _Linea l, VoidCallback refresh) {
    final esEquipo = l.item.fuente == 'equipo';
    final accent = esEquipo ? ESC.equip : ESC.brand;
    return ESCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              color: esEquipo ? ESC.equipBg : ESC.matBg, borderRadius: BorderRadius.circular(9)),
          child: Icon(esEquipo ? ESIcons.wrench : ESIcons.box,
              size: 17, color: esEquipo ? ESC.equip : ESC.brandDeep),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(l.item.nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: pj(size: 13.5, weight: FontWeight.w700)),
            Text('Disp: ${l.item.disponible} ${l.item.unidad}',
                style: pj(size: 11, color: ESC.inkFaint)),
          ]),
        ),
        const SizedBox(width: 8),
        // Stepper de cantidad
        _stepBtn(Icons.remove_rounded, () { _setCantidad(k, l.cantidad - 1); refresh(); }),
        Container(
          constraints: const BoxConstraints(minWidth: 34),
          alignment: Alignment.center,
          child: Text('${l.cantidad}', style: pj(size: 15, weight: FontWeight.w800, color: accent)),
        ),
        _stepBtn(Icons.add_rounded, () { _setCantidad(k, l.cantidad + 1); refresh(); }),
      ]),
    );
  }

  Widget _stepBtn(IconData ic, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: ESC.surfaceAlt, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ESC.line)),
          child: Icon(ic, size: 17, color: ESC.ink),
        ),
      );

  Widget _sinAlmacenes() => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.warehouse_outlined, size: 48, color: ESC.inkFaint),
          const SizedBox(height: 14),
          Text('Se necesitan al menos 2 almacenes',
              style: pj(size: 15, weight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text('Las transferencias mueven ítems entre dos almacenes distintos.',
              style: pj(size: 12.5, color: ESC.inkSub), textAlign: TextAlign.center),
        ]),
      );
}

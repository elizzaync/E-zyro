import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../models/epp_models.dart';
import '../models/proyecto_models.dart';
import '../services/epp_service.dart';
import '../utils/api_provider.dart';

/// Wizard de entrega de EPP: receptor + ítems (con stock) + firma → registra y
/// genera la constancia. El backend descuenta stock y crea la constancia PDF.
class PantallaEppEntrega extends StatefulWidget {
  const PantallaEppEntrega({super.key});

  @override
  State<PantallaEppEntrega> createState() => _PantallaEppEntregaState();
}

class _ItemSel {
  final Epp epp;
  int cantidad;
  _ItemSel(this.epp, this.cantidad);
}

class _PantallaEppEntregaState extends State<PantallaEppEntrega> {
  EppService? _svc;
  final _firma = SignatureController(penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white);
  final _obsCtrl = TextEditingController();

  List<TecnicoDisponible> _tecnicos = [];
  List<Epp> _catalogo = [];
  final List<_ItemSel> _items = [];
  String? _receptorId;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _firma.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getEppService();
    final proy = await getProyectoService();
    final personal = await proy.getPersonalTecnicos();
    final cat = await _svc!.listar();
    if (!mounted) return;
    setState(() {
      _tecnicos = personal.tecnicos;
      _catalogo = cat.ok ? (cat.data ?? []) : [];
      _cargando = false;
    });
  }

  Future<void> _agregarItem() async {
    if (_catalogo.isEmpty) {
      _snack('No hay EPP en el catálogo', error: true);
      return;
    }
    Epp sel = _catalogo.first;
    final cantCtrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Agregar ítem'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Epp>(
                initialValue: sel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'EPP'),
                items: _catalogo
                    .map((e) => DropdownMenuItem(value: e, child: Text('${e.nombre} (stock ${e.stockActual})', overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setLocal(() => sel = v ?? sel),
              ),
              TextField(controller: cantCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final cant = int.tryParse(cantCtrl.text) ?? 0;
    if (cant <= 0) {
      _snack('Cantidad inválida', error: true);
      return;
    }
    if (cant > sel.stockActual) {
      _snack('Stock insuficiente de ${sel.nombre} (hay ${sel.stockActual})', error: true);
      return;
    }
    setState(() => _items.add(_ItemSel(sel, cant)));
  }

  Future<void> _guardar() async {
    if (_receptorId == null) {
      _snack('Selecciona el receptor', error: true);
      return;
    }
    if (_items.isEmpty) {
      _snack('Agrega al menos un ítem', error: true);
      return;
    }
    String? firmaB64;
    if (_firma.isNotEmpty) {
      final bytes = await _firma.toPngBytes();
      if (bytes != null) firmaB64 = base64Encode(bytes);
    }
    setState(() => _guardando = true);
    final res = await _svc!.crearEntrega(
      empleadoId: _receptorId!,
      items: _items.map((i) => {'epp_id': i.epp.id, 'cantidad': i.cantidad}).toList(),
      firmaBase64: firmaB64,
      observacion: _obsCtrl.text,
    );
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _guardando = false);
      _snack(res.errorMessage, error: true);
      return;
    }
    // Generar constancia (no bloqueante para el éxito de la entrega)
    final entregaId = res.data!.id;
    await _svc!.generarConstancia(entregaId);
    if (!mounted) return;
    setState(() => _guardando = false);
    _snack('Entrega registrada y constancia generada');
    Navigator.pop(context, true);
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva entrega de EPP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _receptorId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Receptor', border: OutlineInputBorder()),
                  items: _tecnicos
                      .map((t) => DropdownMenuItem(value: t.id, child: Text('${t.nombre} ${t.apellido}', overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => _receptorId = v),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ítems', style: TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(onPressed: _agregarItem, icon: const Icon(Icons.add), label: const Text('Agregar')),
                  ],
                ),
                if (_items.isEmpty) const Text('Sin ítems agregados.', style: TextStyle(color: Colors.grey)),
                ..._items.asMap().entries.map((e) => ListTile(
                      dense: true,
                      title: Text(e.value.epp.nombre),
                      subtitle: Text('Cantidad: ${e.value.cantidad}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => setState(() => _items.removeAt(e.key)),
                      ),
                    )),
                const SizedBox(height: 16),
                TextField(
                  controller: _obsCtrl,
                  decoration: const InputDecoration(labelText: 'Observación (opcional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                const Text('Firma del receptor', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                  child: Signature(controller: _firma, height: 180, backgroundColor: const Color(0xFFF2F2F2)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _firma.clear(),
                    icon: const Icon(Icons.clear),
                    label: const Text('Limpiar firma'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(_guardando ? 'Registrando...' : 'Registrar entrega'),
                ),
              ],
            ),
    );
  }
}

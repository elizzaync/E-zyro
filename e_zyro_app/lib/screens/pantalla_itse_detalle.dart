import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/itse_models.dart';
import '../services/itse_service.dart';
import '../utils/api_provider.dart';
import '../utils/abrir_enlace.dart';
import 'pantalla_galeria.dart';

/// Detalle de una inspección ITSE: tableros + ítems (hallazgos) + fotos + finalizar.
class PantallaItseDetalle extends StatefulWidget {
  final String inspeccionId;
  final String modo;   // tablero | zona
  final String estado; // borrador | en_proceso | finalizada | anulada
  const PantallaItseDetalle({
    super.key,
    required this.inspeccionId,
    required this.modo,
    required this.estado,
  });

  @override
  State<PantallaItseDetalle> createState() => _PantallaItseDetalleState();
}

class _PantallaItseDetalleState extends State<PantallaItseDetalle> {
  ItseService? _svc;
  final _picker = ImagePicker();
  List<InspeccionTablero> _tableros = [];
  List<InspeccionItem> _items = [];
  late String _estado;
  bool _cargando = true;
  bool _trabajando = false;

  bool get _esTablero => widget.modo == 'tablero';
  bool get _finalizada => _estado == 'finalizada';

  @override
  void initState() {
    super.initState();
    _estado = widget.estado;
    _init();
  }

  Future<void> _init() async {
    _svc = await getItseService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() => _cargando = true);
    final tabs = _esTablero ? await _svc!.listarTableros(widget.inspeccionId) : null;
    final its = await _svc!.listarItems(widget.inspeccionId);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (tabs != null && tabs.ok) _tableros = tabs.data ?? [];
      if (its.ok) _items = its.data ?? [];
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  // ── Tableros ──
  Future<void> _addTablero() async {
    final n = TextEditingController();
    final a = TextEditingController();
    final d = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo tablero'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'Nombre')),
          TextField(controller: a, decoration: const InputDecoration(labelText: 'Ambiente')),
          TextField(controller: d, decoration: const InputDecoration(labelText: 'Descripción')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
        ],
      ),
    );
    if (ok != true || n.text.trim().isEmpty) return;
    final res = await _svc!.crearTablero(widget.inspeccionId, n.text.trim(), a.text, d.text);
    if (!mounted) return;
    res.ok ? _cargar() : _snack(res.errorMessage, error: true);
  }

  Future<void> _delTablero(InspeccionTablero t) async {
    final res = await _svc!.eliminarTablero(t.id);
    if (!mounted) return;
    res.ok ? _cargar() : _snack(res.errorMessage, error: true);
  }

  // ── Ítems ──
  Future<void> _addItem() async {
    final desc = TextEditingController();
    final obs = TextEditingController();
    String resultado = 'conforme';
    String? tableroId = _tableros.isNotEmpty ? _tableros.first.id : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nuevo hallazgo'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción')),
            DropdownButtonFormField<String>(
              initialValue: resultado,
              decoration: const InputDecoration(labelText: 'Resultado'),
              items: const [
                DropdownMenuItem(value: 'conforme', child: Text('Conforme')),
                DropdownMenuItem(value: 'observado', child: Text('Observado')),
                DropdownMenuItem(value: 'no_conforme', child: Text('No conforme')),
              ],
              onChanged: (v) => setLocal(() => resultado = v ?? 'conforme'),
            ),
            if (_esTablero && _tableros.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: tableroId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tablero'),
                items: _tableros.map((t) => DropdownMenuItem(value: t.id, child: Text(t.nombre, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setLocal(() => tableroId = v),
              ),
            TextField(controller: obs, decoration: const InputDecoration(labelText: 'Observación')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    if (ok != true || desc.text.trim().isEmpty) return;
    final res = await _svc!.crearItem(widget.inspeccionId, desc.text.trim(), resultado, obs.text, _esTablero ? tableroId : null);
    if (!mounted) return;
    res.ok ? _cargar() : _snack(res.errorMessage, error: true);
  }

  Future<void> _delItem(InspeccionItem it) async {
    final res = await _svc!.eliminarItem(it.id);
    if (!mounted) return;
    res.ok ? _cargar() : _snack(res.errorMessage, error: true);
  }

  // ── Fotos ──
  Future<void> _addFoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de galería'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null) return;
    final x = await _picker.pickImage(source: src, imageQuality: 75, maxWidth: 1920);
    if (x == null) return;
    final b64 = base64Encode(await x.readAsBytes());
    if (!mounted) return;
    setState(() => _trabajando = true);
    final res = await _svc!.subirFoto(widget.inspeccionId, b64);
    if (!mounted) return;
    setState(() => _trabajando = false);
    _snack(res.ok ? 'Foto subida' : res.errorMessage, error: !res.ok);
  }

  // ── Finalizar / informe ──
  Future<void> _finalizar() async {
    setState(() => _trabajando = true);
    final res = await _svc!.finalizar(widget.inspeccionId);
    if (!mounted) return;
    setState(() => _trabajando = false);
    if (res.ok) {
      setState(() => _estado = res.data?.estado ?? 'finalizada');
      _snack('Inspección finalizada · informe generado');
      await abrirEnlace(res.data?.pdfUrl);
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  Future<void> _generarInforme() async {
    final res = await _svc!.generarInforme(widget.inspeccionId);
    if (!mounted) return;
    if (res.ok) {
      _snack('Informe generado');
      await abrirEnlace(res.data);
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inspección ${widget.modo}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.photo_library_outlined), tooltip: 'Ver fotos',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PantallaGaleria(entidadTipo: 'itse', entidadId: widget.inspeccionId, titulo: 'Fotos ITSE')))),
          IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Generar informe', onPressed: _generarInforme),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(children: [
                  Chip(label: Text('Estado: $_estado')),
                  const SizedBox(width: 8),
                  if (_trabajando) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
                const SizedBox(height: 8),
                if (_esTablero) ...[
                  _seccion('Tableros (${_tableros.length})', _finalizada ? null : _addTablero),
                  ..._tableros.map((t) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.dashboard_outlined),
                        title: Text(t.nombre),
                        subtitle: Text([t.ambiente, t.descripcion].where((x) => (x ?? '').isNotEmpty).join(' · ')),
                        trailing: _finalizada ? null : IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _delTablero(t)),
                      )),
                  const Divider(),
                ],
                _seccion('Hallazgos (${_items.length})', _finalizada ? null : _addItem),
                ..._items.map((it) => ListTile(
                      dense: true,
                      leading: Icon(_iconoResultado(it.resultado), color: _colorResultado(it.resultado)),
                      title: Text(it.descripcion),
                      subtitle: Text('${it.resultado}${(it.observacion ?? '').isEmpty ? '' : ' · ${it.observacion}'}'),
                      trailing: _finalizada ? null : IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _delItem(it)),
                    )),
                const Divider(),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _finalizada ? null : _addFoto, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Agregar foto'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(
                    onPressed: (_finalizada || _trabajando) ? null : _finalizar,
                    icon: const Icon(Icons.task_alt),
                    label: Text(_finalizada ? 'Finalizada' : 'Finalizar'))),
                ]),
              ],
            ),
    );
  }

  Widget _seccion(String titulo, VoidCallback? onAdd) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (onAdd != null) TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Agregar')),
        ],
      );

  IconData _iconoResultado(String r) => switch (r) {
        'no_conforme' => Icons.cancel_outlined,
        'observado' => Icons.warning_amber_outlined,
        _ => Icons.check_circle_outline,
      };

  Color _colorResultado(String r) => switch (r) {
        'no_conforme' => Colors.red,
        'observado' => Colors.orange,
        _ => Colors.green,
      };
}

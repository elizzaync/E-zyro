import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../models/documento_sst_models.dart';
import '../models/proyecto_models.dart' show ClienteBasico;
import '../services/documento_sst_service.dart';
import '../utils/app_session.dart';

/// Repositorio de documentos de cumplimiento / SST: homologaciones, ATS, PETAR.
/// Almacena, organiza (por cliente + tipo) y controla vencimientos.
class PantallaDocumentosSst extends StatefulWidget {
  const PantallaDocumentosSst({super.key});

  @override
  State<PantallaDocumentosSst> createState() => _PantallaDocumentosSstState();
}

class _PantallaDocumentosSstState extends State<PantallaDocumentosSst> {
  static const _green = Color(0xFF8FD11B);

  DocumentoSstService? _svc;
  List<DocumentoSst> _items = [];
  List<ClienteBasico> _clientes = [];
  bool _cargando = true;

  String _filtroTipo = '';      // '' = todos
  String _filtroCliente = '';   // '' = todos
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = DocumentoSstService(ApiClient(prefs));
    _clientes = await _svc!.getClientes();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() => _cargando = true);
    final items = await _svc!.getDocumentos(
      tipo: _filtroTipo,
      clienteId: _filtroCliente,
      q: _busqueda,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _cargando = false;
    });
  }

  // ── Estado visual ───────────────────────────────────────────────────────────
  ({Color color, String label}) _estadoUi(DocumentoSst d) {
    switch (d.estado) {
      case 'vencida':
        return (color: const Color(0xFFD6584F), label: 'Vencida');
      case 'por_vencer':
        return (
          color: const Color(0xFFD98A16),
          label: d.diasParaVencer != null ? 'Vence en ${d.diasParaVencer}d' : 'Por vencer'
        );
      case 'vigente':
        return (color: _green, label: 'Vigente');
      default:
        return (color: Colors.grey, label: 'Sin fecha');
    }
  }

  Future<void> _abrir(DocumentoSst d) async {
    if (!d.tieneArchivo) {
      _snack('Este documento no tiene archivo adjunto.', Colors.grey);
      return;
    }
    final ok = await launchUrl(Uri.parse(d.archivoUrl!),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('No se pudo abrir el archivo.', Colors.red);
  }

  Future<void> _eliminar(DocumentoSst d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar documento'),
        content: Text('¿Eliminar «${d.titulo}»? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final exito = await _svc!.eliminar(d.id);
    if (!mounted) return;
    if (exito) {
      _snack('Documento eliminado', _green);
      _cargar();
    } else {
      _snack('No se pudo eliminar', Colors.red);
    }
  }

  Future<void> _abrirFormulario([DocumentoSst? doc]) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormDocumento(svc: _svc!, clientes: _clientes, doc: doc),
    );
    if (guardado == true) _cargar();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final puedeCrear = AppSession.i.canCrearDocumentosSst;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documentos SST',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: puedeCrear
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              backgroundColor: _green,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.upload_file),
              label: const Text('Nuevo'),
            )
          : null,
      body: Column(
        children: [
          _buscador(),
          _filtrosTipo(),
          if (_clientes.isNotEmpty) _filtroClienteWidget(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _items.isEmpty
                    ? _vacio()
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        color: _green,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _card(_items[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buscador() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Buscar por título, código o entidad…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            _busqueda = v;
            _cargar();
          },
        ),
      );

  Widget _filtrosTipo() {
    final tipos = ['', ...kTiposDocumentoSst.keys];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tipos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tipos[i];
          final sel = _filtroTipo == t;
          return ChoiceChip(
            label: Text(t.isEmpty ? 'Todos' : kTiposDocumentoSst[t]!),
            selected: sel,
            selectedColor: _green.withValues(alpha: 0.25),
            onSelected: (_) {
              setState(() => _filtroTipo = t);
              _cargar();
            },
          );
        },
      ),
    );
  }

  Widget _filtroClienteWidget() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: DropdownButtonFormField<String>(
          initialValue: _filtroCliente,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Cliente',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Todos los clientes')),
            ..._clientes.map((c) =>
                DropdownMenuItem(value: c.id, child: Text(c.razonSocial))),
          ],
          onChanged: (v) {
            setState(() => _filtroCliente = v ?? '');
            _cargar();
          },
        ),
      );

  Widget _card(DocumentoSst d) {
    final est = _estadoUi(d);
    final puedeEditar = AppSession.i.canEditarDocumentosSst;
    final puedeEliminar = AppSession.i.canEliminarDocumentosSst;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: () => _abrir(d),
        leading: CircleAvatar(
          backgroundColor: est.color.withValues(alpha: 0.15),
          child: Icon(
            d.tieneArchivo ? Icons.description_outlined : Icons.note_outlined,
            color: est.color,
          ),
        ),
        title: Text(d.titulo,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _chip(kTiposDocumentoSst[d.tipo] ?? d.tipo, _green),
              _chip(est.label, est.color),
              if (d.fechaVencimiento != null)
                Text('Vence: ${d.fechaVencimiento}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            if ((d.clienteNombre ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(d.clienteNombre!,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ],
        ),
        trailing: (puedeEditar || puedeEliminar)
            ? PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'editar') _abrirFormulario(d);
                  if (v == 'eliminar') _eliminar(d);
                },
                itemBuilder: (_) => [
                  if (puedeEditar)
                    const PopupMenuItem(value: 'editar', child: Text('Editar')),
                  if (puedeEliminar)
                    const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                ],
              )
            : null,
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _vacio() => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.folder_open_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Center(
            child: Text('Sin documentos',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey)),
          ),
        ],
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Formulario de alta / edición
// ══════════════════════════════════════════════════════════════════════════════
class _FormDocumento extends StatefulWidget {
  final DocumentoSstService svc;
  final List<ClienteBasico> clientes;
  final DocumentoSst? doc;
  const _FormDocumento({required this.svc, required this.clientes, this.doc});

  @override
  State<_FormDocumento> createState() => _FormDocumentoState();
}

class _FormDocumentoState extends State<_FormDocumento> {
  static const _green = Color(0xFF8FD11B);

  late String _tipo;
  late final TextEditingController _titulo;
  late final TextEditingController _entidad;
  late final TextEditingController _codigo;
  late final TextEditingController _obs;
  String? _clienteId;
  DateTime? _fechaEmision;
  DateTime? _fechaVencimiento;

  String? _archivoBase64;
  String? _archivoNombre;
  bool _guardando = false;

  bool get _esEdicion => widget.doc != null;

  @override
  void initState() {
    super.initState();
    final d = widget.doc;
    _tipo = d?.tipo ?? 'homologacion';
    _titulo = TextEditingController(text: d?.titulo ?? '');
    _entidad = TextEditingController(text: d?.entidadEmisora ?? '');
    _codigo = TextEditingController(text: d?.codigo ?? '');
    _obs = TextEditingController(text: d?.observaciones ?? '');
    _clienteId = d?.clienteId;
    _fechaEmision = _parse(d?.fechaEmision);
    _fechaVencimiento = _parse(d?.fechaVencimiento);
    if (_esEdicion) _archivoNombre = d?.nombreArchivo;
  }

  DateTime? _parse(String? s) => (s == null) ? null : DateTime.tryParse(s);
  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  void dispose() {
    _titulo.dispose();
    _entidad.dispose();
    _codigo.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _pickArchivo() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    if (f.bytes == null) return;
    setState(() {
      _archivoBase64 = base64Encode(f.bytes!);
      _archivoNombre = f.name;
    });
  }

  Future<void> _pickFecha(bool emision) async {
    final base = (emision ? _fechaEmision : _fechaVencimiento) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (emision) {
        _fechaEmision = d;
      } else {
        _fechaVencimiento = d;
      }
    });
  }

  Future<void> _guardar() async {
    if (_titulo.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El título es obligatorio'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _guardando = true);
    final fe = _fechaEmision != null ? _iso(_fechaEmision!) : null;
    final fv = _fechaVencimiento != null ? _iso(_fechaVencimiento!) : null;
    bool ok;
    if (_esEdicion) {
      ok = await widget.svc.editar(
        widget.doc!.id,
        titulo: _titulo.text.trim(),
        tipo: _tipo,
        clienteId: _clienteId ?? '',
        entidadEmisora: _entidad.text.trim(),
        codigo: _codigo.text.trim(),
        fechaEmision: fe,
        fechaVencimiento: fv,
        observaciones: _obs.text.trim(),
        archivoBase64: _archivoBase64,
        archivoNombre: _archivoBase64 != null ? _archivoNombre : null,
      );
    } else {
      ok = await widget.svc.crear(
        titulo: _titulo.text.trim(),
        tipo: _tipo,
        clienteId: _clienteId,
        entidadEmisora: _entidad.text.trim(),
        codigo: _codigo.text.trim(),
        fechaEmision: fe,
        fechaVencimiento: fv,
        observaciones: _obs.text.trim(),
        archivoBase64: _archivoBase64,
        archivoNombre: _archivoNombre,
      );
    }
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo guardar el documento'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: BoxDecoration(
          color: surface, borderRadius: BorderRadius.circular(18)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(_esEdicion ? 'Editar documento' : 'Nuevo documento',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
                items: kTiposDocumentoSst.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _tipo = v ?? 'homologacion'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titulo,
                decoration: const InputDecoration(labelText: 'Título *', isDense: true),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _clienteId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cliente', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Sin cliente —')),
                  ...widget.clientes.map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.razonSocial))),
                ],
                onChanged: (v) => setState(() => _clienteId = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _entidad,
                decoration: const InputDecoration(
                    labelText: 'Entidad emisora', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _codigo,
                decoration: const InputDecoration(labelText: 'Código', isDense: true),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _fechaBtn('Emisión', _fechaEmision, () => _pickFecha(true))),
                const SizedBox(width: 10),
                Expanded(child: _fechaBtn('Vencimiento', _fechaVencimiento, () => _pickFecha(false))),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _obs,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Observaciones', isDense: true),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickArchivo,
                icon: const Icon(Icons.attach_file),
                label: Text(_archivoNombre ?? 'Adjuntar archivo (PDF/imagen)',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _green, foregroundColor: Colors.white),
                  child: _guardando
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_esEdicion ? 'Guardar cambios' : 'Crear documento'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fechaBtn(String label, DateTime? value, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(value != null ? _iso(value) : '—',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

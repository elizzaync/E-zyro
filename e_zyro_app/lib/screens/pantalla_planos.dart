import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/planos_models.dart';
import '../services/planos_service.dart';
import '../utils/abrir_enlace.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import '../widgets/topo_background.dart';

/// Navegador de planos tipo Drive (carpetas recursivas + planos versionados).
class PantallaPlanos extends StatefulWidget {
  const PantallaPlanos({super.key});
  @override
  State<PantallaPlanos> createState() => _PantallaPlanosState();
}

class _PantallaPlanosState extends State<PantallaPlanos> {
  static const _green = Color(0xFF8FD11B);
  static const _exts = ['pdf', 'dwg', 'dxf', 'dwf', 'jpg', 'jpeg', 'png', 'webp'];
  static const _disciplinas = [
    'Eléctrica', 'Civil', 'Mecánica', 'Arquitectura', 'Sanitaria', 'Datos/TI', 'Otros'
  ];

  PlanosService? _svc;
  final List<Carpeta> _stack = []; // breadcrumb; vacío = raíz
  List<Carpeta> _carpetas = [];
  List<PlanoItem> _planos = [];
  bool _loading = true;
  bool _puedeGestionar = false;

  Carpeta? get _actual => _stack.isEmpty ? null : _stack.last;

  @override
  void initState() {
    super.initState();
    _puedeGestionar = AppSession.i.canGestionarPlanos;
    _init();
  }

  Future<void> _init() async {
    _svc = await getPlanosService();
    await _load();
  }

  Future<void> _load() async {
    if (_svc == null) return;
    setState(() => _loading = true);
    final res = await Future.wait([
      _svc!.carpetas(padreId: _actual?.id),
      _svc!.planos(carpetaId: _actual?.id),
    ]);
    if (!mounted) return;
    setState(() {
      _carpetas = res[0] as List<Carpeta>;
      _planos = res[1] as List<PlanoItem>;
      _loading = false;
    });
  }

  void _entrar(Carpeta c) {
    setState(() => _stack.add(c));
    _load();
  }

  void _irNivel(int index) {
    // index -1 = raíz
    setState(() => _stack.removeRange(index + 1, _stack.length));
    _load();
  }

  void _volver() {
    if (_stack.isEmpty) return;
    setState(() => _stack.removeLast());
    _load();
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? Colors.red.shade700 : _green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Acciones ────────────────────────────────────────────────────────────────
  Future<void> _nuevaCarpeta() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva carpeta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre de la carpeta'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final r = await _svc!.crearCarpeta(ctrl.text.trim(), padreId: _actual?.id);
    if (r.ok) {
      _snack('Carpeta creada');
      _load();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _renombrarCarpeta(Carpeta c) async {
    final ctrl = TextEditingController(text: c.nombre);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar carpeta'),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final r = await _svc!.renombrarCarpeta(c.id, ctrl.text.trim());
    r.ok ? _load() : _snack(r.errorMessage, error: true);
  }

  Future<void> _eliminarCarpeta(Carpeta c) async {
    final ok = await _confirm('Eliminar carpeta',
        '¿Eliminar "${c.nombre}"? Debe estar vacía.');
    if (!ok) return;
    final r = await _svc!.eliminarCarpeta(c.id);
    if (r.ok) {
      _snack('Carpeta eliminada');
      _load();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _subirPlano() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _exts,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      _snack('No se pudo leer el archivo', error: true);
      return;
    }
    if (bytes.length > 30 * 1024 * 1024) {
      _snack('El archivo supera 30 MB', error: true);
      return;
    }
    if (!mounted) return;

    final nombreCtrl = TextEditingController(text: _sinExt(f.name));
    String disciplina = _disciplinas.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setL) => AlertDialog(
          title: const Text('Subir plano'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(_iconExt(f.extension), color: _green),
              const SizedBox(width: 8),
              Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre del plano')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: disciplina,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Disciplina'),
              items: _disciplinas.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (v) => setL(() => disciplina = v ?? disciplina),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Subir')),
          ],
        ),
      ),
    );
    if (ok != true || nombreCtrl.text.trim().isEmpty) return;

    _snack('Subiendo plano...');
    final r = await _svc!.crearPlano(
      nombre: nombreCtrl.text.trim(),
      archivoBase64: base64Encode(bytes),
      filename: f.name,
      disciplina: disciplina,
      carpetaId: _actual?.id,
    );
    if (r.ok) {
      _snack('Plano subido');
      _load();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _nuevaVersion(PlanoItem p) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: _exts, withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    if (f.bytes == null) return;
    if (f.bytes!.length > 30 * 1024 * 1024) {
      _snack('El archivo supera 30 MB', error: true);
      return;
    }
    _snack('Subiendo versión...');
    final r = await _svc!.subirVersion(p.id, base64Encode(f.bytes!), f.name);
    if (r.ok) {
      _snack('Versión subida');
      if (mounted) Navigator.pop(context);
      _load();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _eliminarPlano(PlanoItem p) async {
    final ok = await _confirm('Eliminar plano',
        '¿Eliminar "${p.nombre}" y todas sus versiones?');
    if (!ok) return;
    final r = await _svc!.eliminarPlano(p.id);
    if (r.ok) {
      if (mounted) Navigator.pop(context);
      _snack('Plano eliminado');
      _load();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<bool> _confirm(String titulo, String msg) async =>
      (await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      )) ??
      false;

  // ── Detalle de plano (bottom sheet) ───────────────────────────────────────
  Future<void> _verPlano(PlanoItem p) async {
    final det = await _svc!.detalle(p.id);
    if (!mounted) return;
    final plano = det.ok ? det.data! : p;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.92, minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) {
          final surface = Theme.of(context).colorScheme.surface;
          return Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(controller: ctrl, padding: const EdgeInsets.all(20), children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(color: _green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(_iconExt(plano.formato), color: _green, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(plano.nombre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  Text([
                    if ((plano.disciplina ?? '').isNotEmpty) plano.disciplina!,
                    if ((plano.versionActiva ?? '').isNotEmpty) plano.versionActiva!,
                    if ((plano.formato ?? '').isNotEmpty) plano.formato!.toUpperCase(),
                    if (plano.tamanoLegible.isNotEmpty) plano.tamanoLegible,
                  ].join(' · '), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ])),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: () async {
                    final abrio = await abrirEnlace(plano.url);
                    if (!abrio) _snack('Enlace copiado al portapapeles');
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir / Descargar'),
                ),
              ),
              if (_puedeGestionar) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => _nuevaVersion(plano),
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Nueva versión'),
                  )),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _eliminarPlano(plano),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Eliminar'),
                  ),
                ]),
              ],
              const SizedBox(height: 20),
              if (plano.versiones.isNotEmpty) ...[
                const Text('HISTORIAL DE VERSIONES',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: Colors.grey, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                ...plano.versiones.map((v) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_iconExt(v.formato),
                          color: v.esActiva ? _green : Colors.grey, size: 22),
                      title: Row(children: [
                        Text(v.version, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (v.esActiva) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(color: _green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10)),
                            child: const Text('Activa',
                                style: TextStyle(fontSize: 10, color: Color(0xFF1E9462), fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      subtitle: Text([
                        if ((v.fecha ?? '').isNotEmpty) v.fecha!,
                        if ((v.formato ?? '').isNotEmpty) v.formato!.toUpperCase(),
                      ].join(' · '), style: const TextStyle(fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new, size: 18),
                        onPressed: () => abrirEnlace(v.url),
                      ),
                    )),
              ],
            ]),
          );
        },
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: _stack.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _volver();
      },
      child: TopoBackground(
        c1: isDark ? const Color(0xFF1E9462) : const Color(0xFF1E9462),
        c2: isDark ? const Color(0xFF1E9462) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0E1611) : const Color(0xFFF5FAF0),
        count: 16, amp: 9, stroke: 0.36, speed: 0.4,
        child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Planos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, color: _green)),
          ],
        ),
        floatingActionButton: _puedeGestionar
            ? FloatingActionButton(
                backgroundColor: _green,
                onPressed: _menuCrear,
                child: const Icon(Icons.add),
              )
            : null,
        body: Column(
            children: [
              _breadcrumb(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _green))
                    : _contenido(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _breadcrumb() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _crumb('Inicio', -1, raiz: true),
          for (var i = 0; i < _stack.length; i++) _crumb(_stack[i].nombre, i),
        ],
      ),
    );
  }

  Widget _crumb(String label, int index, {bool raiz = false}) {
    final esUltimo = index == _stack.length - 1;
    return Row(children: [
      if (!raiz) const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      InkWell(
        onTap: esUltimo ? null : () => _irNivel(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            if (raiz) const Icon(Icons.home_outlined, size: 16, color: _green),
            if (raiz) const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: esUltimo ? FontWeight.w700 : FontWeight.w500,
                    color: esUltimo ? null : Colors.grey)),
          ]),
        ),
      ),
    ]);
  }

  Widget _contenido() {
    if (_carpetas.isEmpty && _planos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: _green,
        child: ListView(children: [
          const SizedBox(height: 120),
          Icon(Icons.folder_open_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(child: Text(
            _puedeGestionar ? 'Carpeta vacía.\nUsa + para crear carpetas o subir planos.'
                : 'Carpeta vacía.',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey),
          )),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _green,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
        children: [
          for (final c in _carpetas) _carpetaTile(c),
          for (final p in _planos) _planoTile(p),
        ],
      ),
    );
  }

  Widget _carpetaTile(Carpeta c) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.folder_rounded, color: Color(0xFFFFC107), size: 30),
        title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${c.totalElementos} elemento(s)',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        onTap: () => _entrar(c),
        trailing: _puedeGestionar
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) {
                  if (v == 'rename') _renombrarCarpeta(c);
                  if (v == 'delete') _eliminarCarpeta(c);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Row(children: [
                    Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text('Renombrar')])),
                  PopupMenuItem(value: 'delete', child: Row(children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 10), Text('Eliminar', style: TextStyle(color: Colors.red))])),
                ],
              )
            : const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }

  Widget _planoTile(PlanoItem p) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: _green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(_iconExt(p.formato), color: _green, size: 22),
        ),
        title: Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if ((p.disciplina ?? '').isNotEmpty) p.disciplina!,
          if ((p.versionActiva ?? '').isNotEmpty) p.versionActiva!,
          if ((p.formato ?? '').isNotEmpty) p.formato!.toUpperCase(),
          if (p.tamanoLegible.isNotEmpty) p.tamanoLegible,
        ].join(' · '), style: const TextStyle(fontSize: 11.5, color: Colors.grey),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: p.numVersiones > 1
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${p.numVersiones} ver.',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)))
            : null,
        onTap: () => _verPlano(p),
      ),
    );
  }

  Future<void> _menuCrear() async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined, color: _green),
            title: const Text('Nueva carpeta'),
            onTap: () => Navigator.pop(context, 'carpeta'),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined, color: _green),
            title: const Text('Subir plano'),
            subtitle: const Text('PDF, DWG, DXF o imagen', style: TextStyle(fontSize: 11)),
            onTap: () => Navigator.pop(context, 'plano'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (opcion == 'carpeta') _nuevaCarpeta();
    if (opcion == 'plano') _subirPlano();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  String _sinExt(String name) => name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

  IconData _iconExt(String? ext) {
    final e = (ext ?? '').toLowerCase();
    if (e == 'pdf') return Icons.picture_as_pdf_outlined;
    if (e == 'dwg' || e == 'dxf' || e == 'dwf') return Icons.architecture_outlined;
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(e)) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

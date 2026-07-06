import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/drive_models.dart';
import '../services/drive_service.dart';
import '../utils/abrir_enlace.dart';
import '../utils/api_provider.dart';

/// Drive de empresa: repositorio de archivos (cualquier tipo) en Cloudinary,
/// organizado en carpetas. Dos ámbitos: Compartido (toda la empresa) y
/// Mi espacio (personal). Abierto a todos los roles.
class PantallaDrive extends StatefulWidget {
  const PantallaDrive({super.key});

  @override
  State<PantallaDrive> createState() => _PantallaDriveState();
}

class _PantallaDriveState extends State<PantallaDrive> {
  static const _green = Color(0xFF8FD11B);

  DriveService? _svc;
  String _ambito = 'compartido';
  // Pila de navegación de carpetas (id, nombre). Vacía = raíz.
  final List<DriveCarpeta> _ruta = [];
  List<DriveCarpeta> _carpetas = [];
  List<DriveArchivo> _archivos = [];
  bool _cargando = true;
  String? _error;

  DriveCarpeta? get _actual => _ruta.isEmpty ? null : _ruta.last;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getDriveService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final cs = await _svc!.listarCarpetas(ambito: _ambito, padreId: _actual?.id);
    final fs = await _svc!.listarArchivos(ambito: _ambito, carpetaId: _actual?.id);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (cs.ok) {
        _carpetas = cs.data ?? [];
      } else {
        _error = cs.errorMessage;
      }
      if (fs.ok) _archivos = fs.data ?? [];
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : _green));
  }

  void _cambiarAmbito(String a) {
    if (_ambito == a) return;
    setState(() {
      _ambito = a;
      _ruta.clear();
    });
    _cargar();
  }

  void _entrar(DriveCarpeta c) {
    setState(() => _ruta.add(c));
    _cargar();
  }

  void _irHasta(int index) {
    // index -1 = raíz
    setState(() => _ruta.removeRange(index + 1, _ruta.length));
    _cargar();
  }

  // ── Acciones ──────────────────────────────────────────────────────────────
  Future<void> _nuevaCarpeta() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva carpeta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre de la carpeta'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final r = await _svc!.crearCarpeta(
        nombre: ctrl.text.trim(), ambito: _ambito, padreId: _actual?.id);
    if (r.ok) {
      _snack('Carpeta creada');
      _cargar();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _subirArchivo() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes;
    // bytes vacíos (no solo null): pasa con archivos "en la nube" no
    // descargados (OneDrive/Google Drive); el backend respondería 422.
    if (bytes == null || bytes.isEmpty) {
      _snack(
        'No se pudo leer el archivo. Si está en la nube (OneDrive/Drive), '
        'descárgalo al dispositivo e inténtalo de nuevo.',
        error: true,
      );
      return;
    }
    if (bytes.length > 30 * 1024 * 1024) {
      _snack('El archivo supera 30 MB', error: true);
      return;
    }
    if (!mounted) return;

    final nombreCtrl = TextEditingController(text: _sinExt(f.name));
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subir archivo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(_iconExt(f.extension), color: _green),
            const SizedBox(width: 8),
            Expanded(
                child: Text(f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
          const SizedBox(height: 12),
          TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Subir')),
        ],
      ),
    );
    if (ok != true || nombreCtrl.text.trim().isEmpty) return;

    _snack('Subiendo archivo...');
    final r = await _svc!.subirArchivo(
      nombre: nombreCtrl.text.trim(),
      filename: f.name,
      archivoBase64: base64Encode(bytes),
      ambito: _ambito,
      carpetaId: _actual?.id,
      descripcion: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
    );
    if (r.ok) {
      _snack('Archivo subido');
      _cargar();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _accionesArchivo(DriveArchivo a) async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(a.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new, color: _green),
            title: const Text('Abrir / descargar'),
            onTap: () => Navigator.pop(ctx, 'abrir'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Eliminar'),
            onTap: () => Navigator.pop(ctx, 'eliminar'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (accion == null || !mounted) return;
    if (accion == 'abrir') {
      final ok = await abrirEnlace(a.url);
      if (!ok) _snack('No se pudo abrir; enlace copiado al portapapeles');
    } else if (accion == 'eliminar') {
      await _eliminarArchivo(a);
    }
  }

  Future<void> _eliminarArchivo(DriveArchivo a) async {
    final ok = await _confirm('Eliminar archivo', '¿Eliminar "${a.nombre}"?');
    if (!ok) return;
    final r = await _svc!.eliminarArchivo(a.id);
    if (r.ok) {
      _snack('Archivo eliminado');
      _cargar();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _accionesCarpeta(DriveCarpeta c) async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline, color: _green),
            title: const Text('Renombrar'),
            onTap: () => Navigator.pop(ctx, 'renombrar'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Eliminar'),
            onTap: () => Navigator.pop(ctx, 'eliminar'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (accion == null || !mounted) return;
    if (accion == 'renombrar') {
      final ctrl = TextEditingController(text: c.nombre);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Renombrar carpeta'),
          content: TextField(controller: ctrl, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      );
      if (ok == true && ctrl.text.trim().isNotEmpty) {
        final r = await _svc!.renombrarCarpeta(c.id, ctrl.text.trim());
        _snack(r.ok ? 'Carpeta renombrada' : r.errorMessage, error: !r.ok);
        if (r.ok) _cargar();
      }
    } else if (accion == 'eliminar') {
      final ok = await _confirm('Eliminar carpeta',
          '¿Eliminar "${c.nombre}"? Debe estar vacía.');
      if (!ok) return;
      final r = await _svc!.eliminarCarpeta(c.id);
      _snack(r.ok ? 'Carpeta eliminada' : r.errorMessage, error: !r.ok);
      if (r.ok) _cargar();
    }
  }

  Future<bool> _confirm(String titulo, String mensaje) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(titulo),
            content: Text(mensaje),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Eliminar')),
            ],
          ),
        ) ??
        false;
  }

  // ── Helpers UI ──────────────────────────────────────────────────────────
  String _sinExt(String n) => n.contains('.') ? n.substring(0, n.lastIndexOf('.')) : n;

  IconData _iconExt(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':
        return Icons.image_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_outlined;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_outlined;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_outlined;
      case 'dwg':
      case 'dxf':
        return Icons.architecture_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive de empresa', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _subirArchivo,
        backgroundColor: _green,
        icon: const Icon(Icons.upload_file),
        label: const Text('Subir archivo'),
      ),
      body: Column(
        children: [
          // ── Toggle de ámbito ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'compartido', label: Text('Compartido'), icon: Icon(Icons.groups_outlined)),
                ButtonSegment(value: 'personal', label: Text('Mi espacio'), icon: Icon(Icons.lock_outline)),
              ],
              selected: {_ambito},
              onSelectionChanged: (s) => _cambiarAmbito(s.first),
            ),
          ),
          // ── Breadcrumb ────────────────────────────────────────────────
          _buildBreadcrumb(),
          const Divider(height: 1),
          Expanded(child: _buildContenido()),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _ruta.isEmpty ? null : () => _irHasta(-1),
            icon: const Icon(Icons.home_outlined, size: 18),
            label: const Text('Inicio'),
            style: TextButton.styleFrom(foregroundColor: _green),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _ruta.length,
              itemBuilder: (_, i) => Row(children: [
                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                TextButton(
                  onPressed: i == _ruta.length - 1 ? null : () => _irHasta(i),
                  child: Text(_ruta[i].nombre,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
          IconButton(
            tooltip: 'Nueva carpeta',
            onPressed: _nuevaCarpeta,
            icon: const Icon(Icons.create_new_folder_outlined, color: _green),
          ),
        ],
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: _green));
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
      );
    }
    if (_carpetas.isEmpty && _archivos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargar,
        color: _green,
        child: ListView(children: const [
          SizedBox(height: 120),
          Icon(Icons.folder_open_outlined, size: 56, color: Colors.black26),
          SizedBox(height: 12),
          Center(child: Text('Carpeta vacía', style: TextStyle(color: Colors.black54))),
          SizedBox(height: 4),
          Center(
              child: Text('Sube un archivo o crea una carpeta',
                  style: TextStyle(color: Colors.black38, fontSize: 13))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      color: _green,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          ..._carpetas.map((c) => ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFFFFC107)),
                title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${c.subCarpetas} carpeta(s) · ${c.archivos} archivo(s)'),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _accionesCarpeta(c),
                ),
                onTap: () => _entrar(c),
              )),
          ..._archivos.map((a) => ListTile(
                leading: Icon(_iconExt(a.formato), color: _green),
                title: Text(a.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  if (a.formato != null) a.formato!.toUpperCase(),
                  if (a.tamanoLegible.isNotEmpty) a.tamanoLegible,
                  if (a.descripcion != null && a.descripcion!.isNotEmpty) a.descripcion!,
                ].join(' · ')),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _accionesArchivo(a),
                ),
                onTap: () async {
                  final ok = await abrirEnlace(a.url);
                  if (!ok) _snack('No se pudo abrir; enlace copiado al portapapeles');
                },
              )),
        ],
      ),
    );
  }
}

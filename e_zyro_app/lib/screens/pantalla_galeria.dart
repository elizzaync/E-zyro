import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/galeria_models.dart';
import '../services/galeria_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';

/// Galería Global de imágenes/recursos (Fase 1).
/// - Modo global: lista toda la empresa con búsqueda.
/// - Modo contextual: pasa [entidadTipo] + [entidadId] para ver solo los de una
///   entidad (servicio/equipo/EPP/...), p. ej. desde el detalle de un servicio.
class PantallaGaleria extends StatefulWidget {
  final String? entidadTipo;
  final String? entidadId;
  final String titulo;

  const PantallaGaleria({
    super.key,
    this.entidadTipo,
    this.entidadId,
    this.titulo = 'Galería',
  });

  bool get esContextual => entidadTipo != null && entidadId != null;

  @override
  State<PantallaGaleria> createState() => _PantallaGaleriaState();
}

class _PantallaGaleriaState extends State<PantallaGaleria> {
  GaleriaService? _svc;
  final _picker = ImagePicker();
  final _searchCtrl = TextEditingController();

  List<RecursoCloudinary> _items = [];
  bool _cargando = true;
  bool _subiendo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getGaleriaService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = widget.esContextual
        ? await _svc!.porEntidad(widget.entidadTipo!, widget.entidadId!)
        : await _svc!.listar(q: _searchCtrl.text);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok) {
        _items = res.data ?? [];
      } else {
        _error = res.errorMessage;
      }
    });
  }

  Future<void> _subir() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final XFile? x =
        await _picker.pickImage(source: source, imageQuality: 75, maxWidth: 1920);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final b64 = base64Encode(bytes);

    if (!mounted) return;
    setState(() => _subiendo = true);
    final res = await _svc!.subir(
      imagenBase64: b64,
      entidadTipo: widget.entidadTipo,
      entidadId: widget.entidadId,
    );
    if (!mounted) return;
    setState(() => _subiendo = false);
    if (res.ok) {
      _snack('Imagen subida');
      await _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  Future<void> _eliminar(RecursoCloudinary r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar imagen'),
        content: const Text('Se eliminará de la nube. ¿Continuar?'),
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
    final res = await _svc!.eliminar(r.id);
    if (!mounted) return;
    if (res.ok) {
      _snack('Imagen eliminada');
      await _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  void _verImagen(RecursoCloudinary r) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: r.secureUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const Center(child: CircularProgressIndicator()),
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Row(
                children: [
                  if (AppSession.i.canEliminarGaleria)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _eliminar(r);
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      floatingActionButton: AppSession.i.canSubirGaleria
          ? FloatingActionButton.extended(
              onPressed: _subiendo ? null : _subir,
              icon: _subiendo
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_a_photo_outlined),
              label: Text(_subiendo ? 'Subiendo...' : 'Subir'),
            )
          : null,
      body: Column(
        children: [
          if (!widget.esContextual)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _cargar(),
                decoration: InputDecoration(
                  hintText: 'Buscar por descripción o carpeta...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _cargar();
                          },
                        ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _mensajeCentro(
        icon: Icons.cloud_off_outlined,
        titulo: 'No se pudo cargar la galería',
        detalle: _error!,
        accion: _cargar,
      );
    }
    if (_items.isEmpty) {
      return _mensajeCentro(
        icon: Icons.photo_library_outlined,
        titulo: 'Sin imágenes',
        detalle: 'Toca "Subir" para agregar la primera.',
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final r = _items[i];
          return GestureDetector(
            onTap: () => _verImagen(r),
            onLongPress: AppSession.i.canEliminarGaleria ? () => _eliminar(r) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: r.esImagen
                  ? CachedNetworkImage(
                      imageUrl: r.secureUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: Colors.black12),
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.broken_image, color: Colors.grey),
                    )
                  : Container(
                      color: Colors.black12,
                      child: const Icon(Icons.insert_drive_file_outlined, size: 32),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _mensajeCentro({
    required IconData icon,
    required String titulo,
    required String detalle,
    VoidCallback? accion,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(titulo,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(detalle,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
            if (accion != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: accion, child: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../models/historial_models.dart';
import '../services/historial_service.dart';
import '../utils/api_provider.dart';

// HU-19: Historial de equipo y descarga de informes
class PantallaHistorialEquipo extends StatefulWidget {
  final String equipoId;
  final String equipoNombre;

  const PantallaHistorialEquipo({
    super.key,
    required this.equipoId,
    required this.equipoNombre,
  });

  @override
  State<PantallaHistorialEquipo> createState() =>
      _PantallaHistorialEquipoState();
}

class _PantallaHistorialEquipoState extends State<PantallaHistorialEquipo> {
  HistorialService? _service;
  List<MantenimientoHistorial> _historial = [];
  bool _loading = true;

  static const _green = Color(0xFF8FD11B);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getHistorialService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _loading = true);
    try {
      final data = await _service!.getHistorialEquipo(widget.equipoId);
      if (!mounted) return;
      setState(() {
        _historial = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _descargarPdf(MantenimientoHistorial item) async {
    if (_service == null) return;
    final url = item.informePdfUrl ?? await _service!.getInformePdfUrl(item.id);
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe PDF no disponible aún.')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Descargando informe PDF...')),
    );
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await Printing.sharePdf(
          bytes: response.bodyBytes,
          filename: 'informe_${item.id}.pdf',
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo descargar el informe.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> _descargarZip(MantenimientoHistorial item) async {
    if (_service == null) return;
    final url =
        item.evidenciasZipUrl ?? await _service!.getEvidenciasZipUrl(item.id);
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evidencias ZIP no disponibles aún.')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Descargando evidencias...')),
    );
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final file =
            File('${dir.path}/evidencias_${item.id}.zip');
        await file.writeAsBytes(response.bodyBytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Guardado en: ${file.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No se pudieron descargar las evidencias.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  void _abrirGaleria(
      List<FotoEvidencia> fotos, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GaleriaEvidenciasScreen(
          fotos: fotos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.equipoNombre,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            const Text(
              'Historial de mantenimientos',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_green),
              ),
            )
          : _historial.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _green,
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    itemCount: _historial.length,
                    itemBuilder: (_, i) => _HistorialCard(
                      item: _historial[i],
                      isDark: isDark,
                      isLast: i == _historial.length - 1,
                      onDescargarPdf: () => _descargarPdf(_historial[i]),
                      onDescargarZip: () => _descargarZip(_historial[i]),
                      onFotoTap: (fotos, idx) =>
                          _abrirGaleria(fotos, idx),
                    ),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Sin historial',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Este equipo aún no tiene mantenimientos registrados',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Card de historial con timeline ────────────────────────────────────────────

class _HistorialCard extends StatelessWidget {
  final MantenimientoHistorial item;
  final bool isDark;
  final bool isLast;
  final VoidCallback onDescargarPdf;
  final VoidCallback onDescargarZip;
  final void Function(List<FotoEvidencia>, int) onFotoTap;

  const _HistorialCard({
    required this.item,
    required this.isDark,
    required this.isLast,
    required this.onDescargarPdf,
    required this.onDescargarZip,
    required this.onFotoTap,
  });

  static const _green = Color(0xFF8FD11B);

  Color get _estadoColor => switch (item.estado.toLowerCase()) {
        'completado' => _green,
        'en_proceso' => const Color(0xFF3B82F6),
        'cancelado' => Colors.red,
        _ => const Color(0xFFF59E0B),
      };

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final color = _estadoColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline indicator
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 18),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.3), width: 3),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 160,
                color: Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 12),
        // Card content
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: isDark
                  ? Border.all(color: _green.withValues(alpha: 0.20))
                  : null,
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: fecha + estado
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.fecha,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isDark ? 0.15 : 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.estado,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Técnico + proyecto
                _InfoChip(
                  icon: Icons.person_outline,
                  label: item.tecnicoNombre,
                ),
                const SizedBox(height: 3),
                _InfoChip(
                  icon: Icons.folder_outlined,
                  label: item.proyectoNombre,
                ),
                // Fotos en miniatura
                if (item.fotos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 56,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: item.fotos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => onFotoTap(item.fotos, i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _FotoThumbnail(foto: item.fotos[i]),
                        ),
                      ),
                    ),
                  ),
                ],
                // Botones de descarga
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDescargarPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined,
                            size: 15),
                        label: const Text(
                          'Informe PDF',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _green,
                          side: BorderSide(
                              color: _green.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDescargarZip,
                        icon: const Icon(Icons.folder_zip_outlined, size: 15),
                        label: const Text(
                          'Evidencias ZIP',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF3B82F6),
                          side: BorderSide(
                              color:
                                  const Color(0xFF3B82F6).withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _FotoThumbnail extends StatelessWidget {
  final FotoEvidencia foto;
  const _FotoThumbnail({required this.foto});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Image.network(
          foto.url,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 56,
            height: 56,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined,
                color: Colors.grey, size: 20),
          ),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 56,
              height: 56,
              color: Colors.grey.shade100,
              child: const Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            );
          },
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              foto.tipoLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Galería full-screen de evidencias ────────────────────────────────────────

class _GaleriaEvidenciasScreen extends StatelessWidget {
  final List<FotoEvidencia> fotos;
  final int initialIndex;

  const _GaleriaEvidenciasScreen({
    required this.fotos,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Evidencias',
          style: TextStyle(color: Colors.white),
        ),
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: fotos.length,
        itemBuilder: (_, i) {
          final foto = fotos[i];
          return Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      foto.url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white38,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
              // Caption
              Container(
                color: Colors.black87,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            foto.tipoLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          if (foto.paso != null)
                            Text(
                              foto.paso!,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          if (foto.fecha != null)
                            Text(
                              foto.fecha!,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${i + 1} / ${fotos.length}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

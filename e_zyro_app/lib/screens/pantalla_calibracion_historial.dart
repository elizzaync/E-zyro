import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/calibracion_models.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_preview_screen.dart';
import '../services/calibracion_service.dart';
import '../utils/abrir_enlace.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';

/// Historial de calibraciones de un equipo (timeline) + registro de nuevas.
class PantallaCalibracionHistorial extends StatefulWidget {
  final String equipoId;
  final String equipoNombre;

  const PantallaCalibracionHistorial({
    super.key,
    required this.equipoId,
    required this.equipoNombre,
  });

  @override
  State<PantallaCalibracionHistorial> createState() => _PantallaCalibracionHistorialState();
}

class _PantallaCalibracionHistorialState extends State<PantallaCalibracionHistorial> {
  CalibracionService? _svc;
  final _picker = ImagePicker();
  List<CalibracionEvento> _eventos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getCalibracionService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final r = await _svc!.listarEventos(widget.equipoId);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _eventos = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  // ── Semáforo de próxima calibración ────────────────────────────────────────
  /// (color, etiqueta) según la próxima fecha respecto de hoy.
  (Color, String) _semaforo(String? fechaProxima) {
    final f = DateTime.tryParse(fechaProxima ?? '');
    if (f == null) return (Colors.grey, 'Sin próxima');
    final dias = f.difference(DateTime.now()).inDays;
    if (dias < 0) return (Colors.red, 'Vencida hace ${-dias} d');
    if (dias <= 30) return (Colors.orange, 'Vence en $dias d');
    return (Colors.green, 'Vigente ($dias d)');
  }

  // ── Registrar calibración ──────────────────────────────────────────────────
  Future<void> _registrar() async {
    final fReal = TextEditingController(text: _hoyIso());
    final periodicidad = TextEditingController(text: '12');
    final quien = TextEditingController();
    final resp = TextEditingController();
    final nroCert = TextEditingController();
    String resultado = 'conforme';
    final obs = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Registrar calibración'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: fReal, decoration: const InputDecoration(labelText: 'Fecha realizada (yyyy-mm-dd)')),
              TextField(controller: periodicidad, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Periodicidad (meses) — calcula la próxima')),
              TextField(controller: quien, decoration: const InputDecoration(labelText: 'Realizada por (técnico/laboratorio)')),
              TextField(controller: resp, decoration: const InputDecoration(labelText: 'Empresa responsable')),
              TextField(controller: nroCert, decoration: const InputDecoration(labelText: 'N° de certificado')),
              DropdownButtonFormField<String>(
                initialValue: resultado,
                decoration: const InputDecoration(labelText: 'Resultado'),
                items: const [
                  DropdownMenuItem(value: 'conforme', child: Text('Conforme')),
                  DropdownMenuItem(value: 'observado', child: Text('Observado')),
                ],
                onChanged: (v) => setLocal(() => resultado = v ?? 'conforme'),
              ),
              TextField(controller: obs, decoration: const InputDecoration(labelText: 'Observación')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (fReal.text.trim().isEmpty) {
      _snack('La fecha realizada es obligatoria', error: true);
      return;
    }
    final res = await _svc!.crearEvento(
      equipoId: widget.equipoId,
      fechaRealizada: fReal.text.trim(),
      periodicidadMeses: int.tryParse(periodicidad.text.trim()),
      realizadaPor: _nullIfEmpty(quien.text),
      empresaResponsable: _nullIfEmpty(resp.text),
      numeroCertificado: _nullIfEmpty(nroCert.text),
      resultado: resultado,
      observacion: _nullIfEmpty(obs.text),
    );
    if (!mounted) return;
    if (res.ok) {
      _snack('Calibración registrada');
      // ofrecer adjuntar certificado de inmediato
      final ev = res.data!;
      await _adjuntarCert(ev);
      _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  // ── Adjuntar certificado (PDF o imagen) ─────────────────────────────────────
  Future<void> _adjuntarCert(CalibracionEvento ev) async {
    final opt = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('Adjuntar PDF'), onTap: () => Navigator.pop(ctx, 'pdf')),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.pop(ctx, 'camara')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir imagen'), onTap: () => Navigator.pop(ctx, 'galeria')),
        ]),
      ),
    );
    if (opt == null) return;

    String? b64;
    String ext;
    if (opt == 'pdf') {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: const ['pdf'], withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final f = picked.files.first;
      if (f.bytes == null) {
        _snack('No se pudo leer el archivo', error: true);
        return;
      }
      if (f.bytes!.length > 20 * 1024 * 1024) {
        _snack('El PDF supera 20 MB', error: true);
        return;
      }
      b64 = base64Encode(f.bytes!);
      ext = 'pdf';
    } else {
      final x = await _picker.pickImage(
        source: opt == 'camara' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80, maxWidth: 1920);
      if (x == null) return;
      b64 = base64Encode(await x.readAsBytes());
      ext = 'jpg';
    }

    final res = await _svc!.subirCertificadoEvento(ev.id, b64, extension: ext);
    if (!mounted) return;
    if (res.ok) {
      _snack('Certificado adjuntado');
      _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  Future<void> _exportarPdf() async {
    if (_eventos.isEmpty) {
      _snack('No hay calibraciones para exportar', error: true);
      return;
    }
    final bytes = await PdfService.historialCalibracion(widget.equipoNombre, _eventos);
    if (!mounted) return;
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo: 'historial_calibracion_${widget.equipoId}.pdf',
      titulo: 'Historial de calibraciones',
    );
  }

  Future<void> _eliminar(CalibracionEvento ev) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar calibración'),
        content: Text('¿Eliminar la calibración del ${ev.fechaRealizada ?? '-'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _svc!.eliminarEvento(ev.id);
    if (!mounted) return;
    res.ok ? _cargar() : _snack(res.errorMessage, error: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.equipoNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _exportarPdf, icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Exportar PDF'),
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: AppSession.i.canCrearCalibracion
          ? FloatingActionButton.extended(
              onPressed: _registrar, icon: const Icon(Icons.add), label: const Text('Registrar'))
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _eventos.isEmpty
                  ? const Center(child: Text('Sin calibraciones registradas.'))
                  : RefreshIndicator(onRefresh: _cargar, child: _timeline()),
    );
  }

  Widget _timeline() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _eventos.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final ev = _eventos[i];
        final (color, etiqueta) = _semaforo(ev.fechaProxima);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(Icons.straighten_outlined, color: color),
          ),
          title: Text('Realizada: ${ev.fechaRealizada ?? '-'}'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Próxima: ${ev.fechaProxima ?? '-'} · $etiqueta',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              if (ev.realizadaPor != null) Text('Por: ${ev.realizadaPor}'),
              if (ev.empresaResponsable != null) Text('Lab.: ${ev.empresaResponsable}'),
              if (ev.numeroCertificado != null) Text('Cert. N°: ${ev.numeroCertificado}'),
              if (ev.resultado != null) Text('Resultado: ${ev.resultado}'),
            ],
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ev.certificadoUrl != null)
                IconButton(
                  icon: const Icon(Icons.description_outlined, color: Colors.green, size: 20),
                  tooltip: 'Abrir certificado',
                  onPressed: () async {
                    final abrio = await abrirEnlace(ev.certificadoUrl);
                    if (!abrio) _snack('Enlace copiado al portapapeles');
                  },
                ),
              if (AppSession.i.canEditarCalibracion)
                IconButton(
                  icon: const Icon(Icons.upload_file_outlined, size: 20),
                  tooltip: 'Adjuntar certificado',
                  onPressed: () => _adjuntarCert(ev),
                ),
              if (AppSession.i.canEliminarCalibracion)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                  tooltip: 'Eliminar',
                  onPressed: () => _eliminar(ev),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _hoyIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();
}

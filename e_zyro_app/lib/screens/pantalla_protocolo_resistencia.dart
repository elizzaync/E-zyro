import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../pdf/pdf_preview_screen.dart';
import '../services/intervencion_service.dart';

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFD6584F);

/// Protocolo de Medición de Resistencia (pozo a tierra): datos del
/// instrumento de medición + evidencia gráfica + 3 firmas.
class PantallaProtocoloResistencia extends StatefulWidget {
  final String servicioId;
  final String eiId;
  final String equipoNombre;

  const PantallaProtocoloResistencia({
    super.key,
    required this.servicioId,
    required this.eiId,
    required this.equipoNombre,
  });

  @override
  State<PantallaProtocoloResistencia> createState() => _PantallaProtocoloResistenciaState();
}

class _PantallaProtocoloResistenciaState extends State<PantallaProtocoloResistencia> {
  IntervencionService? _svc;
  bool _generando = false;

  String? _evidenciaGraficaB64;
  String? _evidenciaGrafica2B64;
  String? _firmaEjecucionB64;
  String? _firmaSupervisorB64;
  String? _firmaEspecialistaB64;

  final _numeroPozoCtrl = TextEditingController();
  final _ubicacionCtrl = TextEditingController();
  final _planoReferenciaCtrl = TextEditingController();
  final _fechaCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  final _numeroSerieCtrl = TextEditingController();
  final _certificadoCalibracionCtrl = TextEditingController();
  final _rangoMedicionCtrl = TextEditingController();
  final _dimensionPozoCtrl = TextEditingController();
  final _tipoVarillaCtrl = TextEditingController();
  final _tipoTierraCtrl = TextEditingController();
  final _horaMedicionCtrl = TextEditingController();
  final _medicionInicialCtrl = TextEditingController();
  final _medicionFinalCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _conclusionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _numeroPozoCtrl.text = widget.equipoNombre;
    final hoy = DateTime.now();
    _fechaCtrl.text =
        '${hoy.day.toString().padLeft(2, '0')}/${hoy.month.toString().padLeft(2, '0')}/${hoy.year}';
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = IntervencionService(ApiClient(prefs));
  }

  @override
  void dispose() {
    for (final c in [
      _numeroPozoCtrl, _ubicacionCtrl, _planoReferenciaCtrl, _fechaCtrl,
      _marcaCtrl, _modeloCtrl, _numeroSerieCtrl, _certificadoCalibracionCtrl,
      _rangoMedicionCtrl, _dimensionPozoCtrl, _tipoVarillaCtrl, _tipoTierraCtrl,
      _horaMedicionCtrl, _medicionInicialCtrl, _medicionFinalCtrl,
      _observacionesCtrl, _conclusionCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<String?> _elegirImagen() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final ext = file.path.split('.').last.toLowerCase();
    final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/png';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<void> _generar() async {
    if (_generando || _svc == null) return;
    setState(() => _generando = true);

    final payload = {
      'numero_pozo': _numeroPozoCtrl.text,
      'ubicacion': _ubicacionCtrl.text,
      'plano_referencia': _planoReferenciaCtrl.text,
      'fecha': _fechaCtrl.text,
      'marca': _marcaCtrl.text,
      'modelo': _modeloCtrl.text,
      'numero_serie': _numeroSerieCtrl.text,
      'certificado_calibracion': _certificadoCalibracionCtrl.text,
      'rango_medicion': _rangoMedicionCtrl.text,
      'dimension_pozo': _dimensionPozoCtrl.text,
      'tipo_varilla': _tipoVarillaCtrl.text,
      'tipo_tierra': _tipoTierraCtrl.text,
      'hora_medicion': _horaMedicionCtrl.text,
      'medicion_inicial': _medicionInicialCtrl.text,
      'medicion_final': _medicionFinalCtrl.text,
      'observaciones': _observacionesCtrl.text,
      'conclusion': _conclusionCtrl.text,
      'evidencia_grafica': _evidenciaGraficaB64,
      'evidencia_grafica_2': _evidenciaGrafica2B64,
      'firma_ejecucion': _firmaEjecucionB64,
      'firma_supervisor': _firmaSupervisorB64,
      'firma_especialista': _firmaEspecialistaB64,
    };

    final res = await _svc!.generarProtocoloResistencia(widget.servicioId, widget.eiId, payload);
    if (!mounted) return;
    setState(() => _generando = false);

    if (res.ok && res.data != null) {
      final nombre = 'PROTOCOLO_RESISTENCIA_${widget.equipoNombre.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')}.pdf';
      await PdfPreviewScreen.abrir(context, bytes: res.data!, nombreArchivo: nombre, titulo: 'Protocolo de Resistencia');
    } else {
      _snack(res.errorMessage.isEmpty ? 'Error al generar el protocolo.' : res.errorMessage, _danger);
    }
  }

  Widget _campo(TextEditingController ctrl, String label, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  Widget _botonImagen(String label, bool cargada, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(cargada ? Icons.check_circle : Icons.image_outlined, size: 16, color: cargada ? _green : null),
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protocolo de Resistencia', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _campo(_numeroPozoCtrl, 'Número de pozo'),
          _campo(_ubicacionCtrl, 'Ubicación'),
          _campo(_planoReferenciaCtrl, 'Plano de referencia'),
          _campo(_fechaCtrl, 'Fecha', hint: 'dd/mm/aaaa'),
          const Divider(height: 20),
          const Text('Instrumento de medición', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _campo(_marcaCtrl, 'Marca'),
          _campo(_modeloCtrl, 'Modelo'),
          _campo(_numeroSerieCtrl, 'N° de serie'),
          _campo(_certificadoCalibracionCtrl, 'Certificado de calibración'),
          _campo(_rangoMedicionCtrl, 'Rango de medición'),
          const Divider(height: 20),
          const Text('Características del pozo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _campo(_dimensionPozoCtrl, 'Dimensión del pozo'),
          _campo(_tipoVarillaCtrl, 'Tipo de varilla'),
          _campo(_tipoTierraCtrl, 'Tipo de tierra'),
          const Divider(height: 20),
          const Text('Medición', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _campo(_horaMedicionCtrl, 'Hora de medición', hint: 'hh:mm'),
          _campo(_medicionInicialCtrl, 'Medición inicial (Ω)'),
          _campo(_medicionFinalCtrl, 'Medición final (Ω)'),
          const Divider(height: 20),
          const Text('Evidencia gráfica', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _botonImagen('Foto 1', _evidenciaGraficaB64 != null, () async {
              final img = await _elegirImagen();
              if (img != null) setState(() => _evidenciaGraficaB64 = img);
            }),
            _botonImagen('Foto 2', _evidenciaGrafica2B64 != null, () async {
              final img = await _elegirImagen();
              if (img != null) setState(() => _evidenciaGrafica2B64 = img);
            }),
          ]),
          const Divider(height: 20),
          _campo(_observacionesCtrl, 'Observaciones'),
          _campo(_conclusionCtrl, 'Conclusión'),
          const Text('Firmas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _botonImagen('Ejecución', _firmaEjecucionB64 != null, () async {
              final img = await _elegirImagen();
              if (img != null) setState(() => _firmaEjecucionB64 = img);
            }),
            _botonImagen('Supervisor', _firmaSupervisorB64 != null, () async {
              final img = await _elegirImagen();
              if (img != null) setState(() => _firmaSupervisorB64 = img);
            }),
            _botonImagen('Especialista', _firmaEspecialistaB64 != null, () async {
              final img = await _elegirImagen();
              if (img != null) setState(() => _firmaEspecialistaB64 = img);
            }),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generando ? null : _generar,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _generando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Colors.white),
              label: Text(_generando ? 'Generando…' : 'Generar vista previa',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../models/intervencion_models.dart';
import '../pdf/pdf_preview_screen.dart';
import '../services/intervencion_service.dart';

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFEF4444);

/// Certificado de un equipo intervenido. Réplica del componente Angular
/// `certificado`: Protocolo de Pozo a Tierra (tipo 'pozo') o Certificado de
/// Operatividad (tipo 'operatividad'). Precarga datos del equipo y del
/// personal del servicio, arma el payload exacto del frontend y muestra el
/// PDF generado en el visor de la app.
class PantallaCertificadoEquipo extends StatefulWidget {
  final String servicioId;
  final String eiId;

  /// 'pozo' | 'operatividad'
  final String tipo;

  const PantallaCertificadoEquipo({
    super.key,
    required this.servicioId,
    required this.eiId,
    required this.tipo,
  });

  @override
  State<PantallaCertificadoEquipo> createState() =>
      _PantallaCertificadoEquipoState();
}

class _PantallaCertificadoEquipoState extends State<PantallaCertificadoEquipo> {
  IntervencionService? _svc;
  bool _generando = false;

  // Datos auto-completados
  List<PersonalInforme> _personal = [];
  String? _fotoProc1, _fotoProc4, _fotoProc7;

  // Firmas (data-url base64)
  String? _firmaTecB64; // pozo
  String? _firmaVerB64; // operatividad
  String? _firmaGerB64; // operatividad

  // Campos del formulario (mismos nombres que el componente Angular)
  final _ubicacionCtrl = TextEditingController();
  final _numeroPozoCtrl = TextEditingController();
  final _fechaEjecucionCtrl = TextEditingController();
  final _fechaHoraMedicionCtrl = TextEditingController();
  final _resultadoMedicionCtrl = TextEditingController();
  final _horaInicioCtrl = TextEditingController();
  final _horaTerminoCtrl = TextEditingController();
  final _nombreTecnicoCtrl = TextEditingController();
  final _nombreTableroCtrl = TextEditingController();
  final _fechaCtrl = TextEditingController();
  final _razonSocialCtrl = TextEditingController();
  String? _personalTecnicoSel;

  bool get _esPozo => widget.tipo == 'pozo';
  String get _titulo =>
      _esPozo ? 'Protocolo de Pozo a Tierra' : 'Certificado de Operatividad';

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _fechaCtrl.text =
        '${hoy.day.toString().padLeft(2, '0')}/${hoy.month.toString().padLeft(2, '0')}/${hoy.year}';
    _init();
  }

  @override
  void dispose() {
    for (final c in [
      _ubicacionCtrl,
      _numeroPozoCtrl,
      _fechaEjecucionCtrl,
      _fechaHoraMedicionCtrl,
      _resultadoMedicionCtrl,
      _horaInicioCtrl,
      _horaTerminoCtrl,
      _nombreTecnicoCtrl,
      _nombreTableroCtrl,
      _fechaCtrl,
      _razonSocialCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = IntervencionService(ApiClient(prefs));

    // Datos del equipo + fotos de los procedimientos 1, 4 y 7 (solo Pozo).
    final insp =
        await _svc!.getInspeccionActiva(widget.servicioId, widget.eiId);
    if (mounted && insp.ok && insp.data != null) {
      final eq = insp.data!.equipo;
      setState(() {
        _ubicacionCtrl.text = eq.ubicacionReferencia ?? '';
        _nombreTableroCtrl.text = eq.nombre;
        String? fotoDe(int orden) => insp.data!.pasos
            .where((p) => p.orden == orden)
            .firstOrNull
            ?.fotoUrl;
        _fotoProc1 = fotoDe(1);
        _fotoProc4 = fotoDe(4);
        _fotoProc7 = fotoDe(7);
      });
    }

    // Personal del servicio + razón social (cliente del proyecto).
    final pre = await _svc!.getPrecargaInforme(widget.servicioId);
    if (mounted && pre.ok && pre.data != null) {
      setState(() {
        _personal = pre.data!.personal;
        if ((pre.data!.clienteNombre ?? '').isNotEmpty) {
          _razonSocialCtrl.text = pre.data!.clienteNombre!;
        }
      });
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _firmar(String tipo) async {
    final file =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    final ext = file.path.split('.').last.toLowerCase();
    final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/png';
    final b64 = 'data:$mime;base64,${base64Encode(bytes)}';
    setState(() {
      switch (tipo) {
        case 'tecnico':
          _firmaTecB64 = b64;
        case 'verificador':
          _firmaVerB64 = b64;
        default:
          _firmaGerB64 = b64;
      }
    });
  }

  Map<String, dynamic> _payloadPozo() => {
        'ubicacion': _ubicacionCtrl.text,
        'numero_pozo': _numeroPozoCtrl.text,
        // fecha_actualizacion se auto-genera en backend (fecha de hoy)
        'fecha_ejecucion': _fechaEjecucionCtrl.text,
        'fecha_hora_medicion': _fechaHoraMedicionCtrl.text,
        'resultado_medicion': _resultadoMedicionCtrl.text,
        'hora_inicio': _horaInicioCtrl.text,
        'hora_termino': _horaTerminoCtrl.text,
        'nombre_tecnico': _nombreTecnicoCtrl.text,
        'firma_tecnico': _firmaTecB64,
        'fotos_procedimientos': [_fotoProc1, _fotoProc4, _fotoProc7],
      };

  Map<String, dynamic> _payloadOperatividad() => {
        'nombre_tablero': _nombreTableroCtrl.text,
        'fecha': _fechaCtrl.text,
        'razon_social': _razonSocialCtrl.text,
        'ubicacion': _ubicacionCtrl.text,
        'personal_tecnico': _personalTecnicoSel ?? _nombreTecnicoCtrl.text,
        'firma_verificador': _firmaVerB64,
        'firma_gerente': _firmaGerB64,
      };

  Future<void> _generar() async {
    if (_generando || _svc == null) return;
    setState(() => _generando = true);

    final payload = _esPozo ? _payloadPozo() : _payloadOperatividad();
    final res = _esPozo
        ? await _svc!
            .generarCertificadoPozo(widget.servicioId, widget.eiId, payload)
        : await _svc!.generarCertificadoOperatividad(
            widget.servicioId, widget.eiId, payload);

    if (!mounted) return;
    setState(() => _generando = false);

    if (res.ok && res.data != null) {
      final id = _esPozo
          ? (_numeroPozoCtrl.text.isEmpty ? 'XX' : _numeroPozoCtrl.text)
          : (_nombreTableroCtrl.text.isEmpty ? 'doc' : _nombreTableroCtrl.text);
      final nombre =
          '${_esPozo ? 'PROTOCOLO_POZO' : 'CERT_OPERATIVIDAD'}_${id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')}.pdf';
      await PdfPreviewScreen.abrir(
        context,
        bytes: res.data!,
        nombreArchivo: nombre,
        titulo: _titulo,
      );
    } else {
      _snack(
          res.errorMessage.isEmpty
              ? 'Error al generar el certificado.'
              : res.errorMessage,
          _danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titulo,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _ubicacionCtrl,
            decoration: const InputDecoration(
                labelText: 'Ubicación', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          if (_esPozo) ..._camposPozo() else ..._camposOperatividad(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generando ? null : _generar,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _generando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf_outlined,
                      size: 18, color: Colors.white),
              label: Text(_generando ? 'Generando…' : 'Generar vista previa',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _camposPozo() => [
        TextField(
          controller: _numeroPozoCtrl,
          decoration: const InputDecoration(
              labelText: 'Número de pozo', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _fechaEjecucionCtrl,
          decoration: const InputDecoration(
              labelText: 'Fecha de ejecución',
              hintText: 'dd/mm/aaaa',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _fechaHoraMedicionCtrl,
          decoration: const InputDecoration(
              labelText: 'Fecha y hora de medición',
              hintText: 'dd/mm/aaaa hh:mm',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _resultadoMedicionCtrl,
          decoration: const InputDecoration(
              labelText: 'Resultado de medición (Ω)',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _horaInicioCtrl,
                decoration: const InputDecoration(
                    labelText: 'Hora inicio',
                    hintText: 'hh:mm',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _horaTerminoCtrl,
                decoration: const InputDecoration(
                    labelText: 'Hora término',
                    hintText: 'hh:mm',
                    border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _selectorTecnico(_nombreTecnicoCtrl),
        const SizedBox(height: 10),
        _botonFirma('Firma del técnico', _firmaTecB64 != null,
            () => _firmar('tecnico')),
        const SizedBox(height: 10),
        _resumenFotos(),
      ];

  List<Widget> _camposOperatividad() => [
        TextField(
          controller: _nombreTableroCtrl,
          decoration: const InputDecoration(
              labelText: 'Nombre del tablero', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _fechaCtrl,
          decoration: const InputDecoration(
              labelText: 'Fecha',
              hintText: 'dd/mm/aaaa',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _razonSocialCtrl,
          decoration: const InputDecoration(
              labelText: 'Razón social', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _personalTecnicoSel,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Personal técnico', border: OutlineInputBorder()),
          items: [
            for (final p in _personal)
              DropdownMenuItem(
                  value: p.nombre,
                  child: Text(p.nombre, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _personalTecnicoSel = v),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _botonFirma('Firma verificador', _firmaVerB64 != null,
                  () => _firmar('verificador')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _botonFirma('Firma gerente', _firmaGerB64 != null,
                  () => _firmar('gerente')),
            ),
          ],
        ),
      ];

  Widget _selectorTecnico(TextEditingController ctrl) => _personal.isEmpty
      ? TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'Nombre del técnico', border: OutlineInputBorder()),
        )
      : DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Nombre del técnico', border: OutlineInputBorder()),
          items: [
            for (final p in _personal)
              DropdownMenuItem(
                  value: p.nombre,
                  child: Text(p.nombre, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => ctrl.text = v ?? '',
        );

  Widget _botonFirma(String label, bool firmado, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(firmado ? Icons.check_circle : Icons.draw_outlined,
            size: 16, color: firmado ? _green : null),
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
      );

  /// Resumen de las fotos de los procedimientos 1, 4 y 7 que se inyectan al
  /// protocolo (igual que el frontend, que las toma de la inspección).
  Widget _resumenFotos() {
    final fotos = [
      ('Proc. 1', _fotoProc1),
      ('Proc. 4', _fotoProc4),
      ('Proc. 7', _fotoProc7),
    ];
    return Wrap(
      spacing: 10,
      children: [
        for (final (label, url) in fotos)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                url == null ? Icons.image_not_supported_outlined : Icons.image,
                size: 14,
                color: url == null ? Colors.grey : _green,
              ),
              const SizedBox(width: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: url == null ? Colors.grey : Colors.black87)),
            ],
          ),
      ],
    );
  }
}

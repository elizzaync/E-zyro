import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../pdf/pdf_preview_screen.dart';
import '../services/intervencion_service.dart';

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFD6584F);

class _Hallazgo {
  String elemento = '';
  String actividad = '';
  String fecha = '';
  String tempObj = '';
  String temReflejada = '';
  String tempAire = '';
  String escala = '';
  String cielo = '';
  String velViento = '';
  String distancia = '';
  String pctCarga = '';
  String? imgTermografica;
  String? imgTablero;

  Map<String, dynamic> toJson() => {
        'elemento': elemento,
        'actividad': actividad,
        'fecha': fecha,
        'temp_obj': tempObj,
        'tem_reflejada': temReflejada,
        'temp_aire': tempAire,
        'escala_temperatura': escala,
        'cielo': cielo,
        'vel_viento': velViento,
        'distancia': distancia,
        'pct_carga': pctCarga,
        'img_termografica': imgTermografica,
        'img_tablero': imgTablero,
      };
}

/// Informe Termográfico: N hallazgos (puntos calientes), cada uno con
/// foto normal + foto térmica y datos ambientales/de cámara.
class PantallaInformeTermografico extends StatefulWidget {
  final String servicioId;
  final String eiId;
  final String equipoNombre;

  const PantallaInformeTermografico({
    super.key,
    required this.servicioId,
    required this.eiId,
    required this.equipoNombre,
  });

  @override
  State<PantallaInformeTermografico> createState() => _PantallaInformeTermograficoState();
}

class _PantallaInformeTermograficoState extends State<PantallaInformeTermografico> {
  IntervencionService? _svc;
  bool _generando = false;

  final _areaCtrl = TextEditingController();
  final _tableroCtrl = TextEditingController();
  final _camaraCtrl = TextEditingController();
  final List<_Hallazgo> _hallazgos = [];

  @override
  void initState() {
    super.initState();
    _tableroCtrl.text = widget.equipoNombre;
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = IntervencionService(ApiClient(prefs));
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _tableroCtrl.dispose();
    _camaraCtrl.dispose();
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

  Future<void> _abrirFormularioHallazgo({_Hallazgo? existente, int? index}) async {
    final h = existente ?? _Hallazgo();
    final elementoCtrl = TextEditingController(text: h.elemento);
    final actividadCtrl = TextEditingController(text: h.actividad);
    final fechaCtrl = TextEditingController(text: h.fecha);
    final tempObjCtrl = TextEditingController(text: h.tempObj);
    final temReflejadaCtrl = TextEditingController(text: h.temReflejada);
    final tempAireCtrl = TextEditingController(text: h.tempAire);
    final escalaCtrl = TextEditingController(text: h.escala);
    final cieloCtrl = TextEditingController(text: h.cielo);
    final velVientoCtrl = TextEditingController(text: h.velViento);
    final distanciaCtrl = TextEditingController(text: h.distancia);
    final pctCargaCtrl = TextEditingController(text: h.pctCarga);
    String? imgTermo = h.imgTermografica;
    String? imgTab = h.imgTablero;

    final guardar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existente == null ? 'Nuevo hallazgo' : 'Editar hallazgo',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(controller: elementoCtrl, decoration: const InputDecoration(labelText: 'Elemento', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: actividadCtrl, decoration: const InputDecoration(labelText: 'Actividad', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: fechaCtrl, decoration: const InputDecoration(labelText: 'Fecha', hintText: 'dd/mm/aaaa', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: tempObjCtrl, decoration: const InputDecoration(labelText: 'Temp. objeto', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: temReflejadaCtrl, decoration: const InputDecoration(labelText: 'Temp. reflejada', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: tempAireCtrl, decoration: const InputDecoration(labelText: 'Temp. ambiente', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: escalaCtrl, decoration: const InputDecoration(labelText: 'Escala', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: cieloCtrl, decoration: const InputDecoration(labelText: 'Cielo', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: velVientoCtrl, decoration: const InputDecoration(labelText: 'Vel. viento', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: distanciaCtrl, decoration: const InputDecoration(labelText: 'Distancia', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: pctCargaCtrl, decoration: const InputDecoration(labelText: '% de carga', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final img = await _elegirImagen();
                      if (img != null) setSheet(() => imgTermo = img);
                    },
                    icon: Icon(imgTermo != null ? Icons.check_circle : Icons.thermostat_outlined, size: 16, color: imgTermo != null ? _green : null),
                    label: const Text('Foto térmica', style: TextStyle(fontSize: 11.5)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final img = await _elegirImagen();
                      if (img != null) setSheet(() => imgTab = img);
                    },
                    icon: Icon(imgTab != null ? Icons.check_circle : Icons.image_outlined, size: 16, color: imgTab != null ? _green : null),
                    label: const Text('Foto normal', style: TextStyle(fontSize: 11.5)),
                  ),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      h
                        ..elemento = elementoCtrl.text
                        ..actividad = actividadCtrl.text
                        ..fecha = fechaCtrl.text
                        ..tempObj = tempObjCtrl.text
                        ..temReflejada = temReflejadaCtrl.text
                        ..tempAire = tempAireCtrl.text
                        ..escala = escalaCtrl.text
                        ..cielo = cieloCtrl.text
                        ..velViento = velVientoCtrl.text
                        ..distancia = distanciaCtrl.text
                        ..pctCarga = pctCargaCtrl.text
                        ..imgTermografica = imgTermo
                        ..imgTablero = imgTab;
                      Navigator.pop(ctx, true);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: _green, padding: const EdgeInsets.symmetric(vertical: 13)),
                    child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (guardar != true) return;
    setState(() {
      if (index != null) {
        _hallazgos[index] = h;
      } else {
        _hallazgos.add(h);
      }
    });
  }

  Future<void> _generar() async {
    if (_generando || _svc == null) return;
    if (_hallazgos.isEmpty) {
      _snack('Agrega al menos un hallazgo.', _danger);
      return;
    }
    setState(() => _generando = true);

    final payload = {
      'area': _areaCtrl.text,
      'nombre_tablero': _tableroCtrl.text,
      'equipo': _camaraCtrl.text,
      'items': _hallazgos.map((h) => h.toJson()).toList(),
    };

    final res = await _svc!.generarInformeTermografico(widget.servicioId, widget.eiId, payload);
    if (!mounted) return;
    setState(() => _generando = false);

    if (res.ok && res.data != null) {
      final nombre = 'INFORME_TERMOGRAFICO_${widget.equipoNombre.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')}.pdf';
      await PdfPreviewScreen.abrir(context, bytes: res.data!, nombreArchivo: nombre, titulo: 'Informe Termográfico');
    } else {
      _snack(res.errorMessage.isEmpty ? 'Error al generar el informe.' : res.errorMessage, _danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informe Termográfico', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _green,
        onPressed: () => _abrirFormularioHallazgo(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(controller: _areaCtrl, decoration: const InputDecoration(labelText: 'Área', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _tableroCtrl, decoration: const InputDecoration(labelText: 'Tablero', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _camaraCtrl, decoration: const InputDecoration(labelText: 'Cámara utilizada', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          Text('Hallazgos (${_hallazgos.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          if (_hallazgos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Sin hallazgos. Usa el botón + para agregar uno.',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            )
          else
            for (var i = 0; i < _hallazgos.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.thermostat_outlined, color: _green),
                  title: Text(_hallazgos[i].elemento.isEmpty ? 'Hallazgo ${i + 1}' : _hallazgos[i].elemento,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${_hallazgos[i].tempObj.isEmpty ? '-' : _hallazgos[i].tempObj} · ${_hallazgos[i].actividad}'),
                  onTap: () => _abrirFormularioHallazgo(existente: _hallazgos[i], index: i),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: _danger, size: 20),
                    onPressed: () => setState(() => _hallazgos.removeAt(i)),
                  ),
                ),
              ),
          const SizedBox(height: 12),
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

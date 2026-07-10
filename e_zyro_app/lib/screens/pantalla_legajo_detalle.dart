import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/legajo_models.dart';
import '../services/legajo_service.dart';
import '../utils/abrir_enlace.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';

const _kTiposDocumentoLegajo = [
  'Boleta Mensual', 'Contrato', 'Memorándum', 'Certificado',
  'Constancia', 'Acta de compromiso', 'Política interna', 'Otro',
];

const _kMesesEs = [
  '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

/// Legajo Digital — documentos de UN empleado: listar, subir (admin), eliminar (admin).
class PantallaLegajoDetalle extends StatefulWidget {
  final String empleadoId;
  final String nombreEmpleado;
  const PantallaLegajoDetalle({super.key, required this.empleadoId, required this.nombreEmpleado});

  @override
  State<PantallaLegajoDetalle> createState() => _PantallaLegajoDetalleState();
}

class _PantallaLegajoDetalleState extends State<PantallaLegajoDetalle> {
  static const _brown = Color(0xFF8D6E63);

  LegajoService? _svc;
  LegajoEmpleadoDetalle? _detalle;
  bool _cargando = true;
  String _categoria = ''; // '' = todos

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getLegajoService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() => _cargando = true);
    final d = await _svc!.getDetalle(widget.empleadoId);
    if (!mounted) return;
    setState(() {
      _detalle = d;
      _cargando = false;
    });
  }

  List<DocumentoLegajo> get _documentosFiltrados {
    final docs = _detalle?.documentos ?? [];
    switch (_categoria) {
      case 'contratos':
        return docs.where((d) => d.tipo.trim().toLowerCase() == 'contrato').toList();
      case 'certificaciones':
        return docs.where((d) =>
            ['certificado', 'constancia'].contains(d.tipo.trim().toLowerCase())).toList();
      case 'otros':
        return docs.where((d) =>
            !['contrato', 'certificado', 'constancia'].contains(d.tipo.trim().toLowerCase())).toList();
      default:
        return docs;
    }
  }

  Future<void> _eliminar(DocumentoLegajo d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar documento'),
        content: Text('¿Eliminar «${d.nombre}»? Esta acción no se puede deshacer.'),
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
    final exito = await _svc!.eliminarDocumento(d.id);
    if (!mounted) return;
    if (exito) {
      _snack('Documento eliminado', _brown);
      _cargar();
    } else {
      _snack('No se pudo eliminar', Colors.red);
    }
  }

  Future<void> _abrirFormulario() async {
    final subido = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormDocumentoLegajo(svc: _svc!, empleadoId: widget.empleadoId),
    );
    if (subido == true) _cargar();
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
    final puedeGestionar = AppSession.i.isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombreEmpleado,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      floatingActionButton: puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: _abrirFormulario,
              backgroundColor: _brown,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.upload_file),
              label: const Text('Nuevo'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _brown))
          : _detalle == null
              ? const Center(child: Text('No se pudo cargar el legajo'))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  color: _brown,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                    children: [
                      _stats(_detalle!),
                      const SizedBox(height: 10),
                      _filtrosCategoria(),
                      const SizedBox(height: 8),
                      if (_documentosFiltrados.isEmpty)
                        _vacio()
                      else
                        for (final d in _documentosFiltrados) _card(d, puedeGestionar),
                    ],
                  ),
                ),
    );
  }

  Widget _stats(LegajoEmpleadoDetalle d) => Row(
        children: [
          Expanded(child: _statChip('Total', d.total, Colors.blueGrey)),
          const SizedBox(width: 8),
          Expanded(child: _statChip('Contratos', d.contratos, Colors.indigo)),
          const SizedBox(width: 8),
          Expanded(child: _statChip('Firmados', d.firmados, Colors.green)),
          const SizedBox(width: 8),
          Expanded(child: _statChip('Pendientes', d.pendientesFirma, Colors.orange)),
        ],
      );

  Widget _statChip(String label, int value, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$value', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      );

  Widget _filtrosCategoria() {
    const opciones = [
      ('', 'Todos'), ('contratos', 'Contratos'),
      ('certificaciones', 'Certificaciones'), ('otros', 'Otros'),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: opciones.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (val, label) = opciones[i];
          return ChoiceChip(
            label: Text(label),
            selected: _categoria == val,
            selectedColor: _brown.withValues(alpha: 0.25),
            onSelected: (_) => setState(() => _categoria = val),
          );
        },
      ),
    );
  }

  Widget _card(DocumentoLegajo d, bool puedeGestionar) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: () => abrirEnlace(d.urlArchivo),
          leading: CircleAvatar(
            backgroundColor: _brown.withValues(alpha: 0.15),
            child: const Icon(Icons.description_outlined, color: _brown),
          ),
          title: Text(d.nombre, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text('${d.tipo} · ${d.fechaTexto}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          trailing: puedeGestionar
              ? PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'eliminar') _eliminar(d);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                  ],
                )
              : null,
        ),
      );

  Widget _vacio() => Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(Icons.folder_open_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Sin documentos',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey)),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════
// Formulario de subida
// ══════════════════════════════════════════════════════════════════════════
class _FormDocumentoLegajo extends StatefulWidget {
  final LegajoService svc;
  final String empleadoId;
  const _FormDocumentoLegajo({required this.svc, required this.empleadoId});

  @override
  State<_FormDocumentoLegajo> createState() => _FormDocumentoLegajoState();
}

class _FormDocumentoLegajoState extends State<_FormDocumentoLegajo> {
  static const _brown = Color(0xFF8D6E63);

  String _tipo = 'Boleta Mensual';
  final _nombreCtrl = TextEditingController();
  DateTime? _fechaEmision;
  int _mes = DateTime.now().month;
  int _anio = DateTime.now().year;
  bool _requiereFirma = false;

  Uint8List? _archivoBytes;
  String? _archivoNombre;
  bool _guardando = false;

  bool get _esBoleta => _tipo == 'Boleta Mensual';
  bool get _esContrato => _tipo == 'Contrato';

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickArchivo() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true, type: FileType.custom, allowedExtensions: ['pdf'],
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    if (f.bytes == null) return;
    setState(() {
      _archivoBytes = f.bytes;
      _archivoNombre = f.name;
    });
  }

  Future<void> _pickFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fechaEmision ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _fechaEmision = d);
  }

  Future<void> _guardar() async {
    if (_archivoBytes == null) {
      _error('Selecciona un archivo PDF');
      return;
    }
    String nombre;
    String fechaEmisionStr;
    if (_esBoleta) {
      nombre = 'Boleta de Pago - ${_kMesesEs[_mes]} $_anio';
      fechaEmisionStr = '$_anio-${_mes.toString().padLeft(2, '0')}-01';
    } else {
      if (_nombreCtrl.text.trim().isEmpty) {
        _error('El nombre es obligatorio');
        return;
      }
      if (_fechaEmision == null) {
        _error('La fecha de emisión es obligatoria');
        return;
      }
      nombre = _nombreCtrl.text.trim();
      fechaEmisionStr =
          '${_fechaEmision!.year}-${_fechaEmision!.month.toString().padLeft(2, '0')}-${_fechaEmision!.day.toString().padLeft(2, '0')}';
    }

    setState(() => _guardando = true);
    final ok = await widget.svc.subirDocumento(
      widget.empleadoId,
      tipo: _tipo,
      nombre: nombre,
      fechaEmision: fechaEmisionStr,
      requiereFirma: _esContrato || _requiereFirma,
      mes: _esBoleta ? _mes : null,
      anio: _esBoleta ? _anio : null,
      archivoBytes: _archivoBytes!,
      archivoNombre: _archivoNombre!,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      _error('No se pudo subir el documento');
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final anios = List.generate(6, (i) => DateTime.now().year - i);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Nuevo documento',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
                items: _kTiposDocumentoLegajo
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _tipo = v ?? 'Boleta Mensual'),
              ),
              const SizedBox(height: 10),
              if (_esBoleta) ...[
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _mes,
                      decoration: const InputDecoration(labelText: 'Mes', isDense: true),
                      items: [
                        for (int m = 1; m <= 12; m++)
                          DropdownMenuItem(value: m, child: Text(_kMesesEs[m])),
                      ],
                      onChanged: (v) => setState(() => _mes = v ?? _mes),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _anio,
                      decoration: const InputDecoration(labelText: 'Año', isDense: true),
                      items: [
                        for (final a in anios) DropdownMenuItem(value: a, child: Text('$a')),
                      ],
                      onChanged: (v) => setState(() => _anio = v ?? _anio),
                    ),
                  ),
                ]),
              ] else ...[
                TextField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre *', isDense: true),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _pickFecha,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_fechaEmision != null
                        ? 'Fecha de emisión: ${_fechaEmision!.day}/${_fechaEmision!.month}/${_fechaEmision!.year}'
                        : 'Elegir fecha de emisión *'),
                  ),
                ),
                if (_esContrato)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Los contratos siempre requieren firma electrónica.',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  )
                else
                  CheckboxListTile(
                    value: _requiereFirma,
                    onChanged: (v) => setState(() => _requiereFirma = v ?? false),
                    title: const Text('Requiere firma del empleado', style: TextStyle(fontSize: 13)),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickArchivo,
                icon: const Icon(Icons.attach_file),
                label: Text(_archivoNombre ?? 'Adjuntar PDF',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  style: ElevatedButton.styleFrom(backgroundColor: _brown, foregroundColor: Colors.white),
                  child: _guardando
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Subir documento'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

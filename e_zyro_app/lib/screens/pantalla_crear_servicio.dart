import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';
import '../widgets/geo_cascade_picker.dart';

/// Crear o editar un servicio dentro de un proyecto.
/// Equivalente móvil del `crear-servicio-modal` del frontend.
class PantallaCrearServicio extends StatefulWidget {
  final ProyectoService service;
  final String proyectoId;
  final String mode; // 'crear' | 'editar'
  final String? servicioId;

  const PantallaCrearServicio({
    super.key,
    required this.service,
    required this.proyectoId,
    this.mode = 'crear',
    this.servicioId,
  });

  @override
  State<PantallaCrearServicio> createState() => _PantallaCrearServicioState();
}

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFE53935);

class _PantallaCrearServicioState extends State<PantallaCrearServicio> {
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _zona = TextEditingController();
  final _alcance = TextEditingController();
  final _nroDocumento = TextEditingController();

  List<CatalogoServicio> _catalogo = [];
  List<PersonaServicio> _lideres = [];
  List<PersonaServicio> _responsables = [];

  String? _catalogoId;
  String? _liderId;
  String? _responsableId;
  // Geografía del servicio (FK). El servicio posee ubicación/zona.
  GeoSeleccion _geo = const GeoSeleccion();
  String _tipoDoc = 'SIN_OC';
  String _estado = 'Pendiente';
  String? _fechaProgramada;
  String? _fechaInicio;
  String? _fechaFin;

  bool _inspeccionEquipos = false;
  bool _cargando = true;
  bool _guardando = false;
  String? _errorMsg;

  static const _estados = [
    'Pendiente',
    'En_Proceso',
    'Completado',
    'Cancelado',
  ];
  static const _tiposDoc = [
    ('OC', 'Orden de Compra (OC)'),
    ('PROF', 'Proforma'),
    ('SIN_OC', 'Sin OC'),
  ];

  bool get _esEditar => widget.mode == 'editar' && widget.servicioId != null;
  bool get _nroRequerido => _tipoDoc != 'SIN_OC';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _zona.dispose();
    _alcance.dispose();
    _nroDocumento.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final results = await Future.wait([
      widget.service.getCatalogoServicios(),
      widget.service.getLideresServicio(),
      widget.service.getResponsablesServicio(),
    ]);
    _catalogo = results[0] as List<CatalogoServicio>;
    _lideres = results[1] as List<PersonaServicio>;
    _responsables = results[2] as List<PersonaServicio>;

    if (_esEditar) {
      final s = await widget.service.getDetalleServicio(widget.servicioId!);
      if (s != null) {
        _nombre.text = s.tipoServicio;
        _descripcion.text = s.descripcion;
        _catalogoId = s.catalogoServicioId;
        _liderId = s.liderId;
        _responsableId = s.responsableId;
        _zona.text = s.zonaEjecucion ?? '';
        _geo = GeoSeleccion(ubicacionId: s.ubicacionId, zonaId: s.zonaId);
        _alcance.text = s.alcance ?? '';
        _tipoDoc = s.tipoDocumentoCliente ?? 'SIN_OC';
        _nroDocumento.text = s.nroDocumento ?? '';
        _estado = s.estado;
        _fechaProgramada = _soloFecha(s.fechaProgramada);
        _fechaInicio = _soloFecha(s.fechaInicio);
        _fechaFin = _soloFecha(s.fechaFin);
        _inspeccionEquipos = s.inspeccionEquiposActiva;
      }
    }
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  String? _soloFecha(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return iso.contains('T') ? iso.split('T').first : iso.trim();
  }

  Future<void> _pickFecha(String campo) async {
    final actual = switch (campo) {
      'prog' => _fechaProgramada,
      'inicio' => _fechaInicio,
      _ => _fechaFin,
    };
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(actual ?? '') ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      final str = DateFormat('yyyy-MM-dd').format(picked);
      switch (campo) {
        case 'prog':
          _fechaProgramada = str;
        case 'inicio':
          _fechaInicio = str;
        default:
          _fechaFin = str;
      }
    });
  }

  Future<void> _guardar() async {
    setState(() => _errorMsg = null);
    if (_nombre.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Indica el nombre del servicio.');
      return;
    }
    if (_catalogoId == null) {
      setState(() => _errorMsg = 'Selecciona el tipo de servicio (catálogo).');
      return;
    }
    if (_liderId == null) {
      setState(() => _errorMsg =
          'Selecciona el Líder del Servicio (Jefe de Operaciones o Proyecto).');
      return;
    }
    if (_fechaInicio != null &&
        _fechaFin != null &&
        _fechaFin!.compareTo(_fechaInicio!) < 0) {
      setState(() => _errorMsg = 'La fecha fin no puede ser anterior al inicio.');
      return;
    }
    if (_nroRequerido && _nroDocumento.text.trim().isEmpty) {
      setState(() =>
          _errorMsg = 'Indica el N° de documento para la OC/Proforma.');
      return;
    }

    setState(() => _guardando = true);
    final payload = {
      'nombre': _nombre.text.trim(),
      'catalogo_servicio_id': _catalogoId,
      'descripcion':
          _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
      'lider_id': _liderId,
      'responsable_id': _responsableId,
      'zona_ejecucion': _zona.text.trim().isEmpty ? null : _zona.text.trim(),
      'ubicacion_id': _geo.ubicacionId,
      'zona_id': _geo.zonaId,
      'alcance': _alcance.text.trim().isEmpty ? null : _alcance.text.trim(),
      'tipo_documento_cliente': _tipoDoc,
      'nro_documento': _tipoDoc == 'SIN_OC'
          ? null
          : (_nroDocumento.text.trim().isEmpty
              ? null
              : _nroDocumento.text.trim()),
      'estado': _estado,
      'tiene_equipos_intervenidos': _inspeccionEquipos,
      'fecha_programada': _fechaProgramada,
      'fecha_inicio': _fechaInicio,
      'fecha_fin': _fechaFin,
    };

    bool ok;
    if (_esEditar) {
      ok = await widget.service.actualizarServicio(widget.servicioId!, payload);
    } else {
      ok = (await widget.service.crearServicio(widget.proyectoId, payload)) !=
          null;
    }

    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _errorMsg = 'No se pudo guardar el servicio.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_esEditar ? 'Editar servicio' : 'Nuevo servicio',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_green)))
          : Column(
              children: [
                if (_errorMsg != null) _errorBanner(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _label('Nombre del servicio *'),
                      TextField(
                          controller: _nombre,
                          decoration: _dec('Ej. Mantenimiento de tablero')),
                      const SizedBox(height: 14),
                      _label('Tipo de servicio (catálogo) *'),
                      DropdownButtonFormField<String>(
                        initialValue: _catalogoId,
                        isExpanded: true,
                        decoration: _dec('Selecciona del catálogo'),
                        items: _catalogo
                            .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.nombre,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _catalogoId = v),
                      ),
                      const SizedBox(height: 14),
                      _label('Descripción'),
                      TextField(
                        controller: _descripcion,
                        maxLines: 3,
                        decoration: _dec('Detalle del trabajo'),
                      ),
                      const SizedBox(height: 14),
                      _label('Líder del servicio *'),
                      DropdownButtonFormField<String>(
                        initialValue:
                            _lideres.any((p) => p.id == _liderId) ? _liderId : null,
                        isExpanded: true,
                        decoration: _dec('Jefe de Operaciones / Proyecto'),
                        items: _lideres
                            .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.nombreCompleto,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _liderId = v),
                      ),
                      const SizedBox(height: 14),
                      _label('Técnico líder (opcional)'),
                      DropdownButtonFormField<String>(
                        initialValue: _responsables.any((p) => p.id == _responsableId)
                            ? _responsableId
                            : null,
                        isExpanded: true,
                        decoration: _dec('Selecciona (opcional)'),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('— Ninguno —')),
                          ..._responsables.map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.nombreCompleto,
                                  overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) => setState(() => _responsableId = v),
                      ),
                      const SizedBox(height: 14),
                      _label('Ubicación y zona de ejecución'),
                      GeoCascadePicker(
                        valor: _geo,
                        mostrarArea: false,
                        onChanged: (g) => setState(() => _geo = g),
                      ),
                      const SizedBox(height: 14),
                      _label('Alcance'),
                      TextField(
                        controller: _alcance,
                        maxLines: 3,
                        decoration: _dec('Alcance del servicio'),
                      ),
                      const SizedBox(height: 14),
                      _label('Documento del cliente'),
                      DropdownButtonFormField<String>(
                        initialValue: _tipoDoc,
                        isExpanded: true,
                        decoration: _dec(''),
                        items: _tiposDoc
                            .map((t) => DropdownMenuItem(
                                value: t.$1, child: Text(t.$2)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _tipoDoc = v ?? 'SIN_OC';
                          if (_tipoDoc == 'SIN_OC') _nroDocumento.clear();
                        }),
                      ),
                      if (_nroRequerido) ...[
                        const SizedBox(height: 10),
                        _label('N° de documento *'),
                        TextField(
                            controller: _nroDocumento,
                            decoration: _dec('N° de OC / Proforma')),
                      ],
                      const SizedBox(height: 14),
                      _label('Estado'),
                      DropdownButtonFormField<String>(
                        initialValue: _estado,
                        isExpanded: true,
                        decoration: _dec(''),
                        items: _estados
                            .map((e) => DropdownMenuItem(
                                value: e, child: Text(_estadoLabel(e))))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _estado = v ?? 'Pendiente'),
                      ),
                      const SizedBox(height: 14),
                      _fechaField('Fecha programada', _fechaProgramada,
                          () => _pickFecha('prog')),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: _fechaField('Fecha inicio', _fechaInicio,
                                  () => _pickFecha('inicio'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _fechaField('Fecha fin', _fechaFin,
                                  () => _pickFecha('fin'))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // ── Toggle Inspección de Equipos ──────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _inspeccionEquipos
                              ? _green.withValues(alpha: 0.08)
                              : Colors.grey.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _inspeccionEquipos
                                ? _green.withValues(alpha: 0.35)
                                : Colors.grey.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.electrical_services_outlined,
                                size: 20, color: _green),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Inspección de Equipos',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Activa la sección para intervenir activos del cliente en este servicio.',
                                    style: TextStyle(
                                        fontSize: 11.5, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _inspeccionEquipos,
                              onChanged: (v) =>
                                  setState(() => _inspeccionEquipos = v),
                              activeThumbColor: _green,
                              activeTrackColor: _green.withValues(alpha: 0.35),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _bottomSave(),
              ],
            ),
    );
  }

  // ── Helpers de UI ─────────────────────────────────────────────────────────

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _fechaField(String label, String? value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration: _dec(''),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14),
                const SizedBox(width: 6),
                Text(value ?? 'Elegir',
                    style: TextStyle(
                        fontSize: 13,
                        color: value == null ? Colors.grey : null)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _estadoLabel(String e) => e == 'En_Proceso' ? 'En Proceso' : e;

  Widget _errorBanner() => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: _danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_errorMsg!,
                    style: const TextStyle(color: _danger, fontSize: 12.5))),
          ],
        ),
      );

  Widget _bottomSave() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _guardando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_esEditar ? 'Guardar cambios' : 'Crear servicio',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
}

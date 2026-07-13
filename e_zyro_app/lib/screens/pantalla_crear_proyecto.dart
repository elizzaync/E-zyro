import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';

/// Crear o editar un proyecto. El N° de Orden de Trabajo lo asigna el backend
/// (correlativo por año); aquí se muestra como solo-lectura.
/// Equivalente móvil del `crear-proyecto-modal` del frontend.
class PantallaCrearProyecto extends StatefulWidget {
  final ProyectoService service;
  final String mode; // 'crear' | 'editar'
  final String? proyectoId;

  const PantallaCrearProyecto({
    super.key,
    required this.service,
    this.mode = 'crear',
    this.proyectoId,
  });

  @override
  State<PantallaCrearProyecto> createState() => _PantallaCrearProyectoState();
}

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFD6584F);

class _PantallaCrearProyectoState extends State<PantallaCrearProyecto> {
  final _nombre = TextEditingController();
  final _ordenCompra = TextEditingController();

  List<ClienteBasico> _clientes = [];
  String? _clienteId;
  String _estado = 'Pendiente';
  String _ordenTrabajo = '';
  String? _fechaInicio;
  String? _fechaFinEstimada;

  bool _cargando = true;
  bool _guardando = false;
  String? _errorMsg;

  static const _estados = [
    'Pendiente',
    'En_Proceso',
    'En_Pausa',
    'Completado',
    'Cancelado',
  ];

  bool get _esEditar => widget.mode == 'editar' && widget.proyectoId != null;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _ordenCompra.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    _clientes = await widget.service.getClientes();

    if (_esEditar) {
      final p = await widget.service.getDetalleProyecto(widget.proyectoId!);
      if (p != null) {
        _nombre.text = p.nombreProyecto;
        _clienteId = p.clienteId.isNotEmpty ? p.clienteId : null;
        _estado = p.estado;
        _ordenTrabajo = p.ordenTrabajo;
        _fechaInicio = _soloFecha(p.fechaInicio);
        _fechaFinEstimada = _soloFecha(p.fechaFinEstimada);
        _ordenCompra.text = p.ordenCompraCliente ?? '';
      }
    } else {
      _ordenTrabajo = await widget.service.getSiguienteOrden() ?? '(automático)';
    }
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  String? _soloFecha(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return iso.contains('T') ? iso.split('T').first : iso.trim();
  }

  Future<void> _pickFecha(bool inicio) async {
    final base =
        DateTime.tryParse((inicio ? _fechaInicio : _fechaFinEstimada) ?? '') ??
            DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      final str = DateFormat('yyyy-MM-dd').format(picked);
      if (inicio) {
        _fechaInicio = str;
      } else {
        _fechaFinEstimada = str;
      }
    });
  }

  Future<void> _guardar() async {
    setState(() => _errorMsg = null);
    if (_nombre.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Indica el nombre del proyecto.');
      return;
    }
    if (_clienteId == null) {
      setState(() => _errorMsg = 'Selecciona un cliente.');
      return;
    }
    if (_fechaInicio != null &&
        _fechaFinEstimada != null &&
        _fechaFinEstimada!.compareTo(_fechaInicio!) < 0) {
      setState(() => _errorMsg = 'La fecha fin no puede ser anterior al inicio.');
      return;
    }

    setState(() => _guardando = true);
    final payload = {
      'nombre_proyecto': _nombre.text.trim(),
      'cliente_id': _clienteId,
      'estado': _estado,
      'fecha_inicio': _fechaInicio,
      'fecha_fin_estimada': _fechaFinEstimada,
      'orden_compra_cliente':
          _ordenCompra.text.trim().isEmpty ? null : _ordenCompra.text.trim(),
    };

    bool ok;
    if (_esEditar) {
      ok = await widget.service.actualizarProyecto(widget.proyectoId!, payload);
    } else {
      ok = (await widget.service.crearProyecto(payload)) != null;
    }

    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _errorMsg = 'No se pudo guardar. Verifica los datos.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_esEditar ? 'Editar proyecto' : 'Nuevo proyecto',
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
                if (_errorMsg != null) _ErrorBanner(msg: _errorMsg!),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _label('Nombre del proyecto *'),
                      TextField(
                        controller: _nombre,
                        decoration: _dec('Ej. Mantenimiento anual Sede Norte'),
                      ),
                      const SizedBox(height: 14),
                      _label('Cliente *'),
                      DropdownButtonFormField<String>(
                        initialValue: _clienteId,
                        isExpanded: true,
                        decoration: _dec('Selecciona un cliente'),
                        items: _clientes
                            .map((c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.razonSocial,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _clienteId = v),
                      ),
                      const SizedBox(height: 14),
                      _label('N° Orden de Trabajo'),
                      TextField(
                        enabled: false,
                        decoration: _dec('').copyWith(
                          hintText: _ordenTrabajo,
                          suffixIcon: const Icon(Icons.lock_outline, size: 16),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('Lo asigna el sistema automáticamente.',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
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
                      Row(
                        children: [
                          Expanded(
                            child: _fechaField(
                                'Fecha inicio', _fechaInicio, () => _pickFecha(true)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _fechaField('Fecha fin estimada',
                                _fechaFinEstimada, () => _pickFecha(false)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _label('Orden de compra del cliente (opcional)'),
                      TextField(
                        controller: _ordenCompra,
                        decoration: _dec('OC marco del proyecto'),
                      ),
                    ],
                  ),
                ),
                _BottomSave(
                  guardando: _guardando,
                  label: _esEditar ? 'Guardar cambios' : 'Crear proyecto',
                  onTap: _guardar,
                ),
              ],
            ),
    );
  }

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

  String _estadoLabel(String e) => switch (e) {
        'En_Proceso' => 'En Proceso',
        'En_Pausa' => 'En Pausa',
        _ => e,
      };
}

// ── Widgets compartidos ────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String msg;
  const _ErrorBanner({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              child: Text(msg,
                  style: const TextStyle(color: _danger, fontSize: 12.5))),
        ],
      ),
    );
  }
}

class _BottomSave extends StatelessWidget {
  final bool guardando;
  final String label;
  final VoidCallback onTap;

  const _BottomSave({
    required this.guardando,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
            onPressed: guardando ? null : onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: guardando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

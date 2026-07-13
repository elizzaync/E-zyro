import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../models/garantia_models.dart';
import '../models/proyecto_models.dart' show ClienteBasico;
import '../services/garantia_service.dart';
import '../utils/app_session.dart';

/// Repositorio central de garantías: todas las cartas de garantía generadas
/// (post-servicio) + manuales, con filtros y apertura del PDF. Punto final de
/// la documentación de garantías del servicio.
class PantallaGarantias extends StatefulWidget {
  /// Cuando va embebida en una pestaña, se oculta su AppBar propia.
  final bool showAppBar;
  const PantallaGarantias({super.key, this.showAppBar = true});

  @override
  State<PantallaGarantias> createState() => _PantallaGarantiasState();
}

class _PantallaGarantiasState extends State<PantallaGarantias> {
  static const _green = Color(0xFF8FD11B);

  GarantiaService? _svc;
  List<Garantia> _items = [];
  List<ClienteBasico> _clientes = [];
  bool _cargando = true;

  String _filtroEstado = '';
  String _filtroCliente = '';
  String _busqueda = '';

  static const _estados = {
    '': 'Todas',
    'vigente': 'Vigentes',
    'por_vencer': 'Por vencer',
    'vencida': 'Vencidas',
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = GarantiaService(ApiClient(prefs));
    _clientes = await _svc!.getClientes();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() => _cargando = true);
    final items = await _svc!.getGarantias(
      estado: _filtroEstado,
      clienteId: _filtroCliente,
      q: _busqueda,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _cargando = false;
    });
  }

  ({Color color, String label}) _estadoUi(Garantia g) {
    switch (g.estado) {
      case 'vencida':
        return (color: const Color(0xFFD6584F), label: 'Vencida');
      case 'por_vencer':
        return (
          color: const Color(0xFFD98A16),
          label: g.diasParaVencer != null ? 'Vence en ${g.diasParaVencer}d' : 'Por vencer'
        );
      case 'vigente':
        return (color: _green, label: 'Vigente');
      default:
        return (color: Colors.grey, label: 'Sin fecha');
    }
  }

  Future<void> _abrir(Garantia g) async {
    if (!g.tienePdf) {
      _snack('Esta garantía no tiene PDF.', Colors.grey);
      return;
    }
    final ok = await launchUrl(Uri.parse(g.documentoPdfUrl!),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('No se pudo abrir el PDF.', Colors.red);
  }

  Future<void> _eliminar(Garantia g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar garantía'),
        content: Text('¿Eliminar la garantía de «${g.nombreCliente}»?'),
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
    final exito = await _svc!.eliminar(g.id);
    if (!mounted) return;
    if (exito) {
      _snack('Garantía eliminada', _green);
      _cargar();
    } else {
      _snack('No se pudo eliminar', Colors.red);
    }
  }

  Future<void> _subirManual() async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormGarantiaManual(svc: _svc!, clientes: _clientes),
    );
    if (guardado == true) _cargar();
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
    final puedeSubir = AppSession.i.hasPerm('correctivo:crear');
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Garantías',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
            )
          : null,
      floatingActionButton: puedeSubir
          ? FloatingActionButton.extended(
              onPressed: _subirManual,
              backgroundColor: _green,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.upload_file),
              label: const Text('Subir'),
            )
          : null,
      body: Column(
        children: [
          _buscador(),
          _filtrosEstado(),
          if (_clientes.isNotEmpty) _filtroClienteWidget(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _items.isEmpty
                    ? _vacio()
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        color: _green,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _card(_items[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buscador() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Buscar por cliente, servicio o proyecto…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            _busqueda = v;
            _cargar();
          },
        ),
      );

  Widget _filtrosEstado() {
    final keys = _estados.keys.toList();
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: keys.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final k = keys[i];
          return ChoiceChip(
            label: Text(_estados[k]!),
            selected: _filtroEstado == k,
            selectedColor: _green.withValues(alpha: 0.25),
            onSelected: (_) {
              setState(() => _filtroEstado = k);
              _cargar();
            },
          );
        },
      ),
    );
  }

  Widget _filtroClienteWidget() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: DropdownButtonFormField<String>(
          initialValue: _filtroCliente,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Cliente',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Todos los clientes')),
            ..._clientes.map((c) =>
                DropdownMenuItem(value: c.id, child: Text(c.razonSocial))),
          ],
          onChanged: (v) {
            setState(() => _filtroCliente = v ?? '');
            _cargar();
          },
        ),
      );

  Widget _card(Garantia g) {
    final est = _estadoUi(g);
    final puedeEliminar = AppSession.i.hasPerm('correctivo:editar');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: () => _abrir(g),
        leading: CircleAvatar(
          backgroundColor: est.color.withValues(alpha: 0.15),
          child: Icon(
            g.tienePdf ? Icons.workspace_premium_outlined : Icons.shield_outlined,
            color: est.color,
          ),
        ),
        title: Text(g.nombreCliente,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if ((g.servicioNombre ?? '').isNotEmpty || (g.proyectoNombre ?? '').isNotEmpty)
              Text(
                [g.proyectoNombre, g.servicioNombre].where((e) => (e ?? '').isNotEmpty).join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _chip(est.label, est.color),
              if (g.vigenciaGarantia != null)
                Text('Vence: ${g.vigenciaGarantia}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ],
        ),
        trailing: puedeEliminar
            ? PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'abrir') _abrir(g);
                  if (v == 'eliminar') _eliminar(g);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'abrir', child: Text('Abrir PDF')),
                  const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                ],
              )
            : const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _vacio() => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.workspace_premium_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Center(
            child: Text('Sin garantías',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey)),
          ),
        ],
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Formulario de subida manual
// ══════════════════════════════════════════════════════════════════════════════
class _FormGarantiaManual extends StatefulWidget {
  final GarantiaService svc;
  final List<ClienteBasico> clientes;
  const _FormGarantiaManual({required this.svc, required this.clientes});

  @override
  State<_FormGarantiaManual> createState() => _FormGarantiaManualState();
}

class _FormGarantiaManualState extends State<_FormGarantiaManual> {
  static const _green = Color(0xFF8FD11B);

  final _razon = TextEditingController();
  final _lugar = TextEditingController();
  String? _clienteId;
  DateTime? _fechaOperatividad;
  DateTime? _vigencia;
  String? _archivoBase64;
  String? _archivoNombre;
  bool _guardando = false;

  @override
  void dispose() {
    _razon.dispose();
    _lugar.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _pickArchivo() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    if (f.bytes == null) return;
    setState(() {
      _archivoBase64 = base64Encode(f.bytes!);
      _archivoNombre = f.name;
    });
  }

  Future<void> _pickFecha(bool operatividad) async {
    final base = (operatividad ? _fechaOperatividad : _vigencia) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (operatividad) {
        _fechaOperatividad = d;
      } else {
        _vigencia = d;
      }
    });
  }

  Future<void> _guardar() async {
    if (_archivoBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Adjunta el PDF de la garantía'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _guardando = true);
    final ok = await widget.svc.crearManual(
      archivoBase64: _archivoBase64!,
      archivoNombre: _archivoNombre,
      razonSocial: _razon.text.trim().isEmpty ? null : _razon.text.trim(),
      clienteId: _clienteId,
      lugar: _lugar.text.trim().isEmpty ? null : _lugar.text.trim(),
      fechaOperatividad: _fechaOperatividad != null ? _iso(_fechaOperatividad!) : null,
      vigenciaGarantia: _vigencia != null ? _iso(_vigencia!) : null,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo subir la garantía'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
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
              const Text('Subir garantía',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _clienteId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cliente', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Sin cliente —')),
                  ...widget.clientes.map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.razonSocial))),
                ],
                onChanged: (v) => setState(() => _clienteId = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _razon,
                decoration: const InputDecoration(
                    labelText: 'Razón social (si no eliges cliente)', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lugar,
                decoration: const InputDecoration(labelText: 'Lugar', isDense: true),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _fechaBtn('Operatividad', _fechaOperatividad, () => _pickFecha(true))),
                const SizedBox(width: 10),
                Expanded(child: _fechaBtn('Vence', _vigencia, () => _pickFecha(false))),
              ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickArchivo,
                icon: const Icon(Icons.attach_file),
                label: Text(_archivoNombre ?? 'Adjuntar PDF de garantía',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _green, foregroundColor: Colors.white),
                  child: _guardando
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Subir garantía'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fechaBtn(String label, DateTime? value, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(value != null ? _iso(value) : '—',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

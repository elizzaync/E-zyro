import 'package:flutter/material.dart';

import '../models/correctivo_models.dart';
import '../models/proyecto_models.dart';
import '../services/correctivo_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../utils/abrir_enlace.dart';
import '../utils/app_session.dart';

/// Garantías/Correctivos (Fase 4). Lista global con su estado y transiciones.
/// El alta se hace desde el detalle de un servicio (servicio_id requerido).
class PantallaCorrectivos extends StatefulWidget {
  final String? servicioId;
  /// Cuando va embebida en una pestaña, se oculta su AppBar propia.
  final bool showAppBar;
  const PantallaCorrectivos({super.key, this.servicioId, this.showAppBar = true});

  @override
  State<PantallaCorrectivos> createState() => _PantallaCorrectivosState();
}

class _PantallaCorrectivosState extends State<PantallaCorrectivos> {
  CorrectivoService? _svc;
  List<Correctivo> _items = [];
  bool _cargando = true;
  String? _error;

  static const _siguientes = {
    'registrado': 'en_proceso',
    'en_proceso': 'en_revision',
    'en_revision': 'aprobado',
    'aprobado': 'finalizado',
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getCorrectivoService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = await _svc!.listar(servicioId: widget.servicioId);
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

  Future<void> _avanzar(Correctivo c) async {
    final destino = c.estado == 'aprobado' ? 'finalizado' : _siguientes[c.estado];
    if (destino == null) return;
    final res = await _svc!.transicionar(c.id, destino);
    if (!mounted) return;
    if (res.ok) {
      _cargar();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.errorMessage), backgroundColor: Colors.red.shade700));
    }
  }

  Future<void> _informe(Correctivo c) async {
    final res = await _svc!.generarInforme(c.id);
    if (!mounted) return;
    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe generado')));
      await abrirEnlace(res.data);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorMessage), backgroundColor: Colors.red.shade700));
    }
  }

  void _msg(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _nuevoCorrectivo() async {
    final proy = await getProyectoService();
    final data = await proy.getProyectos();
    if (!mounted) return;
    final proyectos = data?.proyectos ?? [];
    if (proyectos.isEmpty) {
      _msg('No hay proyectos', error: true);
      return;
    }
    String? proyectoId;
    String? servicioId;
    List<ServicioItem> servicios = [];
    bool cargandoServ = false;
    final alcance = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nuevo correctivo'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: proyectoId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Proyecto'),
              items: proyectos.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nombreProyecto, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) async {
                setLocal(() {
                  proyectoId = v;
                  servicioId = null;
                  servicios = [];
                  cargandoServ = true;
                });
                final s = await proy.getServiciosProyecto(v ?? '');
                setLocal(() {
                  servicios = s;
                  cargandoServ = false;
                });
              },
            ),
            if (cargandoServ) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            DropdownButtonFormField<String>(
              initialValue: servicioId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Servicio'),
              items: servicios.map((s) => DropdownMenuItem(value: s.id, child: Text(s.nombre, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setLocal(() => servicioId = v),
            ),
            TextField(controller: alcance, decoration: const InputDecoration(labelText: 'Alcance')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
          ],
        ),
      ),
    );
    if (ok != true || servicioId == null) {
      if (ok == true) _msg('Selecciona un servicio', error: true);
      return;
    }
    final res = await _svc!.crear(servicioId: servicioId!, alcance: alcance.text);
    if (!mounted) return;
    res.ok ? _cargar() : _msg(res.errorMessage, error: true);
  }

  Color _colorEstado(String estado) => switch (estado) {
        'finalizado' => Colors.green,
        'aprobado' => Colors.teal,
        'desaprobado' => Colors.red,
        'anulado' => Colors.grey,
        'en_revision' => Colors.orange,
        _ => Colors.blueGrey,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Garantías / Correctivos',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
            )
          : null,
      floatingActionButton: AppSession.i.canCrearCorrectivo
          ? FloatingActionButton.extended(
              onPressed: _nuevoCorrectivo, icon: const Icon(Icons.add), label: const Text('Nuevo'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('Sin correctivos.'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: bottomSafePadding(context, extra: 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _items[i];
                          final puedeAvanzar = _siguientes.containsKey(c.estado) &&
                              (AppSession.i.canAprobarCorrectivo ||
                                  AppSession.i.canFinalizarCorrectivo);
                          return ListTile(
                            leading: const Icon(Icons.build_outlined),
                            title: Text(c.codigo ?? c.id),
                            subtitle: Text(c.alcance ?? 'Sin alcance'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text(c.estado, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                  backgroundColor: _colorEstado(c.estado),
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                                  tooltip: 'Generar informe (PDF)',
                                  onPressed: () => _informe(c),
                                ),
                                if (puedeAvanzar)
                                  IconButton(
                                    icon: const Icon(Icons.arrow_forward),
                                    tooltip: 'Avanzar estado',
                                    onPressed: () => _avanzar(c),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

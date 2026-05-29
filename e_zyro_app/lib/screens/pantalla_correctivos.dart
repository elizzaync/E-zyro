import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/correctivo_models.dart';
import '../services/correctivo_service.dart';
import '../utils/api_provider.dart';

/// Garantías/Correctivos (Fase 4). Lista global con su estado y transiciones.
/// El alta se hace desde el detalle de un servicio (servicio_id requerido).
class PantallaCorrectivos extends StatefulWidget {
  final String? servicioId;
  const PantallaCorrectivos({super.key, this.servicioId});

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
      Clipboard.setData(ClipboardData(text: res.data ?? ''));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe generado · enlace copiado')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorMessage), backgroundColor: Colors.red.shade700));
    }
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
      appBar: AppBar(
        title: const Text('Garantías / Correctivos', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('Sin correctivos.'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _items[i];
                          final puedeAvanzar = _siguientes.containsKey(c.estado);
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

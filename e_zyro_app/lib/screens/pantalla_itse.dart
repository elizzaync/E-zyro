import 'package:flutter/material.dart';

import '../models/itse_models.dart';
import '../services/itse_service.dart';
import '../utils/api_provider.dart';

/// Inspección ITSE (Fase 5). Lista + alta de inspección (borrador).
/// El detalle (tableros/ítems/fotos/finalizar) se construye sobre esta base.
class PantallaItse extends StatefulWidget {
  const PantallaItse({super.key});

  @override
  State<PantallaItse> createState() => _PantallaItseState();
}

class _PantallaItseState extends State<PantallaItse> {
  ItseService? _svc;
  List<InspeccionItse> _items = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getItseService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = await _svc!.listar();
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

  Future<void> _nueva() async {
    String modo = 'tablero';
    final obsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nueva inspección ITSE'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: modo,
                decoration: const InputDecoration(labelText: 'Modo'),
                items: const [
                  DropdownMenuItem(value: 'tablero', child: Text('Por tablero')),
                  DropdownMenuItem(value: 'zona', child: Text('Por zona')),
                ],
                onChanged: (v) => setLocal(() => modo = v ?? 'tablero'),
              ),
              TextField(controller: obsCtrl, decoration: const InputDecoration(labelText: 'Observaciones (opcional)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final res = await _svc!.crear(modo: modo, observaciones: obsCtrl.text);
    if (!mounted) return;
    if (res.ok) {
      _cargar();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.errorMessage), backgroundColor: Colors.red.shade700));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspección ITSE', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nueva, icon: const Icon(Icons.add), label: const Text('Nueva'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('Sin inspecciones.'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final it = _items[i];
                          return ListTile(
                            leading: Icon(it.modo == 'zona' ? Icons.map_outlined : Icons.dashboard_outlined),
                            title: Text('Inspección ${it.modo} · ${it.fecha ?? ''}'),
                            subtitle: Text(it.observaciones ?? 'Sin observaciones'),
                            trailing: Chip(label: Text(it.estado, style: const TextStyle(fontSize: 11))),
                          );
                        },
                      ),
                    ),
    );
  }
}

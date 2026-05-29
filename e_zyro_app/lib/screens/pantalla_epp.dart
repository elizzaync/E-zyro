import 'package:flutter/material.dart';

import '../models/epp_models.dart';
import '../services/epp_service.dart';
import '../utils/api_provider.dart';
import '../utils/abrir_enlace.dart';
import '../utils/app_session.dart';
import 'pantalla_epp_entrega.dart';

/// EPP — Equipos de Protección Personal (Fase 2).
/// Tabs: Catálogo (stock + alta) e Historial de entregas.
class PantallaEpp extends StatefulWidget {
  const PantallaEpp({super.key});

  @override
  State<PantallaEpp> createState() => _PantallaEppState();
}

class _PantallaEppState extends State<PantallaEpp> {
  EppService? _svc;
  List<Epp> _catalogo = [];
  List<EppEntrega> _entregas = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getEppService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final cat = await _svc!.listar();
    final ent = await _svc!.listarEntregas();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (cat.ok) {
        _catalogo = cat.data ?? [];
      } else {
        _error = cat.errorMessage;
      }
      if (ent.ok) _entregas = ent.data ?? [];
    });
  }

  Future<void> _nuevoEpp() async {
    final nombreCtrl = TextEditingController();
    final stockMinCtrl = TextEditingController(text: '0');
    final precioCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo EPP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: stockMinCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock mínimo')),
            TextField(controller: precioCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio (opcional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || nombreCtrl.text.trim().isEmpty) return;
    final res = await _svc!.crear(
      nombre: nombreCtrl.text.trim(),
      stockMin: int.tryParse(stockMinCtrl.text) ?? 0,
      precio: double.tryParse(precioCtrl.text),
    );
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('EPP', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Catálogo'), Tab(text: 'Entregas')]),
          actions: [
            if (AppSession.i.canEntregarEpp)
              IconButton(
                icon: const Icon(Icons.assignment_add),
                tooltip: 'Nueva entrega',
                onPressed: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaEppEntrega()),
                  );
                  if (ok == true) _cargar();
                },
              ),
            IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
          ],
        ),
        floatingActionButton: AppSession.i.canCrearEpp
            ? FloatingActionButton.extended(
                onPressed: _nuevoEpp,
                icon: const Icon(Icons.add),
                label: const Text('Nuevo EPP'),
              )
            : null,
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_catalogoTab(), _entregasTab()]),
      ),
    );
  }

  Widget _catalogoTab() {
    if (_catalogo.isEmpty) {
      return const Center(child: Text('Sin EPP. Toca "Nuevo EPP".'));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _catalogo.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = _catalogo[i];
          return ListTile(
            leading: const Icon(Icons.health_and_safety_outlined),
            title: Text(e.nombre),
            subtitle: Text(e.descripcion ?? ''),
            trailing: Chip(
              label: Text('Stock ${e.stockActual}'),
              backgroundColor: e.stockBajo ? Colors.red.shade100 : Colors.green.shade100,
            ),
          );
        },
      ),
    );
  }

  Future<void> _constancia(EppEntrega en) async {
    final res = await _svc!.generarConstancia(en.id);
    if (!mounted) return;
    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Constancia generada')));
      await abrirEnlace(res.data);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorMessage), backgroundColor: Colors.red.shade700));
    }
  }

  Widget _entregasTab() {
    if (_entregas.isEmpty) {
      return const Center(child: Text('Sin entregas registradas.'));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _entregas.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final en = _entregas[i];
          final resumen = en.items.map((it) => '${it.nombre} x${it.cantidad}').join(', ');
          return ListTile(
            leading: Icon(en.estado == 'anulada' ? Icons.cancel_outlined : Icons.assignment_turned_in_outlined),
            title: Text(resumen.isEmpty ? '(sin ítems)' : resumen),
            subtitle: Text('Fecha: ${en.fecha ?? '-'} · ${en.estado}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (en.firmaUrl != null) const Icon(Icons.draw_outlined, size: 18),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                  tooltip: 'Generar constancia (PDF)',
                  onPressed: () => _constancia(en),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

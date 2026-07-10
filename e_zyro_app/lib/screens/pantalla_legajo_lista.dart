import 'package:flutter/material.dart';

import '../models/legajo_models.dart';
import '../services/legajo_service.dart';
import '../utils/api_provider.dart';
import 'pantalla_legajo_detalle.dart';

/// Legajo Digital — lista de empleados de la empresa con conteo de
/// documentos, para que RR.HH./admin entre al detalle de cada uno.
class PantallaLegajoLista extends StatefulWidget {
  const PantallaLegajoLista({super.key});

  @override
  State<PantallaLegajoLista> createState() => _PantallaLegajoListaState();
}

class _PantallaLegajoListaState extends State<PantallaLegajoLista> {
  static const _brown = Color(0xFF8D6E63);

  LegajoService? _svc;
  List<LegajoEmpleadoResumen> _empleados = [];
  bool _cargando = true;
  int _page = 1;
  int _totalPaginas = 1;
  String _busqueda = '';

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
    final r = await _svc!.getEmpleados(page: _page);
    if (!mounted) return;
    setState(() {
      _empleados = r.empleados;
      _totalPaginas = r.totalPaginas;
      _cargando = false;
    });
  }

  List<LegajoEmpleadoResumen> get _filtrados {
    if (_busqueda.trim().isEmpty) return _empleados;
    final q = _busqueda.trim().toLowerCase();
    return _empleados.where((e) =>
        e.nombreCompleto.toLowerCase().contains(q) ||
        e.cargo.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documentos (Legajo Digital)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o cargo…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _busqueda = v),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: _brown))
                : _filtrados.isEmpty
                    ? _vacio()
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        color: _brown,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemCount: _filtrados.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _card(_filtrados[i]),
                        ),
                      ),
          ),
          if (_totalPaginas > 1) _paginacion(),
        ],
      ),
    );
  }

  Widget _card(LegajoEmpleadoResumen e) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PantallaLegajoDetalle(
                empleadoId: e.id, nombreEmpleado: e.nombreCompleto,
              ),
            ),
          ).then((_) => _cargar()),
          leading: CircleAvatar(
            backgroundColor: _brown.withValues(alpha: 0.15),
            child: Text(e.iniciales,
                style: const TextStyle(color: _brown, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          title: Text(e.nombreCompleto,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text('${e.cargo}${e.area.isNotEmpty ? " · ${e.area}" : ""}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 2),
              Text('Última actualización: ${e.ultimaActualizacion}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _brown.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${e.documentosCount} docs',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _brown)),
          ),
        ),
      );

  Widget _paginacion() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _page > 1
                  ? () {
                      setState(() => _page--);
                      _cargar();
                    }
                  : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Anterior'),
            ),
            Text('$_page / $_totalPaginas', style: const TextStyle(fontSize: 12)),
            TextButton.icon(
              onPressed: _page < _totalPaginas
                  ? () {
                      setState(() => _page++);
                      _cargar();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Siguiente'),
            ),
          ],
        ),
      );

  Widget _vacio() => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.folder_shared_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Center(
            child: Text('Sin empleados',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey)),
          ),
        ],
      );
}

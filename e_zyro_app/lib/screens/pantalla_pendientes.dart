import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';

/// Bandeja unificada "Mis pendientes": todo lo que espera acción del usuario
/// (requerimientos, cobros/pagos por vencer, vacaciones, solicitudes), en una
/// sola vista. El backend filtra las secciones según los permisos del usuario.
class PantallaPendientes extends StatefulWidget {
  const PantallaPendientes({super.key});
  @override
  State<PantallaPendientes> createState() => _PantallaPendientesState();
}

class _Seccion {
  final String id, titulo;
  final int total;
  final List<_Item> items;
  _Seccion(this.id, this.titulo, this.total, this.items);

  factory _Seccion.fromJson(Map<String, dynamic> j) => _Seccion(
        j['id'].toString(),
        j['titulo'].toString(),
        (j['total'] as num?)?.toInt() ?? 0,
        (j['items'] as List? ?? [])
            .map((e) => _Item.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class _Item {
  final String id, titulo;
  final String? subtitulo, fecha;
  _Item(this.id, this.titulo, this.subtitulo, this.fecha);

  factory _Item.fromJson(Map<String, dynamic> j) => _Item(
        j['id'].toString(),
        j['titulo'].toString(),
        j['subtitulo']?.toString(),
        j['fecha']?.toString(),
      );
}

const _iconos = <String, IconData>{
  'requerimientos': Icons.inventory_2_outlined,
  'cxc_vencer': Icons.point_of_sale_outlined,
  'cxp_vencer': Icons.shopping_cart_outlined,
  'vacaciones': Icons.beach_access_outlined,
  'solicitudes': Icons.article_outlined,
};

const _colores = <String, Color>{
  'requerimientos': Colors.indigo,
  'cxc_vencer': Colors.teal,
  'cxp_vencer': Colors.deepOrange,
  'vacaciones': Colors.blue,
  'solicitudes': Colors.purple,
};

class _PantallaPendientesState extends State<PantallaPendientes> {
  List<_Seccion> _secciones = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = await ApiClient(prefs).get('/pendientes');
      if (!mounted) return;
      setState(() {
        _cargando = false;
        if (r.statusCode == 200) {
          _secciones = (jsonDecode(r.body) as List)
              .map((e) => _Seccion.fromJson(e as Map<String, dynamic>))
              .toList();
        } else {
          _error = 'Error ${r.statusCode} al cargar pendientes';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'Sin conexión'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis pendientes',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _secciones.isEmpty
                  ? const _TodoAlDia()
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          for (final s in _secciones) _seccion(s),
                        ],
                      ),
                    ),
    );
  }

  Widget _seccion(_Seccion s) {
    final color = _colores[s.id] ?? Colors.blueGrey;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 17,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(_iconos[s.id] ?? Icons.pending_actions,
                    color: color, size: 19),
              ),
              title: Text(s.titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${s.total}',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            for (final it in s.items)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(it.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5)),
                subtitle: it.subtitulo == null
                    ? null
                    : Text(it.subtitulo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                trailing: it.fecha == null
                    ? null
                    : Text(it.fecha!,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            if (s.total > s.items.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('… y ${s.total - s.items.length} más',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodoAlDia extends StatelessWidget {
  const _TodoAlDia();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.task_alt, size: 64, color: Colors.green.shade400),
          const SizedBox(height: 14),
          const Text('Todo al día',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('No tienes pendientes que requieran tu acción.',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }
}

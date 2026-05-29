import 'package:flutter/material.dart';

import '../models/informe_servicio_models.dart';
import '../services/informe_servicio_service.dart';
import '../utils/api_provider.dart';
import '../utils/abrir_enlace.dart';

/// Informes de un servicio: pre-informe (estado actual) e informe final (al cerrar).
class PantallaInformesServicio extends StatefulWidget {
  final String servicioId;
  final String estado;
  const PantallaInformesServicio({super.key, required this.servicioId, this.estado = ''});

  @override
  State<PantallaInformesServicio> createState() => _PantallaInformesServicioState();
}

class _PantallaInformesServicioState extends State<PantallaInformesServicio> {
  InformeServicioService? _svc;
  List<InformeServicio> _items = [];
  bool _cargando = true;
  bool _generando = false;
  String? _error;

  bool get _cerrado => widget.estado == 'Completado';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getInformeServicioService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = await _svc!.listar(widget.servicioId);
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

  Future<void> _generar({required bool fin}) async {
    setState(() => _generando = true);
    final res = fin ? await _svc!.generarFinal(widget.servicioId) : await _svc!.generarPre(widget.servicioId);
    if (!mounted) return;
    setState(() => _generando = false);
    if (res.ok) {
      _snack(fin ? 'Informe final generado' : 'Pre-informe generado');
      await _cargar();
      await abrirEnlace(res.data?.url);  // abre el PDF recién generado
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  Future<void> _abrir(String? url) async {
    final abierto = await abrirEnlace(url);
    if (!abierto) _snack('Enlace copiado al portapapeles');
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informes del servicio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _generando ? null : () => _generar(fin: false),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Pre-informe'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_generando || !_cerrado) ? null : () => _generar(fin: true),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Informe final'),
                  ),
                ),
              ],
            ),
          ),
          if (!_cerrado)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('El informe final se habilita cuando el servicio está "Completado".',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          if (_generando) const LinearProgressIndicator(),
          const Divider(),
          Expanded(child: _buildLista()),
        ],
      ),
    );
  }

  Widget _buildLista() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_items.isEmpty) return const Center(child: Text('Aún no hay informes generados.'));
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final inf = _items[i];
          return ListTile(
            leading: Icon(inf.esFinal ? Icons.verified_outlined : Icons.description_outlined,
                color: inf.esFinal ? Colors.green : null),
            title: Text(inf.titulo ?? (inf.esFinal ? 'Informe final' : 'Pre-informe')),
            subtitle: Text('${inf.esFinal ? 'Final' : 'Pre'} · ${inf.fecha ?? ''}'),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Abrir PDF',
              onPressed: () => _abrir(inf.url),
            ),
          );
        },
      ),
    );
  }
}

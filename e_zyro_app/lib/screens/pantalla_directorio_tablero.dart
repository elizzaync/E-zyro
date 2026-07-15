import 'package:flutter/material.dart';
import '../models/equipo_intervenido_models.dart';
import '../services/equipo_intervenido_service.dart';
import '../utils/api_provider.dart';
import '../pdf/pdf_preview_screen.dart';

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFD6584F);
const _tipos = ['IG', 'ID', 'ITM'];

/// Directorio de circuitos de un tablero eléctrico: lista editable
/// (agregar/editar/eliminar) + exportar PDF.
class PantallaDirectorioTablero extends StatefulWidget {
  final String equipoId;
  final String equipoNombre;

  const PantallaDirectorioTablero({
    super.key,
    required this.equipoId,
    required this.equipoNombre,
  });

  @override
  State<PantallaDirectorioTablero> createState() => _PantallaDirectorioTableroState();
}

class _PantallaDirectorioTableroState extends State<PantallaDirectorioTablero> {
  EquipoIntervenidoService? _svc;
  List<TableroCircuito> _circuitos = [];
  bool _cargando = true;
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getEquipoIntervenidoService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() => _cargando = true);
    final res = await _svc!.listarCircuitos(widget.equipoId);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok) _circuitos = res.data ?? [];
    });
    if (!res.ok) _snack(res.errorMessage.isEmpty ? 'Error al cargar circuitos.' : res.errorMessage, _danger);
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _exportarPdf() async {
    if (_svc == null || _exportando) return;
    setState(() => _exportando = true);
    final res = await _svc!.generarDirectorioPdf(widget.equipoId);
    if (!mounted) return;
    setState(() => _exportando = false);
    if (res.ok && res.data != null) {
      await PdfPreviewScreen.abrir(
        context,
        bytes: res.data!,
        nombreArchivo: 'DIRECTORIO_${widget.equipoNombre.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')}.pdf',
        titulo: 'Directorio de Tablero',
      );
    } else {
      _snack(res.errorMessage.isEmpty ? 'Error al generar el PDF.' : res.errorMessage, _danger);
    }
  }

  Future<void> _abrirFormulario({TableroCircuito? circuito}) async {
    final circuitoCtrl = TextEditingController(text: circuito?.circuito ?? '');
    final capacidadCtrl = TextEditingController(text: circuito?.capacidadItm ?? '');
    final descripcionCtrl = TextEditingController(text: circuito?.descripcion ?? '');
    String tipo = circuito?.tipoCircuito ?? 'ITM';

    final guardar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(circuito == null ? 'Nuevo circuito' : 'Editar circuito',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: circuitoCtrl,
                decoration: const InputDecoration(labelText: 'Circuito', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: tipo,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                items: [for (final t in _tipos) DropdownMenuItem(value: t, child: Text(t))],
                onChanged: (v) => setSheet(() => tipo = v ?? tipo),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: capacidadCtrl,
                decoration: const InputDecoration(labelText: 'Capacidad ITM', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descripcionCtrl,
                decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: _green, padding: const EdgeInsets.symmetric(vertical: 13)),
                  child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (guardar != true || _svc == null) return;
    if (circuitoCtrl.text.trim().isEmpty) {
      _snack('El circuito es obligatorio.', _danger);
      return;
    }

    final body = {
      'circuito': circuitoCtrl.text.trim(),
      'tipo_circuito': tipo,
      'capacidad_itm': capacidadCtrl.text.trim(),
      'descripcion': descripcionCtrl.text.trim(),
    };

    final res = circuito == null
        ? await _svc!.crearCircuito(widget.equipoId, body)
        : await _svc!.actualizarCircuito(circuito.id, body);

    if (!mounted) return;
    if (res.ok) {
      await _cargar();
    } else {
      _snack(res.errorMessage.isEmpty ? 'Error al guardar.' : res.errorMessage, _danger);
    }
  }

  Future<void> _eliminar(TableroCircuito c) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar circuito'),
        content: Text('¿Eliminar "${c.circuito}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar != true || _svc == null) return;
    final res = await _svc!.eliminarCircuito(c.id);
    if (!mounted) return;
    if (res.ok) {
      await _cargar();
    } else {
      _snack(res.errorMessage.isEmpty ? 'Error al eliminar.' : res.errorMessage, _danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Directorio de Tablero', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.equipoNombre, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Exportar PDF',
            icon: _exportando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportando ? null : _exportarPdf,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _green,
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_green)))
          : _circuitos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.electrical_services_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('Sin circuitos registrados', style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  color: _green,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: _circuitos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = _circuitos[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _green.withValues(alpha: 0.15),
                            child: Text(c.tipoCircuito, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _green)),
                          ),
                          title: Text(c.circuito, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            if ((c.capacidadItm ?? '').isNotEmpty) 'ITM: ${c.capacidadItm}',
                            if ((c.descripcion ?? '').isNotEmpty) c.descripcion!,
                          ].join(' · ')),
                          onTap: () => _abrirFormulario(circuito: c),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: _danger, size: 20),
                            onPressed: () => _eliminar(c),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

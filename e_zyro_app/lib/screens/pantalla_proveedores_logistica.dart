import 'package:flutter/material.dart';
import '../models/compras_models.dart';
import '../services/compras_service.dart';
import '../services/consulta_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../widgets/topo_background.dart';

const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);

/// Fase 5 — Directorio de proveedores (CRUD).
class PantallaProveedoresLogistica extends StatefulWidget {
  const PantallaProveedoresLogistica({super.key});

  @override
  State<PantallaProveedoresLogistica> createState() =>
      _PantallaProveedoresLogisticaState();
}

class _PantallaProveedoresLogisticaState
    extends State<PantallaProveedoresLogistica> {
  ComprasService? _service;
  List<Proveedor> _proveedores = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getComprasService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final data = await _service!.getProveedores();
    if (!mounted) return;
    setState(() {
      _proveedores = data;
      _isLoading = false;
    });
  }

  void _msg(bool ok, String okMsg, String errMsg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? okMsg : errMsg),
      backgroundColor: ok ? _kGreen : _kRed,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _abrirForm({Proveedor? prov}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProveedorSheet(service: _service!, proveedor: prov),
    );
    if (ok == true) await _load();
  }

  Future<void> _eliminar(Proveedor p) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar proveedor'),
        content: Text('¿Eliminar "${p.razonSocial}" del directorio?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar', style: TextStyle(color: _kRed))),
        ],
      ),
    );
    if (confirmar != true) return;
    final ok = await _service!.eliminarProveedor(p.id);
    _msg(ok, 'Proveedor eliminado', 'No se pudo eliminar');
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Proveedores',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _service == null ? null : () => _abrirForm(),
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 16,
        amp: 9,
        stroke: 0.38,
        speed: 0.45,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _kGreen))
            : _proveedores.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_shipping_outlined,
                            size: 52, color: Colors.grey.shade400),
                        const SizedBox(height: 14),
                        const Text('Sin proveedores',
                            style: TextStyle(
                                color: Colors.grey,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text('Agrega tu primer proveedor',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: _kGreen,
                    child: ListView.separated(
                      padding: bottomSafePadding(context, extra: 90),
                      itemCount: _proveedores.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ProveedorCard(
                        prov: _proveedores[i],
                        onEditar: () => _abrirForm(prov: _proveedores[i]),
                        onEliminar: () => _eliminar(_proveedores[i]),
                      ),
                    ),
                  ),
      ),
    );
  }
}

// ─── Card de proveedor ───────────────────────────────────────────────────────
class _ProveedorCard extends StatelessWidget {
  final Proveedor prov;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _ProveedorCard({
    required this.prov,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.store_outlined, color: _kGreen, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prov.razonSocial,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                if (prov.ruc != null && prov.ruc!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('RUC: ${prov.ruc}',
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
                if (prov.contacto != null && prov.contacto!.isNotEmpty ||
                    prov.telefono != null && prov.telefono!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (prov.contacto != null && prov.contacto!.isNotEmpty)
                        prov.contacto,
                      if (prov.telefono != null && prov.telefono!.isNotEmpty)
                        prov.telefono,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: _kGreen),
            onPressed: onEditar,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: _kRed),
            onPressed: onEliminar,
          ),
        ],
      ),
    );
  }
}

// ─── Sheet crear/editar proveedor ────────────────────────────────────────────
class _ProveedorSheet extends StatefulWidget {
  final ComprasService service;
  final Proveedor? proveedor;

  const _ProveedorSheet({required this.service, this.proveedor});

  @override
  State<_ProveedorSheet> createState() => _ProveedorSheetState();
}

class _ProveedorSheetState extends State<_ProveedorSheet> {
  late final TextEditingController _razon;
  late final TextEditingController _ruc;
  late final TextEditingController _contacto;
  late final TextEditingController _email;
  late final TextEditingController _telefono;
  late final TextEditingController _direccion;
  bool _guardando = false;
  bool _consultandoRuc = false;

  bool get _esEdicion => widget.proveedor != null;

  Future<void> _buscarRuc() async {
    final ruc = _ruc.text.trim();
    if (ruc.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El RUC debe tener 11 dígitos'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _consultandoRuc = true);
    final r = await ConsultaService.ruc(ruc);
    if (!mounted) return;
    setState(() => _consultandoRuc = false);
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se encontró el RUC (o consulta no configurada)'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() {
      if (r.razonSocial.isNotEmpty) _razon.text = r.razonSocial;
      if ((r.direccion ?? '').isNotEmpty) _direccion.text = r.direccion!;
    });
  }

  @override
  void initState() {
    super.initState();
    final p = widget.proveedor;
    _razon = TextEditingController(text: p?.razonSocial ?? '');
    _ruc = TextEditingController(text: p?.ruc ?? '');
    _contacto = TextEditingController(text: p?.contacto ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _telefono = TextEditingController(text: p?.telefono ?? '');
    _direccion = TextEditingController(text: p?.direccion ?? '');
  }

  @override
  void dispose() {
    _razon.dispose();
    _ruc.dispose();
    _contacto.dispose();
    _email.dispose();
    _telefono.dispose();
    _direccion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_razon.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('La razón social es obligatoria'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _guardando = true);
    final body = {
      'razon_social': _razon.text.trim(),
      'ruc': _ruc.text.trim(),
      'contacto': _contacto.text.trim(),
      'email': _email.text.trim(),
      'telefono': _telefono.text.trim(),
      'direccion': _direccion.text.trim(),
    };
    final ok = _esEdicion
        ? await widget.service.editarProveedor(widget.proveedor!.id, body)
        : await widget.service.crearProveedor(body);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo guardar'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _campo(String label, TextEditingController ctrl, String hint,
      {TextInputType? keyboard}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
            controller: ctrl, keyboardType: keyboard, decoration: _dec(hint)),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(_esEdicion ? 'Editar proveedor' : 'Nuevo proveedor',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _campo('Razón social *', _razon, 'Nombre de la empresa'),
            // RUC con búsqueda SUNAT: autocompleta razón social y dirección.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('RUC',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: _ruc,
                  keyboardType: TextInputType.number,
                  decoration: _dec('11 dígitos — toca la lupa para buscar')
                      .copyWith(
                    suffixIcon: _consultandoRuc
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            tooltip: 'Buscar en SUNAT',
                            icon: const Icon(Icons.search),
                            onPressed: _buscarRuc,
                          ),
                  ),
                  onSubmitted: (_) => _buscarRuc(),
                ),
                const SizedBox(height: 12),
              ],
            ),
            _campo('Contacto', _contacto, 'Persona de contacto'),
            _campo('Teléfono', _telefono, 'Opcional',
                keyboard: TextInputType.phone),
            _campo('Email', _email, 'Opcional',
                keyboard: TextInputType.emailAddress),
            _campo('Dirección', _direccion, 'Opcional'),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_esEdicion ? 'Guardar' : 'Crear',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

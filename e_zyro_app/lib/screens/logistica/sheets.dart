// Bottom sheets: detalle de item y nuevo material.
part of '../pantalla_logistica.dart';

// -- Bottom sheet: detalle de item (solo lectura) ------------------------------
// Sin selector de cantidad ni botón "Agregar al Pedido": esa funcionalidad se
// trasladó al detalle del servicio (donde la solicitud se vincula al servicio).
class _ItemDetailSheet extends StatelessWidget {
  final CatalogoItem item;
  const _ItemDetailSheet({required this.item});

  Color _stockColor() {
    if (item.stock == 0) return Colors.red;
    if (item.stock <= 10) return const Color(0xFFF59E0B);
    return const Color(0xFF8FD11B);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    final stockColor = _stockColor();

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? green.withValues(alpha: 0.12)
                      : const Color(0xFFEFFAE0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombre,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    if (item.categoria != null)
                      Text(item.categoria!,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    if (item.codigo != null)
                      Text('Cód: ${item.codigo}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // Stock card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: stockColor.withValues(alpha: isDark ? 0.08 : 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: stockColor.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Stock disponible',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(text: '${item.stock} ',
                        style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface)),
                      TextSpan(text: item.unidad,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.grey)),
                    ]),
                  ),
                ],
              ),
            ),
            if (item.descripcion != null && item.descripcion!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(item.descripcion!,
                  style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}


// -- Sheet: Nuevo material en inventario ---------------------------------------
class _NuevoMaterialSheet extends StatefulWidget {
  final List<CategoriaItem> categorias;
  final List<AlmacenItem> almacenes;
  final RequerimientoService service;
  final VoidCallback onCreado;

  const _NuevoMaterialSheet({
    required this.categorias,
    required this.almacenes,
    required this.service,
    required this.onCreado,
  });

  @override
  State<_NuevoMaterialSheet> createState() => _NuevoMaterialSheetState();
}

class _NuevoMaterialSheetState extends State<_NuevoMaterialSheet> {
  static const _green = Color(0xFF8FD11B);

  final _nombreCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '0');

  String? _categoriaId;
  String? _almacenId;
  String _unidad = 'Unidades';
  bool _sending = false;

  static const _unidades = [
    'Unidades',
    'Metros',
    'Rollos',
    'Barras',
    'Pares',
    'Sets',
    'Litros',
    'Kilogramos',
    'Cajas',
  ];

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _codigoCtrl.dispose();
    _descCtrl.dispose();
    _cantidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _snack('Ingresa el nombre del material');
      return;
    }
    if (_categoriaId == null) {
      _snack('Selecciona una categoría');
      return;
    }
    final cantidad = int.tryParse(_cantidadCtrl.text) ?? 0;

    setState(() => _sending = true);
    final ok = await widget.service.crearMaterial(
      nombre: nombre,
      codigo: _codigoCtrl.text.trim().isEmpty ? null : _codigoCtrl.text.trim(),
      unidad: _unidad,
      categoriaId: _categoriaId!,
      descripcion: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      cantidadInicial: cantidad,
      almacenId: _almacenId,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      Navigator.pop(context);
      widget.onCreado();
    } else {
      _snack('Error al guardar. Verifica permisos.');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final inputBg = Theme.of(context).colorScheme.surfaceContainerHighest;
    final inputDec = InputDecoration(
      filled: true,
      fillColor: inputBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.add_box_outlined,
                    color: _green,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nuevo Material',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Agregar al inventario',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            _label('Nombre *'),
            TextField(
              controller: _nombreCtrl,
              decoration: inputDec.copyWith(hintText: 'Ej: Cable THW 12 AWG'),
            ),
            const SizedBox(height: 14),
            _label('Código (opcional)'),
            TextField(
              controller: _codigoCtrl,
              decoration: inputDec.copyWith(hintText: 'Ej: CBL-THW-12'),
            ),
            const SizedBox(height: 14),
            _label('Categoría *'),
            DropdownButtonFormField<String>(
              initialValue: _categoriaId,
              hint: const Text('Selecciona categoría'),
              decoration: inputDec,
              items: widget.categorias
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        c.nombre,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _categoriaId = v),
            ),
            const SizedBox(height: 14),
            _label('Unidad de medida'),
            DropdownButtonFormField<String>(
              initialValue: _unidad,
              decoration: inputDec,
              items: _unidades
                  .map(
                    (u) => DropdownMenuItem(
                      value: u,
                      child: Text(u, style: const TextStyle(fontSize: 13)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _unidad = v ?? 'Unidades'),
            ),
            const SizedBox(height: 14),
            _label('Descripción (opcional)'),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: inputDec.copyWith(
                hintText: 'Especificaciones técnicas...',
              ),
            ),
            const SizedBox(height: 14),
            _label('Cantidad inicial en stock'),
            TextField(
              controller: _cantidadCtrl,
              keyboardType: TextInputType.number,
              decoration: inputDec.copyWith(hintText: '0'),
            ),
            const SizedBox(height: 14),
            if (widget.almacenes.isNotEmpty) ...[
              _label('Almacén (opcional)'),
              DropdownButtonFormField<String>(
                initialValue: _almacenId,
                hint: const Text('Almacén principal por defecto'),
                decoration: inputDec,
                items: widget.almacenes
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          a.ubicacion != null
                              ? '${a.nombre} �?" ${a.ubicacion}'
                              : a.nombre,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _almacenId = v),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _sending ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Guardar en Inventario',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    ),
  );
}

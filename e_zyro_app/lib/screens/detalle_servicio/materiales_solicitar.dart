// Materiales: sheet de solicitar (catalogo/equipo/externo) + chips y card.
part of '../pantalla_detalle_servicio.dart';

// ─── Sheet: Solicitar material (catálogo + compra externa) ────────────────────

class _SolicitarMaterialSheet extends StatefulWidget {
  final String servicioId;
  final ProyectoService service;
  final Future<void> Function() onAgregado;

  const _SolicitarMaterialSheet({
    required this.servicioId,
    required this.service,
    required this.onAgregado,
  });

  @override
  State<_SolicitarMaterialSheet> createState() =>
      _SolicitarMaterialSheetState();
}

class _SolicitarMaterialSheetState extends State<_SolicitarMaterialSheet> {
  int _modo = 0; // 0 = catálogo · 1 = equipos/herramientas · 2 = compra externa
  bool _guardando = false;

  // Catálogo
  final _busquedaCtrl = TextEditingController();
  List<MaterialBusqueda> _resultados = [];
  MaterialBusqueda? _elegido;
  int _cantidad = 1;
  Timer? _debounce;

  // Equipos / Herramientas
  final _busquedaEqCtrl = TextEditingController();
  List<EquipoBusqueda> _resultadosEq = [];
  EquipoBusqueda? _equipoElegido;
  int _cantEquipo = 1;
  Timer? _debounceEq;

  // Compra externa
  final _nombreCtrl = TextEditingController();
  final _especCtrl = TextEditingController();
  String _unidad = 'Unidades';
  int _cantExterno = 1;

  @override
  void dispose() {
    _debounce?.cancel();
    _debounceEq?.cancel();
    _busquedaCtrl.dispose();
    _busquedaEqCtrl.dispose();
    _nombreCtrl.dispose();
    _especCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await widget.service.buscarMateriales(q);
      if (mounted) setState(() => _resultados = r);
    });
  }

  void _onSearchEq(String q) {
    _debounceEq?.cancel();
    _debounceEq = Timer(const Duration(milliseconds: 350), () async {
      final r = await widget.service.buscarEquipos(q);
      if (mounted) setState(() => _resultadosEq = r);
    });
  }

  Future<void> _agregarEquipo() async {
    final eq = _equipoElegido;
    if (eq == null) return;
    setState(() => _guardando = true);
    final etiqueta = eq.esHerramienta ? 'Herramienta' : 'Equipo';
    final res = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: null,
      nombre: eq.nombre,
      unidad: 'Unidades',
      cantidad: _cantEquipo,
      especificacion: '[$etiqueta] ${eq.nombre} del inventario',
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    } else {
      _snackError(res.errorMessage.isEmpty ? 'No se pudo agregar' : res.errorMessage);
    }
  }

  void _snackError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: _danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _agregarCatalogo() async {
    if (_elegido == null) return;
    setState(() => _guardando = true);
    final res = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: _elegido!.id,
      nombre: _elegido!.nombre,
      unidad: _elegido!.unidad,
      cantidad: _cantidad,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    } else {
      _snackError(res.errorMessage.isEmpty ? 'No se pudo agregar' : res.errorMessage);
    }
  }

  Future<void> _agregarExterno() async {
    final nombre = _nombreCtrl.text.trim();
    final espec = _especCtrl.text.trim();
    if (nombre.isEmpty || espec.isEmpty) return;
    setState(() => _guardando = true);
    final res = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: null,
      nombre: nombre,
      unidad: _unidad,
      cantidad: _cantExterno,
      especificacion: espec,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    } else {
      _snackError(res.errorMessage.isEmpty ? 'No se pudo agregar' : res.errorMessage);
    }
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
          const Text('Solicitar al Requerimiento',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Toggle: catálogo / equipos-herramientas / compra externa
          Row(
            children: [
              _ToggleChip(
                label: 'Material',
                selected: _modo == 0,
                onTap: () => setState(() => _modo = 0),
              ),
              const SizedBox(width: 6),
              _ToggleChip(
                label: 'Equipo/Herr.',
                selected: _modo == 1,
                onTap: () => setState(() => _modo = 1),
              ),
              const SizedBox(width: 6),
              _ToggleChip(
                label: 'Compra ext.',
                selected: _modo == 2,
                onTap: () => setState(() => _modo = 2),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_modo == 0)
            ..._buildCatalogo()
          else if (_modo == 1)
            ..._buildEquipos()
          else
            ..._buildExterno(),
        ],
      ),
    );
  }

  List<Widget> _buildCatalogo() {
    return [
      TextField(
        controller: _busquedaCtrl,
        onChanged: _onSearch,
        decoration: InputDecoration(
          hintText: 'Buscar material (mín. 2 letras)...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      if (_elegido == null && _resultados.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView(
            shrinkWrap: true,
            children: _resultados
                .map((m) => ListTile(
                      dense: true,
                      title: Text(m.nombre),
                      subtitle: Text('Stock: ${m.stock} ${m.unidad}'),
                      onTap: () => setState(() {
                        _elegido = m;
                        _busquedaCtrl.text = m.nombre;
                        _resultados = [];
                      }),
                    ))
                .toList(),
          ),
        ),
      if (_elegido != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _green.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_elegido!.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              _QtyStepper(
                value: _cantidad,
                onChanged: (v) => setState(() => _cantidad = v),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_elegido == null || _guardando) ? null : _agregarCatalogo,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Agregar al Borrador',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  List<Widget> _buildEquipos() {
    return [
      TextField(
        controller: _busquedaEqCtrl,
        onChanged: _onSearchEq,
        decoration: InputDecoration(
          hintText: 'Buscar equipo o herramienta (mín. 2 letras)...',
          prefixIcon: const Icon(Icons.handyman_outlined),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      if (_equipoElegido == null && _resultadosEq.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView(
            shrinkWrap: true,
            children: _resultadosEq
                .map((e) => ListTile(
                      dense: true,
                      title: Text(e.nombre),
                      subtitle: Text(
                          '${e.esHerramienta ? 'Herramienta' : 'Equipo'} · Disponibles: ${e.cantidad}'),
                      onTap: () => setState(() {
                        _equipoElegido = e;
                        _busquedaEqCtrl.text = e.nombre;
                        _resultadosEq = [];
                        _cantEquipo = 1;
                      }),
                    ))
                .toList(),
          ),
        ),
      if (_equipoElegido != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _green.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_equipoElegido!.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '${_equipoElegido!.esHerramienta ? 'Herramienta' : 'Equipo'} · Disp.: ${_equipoElegido!.cantidad}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              _QtyStepper(
                value: _cantEquipo,
                onChanged: (v) => setState(() => _cantEquipo = v),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed:
              (_equipoElegido == null || _guardando) ? null : _agregarEquipo,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Añadir al Borrador',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  List<Widget> _buildExterno() {
    return [
      TextField(
        controller: _nombreCtrl,
        decoration: InputDecoration(
          labelText: 'Nombre del material',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _especCtrl,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Especificación (obligatoria)',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _unidad,
              decoration: InputDecoration(
                labelText: 'Unidad',
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              items: const ['Unidades', 'Metros', 'Kilogramos', 'Litros', 'Cajas']
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => setState(() => _unidad = v ?? 'Unidades'),
            ),
          ),
          const SizedBox(width: 12),
          _QtyStepper(
            value: _cantExterno,
            onChanged: (v) => setState(() => _cantExterno = v),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _guardando ? null : _agregarExterno,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Agregar al Borrador',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _green : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? _green : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _QtyStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: _green),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          visualDensity: VisualDensity.compact,
        ),
        Text('$value',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: _green),
          onPressed: () => onChanged(value + 1),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionTitle(this.title, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final ItemMaterial item;
  final VoidCallback? onEdit;
  const _MaterialCard({required this.item, this.onEdit});

  // No se edita lo ya entregado o aprobado por Logística.
  bool get _editable =>
      item.estadoReq != 'entregado' && item.estadoReq != 'aprobado';

  Color _estadoColor() => switch (item.estadoReq) {
        'entregado' => _green,
        'aprobado' => const Color(0xFF3B82F6),
        'rechazado' => _danger,
        _ => _amber,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final tappable = _editable && onEdit != null;

    return InkWell(
      onTap: tappable ? onEdit : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isDark
                  ? Colors.grey.withValues(alpha: 0.20)
                  : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.nombre,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(item.estadoReq,
                      style: TextStyle(
                          color: _estadoColor(),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Text('${item.cantidad} ${item.unidad}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (tappable) ...[
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
            ],
          ],
        ),
      ),
    );
  }
}


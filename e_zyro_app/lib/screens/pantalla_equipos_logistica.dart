import 'package:flutter/material.dart';
import '../core/api_result.dart';
import '../models/equipo_models.dart';
import '../services/equipo_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import '../widgets/topo_background.dart';

class PantallaEquiposLogistica extends StatefulWidget {
  const PantallaEquiposLogistica({super.key});
  @override
  State<PantallaEquiposLogistica> createState() => _State();
}

class _State extends State<PantallaEquiposLogistica>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF8FD11B);

  EquipoService? _svc;
  late TabController _tabs;

  // Listas por tab
  List<EquipoItem> _equipos = [];
  List<EquipoItem> _herramientas = [];
  bool _cargando = true;
  String? _error;

  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() {
      if (_searchCtrl.text != _q) {
        setState(() => _q = _searchCtrl.text);
        _cargar();
      }
    });
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getEquipoService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final resEq = await _svc!.listar(q: _q, clase: 'equipo',      pageSize: 200);
    final resHr = await _svc!.listar(q: _q, clase: 'herramienta', pageSize: 200);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (resEq.ok) _equipos      = resEq.data?.items ?? [];
      if (resHr.ok) _herramientas = resHr.data?.items ?? [];
      if (!resEq.ok) _error = resEq.errorMessage;
    });
  }

  // ── Colores de estado ───────────────────────────────────────────────────────
  Color _colorEstado(String e) => switch (e) {
        'operativo'        => _green,
        'en_mantenimiento' => Colors.orange.shade700,
        'fuera_de_servicio'=> Colors.red.shade600,
        'baja'             => Colors.grey,
        _                  => Colors.grey,
      };

  String _labelEstado(String e) => switch (e) {
        'operativo'        => 'Operativo',
        'en_mantenimiento' => 'Mantenimiento',
        'fuera_de_servicio'=> 'Fuera de servicio',
        'baja'             => 'Baja',
        _                  => e,
      };

  String _labelFrecuencia(String f) => switch (f) {
        'mensual'    => 'Mensual',
        'trimestral' => 'Trimestral',
        'semestral'  => 'Semestral',
        'anual'      => 'Anual',
        _            => 'Sin programa',
      };

  // ── Detalle ─────────────────────────────────────────────────────────────────
  void _verDetalle(EquipoItem e) {
    final surface = Theme.of(context).colorScheme.surface;
    final color = _colorEstado(e.estado);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(e.esHerramienta ? Icons.handyman_outlined
                      : Icons.precision_manufacturing_outlined,
                      color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.nombre, style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (e.codigo.isNotEmpty)
                      Text(e.codigo, style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                  ],
                )),
                _badge(color, _labelEstado(e.estado)),
              ]),
            ),
            Expanded(child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _seccion('IDENTIFICACIÓN'),
                if (e.tipo != null && e.tipo!.isNotEmpty)
                  _row(Icons.category_outlined, 'Tipo', e.tipo!),
                if (e.marca != null && e.marca!.isNotEmpty)
                  _row(Icons.verified_outlined, 'Marca', e.marca!),
                if (e.modelo != null && e.modelo!.isNotEmpty)
                  _row(Icons.info_outline, 'Modelo', e.modelo!),
                if (e.numeroSerie != null && e.numeroSerie!.isNotEmpty)
                  _row(Icons.qr_code_outlined, 'N° Serie', e.numeroSerie!),
                if (e.fechaAdquisicion != null)
                  _row(Icons.calendar_today_outlined, 'Adquisición', e.fechaAdquisicion!),
                _row(Icons.inventory_2_outlined, 'Cantidad', '${e.cantidad}'),

                _seccion('MANTENIMIENTO'),
                _row(Icons.build_circle_outlined, 'Requiere mant.',
                    e.requiereMantenimiento ? 'Sí' : 'No'),
                if (e.requiereMantenimiento) ...[
                  _row(Icons.repeat_outlined, 'Frecuencia',
                      _labelFrecuencia(e.frecuenciaMantenimiento)),
                  if (e.proximaFechaMantenimiento != null)
                    _row(Icons.event_outlined, 'Próximo', e.proximaFechaMantenimiento!),
                ],

                if (AppSession.i.canGestionarInventario) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); _abrirFormulario(e); },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Editar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _green,
                        side: const BorderSide(color: _green),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            )),
          ]),
        ),
      ),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: Colors.grey, letterSpacing: 0.8)),
      );

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: _green),
          const SizedBox(width: 10),
          SizedBox(width: 90, child: Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey))),
          Expanded(child: Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );

  Widget _badge(Color c, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
      );

  // ── Formulario ──────────────────────────────────────────────────────────────
  void _abrirFormulario([EquipoItem? item]) {
    final nombreCtrl = TextEditingController(text: item?.nombre ?? '');
    final codigoCtrl = TextEditingController(text: item?.codigo ?? '');
    final marcaCtrl  = TextEditingController(text: item?.marca ?? '');
    final modeloCtrl = TextEditingController(text: item?.modelo ?? '');
    final serieCtrl  = TextEditingController(text: item?.numeroSerie ?? '');
    final cantCtrl   = TextEditingController(text: '${item?.cantidad ?? 1}');
    String clase     = item?.clase ?? (_tabs.index == 0 ? 'equipo' : 'herramienta');
    String estado    = item?.estado ?? 'operativo';
    bool reqMant     = item?.requiereMantenimiento ?? false;
    String frecuencia= item?.frecuenciaMantenimiento ?? 'ninguno';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final surface = Theme.of(ctx).colorScheme.surface;

          InputDecoration deco(String label, IconData icon) => InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20, color: _green),
            filled: true,
            fillColor: isDark ? _green.withValues(alpha: 0.04) : Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? _green.withValues(alpha: 0.2) : Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? _green.withValues(alpha: 0.2) : Colors.grey.shade200)),
            focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: _green, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          );

          return Material(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Center(child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  )),
                  const SizedBox(height: 16),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(clase == 'herramienta'
                          ? Icons.handyman_outlined
                          : Icons.precision_manufacturing_outlined,
                          color: _green, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(item == null ? 'Nuevo registro' : 'Editar registro',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 20),

                  // Tipo (equipo / herramienta)
                  Row(children: [
                    Expanded(child: _tipoChip('equipo', 'Equipo',
                        Icons.precision_manufacturing_outlined, clase, setLocal, (v) => clase = v)),
                    const SizedBox(width: 10),
                    Expanded(child: _tipoChip('herramienta', 'Herramienta',
                        Icons.handyman_outlined, clase, setLocal, (v) => clase = v)),
                  ]),
                  const SizedBox(height: 16),

                  TextField(controller: nombreCtrl, decoration: deco('Nombre *', Icons.label_outline)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: codigoCtrl,
                        decoration: deco('Código', Icons.qr_code_outlined))),
                    const SizedBox(width: 10),
                    SizedBox(width: 80, child: TextField(
                      controller: cantCtrl,
                      keyboardType: TextInputType.number,
                      decoration: deco('Cant.', Icons.numbers_outlined),
                    )),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: marcaCtrl,
                        decoration: deco('Marca', Icons.verified_outlined))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: modeloCtrl,
                        decoration: deco('Modelo', Icons.info_outline))),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: serieCtrl,
                      decoration: deco('N° de Serie', Icons.numbers_outlined)),
                  const SizedBox(height: 12),

                  // Estado
                  DropdownButtonFormField<String>(
                    value: estado,
                    decoration: deco('Estado', Icons.circle_outlined),
                    items: const [
                      DropdownMenuItem(value: 'operativo',         child: Text('Operativo')),
                      DropdownMenuItem(value: 'en_mantenimiento',  child: Text('En mantenimiento')),
                      DropdownMenuItem(value: 'fuera_de_servicio', child: Text('Fuera de servicio')),
                      DropdownMenuItem(value: 'baja',              child: Text('Baja')),
                    ],
                    onChanged: (v) => setLocal(() => estado = v ?? 'operativo'),
                  ),
                  const SizedBox(height: 12),

                  // Mantenimiento
                  SwitchListTile(
                    value: reqMant,
                    onChanged: (v) => setLocal(() => reqMant = v),
                    title: const Text('Requiere mantenimiento',
                        style: TextStyle(fontSize: 14)),
                    activeColor: _green,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (reqMant) ...[
                    DropdownButtonFormField<String>(
                      value: frecuencia == 'ninguno' ? 'mensual' : frecuencia,
                      decoration: deco('Frecuencia', Icons.repeat_outlined),
                      items: const [
                        DropdownMenuItem(value: 'mensual',    child: Text('Mensual')),
                        DropdownMenuItem(value: 'trimestral', child: Text('Trimestral')),
                        DropdownMenuItem(value: 'semestral',  child: Text('Semestral')),
                        DropdownMenuItem(value: 'anual',      child: Text('Anual')),
                      ],
                      onChanged: (v) => setLocal(() => frecuencia = v ?? 'mensual'),
                    ),
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: () => _guardar(
                        ctx: ctx, item: item,
                        nombre: nombreCtrl.text.trim(),
                        codigo: codigoCtrl.text.trim(),
                        marca: marcaCtrl.text.trim(),
                        modelo: modeloCtrl.text.trim(),
                        serie: serieCtrl.text.trim(),
                        cantidad: int.tryParse(cantCtrl.text) ?? 1,
                        clase: clase, estado: estado,
                        reqMant: reqMant, frecuencia: frecuencia,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green, foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(item == null ? 'Crear' : 'Guardar',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
            ),    // SafeArea
          ),      // Padding
        );        // Material
        },
      ),
    );
  }

  Widget _tipoChip(String val, String label, IconData icon,
      String current, StateSetter setLocal, void Function(String) onChange) {
    final sel = current == val;
    return GestureDetector(
      onTap: () => setLocal(() => onChange(val)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? _green : Colors.grey.shade300),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: sel ? Colors.white : Colors.grey),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
              color: sel ? Colors.white : Colors.grey,
              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13)),
        ]),
      ),
    );
  }

  Future<void> _guardar({
    required BuildContext ctx,
    required EquipoItem? item,
    required String nombre, required String codigo,
    required String marca, required String modelo, required String serie,
    required int cantidad, required String clase, required String estado,
    required bool reqMant, required String frecuencia,
  }) async {
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('El nombre es obligatorio')));
      return;
    }
    final body = <String, dynamic>{
      'nombre': nombre, 'clase': clase, 'estado': estado,
      'cantidad': cantidad,
      'requiereMantenimiento': reqMant,
      'frecuenciaMantenimiento': reqMant ? frecuencia : 'ninguno',
      if (codigo.isNotEmpty) 'codigo': codigo,
      if (marca.isNotEmpty)  'marca': marca,
      if (modelo.isNotEmpty) 'modelo': modelo,
      if (serie.isNotEmpty)  'numeroSerie': serie,
    };

    final ApiResult res = item == null
        ? await _svc!.crear(body)
        : await _svc!.actualizar(item.id, body);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(ctx);
    nav.pop();
    if (res.ok) {
      messenger.showSnackBar(SnackBar(
        content: Text(item == null ? 'Registro creado' : 'Registro actualizado'),
        backgroundColor: _green, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      _cargar();
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(res.errorMessage),
        backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TopoBackground(
        c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
        c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
        base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
        count: 18, amp: 10, stroke: 0.40, speed: 0.5,
        child: SafeArea(
        child: Column(children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.07),
                blurRadius: 16, offset: const Offset(0, 4),
              )],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text('Equipos y Herramientas',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                if (AppSession.i.canGestionarInventario)
                  IconButton(
                    onPressed: () => _abrirFormulario(),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: _green, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.add, color: Colors.white, size: 20),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              // Buscador
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, marca, código...',
                  prefixIcon: const Icon(Icons.search, size: 20, color: _green),
                  suffixIcon: _q.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchCtrl.clear())
                      : null,
                  filled: true,
                  fillColor: isDark
                      ? _green.withValues(alpha: 0.06) : Colors.grey.shade100,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              // Tabs
              TabBar(
                controller: _tabs,
                labelColor: _green,
                unselectedLabelColor: Colors.grey,
                indicatorColor: _green,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: [
                  Tab(text: 'Equipos (${_equipos.length})'),
                  Tab(text: 'Herramientas (${_herramientas.length})'),
                ],
              ),
            ]),
          ),
          // Lista
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_green)))
                : _error != null
                    ? _errorWidget()
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _lista(_equipos, Icons.precision_manufacturing_outlined),
                          _lista(_herramientas, Icons.handyman_outlined),
                        ],
                      ),
          ),
        ]),
        ),      // SafeArea
      ),        // TopoBackground
    );          // Scaffold
  }

  Widget _lista(List<EquipoItem> items, IconData icon) {
    if (items.isEmpty) return _emptyWidget();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return RefreshIndicator(
      onRefresh: _cargar,
      color: _green,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        itemCount: items.length,
        itemBuilder: (_, i) => _tarjeta(items[i], icon, isDark, surface),
      ),
    );
  }

  Widget _tarjeta(EquipoItem e, IconData icon, bool isDark, Color surface) {
    final color = _colorEstado(e.estado);
    return GestureDetector(
      onTap: () => _verDetalle(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark ? Border.all(color: _green.withValues(alpha: 0.12)) : null,
          boxShadow: isDark
              ? [BoxShadow(color: _green.withValues(alpha: 0.05), blurRadius: 8)]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.nombre, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  if (e.marca != null && e.marca!.isNotEmpty) ...[
                    Text(e.marca!, style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
                    if (e.modelo != null && e.modelo!.isNotEmpty)
                      Text(' · ${e.modelo!}', style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                  ],
                  if (e.codigo.isNotEmpty) ...[
                    if (e.marca != null) const Text(' · ',
                        style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text(e.codigo, style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
                  ],
                ]),
                if (e.requiereMantenimiento && e.proximaFechaMantenimiento != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const Icon(Icons.build_circle_outlined, size: 11,
                          color: Colors.orange),
                      const SizedBox(width: 3),
                      Text('Mant: ${e.proximaFechaMantenimiento}',
                          style: const TextStyle(fontSize: 10,
                              color: Colors.orange)),
                    ]),
                  ),
              ],
            )),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _badge(color, _labelEstado(e.estado)),
              const SizedBox(height: 6),
              Text('× ${e.cantidad}', style: const TextStyle(
                  fontSize: 12, color: Colors.grey,
                  fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _emptyWidget() => Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(_q.isNotEmpty ? 'Sin resultados para "$_q"'
              : 'No hay registros aún',
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
          if (_q.isEmpty && AppSession.i.canGestionarInventario) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
              style: ElevatedButton.styleFrom(backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
          ],
        ],
      ));

  Widget _errorWidget() => Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(_error ?? 'Error', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh, color: _green),
            label: const Text('Reintentar', style: TextStyle(color: _green)),
          ),
        ],
      ));
}

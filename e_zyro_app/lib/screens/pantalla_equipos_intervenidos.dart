import 'package:flutter/material.dart';
import '../models/equipo_intervenido_models.dart';
import '../models/catalogo_models.dart';
import '../models/proyecto_models.dart';
import '../services/equipo_intervenido_service.dart';
import '../services/catalogo_service.dart';
import '../services/proyecto_service.dart';
import '../utils/api_provider.dart';
import '../core/api_result.dart';
import '../utils/app_session.dart';
import '../widgets/topo_background.dart';
import 'detalle_equipo_intervenido.dart';

class PantallaEquiposIntervenidos extends StatefulWidget {
  const PantallaEquiposIntervenidos({super.key});
  @override
  State<PantallaEquiposIntervenidos> createState() => _State();
}

class _State extends State<PantallaEquiposIntervenidos> {
  static const _green = Color(0xFF8FD11B);
  static const _estados = ['todos', 'operativo', 'inoperativo', 'mantenimiento', 'en_revision'];

  EquipoIntervenidoService? _svc;
  CatalogoService? _catSvc;
  ProyectoService? _proySvc;

  List<EquipoIntervenido> _todos = [];
  List<EquipoIntervenido> _filtrados = [];
  List<Ubicacion> _ubicaciones = [];
  List<Zona> _zonas = [];
  List<Area> _areas = [];
  List<ClienteBasico> _clientes = [];

  bool _cargando = true;
  String? _error;
  String _estadoFiltro = 'todos';
  String _busqueda = '';
  bool _vistaParque = false; // false = lista plana, true = agrupado por sede
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
    _searchCtrl.addListener(_aplicarFiltros);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc     = await getEquipoIntervenidoService();
    _catSvc  = await getCatalogoService();
    _proySvc = await getProyectoService();
    await Future.wait([_cargar(), _cargarCatalogos()]);
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final res = await _svc!.listar();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok) {
        _todos = res.data ?? [];
        _aplicarFiltros();
      } else {
        _error = res.errorMessage;
      }
    });
  }

  Future<void> _cargarCatalogos() async {
    if (_catSvc == null || _proySvc == null) return;
    final resUbic  = await _catSvc!.ubicaciones();
    final resZonas = await _catSvc!.zonas();
    final resAreas = await _catSvc!.areas();
    final clientes = await _proySvc!.getClientes();
    if (!mounted) return;
    setState(() {
      if (resUbic.ok)  _ubicaciones = resUbic.data ?? [];
      if (resZonas.ok) _zonas = resZonas.data ?? [];
      if (resAreas.ok) _areas = resAreas.data ?? [];
      _clientes = clientes;
    });
  }

  /// Crea un área bajo [zonaId] (catálogo) y la deja disponible. Devuelve el id
  /// de la nueva área o null si se canceló/falló.
  Future<String?> _crearAreaInline(String zonaId) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva área'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );
    final nombre = ctrl.text.trim();
    if (ok != true || nombre.isEmpty || _catSvc == null) return null;
    final res = await _catSvc!.crearAreaRet(nombre, zonaId: zonaId);
    if (!mounted) return null;
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorMessage), backgroundColor: Colors.red.shade700));
      return null;
    }
    setState(() => _areas = [..._areas, res.data!]);
    return res.data!.id;
  }

  void _aplicarFiltros() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _busqueda = q;
      _filtrados = _todos.where((e) {
        final matchEstado = _estadoFiltro == 'todos' || e.estado == _estadoFiltro;
        final matchQ = q.isEmpty ||
            e.nombre.toLowerCase().contains(q) ||
            (e.clienteNombre?.toLowerCase().contains(q) ?? false) ||
            (e.ubicacionNombre?.toLowerCase().contains(q) ?? false) ||
            (e.zonaNombre?.toLowerCase().contains(q) ?? false) ||
            (e.codigo?.toLowerCase().contains(q) ?? false);
        return matchEstado && matchQ;
      }).toList();
      // Próximo mantenimiento más cercano primero; sin plan al final.
      _filtrados.sort((a, b) {
        final pa = a.proximoMantDate;
        final pb = b.proximoMantDate;
        if (pa == null && pb == null) return a.nombre.compareTo(b.nombre);
        if (pa == null) return 1;
        if (pb == null) return -1;
        final cmp = pa.compareTo(pb);
        return cmp != 0 ? cmp : a.nombre.compareTo(b.nombre);
      });
    });
  }

  void _setEstado(String e) {
    _estadoFiltro = e;
    _aplicarFiltros();
  }

  // ── Colores y labels de estado ──────────────────────────────────────────────

  Color _colorEstado(String estado) => switch (estado) {
        'operativo'    => const Color(0xFF8FD11B),
        'inoperativo'  => Colors.red.shade600,
        'mantenimiento'=> Colors.orange.shade700,
        'en_revision'  => Colors.blue.shade600,
        _              => Colors.grey,
      };

  String _labelEstado(String estado) => switch (estado) {
        'operativo'    => 'Operativo',
        'inoperativo'  => 'Inoperativo',
        'mantenimiento'=> 'Mantenimiento',
        'en_revision'  => 'En revisión',
        _              => estado,
      };

  IconData _iconEstado(String estado) => switch (estado) {
        'operativo'    => Icons.check_circle_outline,
        'inoperativo'  => Icons.cancel_outlined,
        'mantenimiento'=> Icons.build_outlined,
        'en_revision'  => Icons.search_outlined,
        _              => Icons.help_outline,
      };

  // ── Detalle (pantalla completa) ─────────────────────────────────────────────

  Future<void> _verDetalle(EquipoIntervenido e) async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetalleEquipoIntervenido(equipo: e)),
    );
    if (!mounted) return;
    if (res == 'editar') {
      _abrirFormulario(equipo: e);
    } else if (res == true) {
      _cargar();
    }
  }

  // ── Formulario crear / editar ───────────────────────────────────────────────

  void _abrirFormulario({EquipoIntervenido? equipo}) {
    final nombreCtrl     = TextEditingController(text: equipo?.nombre ?? '');
    final codigoCtrl     = TextEditingController(text: equipo?.codigo ?? '');
    final marcaCtrl      = TextEditingController(text: equipo?.marca ?? '');
    final modeloCtrl     = TextEditingController(text: equipo?.modelo ?? '');
    final serieCtrl      = TextEditingController(text: equipo?.numeroSerie ?? '');
    final obsCtrl        = TextEditingController(text: equipo?.observaciones ?? '');
    String? clienteId    = equipo?.clienteId;
    String? ubicacionId  = equipo?.ubicacionId;
    String? zonaId       = equipo?.zonaId;
    String? areaId       = equipo?.areaId;
    String estado        = equipo?.estado ?? 'operativo';

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

          final zonasFiltradas = ubicacionId == null
              ? _zonas
              : _zonas.where((z) => z.ubicacionId == ubicacionId).toList();
          final areasFiltradas = zonaId == null
              ? <Area>[]
              : _areas.where((a) => a.zonaId == zonaId).toList();

          return Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40, height: 4,
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
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.electrical_services_outlined,
                              color: _green, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(equipo == null ? 'Nuevo equipo intervenido' : 'Editar equipo',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Nombre
                    TextField(controller: nombreCtrl, decoration: deco('Nombre *', Icons.label_outline)),
                    const SizedBox(height: 14),
                    TextField(controller: codigoCtrl, decoration: deco('Código', Icons.qr_code_outlined)),
                    const SizedBox(height: 20),

                    // Cliente
                    const Text('UBICACIÓN EN EL CLIENTE',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: Colors.grey, letterSpacing: 0.8)),
                    const SizedBox(height: 10),
                    // Cliente dropdown
                    DropdownButtonFormField<String>(
                      initialValue: clienteId,
                      isExpanded: true,
                      decoration: deco('Cliente', Icons.business_outlined),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sin cliente')),
                        ..._clientes.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.razonSocial, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setLocal(() => clienteId = v),
                    ),
                    const SizedBox(height: 14),
                    // Ubicacion
                    DropdownButtonFormField<String>(
                      initialValue: ubicacionId,
                      isExpanded: true,
                      decoration: deco('Sede / Ciudad', Icons.location_city_outlined),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sin sede')),
                        ..._ubicaciones.map((u) => DropdownMenuItem(
                              value: u.id,
                              child: Text(u.nombre, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setLocal(() {
                        ubicacionId = v;
                        zonaId = null;
                        areaId = null;
                      }),
                    ),
                    const SizedBox(height: 14),
                    // Zona
                    DropdownButtonFormField<String>(
                      initialValue: zonasFiltradas.any((z) => z.id == zonaId) ? zonaId : null,
                      isExpanded: true,
                      decoration: deco('Zona / Almacén', Icons.warehouse_outlined),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sin zona')),
                        ...zonasFiltradas.map((z) => DropdownMenuItem(
                              value: z.id,
                              child: Text(z.nombre, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setLocal(() {
                        zonaId = v;
                        areaId = null;
                      }),
                    ),
                    const SizedBox(height: 14),
                    // Área (cuelga de la zona). Estricto + "+ nuevo" inline.
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: areasFiltradas.any((a) => a.id == areaId) ? areaId : null,
                            isExpanded: true,
                            decoration: deco('Área', Icons.domain_outlined),
                            hint: Text(zonaId == null ? 'Elige una zona primero' : 'Sin área'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Sin área')),
                              ...areasFiltradas.map((a) => DropdownMenuItem(
                                    value: a.id,
                                    child: Text(a.nombre, overflow: TextOverflow.ellipsis),
                                  )),
                            ],
                            onChanged: zonaId == null ? null : (v) => setLocal(() => areaId = v),
                          ),
                        ),
                        if (AppSession.i.canCrearCatalogo) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Nueva área',
                            icon: const Icon(Icons.add_circle_outline, color: _green),
                            onPressed: zonaId == null
                                ? null
                                : () async {
                                    final nueva = await _crearAreaInline(zonaId!);
                                    if (nueva != null) setLocal(() => areaId = nueva);
                                  },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Datos técnicos
                    const Text('DATOS TÉCNICOS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: Colors.grey, letterSpacing: 0.8)),
                    const SizedBox(height: 10),
                    TextField(controller: marcaCtrl, decoration: deco('Marca', Icons.verified_outlined)),
                    const SizedBox(height: 14),
                    TextField(controller: modeloCtrl, decoration: deco('Modelo', Icons.info_outline)),
                    const SizedBox(height: 14),
                    TextField(controller: serieCtrl, decoration: deco('N° de Serie', Icons.numbers_outlined)),
                    const SizedBox(height: 14),
                    // Estado
                    DropdownButtonFormField<String>(
                      initialValue: estado,
                      decoration: deco('Estado', Icons.circle_outlined),
                      items: const [
                        DropdownMenuItem(value: 'operativo',    child: Text('Operativo')),
                        DropdownMenuItem(value: 'inoperativo',  child: Text('Inoperativo')),
                        DropdownMenuItem(value: 'mantenimiento',child: Text('En mantenimiento')),
                        DropdownMenuItem(value: 'en_revision',  child: Text('En revisión')),
                      ],
                      onChanged: (v) => setLocal(() => estado = v ?? 'operativo'),
                    ),
                    const SizedBox(height: 14),
                    TextField(controller: obsCtrl, maxLines: 3,
                        decoration: deco('Observaciones', Icons.notes_outlined)),
                    const SizedBox(height: 24),

                    // Guardar
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => _guardar(
                          ctx: ctx,
                          equipo: equipo,
                          nombre: nombreCtrl.text.trim(),
                          codigo: codigoCtrl.text.trim(),
                          marca: marcaCtrl.text.trim(),
                          modelo: modeloCtrl.text.trim(),
                          serie: serieCtrl.text.trim(),
                          areaId: areaId,
                          obs: obsCtrl.text.trim(),
                          clienteId: clienteId,
                          ubicacionId: ubicacionId,
                          zonaId: zonaId,
                          estado: estado,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(equipo == null ? 'Crear equipo' : 'Guardar cambios',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _guardar({
    required BuildContext ctx,
    required EquipoIntervenido? equipo,
    required String nombre,
    required String codigo,
    required String marca,
    required String modelo,
    required String serie,
    required String? areaId,
    required String obs,
    required String? clienteId,
    required String? ubicacionId,
    required String? zonaId,
    required String estado,
  }) async {
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('El nombre es obligatorio')),
      );
      return;
    }
    final body = <String, dynamic>{
      'nombre': nombre,
      if (codigo.isNotEmpty) 'codigo': codigo,
      if (marca.isNotEmpty) 'marca': marca,
      if (modelo.isNotEmpty) 'modelo': modelo,
      if (serie.isNotEmpty) 'numero_serie': serie,
      'area_id': ?areaId,
      if (obs.isNotEmpty) 'observaciones': obs,
      'cliente_id': ?clienteId,
      'ubicacion_id': ?ubicacionId,
      'zona_id': ?zonaId,
      'estado': estado,
    };

    final nav = Navigator.of(ctx);
    final ApiResult<EquipoIntervenido> res;
    if (equipo == null) {
      res = await _svc!.crear(body);
    } else {
      res = await _svc!.actualizar(equipo.id, body);
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    nav.pop();
    if (res.ok) {
      messenger.showSnackBar(SnackBar(
        content: Text(equipo == null ? 'Equipo creado' : 'Equipo actualizado'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      _cargar();
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(res.errorMessage),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  // ── BUILD ───────────────────────────────────────────────────────────────────

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
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.07),
                    blurRadius: 16, offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Mantenimientos',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        tooltip: _vistaParque
                            ? 'Ver como lista'
                            : 'Ver parque por ubicación',
                        onPressed: () =>
                            setState(() => _vistaParque = !_vistaParque),
                        icon: Icon(
                          _vistaParque
                              ? Icons.view_list_rounded
                              : Icons.travel_explore_rounded,
                          color: _green,
                        ),
                      ),
                      if (AppSession.i.canCrearEquipoIntervenido)
                        IconButton(
                          onPressed: () => _abrirFormulario(),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _green,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.add, color: Colors.white, size: 20),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Buscador
                  TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre, cliente, zona...',
                      prefixIcon: const Icon(Icons.search, size: 20, color: _green),
                      suffixIcon: _busqueda.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? _green.withValues(alpha: 0.06) : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Chips de estado
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _estados.map((e) {
                        final sel = _estadoFiltro == e;
                        final label = e == 'todos' ? 'Todos' : _labelEstado(e);
                        final color = e == 'todos' ? _green : _colorEstado(e);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: sel ? Colors.white : color,
                                  fontWeight: FontWeight.w600,
                                )),
                            selected: sel,
                            onSelected: (_) => _setEstado(e),
                            selectedColor: color,
                            backgroundColor: color.withValues(alpha: 0.1),
                            checkmarkColor: Colors.white,
                            showCheckmark: false,
                            side: BorderSide(color: color.withValues(alpha: sel ? 1 : 0.3)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // ── Contador ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Text('${_filtrados.length} equipo${_filtrados.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ),

            // ── Lista ───────────────────────────────────────────────────────
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_green)))
                  : _error != null
                      ? _errorWidget()
                      : _filtrados.isEmpty
                          ? _emptyWidget()
                          : RefreshIndicator(
                              onRefresh: _cargar,
                              color: _green,
                              child: _vistaParque
                                  ? _parqueView(isDark, surface)
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                                      itemCount: _filtrados.length,
                                      itemBuilder: (_, i) => _tarjeta(_filtrados[i], isDark, surface),
                                    ),
                            ),
            ),
          ],
        ),
        ),    // SafeArea
      ),      // TopoBackground
    );        // Scaffold
  }

  Widget _tarjeta(EquipoIntervenido e, bool isDark, Color surface) {
    final color = _colorEstado(e.estado);
    return GestureDetector(
      onTap: () => _verDetalle(e),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: isDark ? Border.all(color: _green.withValues(alpha: 0.15)) : null,
          boxShadow: isDark
              ? [BoxShadow(color: _green.withValues(alpha: 0.06), blurRadius: 10)]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icono de estado
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconEstado(e.estado), color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.nombre,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    // Cadena de ubicacion
                    if (e.ubicacionCompleta.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: Colors.grey),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(e.ubicacionCompleta,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    if (e.tipoEquipoNombre != null || e.marca != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (e.tipoEquipoNombre != null)
                            _miniBadge(e.tipoEquipoNombre!, Colors.blueGrey),
                          if (e.marca != null && e.marca!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _miniBadge(e.marca!, Colors.grey),
                          ],
                        ],
                      ),
                    ],
                    // Semáforo de mantenimiento
                    if (e.proximoMantDate != null) ...[
                      const SizedBox(height: 5),
                      _indicadorMantenimiento(e),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Text(_labelEstado(e.estado),
                        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Vista Parque: equipos agrupados por ubicación → zona con semáforo ───────

  Widget _parqueView(bool isDark, Color surface) {
    // Agrupar los YA filtrados (respeta búsqueda y chips de estado).
    final porUbicacion = <String, List<EquipoIntervenido>>{};
    for (final e in _filtrados) {
      porUbicacion
          .putIfAbsent(e.ubicacionNombre ?? 'Sin ubicación', () => [])
          .add(e);
    }
    final ubicaciones = porUbicacion.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: ubicaciones.length,
      itemBuilder: (_, i) {
        final ubic = ubicaciones[i];
        final equipos = porUbicacion[ubic]!;
        final vencidos =
            equipos.where((e) => (e.diasParaMantenimiento ?? 1) < 0).length;
        final proximos = equipos
            .where((e) {
              final d = e.diasParaMantenimiento;
              return d != null && d >= 0 && d <= 30;
            })
            .length;

        final porZona = <String, List<EquipoIntervenido>>{};
        for (final e in equipos) {
          porZona.putIfAbsent(e.zonaNombre ?? 'Sin zona', () => []).add(e);
        }
        final zonas = porZona.keys.toList()..sort();

        final Color estadoColor = vencidos > 0
            ? Colors.red.shade600
            : proximos > 0
                ? Colors.amber.shade800
                : _green;

        return Container(
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: estadoColor.withValues(alpha: 0.35)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(Icons.location_on_outlined, color: estadoColor),
              title: Text(ubic,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _miniBadge('${equipos.length} equipo${equipos.length == 1 ? '' : 's'}',
                        Colors.blueGrey),
                    if (vencidos > 0)
                      _miniBadge('$vencidos vencido${vencidos == 1 ? '' : 's'}',
                          Colors.red.shade600),
                    if (proximos > 0)
                      _miniBadge('$proximos próximo${proximos == 1 ? '' : 's'} (≤30 d)',
                          Colors.amber.shade800),
                  ],
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final z in zonas) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.layers_outlined,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(z,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  for (final e in porZona[z]!) _tarjeta(e, isDark, surface),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Semáforo de mantenimiento: rojo vencido, ámbar <=30 días, verde al día.
  Widget _indicadorMantenimiento(EquipoIntervenido e) {
    final dias = e.diasParaMantenimiento;
    if (dias == null) return const SizedBox.shrink();
    final Color color;
    final String texto;
    if (dias < 0) {
      color = Colors.red.shade600;
      texto = 'Mant. vencido hace ${-dias} d';
    } else if (dias <= 30) {
      color = Colors.amber.shade800;
      texto = dias == 0 ? 'Mant. hoy' : 'Mant. en $dias d';
    } else {
      color = _green;
      texto = 'Mant. en $dias d';
    }
    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(texto,
            style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _miniBadge(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(texto,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      );

  Widget _errorWidget() => Center(
        child: Column(
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
        ),
      );

  Widget _emptyWidget() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.electrical_services_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _busqueda.isNotEmpty || _estadoFiltro != 'todos'
                  ? 'Sin resultados para el filtro aplicado'
                  : 'No hay equipos intervenidos registrados',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (AppSession.i.canCrearEquipoIntervenido &&
                _busqueda.isEmpty &&
                _estadoFiltro == 'todos') ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _abrirFormulario(),
                icon: const Icon(Icons.add),
                label: const Text('Registrar primer equipo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      );
}

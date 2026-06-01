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
  List<ClienteBasico> _clientes = [];

  bool _cargando = true;
  String? _error;
  String _estadoFiltro = 'todos';
  String _busqueda = '';
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
    final clientes = await _proySvc!.getClientes();
    if (!mounted) return;
    setState(() {
      if (resUbic.ok)  _ubicaciones = resUbic.data ?? [];
      if (resZonas.ok) _zonas = resZonas.data ?? [];
      _clientes = clientes;
    });
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

  // ── Detalle bottom sheet ────────────────────────────────────────────────────

  void _verDetalle(EquipoIntervenido e) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final color = _colorEstado(e.estado);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header con estado
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_iconEstado(e.estado), color: color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.nombre,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (e.codigo != null && e.codigo!.isNotEmpty)
                            Text(e.codigo!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Text(_labelEstado(e.estado),
                          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    // Ubicación
                    if (e.ubicacionCompleta.isNotEmpty) ...[
                      _seccion('UBICACIÓN'),
                      _infoRow(Icons.location_on_outlined, 'Instalación', e.ubicacionCompleta),
                      const SizedBox(height: 4),
                    ],
                    // Proyecto
                    if (e.proyectoNombre != null) ...[
                      _seccion('PROYECTO'),
                      _infoRow(Icons.work_outline, 'Proyecto', e.proyectoNombre!),
                      const SizedBox(height: 4),
                    ],
                    // Datos técnicos
                    _seccion('DATOS TÉCNICOS'),
                    if (e.tipoEquipoNombre != null)
                      _infoRow(Icons.category_outlined, 'Tipo', e.tipoEquipoNombre!),
                    if (e.marca != null && e.marca!.isNotEmpty)
                      _infoRow(Icons.verified_outlined, 'Marca', e.marca!),
                    if (e.modelo != null && e.modelo!.isNotEmpty)
                      _infoRow(Icons.info_outline, 'Modelo', e.modelo!),
                    if (e.numeroSerie != null && e.numeroSerie!.isNotEmpty)
                      _infoRow(Icons.qr_code_outlined, 'N° Serie', e.numeroSerie!),
                    if (e.fechaInstalacion != null)
                      _infoRow(Icons.calendar_today_outlined, 'Instalación', e.fechaInstalacion!),
                    const SizedBox(height: 4),
                    // Ficha técnica
                    if (e.fichaTecnica != null && e.fichaTecnica!.isNotEmpty) ...[
                      _seccion('FICHA TÉCNICA'),
                      ...e.fichaTecnica!.entries
                          .where((en) => en.value != null && en.value.toString().isNotEmpty)
                          .map((en) => _infoRow(
                                Icons.electrical_services_outlined,
                                en.key.replaceAll('_', ' ').toUpperCase(),
                                en.value.toString(),
                              )),
                      const SizedBox(height: 4),
                    ],
                    // Observaciones
                    if (e.observaciones != null && e.observaciones!.isNotEmpty) ...[
                      _seccion('OBSERVACIONES'),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(e.observaciones!,
                            style: const TextStyle(fontSize: 13, height: 1.5)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Botón editar
                    if (AppSession.i.canEditarEquipoIntervenido)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _abrirFormulario(equipo: e);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Editar equipo'),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seccion(String titulo) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(titulo,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: Colors.grey, letterSpacing: 0.8)),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: _green),
            const SizedBox(width: 10),
            SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  // ── Formulario crear / editar ───────────────────────────────────────────────

  void _abrirFormulario({EquipoIntervenido? equipo}) {
    final nombreCtrl     = TextEditingController(text: equipo?.nombre ?? '');
    final codigoCtrl     = TextEditingController(text: equipo?.codigo ?? '');
    final marcaCtrl      = TextEditingController(text: equipo?.marca ?? '');
    final modeloCtrl     = TextEditingController(text: equipo?.modelo ?? '');
    final serieCtrl      = TextEditingController(text: equipo?.numeroSerie ?? '');
    final areaCtrl       = TextEditingController(text: equipo?.areaDescripcion ?? '');
    final obsCtrl        = TextEditingController(text: equipo?.observaciones ?? '');
    String? clienteId    = equipo?.clienteId;
    String? ubicacionId  = equipo?.ubicacionId;
    String? zonaId       = equipo?.zonaId;
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
                      value: clienteId,
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
                      value: ubicacionId,
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
                      }),
                    ),
                    const SizedBox(height: 14),
                    // Zona
                    DropdownButtonFormField<String>(
                      value: zonasFiltradas.any((z) => z.id == zonaId) ? zonaId : null,
                      isExpanded: true,
                      decoration: deco('Zona / Almacén', Icons.warehouse_outlined),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sin zona')),
                        ...zonasFiltradas.map((z) => DropdownMenuItem(
                              value: z.id,
                              child: Text(z.nombre, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setLocal(() => zonaId = v),
                    ),
                    const SizedBox(height: 14),
                    TextField(controller: areaCtrl,
                        decoration: deco('Área (ej: Área de Logística)', Icons.domain_outlined)),
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
                      value: estado,
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
                          area: areaCtrl.text.trim(),
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
    required String area,
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
      if (area.isNotEmpty) 'area_descripcion': area,
      if (obs.isNotEmpty) 'observaciones': obs,
      if (clienteId != null) 'cliente_id': clienteId,
      if (ubicacionId != null) 'ubicacion_id': ubicacionId,
      if (zonaId != null) 'zona_id': zonaId,
      'estado': estado,
    };

    final ApiResult<EquipoIntervenido> res;
    if (equipo == null) {
      res = await _svc!.crear(body);
    } else {
      res = await _svc!.actualizar(equipo.id, body);
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(ctx);
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

    return TopoBackground(
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
                        child: Text('Equipos Intervenidos',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                                itemCount: _filtrados.length,
                                itemBuilder: (_, i) => _tarjeta(_filtrados[i], isDark, surface),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
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

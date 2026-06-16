import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_result.dart';
import '../models/equipo_models.dart';
import '../services/equipo_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import '../widgets/topo_background.dart';
import '../widgets/geo_cascade_picker.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_preview_screen.dart';
import '../widgets/scanner_codigo.dart';

class PantallaEquiposLogistica extends StatefulWidget {
  const PantallaEquiposLogistica({super.key});
  @override
  State<PantallaEquiposLogistica> createState() => _State();
}

class _State extends State<PantallaEquiposLogistica>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF8FD11B);

  static const _pageSize = 40;
  static const _clases = ['equipo', 'herramienta', 'equipo_tecnologico'];

  EquipoService? _svc;
  late TabController _tabs;

  // Estado paginado por clase (Tab 0=equipo, 1=herramienta, 2=equipo_tecnologico)
  final Map<String, _ClaseData> _data = {
    'equipo': _ClaseData(),
    'herramienta': _ClaseData(),
    'equipo_tecnologico': _ClaseData(),
  };
  bool _cargando = true;
  String? _error;
  String _estado = 'todos'; // todos|operativo|en_mantenimiento|fuera_de_servicio|baja

  final _searchCtrl = TextEditingController();
  String _q = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    for (final c in _clases) {
      _data[c]!.scroll.addListener(() => _onScroll(c));
    }
    _searchCtrl.addListener(() {
      if (_searchCtrl.text != _q) {
        _q = _searchCtrl.text;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), () => _cargar());
      }
    });
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    for (final c in _clases) {
      _data[c]!.scroll.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getEquipoService();
    await _cargar();
  }

  void _onScroll(String clase) {
    final d = _data[clase]!;
    if (d.loadingMore || !d.hasMore || _cargando) return;
    if (d.scroll.position.pixels >= d.scroll.position.maxScrollExtent - 240) {
      _loadMore(clase);
    }
  }

  /// Recarga la primera página de las 3 clases (reset). Usado en init, búsqueda,
  /// cambio de filtro de estado y pull-to-refresh.
  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final results = await Future.wait([
      for (final c in _clases)
        _svc!.listar(q: _q, clase: c, estado: _estado, page: 1, pageSize: _pageSize),
    ]);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      for (var i = 0; i < _clases.length; i++) {
        final d = _data[_clases[i]]!;
        final res = results[i];
        if (res.ok) {
          d.items = res.data?.items ?? [];
          d.total = res.data?.total ?? d.items.length;
          d.page = 1;
          d.hasMore = d.items.length >= _pageSize;
        } else if (i == 0) {
          _error = res.errorMessage;
        }
      }
    });
  }

  Future<void> _loadMore(String clase) async {
    final d = _data[clase]!;
    if (_svc == null || d.loadingMore || !d.hasMore) return;
    setState(() => d.loadingMore = true);
    final next = d.page + 1;
    final res = await _svc!.listar(
        q: _q, clase: clase, estado: _estado, page: next, pageSize: _pageSize);
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        final nuevos = res.data?.items ?? [];
        d.items.addAll(nuevos);
        d.page = next;
        d.hasMore = nuevos.length >= _pageSize;
      } else {
        d.hasMore = false;
      }
      d.loadingMore = false;
    });
  }

  void _setEstado(String e) {
    setState(() => _estado = _estado == e ? 'todos' : e);
    _cargar();
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

  IconData _iconoMov(String tipo) => switch (tipo) {
        'alta' => Icons.add_circle_outline,
        'transferencia' => Icons.compare_arrows_rounded,
        'mantenimiento' => Icons.build_circle_outlined,
        'baja' => Icons.cancel_outlined,
        'asignacion' => Icons.assignment_ind_outlined,
        'retorno' => Icons.assignment_return_outlined,
        _ => Icons.history,
      };

  // ── Historial (bitácora) de la unidad ────────────────────────────────────────
  void _verHistorial(EquipoItem e) {
    final surface = Theme.of(context).colorScheme.surface;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _svc?.movimientos(e.id) ?? Future.value(const []),
        builder: (ctx, snap) {
          final movs = snap.data ?? const [];
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.92,
            expand: false,
            builder: (_, ctrl) => Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Text('Historial · ${e.nombre}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (snap.connectionState == ConnectionState.waiting)
                    const Expanded(child: Center(child: CircularProgressIndicator()))
                  else if (movs.isEmpty)
                    const Expanded(
                        child: Center(
                            child: Text('Sin eventos registrados',
                                style: TextStyle(color: Colors.grey))))
                  else
                    Expanded(
                      child: ListView.separated(
                        controller: ctrl,
                        itemCount: movs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final m = movs[i];
                          final fecha = (m['fecha'] ?? '').toString();
                          final partes = [
                            (m['tipo'] ?? '').toString(),
                            (m['responsable_nombre'] ?? '').toString(),
                            fecha.isNotEmpty ? fecha.split('T').first : '',
                          ].where((x) => x.isNotEmpty).join(' · ');
                          return ListTile(
                            dense: true,
                            leading: Icon(_iconoMov(m['tipo']?.toString() ?? ''),
                                size: 20, color: _green),
                            title: Text((m['detalle'] ?? m['tipo'] ?? '').toString(),
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(partes, style: const TextStyle(fontSize: 11)),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

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
                  child: Icon(
                      e.esHerramienta      ? Icons.handyman_outlined
                    : e.esEquipoTecnologico ? Icons.devices_outlined
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

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _verHistorial(e),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Ver historial'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _generarEtiqueta(e),
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: const Text('Etiqueta QR'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                if (AppSession.i.canGestionarInventario) ...[
                  const SizedBox(height: 12),
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

  // Escanea un código y lo vuelca en el buscador para filtrar la lista.
  Future<void> _escanearBuscar() async {
    final cod = await ScannerCodigo.abrir(context, titulo: 'Escanear equipo');
    if (cod != null && cod.trim().isNotEmpty) {
      _searchCtrl.text = cod.trim();
    }
  }

  // Genera y previsualiza la etiqueta QR imprimible del equipo.
  Future<void> _generarEtiqueta(EquipoItem e) async {
    final codigo = e.codigo.trim().isNotEmpty
        ? e.codigo.trim()
        : (e.numeroSerie?.trim() ?? '');
    if (codigo.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El equipo no tiene código ni N° de serie para la etiqueta.'),
      ));
      return;
    }
    final bytes = await PdfService.etiquetaEquipo(
      codigo: codigo,
      nombre: e.nombre,
      marca: e.marca,
      modelo: e.modelo,
      numeroSerie: e.numeroSerie,
    );
    if (!mounted) return;
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo: 'etiqueta_$codigo.pdf',
      titulo: 'Etiqueta · $codigo',
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
    // Tab 0=Equipos, Tab 1=Herramientas, Tab 2=Activos TI
    final clasesPorTab = ['equipo', 'herramienta', 'equipo_tecnologico'];
    String clase = item?.clase ?? clasesPorTab[_tabs.index.clamp(0, 2)];
    String estado    = item?.estado ?? 'operativo';
    bool reqMant     = item?.requiereMantenimiento ?? false;
    String frecuencia= item?.frecuenciaMantenimiento ?? 'ninguno';
    // Ubicación geográfica (FK) del equipo
    GeoSeleccion geo = GeoSeleccion(
        ubicacionId: item?.ubicacionId, zonaId: item?.zonaId, areaId: item?.areaId);

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
                      child: Icon(
                          clase == 'herramienta'        ? Icons.handyman_outlined
                        : clase == 'equipo_tecnologico' ? Icons.devices_outlined
                        : Icons.precision_manufacturing_outlined,
                          color: _green, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(item == null ? 'Nuevo registro' : 'Editar registro',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 20),

                  // Tipo (equipo / herramienta / equipo_tecnologico)
                  Row(children: [
                    Expanded(child: _tipoChip('equipo', 'Equipo',
                        Icons.precision_manufacturing_outlined, clase, setLocal, (v) => clase = v)),
                    const SizedBox(width: 6),
                    Expanded(child: _tipoChip('herramienta', 'Herramienta',
                        Icons.handyman_outlined, clase, setLocal, (v) => clase = v)),
                    const SizedBox(width: 6),
                    Expanded(child: _tipoChip('equipo_tecnologico', 'Activo TI',
                        Icons.devices_outlined, clase, setLocal, (v) => clase = v)),
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
                    initialValue: estado,
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
                    activeThumbColor: _green,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (reqMant) ...[
                    DropdownButtonFormField<String>(
                      initialValue: frecuencia == 'ninguno' ? 'mensual' : frecuencia,
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

                  // Ubicación geográfica (cascada Ubicación → Zona → Área)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('UBICACIÓN', style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.8)),
                    ),
                  ),
                  GeoCascadePicker(
                    valor: geo,
                    onChanged: (g) => setLocal(() => geo = g),
                  ),
                  const SizedBox(height: 16),

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
                        geo: geo,
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
    GeoSeleccion? geo,
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
      // Jerarquía geográfica (FK, camelCase como espera EquipoIn). "" limpia.
      'ubicacionId': geo?.ubicacionId ?? '',
      'zonaId': geo?.zonaId ?? '',
      'areaId': geo?.areaId ?? '',
    };

    final nav = Navigator.of(ctx);
    final ApiResult res = item == null
        ? await _svc!.crear(body)
        : await _svc!.actualizar(item.id, body);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
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
                const Expanded(child: Text('Equipos',
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
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_q.isNotEmpty)
                      IconButton(icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchCtrl.clear()),
                    IconButton(
                      tooltip: 'Escanear código',
                      icon: const Icon(Icons.qr_code_scanner_rounded,
                          size: 20, color: _green),
                      onPressed: _escanearBuscar,
                    ),
                  ]),
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
              // Tabs (con total real del backend, no solo lo cargado)
              TabBar(
                controller: _tabs,
                labelColor: _green,
                unselectedLabelColor: Colors.grey,
                indicatorColor: _green,
                indicatorSize: TabBarIndicatorSize.label,
                isScrollable: true,
                tabs: [
                  Tab(text: 'Equipos (${_data['equipo']!.total})'),
                  Tab(text: 'Herramientas (${_data['herramienta']!.total})'),
                  Tab(text: 'Activos TI (${_data['equipo_tecnologico']!.total})'),
                ],
              ),
            ]),
          ),
          // Chips de filtro por estado
          _estadoChips(),
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
                          _lista('equipo',              Icons.precision_manufacturing_outlined),
                          _lista('herramienta',         Icons.handyman_outlined),
                          _lista('equipo_tecnologico',  Icons.devices_outlined),
                        ],
                      ),
          ),
        ]),
        ),      // SafeArea
      ),        // TopoBackground
    );          // Scaffold
  }

  // ── Chips de filtro por estado operativo ──────────────────────────────────
  Widget _estadoChips() {
    const opciones = [
      ('todos', 'Todos'),
      ('operativo', 'Operativo'),
      ('en_mantenimiento', 'Mantenimiento'),
      ('fuera_de_servicio', 'Fuera de servicio'),
      ('baja', 'Baja'),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        children: [
          for (final (val, label) in opciones)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _setEstado(val),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _estado == val
                        ? (val == 'todos' ? _green : _colorEstado(val))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: _estado == val
                            ? (val == 'todos' ? _green : _colorEstado(val))
                            : Colors.grey.shade300),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              _estado == val ? FontWeight.w700 : FontWeight.w500,
                          color: _estado == val ? Colors.white : Colors.grey.shade600)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lista(String clase, IconData icon) {
    final d = _data[clase]!;
    if (d.items.isEmpty) return _emptyWidget();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return RefreshIndicator(
      onRefresh: _cargar,
      color: _green,
      child: ListView.builder(
        controller: d.scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        itemCount: d.items.length + (d.loadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == d.items.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _green)),
              ),
            );
          }
          return _tarjeta(d.items[i], icon, isDark, surface);
        },
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

/// Estado paginado de una clase (equipo / herramienta / equipo_tecnologico).
class _ClaseData {
  List<EquipoItem> items = [];
  int total = 0;
  int page = 1;
  bool hasMore = true;
  bool loadingMore = false;
  final ScrollController scroll = ScrollController();
}

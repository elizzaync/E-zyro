// pantalla_ingreso_directo.dart — Ingreso Directo de Logística.
//
// Registra uno o varios artículos (material/equipo/herramienta/equipo_tecnológico)
// en una sola operación, ya sea NUEVOS (form dinámico) o EXISTENTES (clonando un
// artículo por código). Define el destino del ingreso (stock / servicio /
// correctivo) y la cabecera (quién compró, fecha, proveedor) y los envía al
// backend vía `POST /logistica/ingreso-directo`.
//
// Reutiliza los 3 artefactos de la Ola 1 (modelos + servicio + FormArticuloDinamico)
// y los servicios existentes de Personal / Proyectos / Correctivos.

import 'package:flutter/material.dart';

import '../../models/ingreso_directo_models.dart';
import '../../models/personal_models.dart';
import '../../models/proyecto_models.dart';
import '../../models/correctivo_models.dart';
import '../../models/compras_models.dart' show Proveedor;
import '../../services/ingreso_directo_service.dart';
import '../../services/personal_service.dart';
import '../../services/proyecto_service.dart';
import '../../services/correctivo_service.dart';
import '../../services/compras_service.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../widgets/form_articulo_dinamico.dart';
import '../../widgets/scanner_codigo.dart';
import 'almacen/es_tokens.dart';
import 'almacen/es_widgets.dart';

/// Clases de artículo soportadas por el form-schema del backend.
class _Clase {
  final String key;
  final String label;
  final IconData icon;
  const _Clase(this.key, this.label, this.icon);
}

const List<_Clase> _kClases = [
  _Clase('material', 'Material', Icons.inventory_2_outlined),
  _Clase('equipo', 'Equipo', Icons.handyman_outlined),
  _Clase('herramienta', 'Herramienta', Icons.build_outlined),
  _Clase('equipo_tecnologico', 'Tecnológico', Icons.devices_other_outlined),
];

class PantallaIngresoDirecto extends StatefulWidget {
  const PantallaIngresoDirecto({super.key});

  @override
  State<PantallaIngresoDirecto> createState() => _PantallaIngresoDirectoState();
}

class _PantallaIngresoDirectoState extends State<PantallaIngresoDirecto> {
  // Servicios
  IngresoDirectoService? _svc;
  PersonalService? _personalSvc;
  ProyectoService? _proyectoSvc;
  CorrectivoService? _correctivoSvc;

  // Selección de clase + esquema dinámico
  int _claseIndex = 0;
  String get _clase => _kClases[_claseIndex].key;
  FormSchemaOut? _schema;
  bool _cargandoSchema = false;
  String? _schemaError;

  // Modo: 0 = nuevos, 1 = existentes
  int _modo = 0;

  // Form dinámico (recreado al cambiar de clase/esquema/clonado)
  FormArticuloController _formCtrl = FormArticuloController();
  Map<String, dynamic>? _valoresIniciales; // para clonar un existente
  String? _existenteId; // id del artículo clonado (modo existente)

  // Modelo dinámico dependiente de la marca (dropdown propio de la pantalla,
  // porque el FormSchema del backend devuelve `modeloId` con opciones vacías).
  bool get _tieneMarcaModelo =>
      (_schema?.campos.any((c) => c.key == 'marcaId') ?? false) &&
      (_schema?.campos.any((c) => c.key == 'modeloId') ?? false);
  String? _ultimaMarcaId;
  List<FormOpcion> _modelos = [];
  String? _modeloSeleccionado;
  bool _cargandoModelos = false;

  // Búsqueda por código (modo existente / escaneo)
  final TextEditingController _codigoCtrl = TextEditingController();
  bool _buscando = false;
  ArticuloPorCodigo? _hallado;

  // Lista de ítems agregados
  final List<IngresoItem> _items = [];

  // ── Cabecera del ingreso ───────────────────────────────────────────────────
  List<Empleado> _empleados = [];
  String? _personalCompraId;
  DateTime _fechaCompra = DateTime.now();
  final TextEditingController _proveedorCtrl = TextEditingController();
  final TextEditingController _notasCtrl = TextEditingController();

  // ── Comprobante (genera Cuenta por Pagar) ───────────────────────────────────
  ComprasService? _comprasSvc;
  FinanzasService? _finanzasSvc;
  List<Proveedor> _proveedores = [];
  bool _compActiva = false;
  String? _compProveedorId;
  String _compTipoDoc = 'factura';
  final TextEditingController _compNumeroCtrl = TextEditingController();
  DateTime? _compFechaEmision;
  DateTime? _compFechaVencimiento;
  final TextEditingController _compSubtotalCtrl = TextEditingController();
  final TextEditingController _compIgvCtrl = TextEditingController();
  // Tasa de IGV (porcentaje) leída de la configuración tributaria. El IGV se
  // autocalcula desde el subtotal; el usuario puede sobrescribirlo a mano
  // (exonerado/inafecto) y se respeta hasta que vuelva a cambiar el subtotal.
  double _tasaIgv = 18.0;
  bool _igvEditadoManual = false;

  // Destino: stock | servicio | correctivo
  String _destinoTipo = 'stock';
  List<ProyectoItem> _proyectos = [];
  String? _proyectoSelId; // para filtrar servicios
  List<ServicioItem> _servicios = [];
  String? _servicioSelId;
  List<Correctivo> _correctivos = [];
  String? _correctivoSelId;
  bool _cargandoServicios = false;
  bool _cargandoCorrectivos = false;

  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _proveedorCtrl.dispose();
    _notasCtrl.dispose();
    _compNumeroCtrl.dispose();
    _compSubtotalCtrl.dispose();
    _compIgvCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getIngresoDirectoService();
    _personalSvc = await getPersonalService();
    _proyectoSvc = await getProyectoService();
    _correctivoSvc = await getCorrectivoService();
    _comprasSvc = await getComprasService();
    _finanzasSvc = await getFinanzasService();
    await _cargarSchema();
    await _cargarAuxiliares();
  }

  Future<void> _cargarAuxiliares() async {
    // Empleados (para "Personal que compró")
    final emp = await _personalSvc!.listar();
    // Proyectos (para resolver servicios y correctivos)
    final proy = await _proyectoSvc!.getProyectos();
    // Proveedores (para el comprobante / CxP)
    final provs = await _comprasSvc!.getProveedores();
    // Tasa de IGV vigente (configuración tributaria; default 18%).
    final tasa = await _finanzasSvc!.getTasaIgv();
    if (!mounted) return;
    setState(() {
      if (emp.ok) _empleados = emp.data ?? [];
      _proyectos = proy?.proyectos ?? [];
      _proveedores = provs;
      _tasaIgv = tasa;
    });
  }

  Future<void> _cargarSchema() async {
    setState(() {
      _cargandoSchema = true;
      _schemaError = null;
    });
    try {
      final s = await _svc!.formSchema(_clase);
      if (!mounted) return;
      setState(() {
        _schema = s;
        // Reinicia el form al cambiar de clase.
        _formCtrl = FormArticuloController();
        _valoresIniciales = null;
        _existenteId = null;
        _ultimaMarcaId = null;
        _modelos = [];
        _modeloSeleccionado = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _schemaError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargandoSchema = false);
    }
  }

  // ── Modelo dependiente de marca ─────────────────────────────────────────────

  /// Disparado por el form en cada cambio: si cambió `marcaId`, recarga modelos.
  void _onFormChanged() {
    if (!_tieneMarcaModelo) return;
    final marcaId = _formCtrl.valores['marcaId']?.toString();
    if (marcaId == _ultimaMarcaId) return;
    _ultimaMarcaId = marcaId;
    if (marcaId == null || marcaId.isEmpty) {
      setState(() {
        _modelos = [];
        _modeloSeleccionado = null;
      });
      return;
    }
    _cargarModelos(marcaId);
  }

  Future<void> _cargarModelos(String marcaId) async {
    setState(() {
      _cargandoModelos = true;
      _modelos = [];
      _modeloSeleccionado = null;
    });
    try {
      final m = await _svc!.modelosPorMarca(marcaId);
      if (!mounted || _ultimaMarcaId != marcaId) return;
      setState(() => _modelos = m);
    } catch (_) {
      // Silencioso: el modelo es opcional; queda dropdown vacío.
    } finally {
      if (mounted) setState(() => _cargandoModelos = false);
    }
  }

  // ── Búsqueda por código (existentes) ────────────────────────────────────────

  Future<void> _buscarCodigo() async {
    final codigo = _codigoCtrl.text.trim();
    if (codigo.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _buscando = true;
      _hallado = null;
    });
    try {
      final art = await _svc!.buscarPorCodigo(codigo);
      if (!mounted) return;
      if (art == null) {
        setState(() => _hallado = null);
        _toast('No se encontró ningún artículo con ese código.');
        return;
      }
      // Precarga (clona) los datos del artículo en el form.
      final ini = <String, dynamic>{};
      for (final f in _schema?.campos ?? const <FormFieldDef>[]) {
        final v = art[f.key];
        if (v != null) ini[f.key] = v;
      }
      ini['nombre'] = art.nombre;
      ini['codigo'] = art.codigo;
      setState(() {
        _hallado = art;
        _existenteId = art.id;
        _valoresIniciales = ini;
        // Recrea el controller para forzar el re-init con los valores clonados.
        _formCtrl = FormArticuloController();
        _ultimaMarcaId = null;
        _modelos = [];
        _modeloSeleccionado = art['modeloId']?.toString();
      });
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  // ── Agregar ítem a la lista ─────────────────────────────────────────────────

  void _agregarItem() {
    if (_schema == null) return;
    if (!_formCtrl.validar()) {
      _toast('Revisa los campos obligatorios.');
      return;
    }
    final esExistente = _modo == 1 && _existenteId != null;
    final base = IngresoItem(
      clase: _clase,
      modo: esExistente ? 'existente' : 'nuevo',
      existenteId: esExistente ? _existenteId : null,
    );
    var item = _formCtrl.buildItem(base: base);
    // El modelo se selecciona en un dropdown propio de la pantalla.
    if (_tieneMarcaModelo && _modeloSeleccionado != null) {
      item = item.copyWith(modeloId: _modeloSeleccionado);
    }
    setState(() {
      _items.add(item);
      // Limpia el form para el siguiente ítem.
      _formCtrl = FormArticuloController();
      _valoresIniciales = null;
      _existenteId = null;
      _hallado = null;
      _codigoCtrl.clear();
      _ultimaMarcaId = null;
      _modelos = [];
      _modeloSeleccionado = null;
    });
    _toast('Ítem agregado a la lista.');
  }

  void _quitarItem(int i) => setState(() => _items.removeAt(i));

  // ── Destino: servicios / correctivos ────────────────────────────────────────

  Future<void> _onProyectoSel(String? id) async {
    setState(() {
      _proyectoSelId = id;
      _servicios = [];
      _servicioSelId = null;
      _correctivos = [];
      _correctivoSelId = null;
    });
    if (id == null) return;
    setState(() => _cargandoServicios = true);
    final s = await _proyectoSvc!.getServiciosProyecto(id);
    if (!mounted) return;
    setState(() {
      _servicios = s;
      _cargandoServicios = false;
    });
  }

  Future<void> _onServicioSel(String? id) async {
    setState(() {
      _servicioSelId = id;
      _correctivos = [];
      _correctivoSelId = null;
    });
    if (_destinoTipo == 'correctivo' && id != null) {
      setState(() => _cargandoCorrectivos = true);
      final r = await _correctivoSvc!.listar(servicioId: id);
      if (!mounted) return;
      setState(() {
        _correctivos = r.ok ? (r.data ?? []) : [];
        _cargandoCorrectivos = false;
      });
    }
  }

  DestinoIngreso _buildDestino() {
    switch (_destinoTipo) {
      case 'servicio':
        return DestinoIngreso(tipo: 'servicio', servicioId: _servicioSelId);
      case 'correctivo':
        return DestinoIngreso(
            tipo: 'correctivo', correctivoId: _correctivoSelId);
      default:
        return const DestinoIngreso.stock();
    }
  }

  String? _validarDestino() {
    if (_destinoTipo == 'servicio' && (_servicioSelId == null)) {
      return 'Selecciona el servicio de destino.';
    }
    if (_destinoTipo == 'correctivo' && (_correctivoSelId == null)) {
      return 'Selecciona el correctivo de destino.';
    }
    return null;
  }

  // ── Comprobante (CxP) ───────────────────────────────────────────────────────

  double get _compSubtotal =>
      double.tryParse(_compSubtotalCtrl.text.trim().replaceAll(',', '.')) ?? 0;
  double get _compIgv =>
      double.tryParse(_compIgvCtrl.text.trim().replaceAll(',', '.')) ?? 0;

  /// Recalcula el IGV a partir del subtotal y la tasa configurada, salvo que el
  /// usuario lo haya editado a mano (override exonerado/inafecto).
  void _onSubtotalChanged() {
    if (!_igvEditadoManual) {
      final igv = _compSubtotal * _tasaIgv / 100;
      _compIgvCtrl.text = igv.toStringAsFixed(2);
    }
    setState(() {});
  }

  void _onIgvEditadoManual() {
    _igvEditadoManual = true;
    setState(() {});
  }

  /// Valida la sección del comprobante (solo si está activa). Devuelve mensaje
  /// de error o null si todo OK.
  String? _validarComprobante() {
    if (!_compActiva) return null;
    if (_compProveedorId == null) return 'Selecciona el proveedor del comprobante.';
    if (_compTipoDoc.trim().isEmpty) return 'Selecciona el tipo de documento.';
    if (_compNumeroCtrl.text.trim().isEmpty) {
      return 'Ingresa el número de documento.';
    }
    if (_compFechaEmision == null) return 'Selecciona la fecha de emisión.';
    if (_compFechaVencimiento == null) {
      return 'Selecciona la fecha de vencimiento.';
    }
    if (_compFechaVencimiento!.isBefore(_compFechaEmision!)) {
      return 'La fecha de vencimiento no puede ser anterior a la de emisión.';
    }
    if (_compSubtotal <= 0) return 'El subtotal debe ser mayor a 0.';
    return null;
  }

  ComprobanteCompra _buildComprobante() => ComprobanteCompra(
        proveedorId: _compProveedorId!,
        tipoDocumento: _compTipoDoc,
        numeroDocumento: _compNumeroCtrl.text.trim(),
        fechaEmision: _fmtFecha(_compFechaEmision!),
        fechaVencimiento: _fmtFecha(_compFechaVencimiento!),
        subtotal: _compSubtotal,
        igv: _compIgv,
      );

  // ── Guardar ─────────────────────────────────────────────────────────────────

  Future<void> _guardar() async {
    if (_items.isEmpty) {
      _toast('Agrega al menos un ítem.');
      return;
    }
    final errDest = _validarDestino();
    if (errDest != null) {
      _toast(errDest);
      return;
    }
    final errComp = _validarComprobante();
    if (errComp != null) {
      _toast(errComp);
      return;
    }
    setState(() => _guardando = true);
    try {
      // Si hay comprobante, el nombre del proveedor manda sobre el campo libre.
      final compProvNombre = _compActiva
          ? _proveedores
              .where((p) => p.id == _compProveedorId)
              .map((p) => p.nombre)
              .firstOrNull
          : null;
      final proveedorTxt = _proveedorCtrl.text.trim();
      final req = IngresoDirectoRequest(
        personalCompraId: _personalCompraId,
        fechaCompra: _fmtFecha(_fechaCompra),
        proveedor: (compProvNombre != null && compProvNombre.isNotEmpty)
            ? compProvNombre
            : (proveedorTxt.isEmpty ? null : proveedorTxt),
        destino: _buildDestino(),
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
        items: List.of(_items),
        comprobante: _compActiva ? _buildComprobante() : null,
      );
      final res = await _svc!.registrarIngresoDirecto(req);
      if (!mounted) return;
      await _mostrarResultado(res);
      setState(() {
        _items.clear();
        _proveedorCtrl.clear();
        _notasCtrl.clear();
        // Reinicia la sección del comprobante.
        _compActiva = false;
        _compProveedorId = null;
        _compTipoDoc = 'factura';
        _compNumeroCtrl.clear();
        _compFechaEmision = null;
        _compFechaVencimiento = null;
        _compSubtotalCtrl.clear();
        _compIgvCtrl.clear();
        _igvEditadoManual = false;
      });
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _mostrarResultado(IngresoDirectoResult res) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ESC.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.check_circle_rounded, color: ESC.entreg, size: 26),
          const SizedBox(width: 10),
          Text('Ingreso registrado',
              style: pj(size: 17, weight: FontWeight.w800)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${res.totalItems} ítem(s) ingresados a ${res.destino}.',
                style: pj(size: 14, color: ESC.inkSub)),
            const SizedBox(height: 8),
            for (final it in res.items)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• ${it.nombre}  x${it.cantidad}  ${it.creado ? '(nuevo)' : '(stock+)'}',
                  style: pj(size: 12.5, color: ESC.ink),
                ),
              ),
            if (res.cxpError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ESC.vencido.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ESC.vencido.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 18, color: ESC.vencido),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ingreso OK, pero la Cuenta por Pagar no se creó: '
                        '${res.cxpError}. Créala manualmente en Finanzas.',
                        style: pj(size: 12, color: ESC.vencido),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (res.cxpFacturaId != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ESC.entreg.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ESC.entreg.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        size: 18, color: ESC.entreg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Cuenta por Pagar generada en Finanzas.',
                          style: pj(size: 12.5, color: ESC.ink)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido',
                style: pj(size: 14, weight: FontWeight.w700, color: ESC.brandDeep)),
          ),
        ],
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ESC.bg,
      body: Column(
        children: [
          ESPanelBar(
            title: 'Ingreso Directo',
            subtitle: '${_items.length} ítem(s) en la lista',
            trailing: ESBarIcon(Icons.refresh_rounded, onTap: _cargarSchema),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ESSectionLabel('Tipo de artículo'),
                  const SizedBox(height: 8),
                  _selectorClase(),
                  const SizedBox(height: 18),
                  const ESSectionLabel('Origen del ítem'),
                  const SizedBox(height: 8),
                  ESSegmented(
                    items: const [
                      ESSeg('Nuevo', icon: Icons.add_box_outlined),
                      ESSeg('Existente', icon: Icons.qr_code_scanner_rounded),
                    ],
                    selected: _modo,
                    onChanged: (i) => setState(() => _modo = i),
                  ),
                  const SizedBox(height: 14),
                  if (_modo == 1) ...[
                    _buscadorCodigo(),
                    const SizedBox(height: 14),
                  ],
                  _formCard(),
                  const SizedBox(height: 12),
                  ESButton('Agregar a la lista',
                      icon: Icons.playlist_add_rounded,
                      expand: true,
                      onTap: _schema == null ? null : _agregarItem),
                  const SizedBox(height: 22),
                  _listaItems(),
                  const SizedBox(height: 22),
                  const ESSectionLabel('Información del ingreso'),
                  const SizedBox(height: 8),
                  _cabecera(),
                  const SizedBox(height: 14),
                  _comprobante(),
                  const SizedBox(height: 14),
                  _destino(),
                  const SizedBox(height: 24),
                  ESButton(
                    _guardando ? 'Guardando…' : 'Registrar ingreso',
                    icon: Icons.save_rounded,
                    expand: true,
                    onTap: _guardando ? null : _guardar,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorClase() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < _kClases.length; i++)
          GestureDetector(
            onTap: i == _claseIndex
                ? null
                : () {
                    setState(() => _claseIndex = i);
                    _cargarSchema();
                  },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: i == _claseIndex ? ESC.brand : ESC.surface,
                borderRadius: BorderRadius.circular(999),
                border: i == _claseIndex
                    ? null
                    : Border.all(color: ESC.line, width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_kClases[i].icon,
                    size: 16,
                    color: i == _claseIndex ? Colors.white : ESC.inkSub),
                const SizedBox(width: 6),
                Text(_kClases[i].label,
                    style: pj(
                        size: 13,
                        weight: FontWeight.w700,
                        color: i == _claseIndex ? Colors.white : ESC.inkSub)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _buscadorCodigo() {
    return ESCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Buscar artículo por código / N° serie',
              style: pj(size: 13, weight: FontWeight.w700, color: ESC.ink)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _codigoCtrl,
                style: pj(size: 14.5, color: ESC.ink),
                onSubmitted: (_) => _buscarCodigo(),
                decoration: InputDecoration(
                  hintText: 'Código…',
                  hintStyle: pj(size: 13.5, color: ESC.inkFaint),
                  filled: true,
                  fillColor: ESC.surfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: ESC.lineStrong),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: ESC.lineStrong),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _miniBtn(Icons.qr_code_scanner_rounded, () async {
              final cod = await ScannerCodigo.abrir(context,
                  titulo: 'Escanear artículo');
              if (cod != null && cod.trim().isNotEmpty) {
                _codigoCtrl.text = cod.trim();
                _buscarCodigo();
              }
            }),
            const SizedBox(width: 8),
            _miniBtn(
              _buscando ? null : Icons.search_rounded,
              _buscando ? null : _buscarCodigo,
              loading: _buscando,
            ),
          ]),
          if (_hallado != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ESC.matBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    size: 18, color: ESC.entreg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_hallado!.nombre} · ${_hallado!.codigo}',
                    style: pj(size: 12.5, weight: FontWeight.w600, color: ESC.ink),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniBtn(IconData? icon, VoidCallback? onTap, {bool loading = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: ESC.brand,
          borderRadius: BorderRadius.circular(14),
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _formCard() {
    if (_cargandoSchema) {
      return const ESCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator(color: ESC.brandDeep)),
        ),
      );
    }
    if (_schemaError != null) {
      return ESCard(
        accent: ESC.vencido,
        child: Row(children: [
          const Icon(Icons.error_outline, color: ESC.vencido),
          const SizedBox(width: 10),
          Expanded(
              child: Text(_schemaError!,
                  style: pj(size: 13, color: ESC.vencido))),
        ]),
      );
    }
    final schema = _schema;
    if (schema == null) return const SizedBox.shrink();
    return ESCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(schema.titulo,
              style: pj(size: 15, weight: FontWeight.w800, color: ESC.ink)),
          const SizedBox(height: 14),
          FormArticuloDinamico(
            // Key por clase + modo de clonado para forzar re-init al clonar.
            key: ValueKey('${schema.clase}-${_existenteId ?? 'nuevo'}'),
            schema: schema,
            controller: _formCtrl,
            valoresIniciales: _valoresIniciales,
            onChanged: _onFormChanged,
          ),
          if (_tieneMarcaModelo) ...[
            const SizedBox(height: 4),
            _dropdownModelo(),
          ],
        ],
      ),
    );
  }

  Widget _dropdownModelo() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue:
            _modelos.any((m) => m.id == _modeloSeleccionado) ? _modeloSeleccionado : null,
        isExpanded: true,
        style: pj(size: 14.5, color: ESC.ink),
        decoration: InputDecoration(
          labelText: 'Modelo',
          labelStyle: pj(size: 13.5, color: ESC.inkSub),
          helperText: _ultimaMarcaId == null
              ? 'Selecciona primero una marca'
              : (_cargandoModelos
                  ? 'Cargando modelos…'
                  : (_modelos.isEmpty ? 'Sin modelos para esta marca' : null)),
          helperStyle: pj(size: 11, color: ESC.inkFaint),
          filled: true,
          fillColor: ESC.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ESC.lineStrong, width: 1.4),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ESC.brandDeep, width: 1.8),
          ),
        ),
        items: [
          for (final m in _modelos)
            DropdownMenuItem(
                value: m.id,
                child: Text(m.nombre, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _modelos.isEmpty
            ? null
            : (v) => setState(() => _modeloSeleccionado = v),
      ),
    );
  }

  Widget _listaItems() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ESSectionLabel('Ítems agregados',
            action: _items.isEmpty ? null : '${_items.length}'),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          ESCard(
            child: Row(children: [
              const Icon(Icons.inbox_outlined, color: ESC.inkFaint),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Aún no agregaste ningún ítem.',
                    style: pj(size: 13, color: ESC.inkSub)),
              ),
            ]),
          )
        else
          for (int i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _itemCard(_items[i], i),
            ),
      ],
    );
  }

  Widget _itemCard(IngresoItem it, int i) {
    final claseLbl = _kClases
        .firstWhere((c) => c.key == it.clase, orElse: () => _kClases.first)
        .label;
    final sub = [
      claseLbl,
      if (it.marca != null && it.marca!.isNotEmpty) it.marca!,
      if (it.modo == 'existente') 'existente',
    ].join(' · ');
    return ESCard(
      child: Row(children: [
        ESAvatar(
          (it.nombre?.isNotEmpty ?? false) ? it.nombre![0].toUpperCase() : '?',
          color: it.modo == 'existente' ? ESC.equip : ESC.brandDeep,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(it.nombre ?? '(sin nombre)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pj(size: 14.5, weight: FontWeight.w700, color: ESC.ink)),
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pj(size: 12, color: ESC.inkSub)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: ESC.matBg, borderRadius: BorderRadius.circular(999)),
          child: Text('x${it.cantidad}',
              style:
                  pj(size: 12.5, weight: FontWeight.w800, color: ESC.brandDeep)),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 18, color: ESC.vencido),
          onPressed: () => _quitarItem(i),
        ),
      ]),
    );
  }

  Widget _cabecera() {
    return ESCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _empleados.any((e) => e.id == _personalCompraId)
                ? _personalCompraId
                : null,
            isExpanded: true,
            style: pj(size: 14.5, color: ESC.ink),
            decoration: _deco('Personal que compró',
                hint: 'Por defecto: usuario actual'),
            items: [
              for (final e in _empleados)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(e.nombre ?? e.codigo ?? e.id,
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _personalCompraId = v),
          ),
          const SizedBox(height: 14),
          _fechaField(),
          const SizedBox(height: 14),
          TextField(
            controller: _proveedorCtrl,
            style: pj(size: 14.5, color: ESC.ink),
            decoration: _deco('Proveedor'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notasCtrl,
            maxLines: 2,
            style: pj(size: 14.5, color: ESC.ink),
            decoration: _deco('Notas (opcional)'),
          ),
        ],
      ),
    );
  }

  Widget _fechaField() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: _fechaCompra,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 1),
        );
        if (picked != null) setState(() => _fechaCompra = picked);
      },
      child: InputDecorator(
        decoration: _deco('Fecha de compra').copyWith(
          suffixIcon: const Icon(Icons.calendar_today_outlined,
              size: 18, color: ESC.inkSub),
        ),
        child: Text(_fmtFecha(_fechaCompra),
            style: pj(size: 14.5, color: ESC.ink)),
      ),
    );
  }

  Widget _comprobante() {
    const tiposDoc = <(String, String)>[
      ('factura', 'Factura'),
      ('boleta', 'Boleta'),
      ('nota_credito', 'Nota de crédito'),
      ('nota_debito', 'Nota de débito'),
    ];
    final total = _compSubtotal + _compIgv;
    return ESCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 18, color: ESC.brandDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Comprobante (genera Cuenta por Pagar)',
                  style: pj(size: 13, weight: FontWeight.w700, color: ESC.ink)),
            ),
            Switch(
              value: _compActiva,
              activeThumbColor: ESC.brand,
              onChanged: (v) => setState(() => _compActiva = v),
            ),
          ]),
          if (_compActiva) ...[
            const SizedBox(height: 6),
            Text(
              'Al registrar, se crea la Cuenta por Pagar pendiente en Finanzas.',
              style: pj(size: 11.5, color: ESC.inkFaint),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _proveedores.any((p) => p.id == _compProveedorId)
                  ? _compProveedorId
                  : null,
              isExpanded: true,
              style: pj(size: 14.5, color: ESC.ink),
              decoration: _deco('Proveedor'),
              items: [
                for (final p in _proveedores)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(p.nombre, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _compProveedorId = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _compTipoDoc,
              isExpanded: true,
              style: pj(size: 14.5, color: ESC.ink),
              decoration: _deco('Tipo de documento'),
              items: [
                for (final t in tiposDoc)
                  DropdownMenuItem(value: t.$1, child: Text(t.$2)),
              ],
              onChanged: (v) =>
                  setState(() => _compTipoDoc = v ?? 'factura'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _compNumeroCtrl,
              style: pj(size: 14.5, color: ESC.ink),
              decoration: _deco('Número de documento', hint: 'Ej: F001-00123'),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _compFechaField(
                  label: 'F. emisión',
                  value: _compFechaEmision,
                  onPick: (d) => setState(() {
                    _compFechaEmision = d;
                    // Si el vencimiento queda antes, lo igualamos.
                    if (_compFechaVencimiento != null &&
                        _compFechaVencimiento!.isBefore(d)) {
                      _compFechaVencimiento = d;
                    }
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _compFechaField(
                  label: 'F. vencimiento',
                  value: _compFechaVencimiento,
                  firstDate: _compFechaEmision,
                  onPick: (d) => setState(() => _compFechaVencimiento = d),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _compSubtotalCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: pj(size: 14.5, color: ESC.ink),
                  onChanged: (_) => _onSubtotalChanged(),
                  decoration: _deco('Subtotal'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _compIgvCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: pj(size: 14.5, color: ESC.ink),
                  onChanged: (_) => _onIgvEditadoManual(),
                  decoration: _deco('IGV',
                      hint: 'Auto ${_tasaIgv.toStringAsFixed(0)}%'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: ESC.matBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Text('Total', style: pj(size: 13, color: ESC.inkSub)),
                const Spacer(),
                Text('S/ ${total.toStringAsFixed(2)}',
                    style: pj(
                        size: 15, weight: FontWeight.w800, color: ESC.brandDeep)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _compFechaField({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onPick,
    DateTime? firstDate,
  }) {
    final now = DateTime.now();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? firstDate ?? now,
          firstDate: firstDate ?? DateTime(now.year - 5),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: _deco(label).copyWith(
          suffixIcon: const Icon(Icons.calendar_today_outlined,
              size: 16, color: ESC.inkSub),
        ),
        child: Text(
          value == null ? '—' : _fmtFecha(value),
          style: pj(
              size: 14, color: value == null ? ESC.inkFaint : ESC.ink),
        ),
      ),
    );
  }

  Widget _destino() {
    return ESCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Destino del ingreso',
              style: pj(size: 13, weight: FontWeight.w700, color: ESC.ink)),
          const SizedBox(height: 10),
          ESSegmented(
            items: const [
              ESSeg('Stock', icon: Icons.warehouse_outlined),
              ESSeg('Servicio', icon: Icons.engineering_outlined),
              ESSeg('Correctivo', icon: Icons.build_circle_outlined),
            ],
            selected: const ['stock', 'servicio', 'correctivo']
                .indexOf(_destinoTipo),
            onChanged: (i) => setState(() {
              _destinoTipo =
                  const ['stock', 'servicio', 'correctivo'][i];
              // Resetea selección dependiente.
              if (_destinoTipo == 'stock') {
                _servicioSelId = null;
                _correctivoSelId = null;
              }
            }),
          ),
          if (_destinoTipo != 'stock') ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue:
                  _proyectos.any((p) => p.id == _proyectoSelId) ? _proyectoSelId : null,
              isExpanded: true,
              style: pj(size: 14.5, color: ESC.ink),
              decoration: _deco('Proyecto'),
              items: [
                for (final p in _proyectos)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(p.nombreProyecto, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _onProyectoSel,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue:
                  _servicios.any((s) => s.id == _servicioSelId) ? _servicioSelId : null,
              isExpanded: true,
              style: pj(size: 14.5, color: ESC.ink),
              decoration: _deco('Servicio',
                  hint: _cargandoServicios ? 'Cargando…' : null),
              items: [
                for (final s in _servicios)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text(s.nombre, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _proyectoSelId == null ? null : _onServicioSel,
            ),
          ],
          if (_destinoTipo == 'correctivo') ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _correctivos.any((c) => c.id == _correctivoSelId)
                  ? _correctivoSelId
                  : null,
              isExpanded: true,
              style: pj(size: 14.5, color: ESC.ink),
              decoration: _deco('Correctivo',
                  hint: _cargandoCorrectivos ? 'Cargando…' : null),
              items: [
                for (final c in _correctivos)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.codigo ?? c.alcance ?? c.id,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _servicioSelId == null
                  ? null
                  : (v) => setState(() => _correctivoSelId = v),
            ),
          ],
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  InputDecoration _deco(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: pj(size: 13.5, color: ESC.inkSub),
        hintStyle: pj(size: 13.5, color: ESC.inkFaint),
        filled: true,
        fillColor: ESC.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ESC.lineStrong, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ESC.brandDeep, width: 1.8),
        ),
      );

  String _fmtFecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: pj(size: 13.5, color: Colors.white)),
        backgroundColor: ESC.ink,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

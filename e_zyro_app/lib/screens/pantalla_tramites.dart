import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../core/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:printing/printing.dart';
import '../core/app_constants.dart';
import '../templates/permiso_pdf_template.dart';

// ─────────────────────────────────────────────
//  Paleta dinámica (light / dark)
// ─────────────────────────────────────────────

class _C {
  static const green = Color(0xFF8FD11B);
  static const danger = Color(0xFFEF4444);

  final bool isDark;
  final ColorScheme cs;

  _C(BuildContext context)
    : isDark = Theme.of(context).brightness == Brightness.dark,
      cs = Theme.of(context).colorScheme;

  Color get surface => cs.surface;
  Color get scaffoldBg =>
      isDark ? const Color(0xFF0F1117) : const Color(0xFFF5F5F5);
  Color get surfaceHigh =>
      isDark ? const Color(0xFF222636) : Colors.grey.shade100;
  Color get border =>
      isDark ? green.withValues(alpha: 0.28) : Colors.grey.shade200;
  Color get inputBg => isDark ? const Color(0xFF141620) : Colors.white;
  Color get textPrimary => cs.onSurface;
  Color get textSecondary => cs.onSurface.withValues(alpha: 0.65);
  Color get textMuted => cs.onSurface.withValues(alpha: 0.40);

  ThemeData pickerTheme(BuildContext ctx) =>
      Theme.of(ctx).copyWith(colorScheme: cs.copyWith(primary: green));
}

// ─────────────────────────────────────────────
//  Modelo de datos
// ─────────────────────────────────────────────

class TramiteModel {
  int tipoPemiso;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  TimeOfDay? horaInicio;
  TimeOfDay? horaFin;
  String sustento;

  TramiteModel({
    this.tipoPemiso = 1,
    this.fechaInicio,
    this.fechaFin,
    this.horaInicio,
    this.horaFin,
    this.sustento = '',
  });
}

const List<Map<String, dynamic>> tiposPermiso = [
  {'id': 1, 'label': '(1) Permiso personal'},
  {'id': 2, 'label': '(2) Comisión de Trabajo'},
  {'id': 3, 'label': '(3) Cita Essalud / Clínica'},
  {'id': 4, 'label': '(4) Permanencia Capacitación'},
  {'id': 5, 'label': '(5) Permanencia Extra (H)'},
  {'id': 6, 'label': '(6) Recuperación (H)'},
  {'id': 7, 'label': '(7) Vacaciones'},
  {'id': 8, 'label': '(8) Día(s) Libre(s)'},
  {'id': 9, 'label': '(9) Transferencia'},
  {'id': 10, 'label': '(10) Otros'},
];

// ─────────────────────────────────────────────
//  Pantalla principal
// ─────────────────────────────────────────────

class PantallaTramites extends StatefulWidget {
  const PantallaTramites({super.key});

  @override
  State<PantallaTramites> createState() => _PantallaTramitesState();
}

class _PantallaTramitesState extends State<PantallaTramites>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TramiteModel _model = TramiteModel();
  Uint8List? _firmaGuardada;
  String? _firmaUrl;
  bool _guardandoFirma = false;
  List<Map<String, dynamic>> _misSolicitudes = [];
  bool _cargandoSolicitudes = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _cargarMisSolicitudes();
      }
    });
    _cargarFirmaGuardada();
    _cargarMisSolicitudes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Firma ───────────────────────────────────

  Future<void> _cargarFirmaGuardada() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/permisos/mi-firma'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final url = data['data']?['url_firma'] as String?;
        if (url != null) {
          final img = await http.get(Uri.parse(url));
          if (img.statusCode == 200 && mounted) {
            setState(() {
              _firmaGuardada = img.bodyBytes;
              _firmaUrl = url;
            });
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Tramites] Error al cargar firma.');
    }
  }

  Future<void> _eliminarFirmaGuardada() async {
    setState(() {
      _firmaGuardada = null;
      _firmaUrl = null;
    });
  }

  // ── Solicitudes ─────────────────────────────

  Future<void> _cargarMisSolicitudes() async {
    if (_cargandoSolicitudes) return;
    setState(() => _cargandoSolicitudes = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/permisos/mis-solicitudes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _misSolicitudes = List<Map<String, dynamic>>.from(data['data'] ?? []);
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Tramites] Error al cargar solicitudes.');
    } finally {
      if (mounted) setState(() => _cargandoSolicitudes = false);
    }
  }

  Future<void> _guardarFirmaEnNube() async {
    if (_firmaGuardada == null || _guardandoFirma) return;
    setState(() => _guardandoFirma = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.baseUrl}/permisos/guardar-firma'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['firma_base64'] =
          'data:image/png;base64,${base64Encode(_firmaGuardada!)}';
      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamed);
      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            _firmaUrl = data['data']['url_firma'];
          });
          _showSnack('✓ Firma guardada en la nube', _C.green);
        } else {
          _showError('Error al guardar la firma en la nube');
        }
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _guardandoFirma = false);
    }
  }

  Future<void> _abrirModalFirma({bool crearNueva = false}) async {
    final result = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ModalFirma(firmaExistente: crearNueva ? null : _firmaGuardada),
    );
    if (result != null && mounted) {
      setState(() {
        _firmaGuardada = result;
        _firmaUrl = null;
      });
      _showSnack('✓ Nueva firma lista para usar', _C.green);
    }
  }

  Future<void> _previsualizarSolicitud() async {
    if (_model.fechaInicio == null) {
      _showError('Selecciona la fecha de inicio');
      return;
    }
    if (_firmaGuardada == null) {
      _showError('Dibuja o sube tu firma digital');
      return;
    }
    if (_firmaUrl == null) {
      _showError('Guarda tu firma en la nube antes de enviar');
      return;
    }
    final horaInicioStr = _model.horaInicio?.format(context) ?? '';
    final horaFinStr = _model.horaFin?.format(context) ?? '';
    final prefs = await SharedPreferences.getInstance();
    final nombre = prefs.getString('user_name') ?? 'Usuario';
    final puesto = prefs.getString('user_rol') ?? 'Colaborador';
    final area = prefs.getString('user_area') ?? 'TIC';
    final dataPdf = {
      'tipo': _model.tipoPemiso,
      'f_inicio': DateFormat('dd/MM/yyyy').format(_model.fechaInicio!),
      'f_fin': _model.fechaFin != null
          ? DateFormat('dd/MM/yyyy').format(_model.fechaFin!)
          : '',
      'hora_inicio': horaInicioStr,
      'hora_fin': horaFinStr,
      'sustento': _model.sustento,
      'nombre': nombre,
      'puesto': puesto,
      'area': area,
      'total_dias': _model.fechaFin != null
          ? _model.fechaFin!.difference(_model.fechaInicio!).inDays + 1
          : 1,
    };
    final pdfBytes = await PermisoPdfTemplate.generate(dataPdf, _firmaGuardada);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VistaPreviaPdfScreen(
          pdfBytes: pdfBytes,
          onConfirm: () => _subirSolicitud(pdfBytes),
        ),
      ),
    );
  }

  Future<void> _subirSolicitud(Uint8List pdfBytes) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: _C.green)),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final uri = Uri.parse('${AppConstants.baseUrl}/permisos/enviar-solicitud');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['tipo'] = _model.tipoPemiso.toString();
      request.fields['tipo_label'] = tiposPermiso.firstWhere(
        (t) => t['id'] == _model.tipoPemiso,
      )['label'];
      if (_model.fechaInicio != null) {
        request.fields['fecha_inicio'] = DateFormat(
          'yyyy-MM-dd',
        ).format(_model.fechaInicio!);
      }
      if (_model.fechaFin != null) {
        request.fields['fecha_fin'] = DateFormat(
          'yyyy-MM-dd',
        ).format(_model.fechaFin!);
      }
      if (_model.horaInicio != null) {
        final now = DateTime.now();
        final dt = DateTime(
          now.year,
          now.month,
          now.day,
          _model.horaInicio!.hour,
          _model.horaInicio!.minute,
        );
        request.fields['hora_inicio'] = DateFormat('HH:mm').format(dt);
      }
      if (_model.horaFin != null) {
        final now = DateTime.now();
        final dt = DateTime(
          now.year,
          now.month,
          now.day,
          _model.horaFin!.hour,
          _model.horaFin!.minute,
        );
        request.fields['hora_fin'] = DateFormat('HH:mm').format(dt);
      }
      request.fields['motivo'] = _model.sustento;
      final totalDias = _model.fechaFin != null
          ? _model.fechaFin!.difference(_model.fechaInicio!).inDays + 1
          : 1;
      request.fields['total_dias'] = totalDias.toString();
      request.files.add(
        http.MultipartFile.fromBytes(
          'pdf_file',
          pdfBytes,
          filename: 'solicitud_${DateTime.now().millisecondsSinceEpoch}.pdf',
        ),
      );
      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamed);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pop();
        _showSnack('✓ Solicitud enviada correctamente', _C.green);
        _tabController.animateTo(1);
      } else {
        _showError('Error al enviar: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showError('Ocurrió un error: $e');
    }
  }

  void _showError(String msg) => _showSnack(msg, _C.danger);

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _C(context);
    return Scaffold(
      backgroundColor: c.scaffoldBg,
      appBar: _buildAppBar(c),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(c),
          _buildTabBar(c),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildFormTab(c), _buildMisTramitesTab(c)],
            ),
          ),
        ],
      ),
    );
  }

  // ── App Bar ───────────────────────────────

  PreferredSizeWidget _buildAppBar(_C c) => AppBar(
    backgroundColor: c.scaffoldBg,
    elevation: 0,
    titleSpacing: 16,
    foregroundColor: c.textPrimary,
    title: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _C.green,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Center(
            child: Text(
              'E',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'E-System ',
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const TextSpan(
                text: 'TIC',
                style: TextStyle(
                  color: _C.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ── Encabezado ────────────────────────────

  Widget _buildPageHeader(_C c) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trámites y Permisos',
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Gestiona tus solicitudes de descanso, vacaciones y licencias.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      ],
    ),
  );

  // ── TabBar ────────────────────────────────

  Widget _buildTabBar(_C c) => Container(
    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.border),
    ),
    child: TabBar(
      controller: _tabController,
      indicator: BoxDecoration(
        color: _C.green,
        borderRadius: BorderRadius.circular(8),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: Colors.black,
      unselectedLabelColor: c.textSecondary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      tabs: const [
        Tab(text: 'Nueva Solicitud'),
        Tab(text: 'Mis Trámites'),
      ],
    ),
  );

  // ─────────────────────────────────────────
  //  Tab 1: Formulario
  // ─────────────────────────────────────────

  Widget _buildFormTab(_C c) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCard(
          c,
          title: 'Detalles de la Solicitud',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel(c, 'Tipo de Permiso'),
              const SizedBox(height: 6),
              _buildDropdown(c),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildDateField(c, 'Fecha Inicio', true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildDateField(c, 'Fecha Fin', false)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildTimeField(c, 'Hora Inicio', true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTimeField(c, 'Hora Fin', false)),
                ],
              ),
              const SizedBox(height: 16),
              _fieldLabel(c, 'Sustento / Motivo *'),
              const SizedBox(height: 6),
              _buildTextArea(c),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildFirmaSection(c),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _previsualizarSolicitud,
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.green,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Previsualizar y Enviar',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildCard(
    _C c, {
    required String title,
    required Widget child,
  }) => Container(
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c.border),
      boxShadow: c.isDark
          ? [BoxShadow(color: _C.green.withValues(alpha: 0.06), blurRadius: 10)]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    ),
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget _fieldLabel(_C c, String text) => Text(
    text,
    style: TextStyle(
      color: c.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
  );

  // ── Dropdown ──────────────────────────────

  Widget _buildDropdown(_C c) => Container(
    decoration: BoxDecoration(
      color: c.inputBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.border),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: _model.tipoPemiso,
        dropdownColor: c.surfaceHigh,
        isExpanded: true,
        style: TextStyle(color: c.textPrimary, fontSize: 14),
        iconEnabledColor: c.textSecondary,
        items: tiposPermiso
            .map(
              (t) => DropdownMenuItem<int>(
                value: t['id'] as int,
                child: Text(t['label'] as String),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() => _model.tipoPemiso = v ?? 1),
      ),
    ),
  );

  // ── Date picker ───────────────────────────

  Widget _buildDateField(_C c, String label, bool isInicio) {
    final date = isInicio ? _model.fechaInicio : _model.fechaFin;
    final text = date != null
        ? DateFormat('dd/MM/yyyy').format(date)
        : 'dd/mm/aaaa';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel(c, label),
            if (!isInicio &&
                _model.fechaInicio != null &&
                _model.fechaFin != null &&
                _model.fechaInicio!.isAtSameMomentAs(_model.fechaFin!)) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _C.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _C.green.withValues(alpha: 0.45)),
                ),
                child: const Text(
                  'MISMO DÍA',
                  style: TextStyle(
                    color: _C.green,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
              builder: (ctx, child) =>
                  Theme(data: c.pickerTheme(ctx), child: child!),
            );
            if (picked != null) {
              setState(() {
                if (isInicio) {
                  _model.fechaInicio = picked;
                } else {
                  _model.fechaFin = picked;
                }
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: date != null ? c.textPrimary : c.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: c.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Time picker ───────────────────────────

  Widget _buildTimeField(_C c, String label, bool isInicio) {
    final time = isInicio ? _model.horaInicio : _model.horaFin;
    final text = time != null ? time.format(context) : '--:--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(c, label),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time ?? TimeOfDay.now(),
              builder: (ctx, child) =>
                  Theme(data: c.pickerTheme(ctx), child: child!),
            );
            if (picked != null) {
              setState(() {
                if (isInicio) {
                  _model.horaInicio = picked;
                } else {
                  _model.horaFin = picked;
                }
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: time != null ? c.textPrimary : c.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(Icons.access_time_outlined, size: 16, color: c.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Área de texto ─────────────────────────

  Widget _buildTextArea(_C c) => Container(
    decoration: BoxDecoration(
      color: c.inputBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.border),
    ),
    child: TextField(
      maxLines: 4,
      style: TextStyle(color: c.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Escribe el motivo detallado de tu solicitud...',
        hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(12),
      ),
      onChanged: (v) => _model.sustento = v,
    ),
  );

  // ─────────────────────────────────────────
  //  Sección firma digital
  // ─────────────────────────────────────────

  Widget _buildFirmaSection(_C c) => Container(
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c.border),
      boxShadow: c.isDark
          ? [BoxShadow(color: _C.green.withValues(alpha: 0.06), blurRadius: 10)]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    ),
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Firma Digital Obligatoria',
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),

        if (_firmaGuardada != null) ...[
          // Preview de firma
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _C.green.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.green.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  width: 90,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(_firmaGuardada!, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Firma lista',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            _firmaUrl != null
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            size: 13,
                            color: _firmaUrl != null ? _C.green : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _firmaUrl != null
                                ? 'Guardada en la nube'
                                : 'Pendiente de guardar',
                            style: TextStyle(
                              color: _firmaUrl != null
                                  ? _C.green
                                  : Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_firmaUrl == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _guardandoFirma ? null : _guardarFirmaEnNube,
                icon: _guardandoFirma
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_outlined, size: 16),
                label: Text(
                  _guardandoFirma ? 'Guardando...' : 'Guardar firma en la nube',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.green,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _abrirModalFirma(crearNueva: false),
                  icon: const Icon(
                    Icons.check_circle_outline,
                    size: 15,
                    color: _C.green,
                  ),
                  label: const Text(
                    'Ver firma',
                    style: TextStyle(
                      color: _C.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _C.green),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _abrirModalFirma(crearNueva: true),
                  icon: Icon(
                    Icons.draw_outlined,
                    size: 15,
                    color: c.textSecondary,
                  ),
                  label: Text(
                    'Nueva firma',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          GestureDetector(
            onTap: _abrirModalFirma,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: c.inputBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  Icon(Icons.draw_outlined, color: c.textMuted, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'Dibuja o sube tu firma aquí',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toca para abrir las opciones',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _abrirModalFirma(crearNueva: true),
          child: Center(
            child: Text(
              'o crea una nueva',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        if (_firmaGuardada != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              await _eliminarFirmaGuardada();
              if (mounted) {
                _showSnack('Firma eliminada', c.textSecondary);
              }
            },
            child: const Center(
              child: Text(
                'Quitar firma actual',
                style: TextStyle(
                  color: _C.danger,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  // ─────────────────────────────────────────
  //  Tab 2: Mis trámites
  // ─────────────────────────────────────────

  Widget _buildMisTramitesTab(_C c) {
    if (_cargandoSolicitudes) {
      return const Center(child: CircularProgressIndicator(color: _C.green));
    }
    if (_misSolicitudes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_outlined, color: c.textMuted, size: 56),
            const SizedBox(height: 16),
            Text(
              'No tienes trámites registrados',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Crea tu primera solicitud en la pestaña anterior',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _cargarMisSolicitudes,
              icon: Icon(Icons.refresh, size: 16, color: c.textSecondary),
              label: Text(
                'Actualizar',
                style: TextStyle(color: c.textSecondary),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _C.green,
      onRefresh: _cargarMisSolicitudes,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _misSolicitudes.length,
        itemBuilder: (_, i) => _buildSolicitudCard(c, _misSolicitudes[i]),
      ),
    );
  }

  Widget _buildSolicitudCard(_C c, Map<String, dynamic> s) {
    final estado = s['estado'] as String? ?? 'pendiente';
    final Color estadoColor = switch (estado) {
      'aprobado' => _C.green,
      'rechazado' => _C.danger,
      _ => Colors.orange,
    };
    final IconData estadoIcon = switch (estado) {
      'aprobado' => Icons.check_circle_outline,
      'rechazado' => Icons.cancel_outlined,
      _ => Icons.schedule_outlined,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
        boxShadow: c.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  s['id'] ?? '',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: estadoColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: estadoColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(estadoIcon, size: 12, color: estadoColor),
                      const SizedBox(width: 4),
                      Text(
                        estado[0].toUpperCase() + estado.substring(1),
                        style: TextStyle(
                          color: estadoColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              s['tipo_label'] ?? s['tipo'] ?? '',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            if (s['fecha_emision'] != null &&
                (s['fecha_emision'] as String).isNotEmpty)
              Text(
                'Emitido: ${s['fecha_emision']}',
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            if (s['fecha_inicio'] != null)
              Text(
                'Período: ${s['fecha_inicio']}${s['fecha_fin'] != null ? ' → ${s['fecha_fin']}' : ''}',
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            if (estado == 'rechazado' &&
                (s['observacion'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _C.danger.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _C.danger.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'Motivo rechazo: ${s['observacion']}',
                  style: const TextStyle(color: _C.danger, fontSize: 12),
                ),
              ),
            ],
            if ((s['url_pdf'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'URL: ${s['url_pdf']}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: c.surfaceHigh,
                        action: SnackBarAction(
                          label: 'Copiar',
                          textColor: _C.green,
                          onPressed: () {},
                        ),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 15,
                    color: _C.green,
                  ),
                  label: const Text(
                    'Ver PDF',
                    style: TextStyle(
                      color: _C.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _C.green),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Modal de firma (Bottom Sheet)
// ─────────────────────────────────────────────

class _ModalFirma extends StatefulWidget {
  final Uint8List? firmaExistente;
  const _ModalFirma({this.firmaExistente});

  @override
  State<_ModalFirma> createState() => _ModalFirmaState();
}

class _ModalFirmaState extends State<_ModalFirma> {
  late final SignatureController _controller;
  bool _lienzo = true;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penColor: Colors.black,
      penStrokeWidth: 3.0,
      exportBackgroundColor: Colors.transparent,
    );
    if (widget.firmaExistente != null) _lienzo = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _seleccionarDeGaleria() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      Navigator.of(context).pop(await image.readAsBytes());
    }
  }

  Future<void> _confirmar() async {
    if (_lienzo) {
      if (_controller.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dibuja tu firma primero'),
            backgroundColor: _C.danger,
          ),
        );
        return;
      }
      final bytes = await _controller.toPngBytes();
      if (bytes != null && mounted) Navigator.of(context).pop(bytes);
    } else {
      Navigator.of(context).pop(widget.firmaExistente);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _C(context);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Título
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.draw_outlined, color: _C.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Firma Digital',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: c.textSecondary, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Tabs Dibujar / Guardada
            if (widget.firmaExistente != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _tabBtn(
                      c,
                      'Dibujar nueva',
                      _lienzo ? null : () => setState(() => _lienzo = true),
                    ),
                    const SizedBox(width: 10),
                    _tabBtn(
                      c,
                      'Usar guardada',
                      !_lienzo ? null : () => setState(() => _lienzo = false),
                    ),
                  ],
                ),
              ),

            if (widget.firmaExistente != null) const SizedBox(height: 12),

            // Canvas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border, width: 2),
                    ),
                    height: 200,
                    child: _lienzo
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Signature(
                              controller: _controller,
                              backgroundColor: Colors.white,
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: widget.firmaExistente != null
                                ? Image.memory(
                                    widget.firmaExistente!,
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                  )
                                : Center(
                                    child: Text(
                                      'Sin firma guardada',
                                      style: TextStyle(color: c.textMuted),
                                    ),
                                  ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  if (_lienzo)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _controller.clear(),
                          icon: Icon(
                            Icons.refresh,
                            size: 15,
                            color: c.textMuted,
                          ),
                          label: Text(
                            'Limpiar',
                            style: TextStyle(color: c.textMuted, fontSize: 13),
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(height: 32),
                ],
              ),
            ),

            if (_lienzo)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Firma en el recuadro blanco con tu dedo',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),

            // Botones
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: c.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: Text(
                            'Cancelar',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _confirmar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _C.green,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text(
                            'Confirmar Firma',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _seleccionarDeGaleria,
                      icon: Icon(
                        Icons.photo_library_outlined,
                        size: 18,
                        color: c.textPrimary,
                      ),
                      label: Text(
                        'Subir imagen desde la Galería',
                        style: TextStyle(color: c.textPrimary),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
    );
  }

  Widget _tabBtn(_C c, String label, VoidCallback? onTap) {
    final active = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _C.green : c.inputBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? _C.green : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : c.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Vista previa PDF
// ─────────────────────────────────────────────

class VistaPreviaPdfScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final VoidCallback onConfirm;

  const VistaPreviaPdfScreen({
    super.key,
    required this.pdfBytes,
    required this.onConfirm,
  });

  @override
  State<VistaPreviaPdfScreen> createState() => _VistaPreviaPdfScreenState();
}

class _VistaPreviaPdfScreenState extends State<VistaPreviaPdfScreen> {
  double? _top;
  double? _left;

  @override
  Widget build(BuildContext context) {
    final c = _C(context);
    return Scaffold(
      backgroundColor: c.scaffoldBg,
      appBar: AppBar(
        backgroundColor: c.scaffoldBg,
        foregroundColor: c.textPrimary,
        elevation: 0,
        title: Text(
          'Vista Previa',
          style: TextStyle(color: c.textPrimary, fontSize: 16),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _top ??= constraints.maxHeight - 80;
          _left ??= constraints.maxWidth - 220;

          return Stack(
            children: [
              PdfPreview(
                build: (format) => widget.pdfBytes,
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                pdfFileName: 'Solicitud_Permiso.pdf',
              ),
              Positioned(
                top: _top,
                left: _left,
                child: GestureDetector(
                  onPanUpdate: (details) => setState(() {
                    _top = (_top! + details.delta.dy).clamp(
                      0.0,
                      constraints.maxHeight - 60.0,
                    );
                    _left = (_left! + details.delta.dx).clamp(
                      0.0,
                      constraints.maxWidth - 210.0,
                    );
                  }),
                  child: FloatingActionButton.extended(
                    backgroundColor: _C.green,
                    onPressed: widget.onConfirm,
                    icon: const Icon(Icons.cloud_upload, color: Colors.black),
                    label: const Text(
                      'Confirmar y Enviar',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

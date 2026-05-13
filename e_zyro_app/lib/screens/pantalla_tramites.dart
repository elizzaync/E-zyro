import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../templates/permiso_pdf_template.dart';

// ─────────────────────────────────────────────
//  TEMA DE COLORES (basado en la captura)
// ─────────────────────────────────────────────
class AppColors {
  static const background = Color(0xFF0F1117);
  static const surface = Color(0xFF1A1D27);
  static const surfaceElevated = Color(0xFF222636);
  static const border = Color(0xFF2E3347);
  static const accent = Color(0xFF4ADE80); // verde E-System
  static const accentDark = Color(0xFF22C55E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMuted = Color(0xFF6B7280);
  static const inputBg = Color(0xFF141620);
  static const danger = Color(0xFFEF4444);
  static const navBg = Color(0xFF13151F);
}

// ─────────────────────────────────────────────
//  MODELO DE DATOS
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

Map<String, dynamic> prepararDatosFirma({
  required String userId,
  required String empresaId,
  required String urlCloudinary,
  required String publicId,
  bool esPrimeraVez = false,
}) {
  return {
    'id': DateTime.now().millisecondsSinceEpoch
        .toString(), // Generar un ID simple
    'usuario_id': userId,
    'empresa_id': empresaId,
    'url_cloudinary': urlCloudinary,
    'public_id_cloudinary': publicId,
    'primera_vez': esPrimeraVez,
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  };
}

// ─────────────────────────────────────────────
//  PANTALLA PRINCIPAL
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
  Uint8List? _firmaGuardada; // firma persistida (PNG bytes)
  String? _firmaUrl; // URL de la firma en Cloudinary (si existe)
  bool _usandoFirmaGuardada = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarFirmaGuardada();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Persistencia de firma ──────────────────
  Future<void> _cargarFirmaGuardada() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    final baseUrl =
        prefs.getString('api_url') ??
        'https://e-zyro-production.up.railway.app';

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/permisos/mi-firma'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data']['url_firma'] != null) {
          final url = data['data']['url_firma'];
          final imgResponse = await http.get(Uri.parse(url));
          if (imgResponse.statusCode == 200) {
            setState(() {
              _firmaGuardada = imgResponse.bodyBytes;
              _firmaUrl = url;
              _usandoFirmaGuardada = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error al cargar firma desde BD: $e');
    }
  }

  Future<void> _eliminarFirmaGuardada() async {
    setState(() {
      _firmaGuardada = null;
      _firmaUrl = null;
      _usandoFirmaGuardada = false;
    });
  }

  // ── Abre el modal de firma ─────────────────
  Future<void> _abrirModalFirma({bool crearNueva = false}) async {
    final result = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ModalFirma(firmaExistente: crearNueva ? null : _firmaGuardada),
    );
    if (result != null) {
      if (mounted) {
        setState(() {
          _firmaGuardada = result;
          _firmaUrl = null;
          _usandoFirmaGuardada = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('✓ Nueva firma lista para usar', AppColors.accent),
        );
      }
    }
  }

  void _previsualizarSolicitud() async {
    if (_model.fechaInicio == null) {
      _mostrarError('Selecciona la fecha de inicio');
      return;
    }

    if (_firmaGuardada == null) {
      _mostrarError('Agrega tu firma digital');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final nombre = prefs.getString('user_name') ?? 'Usuario';
    final puesto = prefs.getString('user_rol') ?? 'Colaborador';
    final area = prefs.getString('user_area') ?? 'TIC';

    // 1. Mapear datos para el PDF
    final dataPdf = {
      'tipo': _model.tipoPemiso,
      'f_inicio': DateFormat('dd/MM/yyyy').format(_model.fechaInicio!),
      'f_fin': _model.fechaFin != null
          ? DateFormat('dd/MM/yyyy').format(_model.fechaFin!)
          : '',
      'hora_inicio': _model.horaInicio?.format(context) ?? '',
      'hora_fin': _model.horaFin?.format(context) ?? '',
      'sustento': _model.sustento,
      'nombre': nombre,
      'puesto': puesto,
      'area': area,
      'total_dias': _model.fechaFin != null
          ? _model.fechaFin!.difference(_model.fechaInicio!).inDays + 1
          : 1,
    };

    // 2. Generar Bytes del PDF
    final pdfBytes = await PermisoPdfTemplate.generate(dataPdf, _firmaGuardada);

    if (!mounted) return;

    // 3. Abrir pantalla de vista previa para confirmación
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
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final baseUrl =
          prefs.getString('api_url') ??
          'https://e-zyro-production.up.railway.app';

      final uri = Uri.parse('$baseUrl/permisos/enviar-solicitud');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $token';

      request.fields['tipo'] = _model.tipoPemiso.toString();
      request.fields['tipo_label'] = tiposPermiso.firstWhere(
        (t) => t['id'] == _model.tipoPemiso,
      )['label'];

      // Si tenemos URL de firma, mandamos eso para que la BD no duplique en Cloudinary. Si es nueva, base64.
      if (_firmaUrl != null) {
        request.fields['firma_base64'] = _firmaUrl!;
      } else {
        request.fields['firma_base64'] =
            'data:image/png;base64,${base64Encode(_firmaGuardada!)}';
      }

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

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      Navigator.of(context).pop(); // cerrar loading
      if (response.statusCode == 200) {
        Navigator.of(context).pop(); // cerrar vista previa
        ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('✓ Solicitud enviada correctamente', AppColors.accent),
        );
        _tabController.animateTo(1);
      } else {
        _mostrarError('Error al enviar la solicitud: ${response.statusCode}');
      }
    } catch (e) {
      Navigator.of(context).pop(); // cerrar loading
      _mostrarError('Ocurrió un error: $e');
    }
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(_snackBar(msg, AppColors.danger));
  }

  SnackBar _snackBar(String msg, Color color) => SnackBar(
    content: Text(
      msg,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
    backgroundColor: color,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  // ─────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // ── App Bar ──────────────────────────
      appBar: _buildAppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildFormTab(), _buildMisTramitesTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ── App Bar ───────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.navBg,
      elevation: 0,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accent,
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
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'E-System ',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                TextSpan(
                  text: 'TIC',
                  style: TextStyle(
                    color: AppColors.accent,
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
  }

  Widget _navItem(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextButton.icon(
        onPressed: () {},
        icon: Icon(icon, size: 15, color: AppColors.textSecondary),
        label: Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Trámites y Permisos',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Gestiona tus solicitudes de descanso, vacaciones y licencias.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _tabController.animateTo(0),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Nueva Solicitud',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── TabBar ────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.black,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        tabs: const [
          Tab(text: 'Nueva Solicitud'),
          Tab(text: 'Mis Trámites'),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  //  TAB 1: FORMULARIO
  // ─────────────────────────────────────────
  Widget _buildFormTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            title: 'Detalles de la Solicitud',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('Tipo de Permiso'),
                const SizedBox(height: 6),
                _buildDropdown(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildDateField('Fecha Inicio', true)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDateField('Fecha Fin', false)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildTimeField('Hora Inicio', true)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTimeField('Hora Fin', false)),
                  ],
                ),
                const SizedBox(height: 16),
                _fieldLabel('Sustento / Motivo *'),
                const SizedBox(height: 6),
                _buildTextArea(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildFirmaSection(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _previsualizarSolicitud,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
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
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // ── Dropdown ──────────────────────────────
  Widget _buildDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _model.tipoPemiso,
          dropdownColor: AppColors.surfaceElevated,
          isExpanded: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          iconEnabledColor: AppColors.textSecondary,
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
  }

  // ── Date picker ───────────────────────────
  Widget _buildDateField(String label, bool isInicio) {
    final date = isInicio ? _model.fechaInicio : _model.fechaFin;
    final text = date != null
        ? DateFormat('dd/MM/yyyy').format(date)
        : 'dd/mm/aaaa';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel(label),
            if (!isInicio &&
                _model.fechaInicio != null &&
                _model.fechaFin != null &&
                _model.fechaInicio!.isAtSameMomentAs(_model.fechaFin!)) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.accent.withOpacity(0.5)),
                ),
                child: const Text(
                  'MISMO DÍA',
                  style: TextStyle(
                    color: AppColors.accent,
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
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.accent,
                    surface: AppColors.surfaceElevated,
                  ),
                ),
                child: child!,
              ),
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
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: date != null
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Time picker ───────────────────────────
  Widget _buildTimeField(String label, bool isInicio) {
    final time = isInicio ? _model.horaInicio : _model.horaFin;
    final text = time != null ? time.format(context) : '--:--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time ?? TimeOfDay.now(),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.accent,
                    surface: AppColors.surfaceElevated,
                  ),
                ),
                child: child!,
              ),
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
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: time != null
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Icon(
                  Icons.access_time_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Área de texto ─────────────────────────
  Widget _buildTextArea() {
    return Container(
      decoration: BoxDecoration(
        color: const ui.Color.fromARGB(255, 20, 32, 20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        maxLines: 4,
        style: const TextStyle(
          color: ui.Color.fromARGB(255, 0, 0, 0),
          fontSize: 14,
        ),
        decoration: const InputDecoration(
          hintText: 'Escribe el motivo detallado de tu solicitud...',
          hintStyle: TextStyle(
            color: ui.Color.fromARGB(255, 255, 255, 255),
            fontSize: 14,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(12),
        ),
        onChanged: (v) => _model.sustento = v,
      ),
    );
  }

  // ─────────────────────────────────────────
  //  SECCIÓN FIRMA DIGITAL
  // ─────────────────────────────────────────
  Widget _buildFirmaSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Firma Digital Obligatoria',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),

          if (_firmaGuardada != null) ...[
            // ── Firma guardada ───────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  // Preview de la firma
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
                      children: const [
                        Text(
                          'Tienes una firma guardada',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Puedes reutilizarla o crear una nueva',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _abrirModalFirma(crearNueva: false),
                    icon: const Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: AppColors.accent,
                    ),
                    label: const Text(
                      'Usar esta firma',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accent),
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
                    icon: const Icon(
                      Icons.draw_outlined,
                      size: 15,
                      color: AppColors.textSecondary,
                    ),
                    label: const Text(
                      'Crear nueva',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
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
            // ── Sin firma ────────────────────
            GestureDetector(
              onTap: () => _abrirModalFirma(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.border,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  children: const [
                    Icon(
                      Icons.draw_outlined,
                      color: AppColors.textMuted,
                      size: 32,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Dibuja tu firma aquí',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Toca para abrir el panel de firma',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _abrirModalFirma(crearNueva: true),
            child: const Center(
              child: Text(
                'o crea una nueva',
                style: TextStyle(
                  color: AppColors.textSecondary,
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    _snackBar('Firma eliminada', AppColors.textSecondary),
                  );
                }
              },
              child: const Center(
                child: Text(
                  'Quitar firma actual',
                  style: TextStyle(
                    color: AppColors.danger,
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
  }

  // ─────────────────────────────────────────
  //  TAB 2: MIS TRÁMITES (placeholder)
  // ─────────────────────────────────────────
  Widget _buildMisTramitesTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            color: AppColors.textMuted,
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'No tienes trámites registrados',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Crea tu primera solicitud',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _tabController.animateTo(0),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Nueva Solicitud',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  MODAL DE FIRMA (Bottom Sheet)
// ─────────────────────────────────────────────
class _ModalFirma extends StatefulWidget {
  final Uint8List? firmaExistente;

  const _ModalFirma({this.firmaExistente});

  @override
  State<_ModalFirma> createState() => _ModalFirmaState();
}

class _ModalFirmaState extends State<_ModalFirma> {
  late final SignatureController _controller;
  bool _lienzo = true; // true = dibujar, false = ver existente

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penColor: Colors.black,
      penStrokeWidth: 3.0,
      exportBackgroundColor: Colors.transparent,
    );
    // Si hay firma existente, empieza mostrándola
    if (widget.firmaExistente != null) {
      _lienzo = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_lienzo) {
      if (_controller.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dibuja tu firma primero'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      final bytes = await _controller.toPngBytes();
      if (bytes != null && mounted) {
        Navigator.of(context).pop(bytes);
      }
    } else {
      // Usar la firma existente tal cual
      Navigator.of(context).pop(widget.firmaExistente);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ─────────────────────
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Título ─────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(
                    Icons.draw_outlined,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Firma Digital',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Tabs Dibujar / Ver existente ───
            if (widget.firmaExistente != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _tabBtn(
                      'Dibujar nueva',
                      !_lienzo ? null : () => setState(() => _lienzo = false),
                    ),
                    const SizedBox(width: 10),
                    _tabBtn(
                      'Usar guardada',
                      _lienzo ? null : () => setState(() => _lienzo = true),
                    ),
                  ],
                ),
              ),

            if (widget.firmaExistente != null) const SizedBox(height: 12),

            // ── Canvas de firma ────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border, width: 2),
                    ),
                    height: 200,
                    child: _lienzo
                        // ── Pad de firma táctil ──
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Signature(
                              controller: _controller,
                              backgroundColor: Colors.white,
                            ),
                          )
                        // ── Preview de firma guardada ──
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: widget.firmaExistente != null
                                ? Image.memory(
                                    widget.firmaExistente!,
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                  )
                                : const Center(
                                    child: Text('Sin firma guardada'),
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
                          icon: const Icon(
                            Icons.refresh,
                            size: 15,
                            color: AppColors.textMuted,
                          ),
                          label: const Text(
                            'Limpiar',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(height: 32),
                ],
              ),
            ),

            // ── Instrucción ────────────────────
            if (_lienzo)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Firma en el recuadro blanco con tu dedo',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),

            // ── Botones de acción ──────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(
                          color: AppColors.textSecondary,
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
                        backgroundColor: AppColors.accent,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(String label, VoidCallback? onTap) {
    final active = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.inputBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PANTALLA VISTA PREVIA PDF
// ─────────────────────────────────────────────
class VistaPreviaPdfScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final VoidCallback onConfirm;

  const VistaPreviaPdfScreen({
    Key? key,
    required this.pdfBytes,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<VistaPreviaPdfScreen> createState() => _VistaPreviaPdfScreenState();
}

class _VistaPreviaPdfScreenState extends State<VistaPreviaPdfScreen> {
  double? _top;
  double? _left;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navBg,
        title: const Text(
          'Vista Previa',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Posición inicial: esquina inferior derecha
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
                  onPanUpdate: (details) {
                    setState(() {
                      // Evitamos que el botón se salga de los bordes de la pantalla
                      _top = (_top! + details.delta.dy).clamp(
                        0.0,
                        constraints.maxHeight - 60.0,
                      );
                      _left = (_left! + details.delta.dx).clamp(
                        0.0,
                        constraints.maxWidth - 210.0,
                      );
                    });
                  },
                  child: FloatingActionButton.extended(
                    backgroundColor: AppColors.accent,
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

// ─────────────────────────────────────────────
//  ENTRY POINT (para pruebas standalone)
// ─────────────────────────────────────────────
void main() {
  runApp(const _App());
}

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-System TIC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
      ),
      home: const PantallaTramites(),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asistencia_models.dart';
import '../repositories/asistencia_local_repo.dart';
import '../services/asistencia_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_notifiers.dart';
import '../widgets/sync_log_panel.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_preview_screen.dart';

part 'asistencia/sheet_foto_base.dart';
part 'asistencia/sheet_registro.dart';
part 'asistencia/camara.dart';
part 'asistencia/reloj_chip.dart';

class AsistenciaScreen extends StatefulWidget {
  const AsistenciaScreen({super.key});

  @override
  State<AsistenciaScreen> createState() => _AsistenciaScreenState();
}

class _AsistenciaScreenState extends State<AsistenciaScreen> {
  AsistenciaService? _service;
  String _userName = '';

  // GPS y dirección
  Position? _position;
  bool _fetchingLocation = false;
  String _locationStatus = 'Toca para obtener ubicación';
  String? _addressLine1;
  String? _addressLine2;

  // Estado del backend
  EstadoHoy? _estadoHoy;
  List<RegistroAsistencia> _historial = [];
  bool _cargandoInicial = true;

  // Registros offline pendientes de sincronización
  int _pendientesSinc = 0;
  bool _syncingBanner = false; // true mientras se ejecuta sync manual
  final _localRepo = AsistenciaLocalRepo();

  // ── Getters derivados ──────────────────────────────────────────────────────
  bool get _tieneFotoBase => _estadoHoy?.tieneFotoBase ?? false;
  bool get _jornadaCompleta => _estadoHoy?.jornadaCompleta ?? false;
  String? get _tipoRegistro => _estadoHoy?.tipoProximo;

  bool _esHoy(DateTime dt) {
    final hoy = DateTime.now();
    return dt.year == hoy.year && dt.month == hoy.month && dt.day == hoy.day;
  }

  RegistroAsistencia? get _entradaHoy => _historial
      .where((r) => r.tipo == 'ENTRADA' && _esHoy(r.timestamp))
      .firstOrNull;

  RegistroAsistencia? get _salidaHoy => _historial
      .where((r) => r.tipo == 'SALIDA' && _esHoy(r.timestamp))
      .firstOrNull;

  // ── Ciclo de vida ──────────────────────────────────────────────────────────
  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];
  static const _dias = [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo',
  ];

  @override
  void initState() {
    super.initState();
    pendientesAsistenciaNotifier.addListener(_onPendientesChanged);
    sessionExpiredSyncNotifier.addListener(_onSessionExpiredChanged);
    syncCompletedNotifier.addListener(_onSyncCompleted);
    _init();
    _fetchLocation();
  }

  @override
  void dispose() {
    pendientesAsistenciaNotifier.removeListener(_onPendientesChanged);
    sessionExpiredSyncNotifier.removeListener(_onSessionExpiredChanged);
    syncCompletedNotifier.removeListener(_onSyncCompleted);
    super.dispose();
  }

  void _onPendientesChanged() {
    if (!mounted) return;
    final anterior = _pendientesSinc;
    final nuevo = pendientesAsistenciaNotifier.value;
    setState(() => _pendientesSinc = nuevo);
    // Si el conteo llegó a 0 desde un valor mayor, recargar el estado del día
    // para que el historial muestre los registros como confirmados por el servidor.
    if (nuevo == 0 && anterior > 0 && _service != null) {
      _cargarDatos(_service!);
    }
  }

  void _onSessionExpiredChanged() {
    if (mounted) setState(() {});
  }

  /// Cuando el MainShell completa un ciclo de sync, refrescar historial y
  /// estado del día para reflejar los cambios confirmados por el servidor.
  void _onSyncCompleted() {
    if (!mounted || _service == null) return;
    _refreshPendientes();
    _cargarDatos(_service!);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final svc = await getAsistenciaService();
    if (mounted) setState(() { _service = svc; _userName = prefs.getString('user_name') ?? 'Usuario'; });
    await _cargarDatos(svc);
    await _refreshPendientes();
    // Auto-sync al abrir la pantalla si hay registros pendientes
    if (_pendientesSinc > 0) _triggerSync();
  }

  /// Sincroniza los registros pendientes verificando primero que Railway es
  /// alcanzable. Actualiza el banner con spinner durante el proceso.
  Future<void> _triggerSync() async {
    if (_service == null || _syncingBanner) return;
    if (mounted) setState(() => _syncingBanner = true);
    try {
      if (await _service!.canReachServer()) {
        await _service!.sincronizarPendientes();
        await _refreshPendientes();
        // Si se enviaron todos, refrescar el estado del día desde el servidor
        if (mounted && _pendientesSinc == 0) {
          await _cargarDatos(_service!);
        }
      }
    } finally {
      if (mounted) setState(() => _syncingBanner = false);
    }
  }

  Future<void> _refreshPendientes() async {
    final count = await _localRepo.contarPendientes();
    if (mounted) setState(() => _pendientesSinc = count);
  }

  Future<void> _confirmarLimpiarFallidos() async {
    if (_service == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar registros fallidos'),
        content: const Text(
          'Se eliminarán todos los registros que no pudieron sincronizarse '
          '(fallidos y abandonados). Los registros aún pendientes también serán '
          'descartados.\n\nEsta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _service!.descartarTodosLosFallidos();
    await _refreshPendientes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registros fallidos eliminados')),
      );
    }
  }

  Future<void> _cargarDatos(AsistenciaService svc) async {
    try {
      final results = await Future.wait([
        svc.getEstadoHoy(),
        svc.getHistorial(),
      ]);
      if (mounted) {
        setState(() {
          _estadoHoy = results[0] as EstadoHoy;
          _historial  = results[1] as List<RegistroAsistencia>;
          _cargandoInicial = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoInicial = false);
    }
  }

  // ── GPS ────────────────────────────────────────────────────────────────────
  Future<void> _fetchLocation() async {
    if (!mounted) return;
    setState(() {
      _fetchingLocation = true;
      _locationStatus   = 'Obteniendo ubicación...';
      _addressLine1     = null;
      _addressLine2     = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) setState(() { _fetchingLocation = false; _locationStatus = 'GPS desactivado'; });
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          if (mounted) setState(() { _fetchingLocation = false; _locationStatus = 'Permiso denegado'; });
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) setState(() { _fetchingLocation = false; _locationStatus = 'Permiso denegado permanentemente'; });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _position       = pos;
        _locationStatus = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        _fetchingLocation = false;
      });
      _resolveAddress(pos.latitude, pos.longitude);
    } catch (_) {
      if (mounted) setState(() { _fetchingLocation = false; _locationStatus = 'Error al obtener ubicación'; });
    }
  }

  Future<void> _resolveAddress(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 10));
      if (placemarks.isEmpty || !mounted) { return; }
      final p = placemarks.first;
      final street = [
        if ((p.thoroughfare ?? '').isNotEmpty) p.thoroughfare!,
        if ((p.subThoroughfare ?? '').isNotEmpty) p.subThoroughfare!,
      ].join(' ');
      final district = [
        if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
        if ((p.locality ?? '').isNotEmpty) p.locality!,
      ].join(', ');
      if (mounted) {
        setState(() {
          _addressLine1 = street.isNotEmpty ? street : null;
          _addressLine2 = district.isNotEmpty ? district : null;
        });
      }
    } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String get _fechaFormateada {
    final n = DateTime.now();
    return '${_dias[n.weekday - 1]} ${n.day} de ${_meses[n.month - 1]}, ${n.year}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  // ── Acciones ───────────────────────────────────────────────────────────────
  void _openSubirFotoBase() {
    if (_service == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (_) => _SubirFotoBaseSheet(
        service: _service!,
        onConfigured: _onFotoBaseConfigured,
      ),
    );
  }

  void _onFotoBaseConfigured() {
    // Optimistic update — UI cambia de inmediato sin esperar el refresh
    if (mounted) {
      final old = _estadoHoy;
      setState(() {
        _estadoHoy = EstadoHoy(
          tieneEntrada:   old?.tieneEntrada   ?? false,
          tieneSalida:    old?.tieneSalida    ?? false,
          tieneFotoBase:  true,
          entradaHora:    old?.entradaHora,
          salidaHora:     old?.salidaHora,
          jornadaCompleta: old?.jornadaCompleta ?? false,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('¡Foto biométrica registrada exitosamente!'),
            ],
          ),
          backgroundColor: const Color(0xFF8FD11B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    // Refresh en background para confirmar con el servidor
    if (_service != null) _cargarDatos(_service!);
  }

  void _openRegistroSheet() {
    if (_service == null || _tipoRegistro == null || !_tieneFotoBase || _cargandoInicial) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RegistroSheet(
        tipo: _tipoRegistro!,
        position: _position,
        addressLine1: _addressLine1,
        addressLine2: _addressLine2,
        service: _service!,
        onCompleted: _onMarkCompleted,
      ),
    );
  }

  void _onMarkCompleted(MarcarResponse result) {
    _showResultDialog(result);
    _refreshPendientes();
    if (_service != null) _cargarDatos(_service!);
  }

  // ── Diálogo de resultado ───────────────────────────────────────────────────
  void _showResultDialog(MarcarResponse r) {
    final esPendiente     = r.status == 'PENDIENTE_SYNC';
    final esErrorServidor = r.status == 'ERROR_SERVIDOR';
    final aprobado        = r.status == 'APROBADO';
    final esRevision      = r.resultadoIa == 'revision_manual';
    const green           = Color(0xFF8FD11B);
    final statusColor = esPendiente
        ? Colors.amber.shade600
        : esErrorServidor
            ? Colors.orange.shade700
            : (aprobado ? green : (esRevision ? Colors.orange : Colors.red));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  color: statusColor, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)],
                ),
                child: Icon(
                  esPendiente
                      ? Icons.cloud_off_rounded
                      : esErrorServidor
                          ? Icons.cloud_sync_outlined
                          : (aprobado ? Icons.check_rounded : (esRevision ? Icons.hourglass_top_rounded : Icons.close_rounded)),
                  color: Colors.white, size: 50,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                esPendiente
                    ? 'GUARDADO OFFLINE'
                    : esErrorServidor
                        ? 'ERROR DEL SERVIDOR'
                        : (aprobado ? '¡APROBADO!' : (esRevision ? 'EN REVISIÓN' : 'RECHAZADO')),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor),
              ),
              const SizedBox(height: 6),
              Text(
                '${r.resultadoIa == "revision_manual" ? "Asistencia registrada" : "Asistencia registrada"} · Tipo marcado',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              // Score badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Similitud: ${r.score.toStringAsFixed(1)}%',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: statusColor),
                ),
              ),
              const SizedBox(height: 10),
              // GPS badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    r.gpsGuardado ? Icons.location_on : Icons.location_off,
                    size: 14,
                    color: r.gpsGuardado ? green : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    r.gpsGuardado ? 'GPS guardado' : 'Sin GPS',
                    style: TextStyle(
                      fontSize: 12,
                      color: r.gpsGuardado ? green : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (r.motivo.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  r.motivo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.5),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '${_pad(r.timestamp.hour)}:${_pad(r.timestamp.minute)}:${_pad(r.timestamp.second)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: statusColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cerrar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportarAsistenciaPdf() async {
    final prefs = await SharedPreferences.getInstance();
    final usuario = prefs.getString('user_name') ?? 'Colaborador';
    final bytes = await PdfService.asistenciaUsuario(_historial, usuario: usuario);
    if (!mounted) return;
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo: 'asistencia_${DateTime.now().millisecondsSinceEpoch}.pdf',
      titulo: 'Reporte de Asistencia',
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          if (_service != null) await _cargarDatos(_service!);
          await _fetchLocation();
        },
        color: const Color(0xFF8FD11B),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildLocationCard(),
              if (_pendientesSinc > 0) ...[
                const SizedBox(height: 12),
                _buildPendingBanner(),
              ],
              const SizedBox(height: 16),
              _buildStatusHoy(),
              const SizedBox(height: 20),
              if (!_cargandoInicial && !_tieneFotoBase) ...[
                _buildFotoBaseAlert(),
                const SizedBox(height: 16),
              ],
              _buildRegisterButton(),
              const SizedBox(height: 28),
              _buildHistorySection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header gradiente ───────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8FD11B), Color(0xFF6BAD10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF8FD11B).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_greeting, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 2),
                    const Text('Mi Asistencia', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    if (_userName.isNotEmpty)
                      Text(_userName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: const Icon(Icons.person, color: Colors.white, size: 26),
                  ),
                  if (!_cargandoInicial)
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        width: 16, height: 16,
                        decoration: BoxDecoration(
                          color: _tieneFotoBase ? const Color(0xFF8FD11B) : Colors.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          _tieneFotoBase ? Icons.check : Icons.priority_high,
                          color: Colors.white, size: 9,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8, runSpacing: 6,
            children: [
              _chip(Icons.calendar_today, _fechaFormateada),
              // Reloj autocontenido: solo este chip se repinta cada segundo,
              // no toda la pantalla.
              const _LiveClockChip(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 13),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    ),
  );

  // ── Tarjeta GPS ────────────────────────────────────────────────────────────
  Widget _buildLocationCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasLoc = _position != null;
    const green  = Color(0xFF8FD11B);

    Color accuracyColor = Colors.grey;
    String accuracyLabel = '';
    if (hasLoc) {
      final acc = _position!.accuracy;
      if (acc <= 10) { accuracyColor = green;          accuracyLabel = 'Alta'; }
      else if (acc <= 30) { accuracyColor = Colors.orange; accuracyLabel = 'Media'; }
      else { accuracyColor = Colors.red; accuracyLabel = 'Baja'; }
    }

    return Container(
      decoration: _cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hasLoc
                        ? (isDark ? green.withValues(alpha: 0.15) : const Color(0xFFEFFAE0))
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasLoc ? Icons.location_on : Icons.location_searching,
                    color: hasLoc ? green : Colors.orange, size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ubicación GPS', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 4),
                      if (_addressLine1 != null)
                        Text(_addressLine1!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      if (_addressLine2 != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(_addressLine2!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                      if (_addressLine1 == null)
                        Text(
                          _fetchingLocation ? 'Obteniendo dirección...' : _locationStatus,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                if (_fetchingLocation)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B))),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.grey, size: 20),
                    onPressed: _fetchLocation,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            if (hasLoc) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}',
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: isDark ? Colors.grey.shade300 : Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: accuracyColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '±${_position!.accuracy.toStringAsFixed(0)}m · $accuracyLabel',
                      style: TextStyle(fontSize: 11, color: accuracyColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Alerta: sin foto biométrica ────────────────────────────────────────────
  Widget _buildFotoBaseAlert() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Foto biométrica requerida', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Para registrar tu asistencia necesitas subir tu foto biométrica base. '
            'Se almacena de forma segura en nuestros servidores y se usa para verificar '
            'tu identidad en cada registro.',
            style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openSubirFotoBase,
              icon: const Icon(Icons.face_retouching_natural, size: 18),
              label: const Text('Registrar mi foto biométrica'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Estado del día ─────────────────────────────────────────────────────────
  Widget _buildStatusHoy() {
    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estado del Día', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (!_cargandoInicial)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (_tieneFotoBase ? const Color(0xFF8FD11B) : Colors.orange).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _tieneFotoBase ? Icons.verified_user : Icons.person_off,
                        size: 11,
                        color: _tieneFotoBase ? const Color(0xFF8FD11B) : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _tieneFotoBase ? 'Foto registrada' : 'Sin foto base',
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: _tieneFotoBase ? const Color(0xFF8FD11B) : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_cargandoInicial)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B))),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(child: _buildStatusItem('Entrada', _entradaHoy, Icons.login, isEntrada: true)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatusItem('Salida',  _salidaHoy,  Icons.logout, isEntrada: false)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, RegistroAsistencia? r, IconData icon, {required bool isEntrada}) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final registered  = r != null;
    const green       = Color(0xFF8FD11B);
    final col         = isEntrada ? green : Colors.blue;

    String horaStr = '--:--';
    if (registered) {
      horaStr = '${_pad(r.timestamp.hour)}:${_pad(r.timestamp.minute)}';
    } else if (isEntrada && (_estadoHoy?.entradaHora != null)) {
      horaStr = _estadoHoy!.entradaHora!;
    } else if (!isEntrada && (_estadoHoy?.salidaHora != null)) {
      horaStr = _estadoHoy!.salidaHora!;
    }

    final gpsInfo = registered && r.latitud != null
        ? (r.precisionM != null ? '±${r.precisionM!.toStringAsFixed(0)}m' : 'GPS ✓')
        : '';
    final scoreInfo = registered ? '${r.score.toStringAsFixed(1)}%' : '';
    final subtitle  = [scoreInfo, gpsInfo].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: registered
            ? (isDark ? col.withValues(alpha: 0.12) : col.withValues(alpha: 0.08))
            : (isDark ? Colors.grey.withValues(alpha: 0.08) : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(12),
        border: registered ? Border.all(color: col.withValues(alpha: 0.3)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: registered ? col : Colors.grey),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 11, color: registered ? col : Colors.grey, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            horaStr,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: registered ? col : Colors.grey.shade400),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle.isNotEmpty ? subtitle : 'Pendiente',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ── Panel de logs ──────────────────────────────────────────────────────────
  void _openSyncLogs() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SyncLogPanel(),
    );
  }

  // ── Banner: registros offline pendientes ──────────────────────────────────
  Widget _buildPendingBanner() {
    // Detectar si la última razón de fallo fue sesión vencida
    final sessionExpired = sessionExpiredSyncNotifier.value > 0;
    final bannerColor    = sessionExpired ? Colors.purple : Colors.amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: sessionExpired ? Colors.purple.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: sessionExpired ? Colors.purple.shade300 : Colors.amber.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _syncingBanner
                  ? SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(bannerColor.shade700),
                      ),
                    )
                  : Icon(
                      sessionExpired
                          ? Icons.lock_outline_rounded
                          : Icons.cloud_sync_outlined,
                      color: bannerColor.shade700,
                      size: 18,
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _syncingBanner
                      ? 'Sincronizando con el servidor...'
                      : '$_pendientesSinc ${_pendientesSinc == 1 ? 'registro pendiente' : 'registros pendientes'} de sincronización',
                  style: TextStyle(
                    fontSize: 12,
                    color: bannerColor.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Botón Ver logs
              IconButton(
                icon: const Icon(Icons.terminal_rounded, size: 18),
                color: bannerColor.shade700,
                tooltip: 'Ver logs de sync',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: _openSyncLogs,
              ),
            ],
          ),
          // Chip de sesión vencida
          if (sessionExpired && !_syncingBanner) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => Navigator.pushNamedAndRemoveUntil(
                context, '/login', (r) => false,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 13, color: Colors.purple),
                    const SizedBox(width: 5),
                    const Text(
                      'Sesión vencida — toca para iniciar sesión',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (!_syncingBanner) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _confirmarLimpiarFallidos,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: Colors.red.shade700,
                  ),
                  child: Text(
                    'Limpiar fallidos',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _triggerSync,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: bannerColor.shade800,
                  ),
                  child: Text(
                    'Sincronizar ahora',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: bannerColor.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Botón de registro ──────────────────────────────────────────────────────
  Widget _buildRegisterButton() {
    const green  = Color(0xFF8FD11B);
    final tipo   = _tipoRegistro;
    final enabled = !_jornadaCompleta && _tieneFotoBase && !_cargandoInicial && _service != null;

    return SizedBox(
      width: double.infinity, height: 58,
      child: ElevatedButton(
        onPressed: enabled ? _openRegistroSheet : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _jornadaCompleta
              ? Colors.grey.shade300
              : (!_tieneFotoBase ? Colors.orange.withValues(alpha: 0.5) : green),
          foregroundColor: _jornadaCompleta ? Colors.grey : Colors.white,
          disabledBackgroundColor: _jornadaCompleta ? Colors.grey.shade200 : Colors.orange.withValues(alpha: 0.3),
          disabledForegroundColor: Colors.white70,
          elevation: enabled ? 4 : 0,
          shadowColor: green.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_cargandoInicial)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
            else
              Icon(
                _jornadaCompleta ? Icons.check_circle
                    : (!_tieneFotoBase ? Icons.lock
                    : (tipo == 'ENTRADA' ? Icons.fingerprint : Icons.logout)),
                size: 24,
              ),
            const SizedBox(width: 10),
            Text(
              _cargandoInicial ? 'Cargando...'
                  : (_jornadaCompleta ? 'Jornada Completada'
                  : (!_tieneFotoBase ? 'Registra tu foto biométrica'
                  : 'Registrar ${tipo ?? ''}')),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  // ── Historial ──────────────────────────────────────────────────────────────
  Widget _buildHistorySection() {
    final Map<String, List<RegistroAsistencia>> grupos = {};
    for (final r in _historial) {
      grupos.putIfAbsent(_dayKey(r.timestamp), () => []).add(r);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Historial', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (_historial.isNotEmpty)
              TextButton.icon(
                onPressed: _exportarAsistenciaPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Exportar PDF'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF8FD11B)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_cargandoInicial)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: _cardDecoration(),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
              ),
            ),
          )
        else if (grupos.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _cardDecoration(),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.history, size: 44, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('Sin registros previos', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  SizedBox(height: 4),
                  Text('Tu primer registro aparecerá aquí', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
          )
        else
          ...grupos.entries.map((entry) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _labelForKey(entry.key),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.6),
                ),
              ),
              ...entry.value.map(_buildRegistroItem),
              const SizedBox(height: 12),
            ],
          )),
      ],
    );
  }

  String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _labelForKey(String key) {
    final now = DateTime.now();
    if (key == _dayKey(now)) return 'HOY';
    if (key == _dayKey(now.subtract(const Duration(days: 1)))) return 'AYER';
    final p = key.split('-');
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  Widget _buildRegistroItem(RegistroAsistencia r) {
    final aprobado   = r.status == 'APROBADO';
    final esRevision = r.resultadoIa == 'revision_manual';
    final isEntrada  = r.tipo == 'ENTRADA';
    const green      = Color(0xFF8FD11B);
    final tipoColor  = isEntrada ? green : Colors.blue;
    final statusColor = aprobado ? green : (esRevision ? Colors.orange : Colors.red);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: tipoColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(isEntrada ? Icons.login : Icons.logout, color: tipoColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.tipo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      '${_pad(r.timestamp.hour)}:${_pad(r.timestamp.minute)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    if (r.latitud != null) ...[
                      const Text(' · ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const Icon(Icons.location_on, size: 11, color: Color(0xFF8FD11B)),
                      Text(
                        r.precisionM != null
                            ? ' ±${r.precisionM!.toStringAsFixed(0)}m'
                            : ' GPS',
                        style: const TextStyle(color: Color(0xFF8FD11B), fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ] else ...[
                      const Text(' · ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const Icon(Icons.location_off, size: 11, color: Colors.grey),
                      const Text(' Sin GPS', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ],
                ),
                if (esRevision) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Requiere revisión manual',
                      style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(r.status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              Text('${r.score.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green   = Color(0xFF8FD11B);
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      border: isDark ? Border.all(color: green.withValues(alpha: 0.45), width: 1.0) : null,
      boxShadow: isDark
          ? [BoxShadow(color: green.withValues(alpha: 0.10), blurRadius: 12, spreadRadius: 1)]
          : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
    );
  }
}


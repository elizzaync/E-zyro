import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asistencia_models.dart';
import '../repositories/asistencia_local_repo.dart';
import '../services/asistencia_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_notifiers.dart';

class AsistenciaScreen extends StatefulWidget {
  const AsistenciaScreen({super.key});

  @override
  State<AsistenciaScreen> createState() => _AsistenciaScreenState();
}

class _AsistenciaScreenState extends State<AsistenciaScreen> {
  AsistenciaService? _service;
  String _userName = '';

  // Reloj en vivo
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

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
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) { if (mounted) setState(() => _now = DateTime.now()); },
    );
    // Escuchar el notifier global para actualizar el badge cuando el sync externo termine
    pendientesAsistenciaNotifier.addListener(_onPendientesChanged);
    _init();
    _fetchLocation();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    pendientesAsistenciaNotifier.removeListener(_onPendientesChanged);
    super.dispose();
  }

  void _onPendientesChanged() {
    if (mounted) setState(() => _pendientesSinc = pendientesAsistenciaNotifier.value);
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
    final h = _now.hour;
    if (h < 12) return 'Buenos días';
    if (h < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String get _fechaFormateada =>
      '${_dias[_now.weekday - 1]} ${_now.day} de ${_meses[_now.month - 1]}, ${_now.year}';

  String get _hora =>
      '${_pad(_now.hour)}:${_pad(_now.minute)}:${_pad(_now.second)}';

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
    final esPendiente  = r.status == 'PENDIENTE_SYNC';
    final aprobado     = r.status == 'APROBADO';
    final esRevision   = r.resultadoIa == 'revision_manual';
    const green        = Color(0xFF8FD11B);
    final statusColor  = esPendiente
        ? Colors.amber.shade600
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
                      : (aprobado ? Icons.check_rounded : (esRevision ? Icons.hourglass_top_rounded : Icons.close_rounded)),
                  color: Colors.white, size: 50,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                esPendiente
                    ? 'GUARDADO OFFLINE'
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
              _chip(Icons.access_time, _hora),
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

  // ── Banner: registros offline pendientes ──────────────────────────────────
  Widget _buildPendingBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          _syncingBanner
              ? SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.amber.shade700),
                  ),
                )
              : Icon(Icons.cloud_sync_outlined, color: Colors.amber.shade700, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _syncingBanner
                  ? 'Sincronizando con el servidor...'
                  : '$_pendientesSinc ${_pendientesSinc == 1 ? 'registro pendiente' : 'registros pendientes'} de sincronización',
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!_syncingBanner) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: _triggerSync,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: Colors.amber.shade800,
              ),
              child: Text(
                'Sincronizar',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber.shade800,
                ),
              ),
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
        const Text('Historial', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

// ── Sheet: Subir foto biométrica base (cámara live) ──────────────────────────
class _SubirFotoBaseSheet extends StatefulWidget {
  final AsistenciaService service;
  final void Function() onConfigured;

  const _SubirFotoBaseSheet({required this.service, required this.onConfigured});

  @override
  State<_SubirFotoBaseSheet> createState() => _SubirFotoBaseSheetState();
}

class _SubirFotoBaseSheetState extends State<_SubirFotoBaseSheet> {
  XFile?  _captured;
  bool    _isSaving = false;
  String? _errorMsg;

  Future<void> _openCamera() async {
    final photo = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(builder: (_) => const _FullScreenCameraPage()),
    );
    if (photo != null && mounted) {
      setState(() { _captured = photo; _errorMsg = null; });
    }
  }

  void _retake() => setState(() { _captured = null; _errorMsg = null; });

  Future<void> _save() async {
    if (_captured == null) {
      setState(() => _errorMsg = 'Primero captura tu foto de referencia');
      return;
    }
    setState(() { _isSaving = true; _errorMsg = null; });
    try {
      await widget.service.subirFotoBase(File(_captured!.path));
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onConfigured();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMsg = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    const green   = Color(0xFF8FD11B);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.face_retouching_natural, color: Colors.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Foto Biométrica', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Centra tu cara · buena iluminación · mira directo', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Área de foto
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _captured == null
                  ? GestureDetector(
                      onTap: _openCamera,
                      child: Container(
                        width: double.infinity, height: 220,
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.45), width: 2),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined, size: 52, color: Colors.orange),
                            SizedBox(height: 12),
                            Text('Tomar foto biométrica', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 15)),
                            SizedBox(height: 4),
                            Text('Toca para abrir la cámara', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(File(_captured!.path), width: double.infinity, height: 280, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 12, left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: green.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.white, size: 13),
                                SizedBox(width: 4),
                                Text('Foto capturada', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        if (_isSaving)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B))),
                                  SizedBox(height: 12),
                                  Text('Subiendo al servidor...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  SizedBox(height: 4),
                                  Text('Procesando foto biométrica', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),

            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 18),

            // Botones
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _isSaving
                  ? SizedBox(
                      width: double.infinity, height: 54,
                      child: ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          disabledBackgroundColor: Colors.orange.withValues(alpha: 0.55),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                            SizedBox(width: 12),
                            Text('Subiendo foto...', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    )
                  : _captured != null
                      ? Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _retake,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Retomar'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  side: const BorderSide(color: Colors.orange),
                                  foregroundColor: Colors.orange,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: _save,
                                icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                                label: const Text('Guardar foto', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ],
                        )
                      : SizedBox(
                          width: double.infinity, height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _openCamera,
                            icon: const Icon(Icons.camera_alt, size: 20),
                            label: const Text('Abrir cámara', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Sheet: Registrar asistencia ───────────────────────────────────────────────
class _RegistroSheet extends StatefulWidget {
  final String tipo;
  final Position? position;
  final String? addressLine1;
  final String? addressLine2;
  final AsistenciaService service;
  final void Function(MarcarResponse) onCompleted;

  const _RegistroSheet({
    required this.tipo,
    required this.position,
    required this.addressLine1,
    required this.addressLine2,
    required this.service,
    required this.onCompleted,
  });

  @override
  State<_RegistroSheet> createState() => _RegistroSheetState();
}

class _RegistroSheetState extends State<_RegistroSheet> {
  XFile? _selfie;
  bool _isLoading = false;
  String? _errorMsg;

  Future<void> _openCamera() async {
    final photo = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(builder: (_) => const _FullScreenCameraPage()),
    );
    if (photo != null && mounted) {
      setState(() { _selfie = photo; _errorMsg = null; });
    }
  }

  void _retake() => setState(() { _selfie = null; _errorMsg = null; });

  Future<void> _submit() async {
    if (_selfie == null) {
      setState(() => _errorMsg = 'Por favor toma una selfie para continuar');
      return;
    }
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final result = await widget.service.marcar(
        selfieFile: File(_selfie!.path),
        tipo: widget.tipo,
        latitud:    widget.position?.latitude,
        longitud:   widget.position?.longitude,
        precisionM: widget.position?.accuracy,
        altitud:    widget.position?.altitude,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCompleted(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg  = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final surface   = Theme.of(context).colorScheme.surface;
    const green     = Color(0xFF8FD11B);
    final now       = DateTime.now();
    final isEntrada = widget.tipo == 'ENTRADA';
    final tipoColor = isEntrada ? green : Colors.orange;
    String pad(int n) => n.toString().padLeft(2, '0');

    return Container(
      decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: tipoColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(isEntrada ? Icons.login : Icons.logout, color: tipoColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Registrar ${widget.tipo}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(
                          '${pad(now.day)}/${pad(now.month)}/${now.year}  ·  ${pad(now.hour)}:${pad(now.minute)}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (widget.position != null ? green : Colors.orange).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (widget.position != null ? green : Colors.orange).withValues(alpha: 0.25)),
                ),
                child: widget.position != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on, color: Color(0xFF8FD11B), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.addressLine1 != null)
                                      Text(widget.addressLine1!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    if (widget.addressLine2 != null)
                                      Text(widget.addressLine2!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    if (widget.addressLine1 == null)
                                      Text(
                                        '${widget.position!.latitude.toStringAsFixed(5)}, ${widget.position!.longitude.toStringAsFixed(5)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                                child: Text(
                                  '±${widget.position!.accuracy.toStringAsFixed(0)}m',
                                  style: const TextStyle(color: Color(0xFF8FD11B), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          if (widget.addressLine1 != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${widget.position!.latitude.toStringAsFixed(5)}, ${widget.position!.longitude.toStringAsFixed(5)}',
                              style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                            ),
                          ],
                        ],
                      )
                    : const Row(
                        children: [
                          Icon(Icons.location_off, color: Colors.orange, size: 18),
                          SizedBox(width: 8),
                          Text('Sin ubicación GPS — se registrará sin coordenadas',
                              style: TextStyle(fontSize: 12, color: Colors.orange)),
                        ],
                      ),
              ),
              const SizedBox(height: 20),

              const Text('Verificación Facial', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 10),

              if (_selfie == null)
                GestureDetector(
                  onTap: _isLoading ? null : _openCamera,
                  child: Container(
                    width: double.infinity, height: 160,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, size: 46, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text('Tomar selfie', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Toca para abrir la cámara', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(File(_selfie!.path), width: double.infinity, height: 220, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 10, right: 10,
                      child: GestureDetector(
                        onTap: _isLoading ? null : _retake,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('Retomar', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_isLoading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16)),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B))),
                              SizedBox(height: 12),
                              Text('Verificando identidad...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('Comparando con foto biométrica del servidor', style: TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity, height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: green.withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                            SizedBox(width: 12),
                            Text('Verificando...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fingerprint, size: 22),
                            SizedBox(width: 10),
                            Text('Verificar y Registrar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cámara a pantalla completa (compartida por ambos flujos) ──────────────────
class _FullScreenCameraPage extends StatefulWidget {
  const _FullScreenCameraPage();

  @override
  State<_FullScreenCameraPage> createState() => _FullScreenCameraPageState();
}

class _FullScreenCameraPageState extends State<_FullScreenCameraPage> {
  CameraController? _ctrl;
  bool _ready = false;
  XFile? _captured;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { if (mounted) Navigator.pop(context); return; }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(front, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await ctrl.initialize();
      try {
        await ctrl.setExposureMode(ExposureMode.auto);
        await ctrl.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) { ctrl.dispose(); return; }
      setState(() { _ctrl = ctrl; _ready = true; });
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _capture() async {
    if (_ctrl == null || !_ready) return;
    final photo = await _ctrl!.takePicture();
    await _ctrl!.pausePreview();
    if (mounted) setState(() => _captured = photo);
  }

  Future<void> _retake() async {
    await _ctrl?.resumePreview();
    if (mounted) setState(() => _captured = null);
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF8FD11B);

    if (!_ready || _ctrl == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)))),
      );
    }

    if (_captured != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(_captured!.path), fit: BoxFit.cover),
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _retake,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.refresh, color: Colors.white),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: green.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Foto tomada', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _retake,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Retomar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context, _captured),
                          icon: const Icon(Icons.check, size: 20),
                          label: const Text('Usar foto', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _ctrl!.value.previewSize?.height ?? 100,
                height: _ctrl!.value.previewSize?.width ?? 100,
                child: CameraPreview(_ctrl!),
              ),
            ),
          ),
          Positioned(
            top: 0, left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Center(
                  child: GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 78, height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.white70, width: 4),
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16)],
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.black87, size: 36),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

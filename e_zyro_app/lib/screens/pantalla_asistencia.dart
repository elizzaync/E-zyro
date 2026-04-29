import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asistencia_models.dart';
import '../services/asistencia_service.dart';

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
  String? _addressLine1; // "Av. Tomás Valle 570"
  String? _addressLine2; // "Bocanegra, Callao"

  // Foto de referencia
  bool _hasRefPhoto = false;
  bool _checkingRefPhoto = true;

  // Estado asistencia del día
  List<RegistroAsistencia> _historial = [];
  RegistroAsistencia? _entradaHoy;
  RegistroAsistencia? _salidaHoy;

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
    _init();
    _fetchLocation();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final svc = AsistenciaService(prefs);
    final hasRef = await svc.tieneRefPhoto();
    if (mounted) {
      setState(() {
        _service = svc;
        _userName = prefs.getString('user_name') ?? 'Usuario';
        _hasRefPhoto = hasRef;
        _checkingRefPhoto = false;
      });
      _refreshData();
    }
  }

  void _refreshData() {
    if (_service == null || !mounted) return;
    final hoy = _service!.getHoy();
    final entradas = hoy.where((r) => r.tipo == 'ENTRADA' && r.status == 'APROBADO');
    final salidas = hoy.where((r) => r.tipo == 'SALIDA' && r.status == 'APROBADO');
    setState(() {
      _historial = _service!.getHistorial();
      _entradaHoy = entradas.isEmpty ? null : entradas.first;
      _salidaHoy = salidas.isEmpty ? null : salidas.first;
    });
  }

  // ── GPS + Geocodificación inversa ────────────────────────────────────────────
  Future<void> _fetchLocation() async {
    if (!mounted) return;
    setState(() {
      _fetchingLocation = true;
      _locationStatus = 'Obteniendo ubicación...';
      _addressLine1 = null;
      _addressLine2 = null;
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
        _position = pos;
        _locationStatus =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        _fetchingLocation = false;
      });

      // Geocodificación inversa para obtener dirección legible
      _resolveAddress(pos.latitude, pos.longitude);
    } catch (_) {
      if (mounted) setState(() { _fetchingLocation = false; _locationStatus = 'Error al obtener ubicación'; });
    }
  }

  Future<void> _resolveAddress(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 10));
      if (placemarks.isEmpty || !mounted) return;
      final p = placemarks.first;

      // Línea 1: "Av. Tomás Valle 570" (vía + número)
      final street = [
        if ((p.thoroughfare ?? '').isNotEmpty) p.thoroughfare!,
        if ((p.subThoroughfare ?? '').isNotEmpty) p.subThoroughfare!,
      ].join(' ');

      // Línea 2: "Bocanegra, Callao" (barrio + ciudad)
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
    } catch (_) {
      // Geocodificación fallida — las coordenadas siguen mostrándose
    }
  }

  // ── Helpers de formato ───────────────────────────────────────────────────────
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

  String? get _tipoRegistro {
    if (_entradaHoy == null) return 'ENTRADA';
    if (_salidaHoy == null) return 'SALIDA';
    return null;
  }

  bool get _jornadaCompleta => _entradaHoy != null && _salidaHoy != null;

  // ── Configurar foto de referencia ────────────────────────────────────────────
  void _openSetupRefPhoto() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SetupRefPhotoSheet(
        onConfigured: () {
          if (mounted) setState(() => _hasRefPhoto = true);
        },
      ),
    );
  }

  // ── Abrir modal de registro ──────────────────────────────────────────────────
  void _openRegistroSheet() {
    if (_service == null || _tipoRegistro == null || !_hasRefPhoto) return;
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
        onCompleted: (registro) {
          _service!.guardarRegistro(registro);
          if (mounted) {
            setState(() {
              _historial.insert(0, registro);
              if (registro.tipo == 'ENTRADA' && registro.status == 'APROBADO') _entradaHoy = registro;
              if (registro.tipo == 'SALIDA' && registro.status == 'APROBADO') _salidaHoy = registro;
            });
            _showResultDialog(registro);
          }
        },
      ),
    );
  }

  // ── Dialog de resultado ──────────────────────────────────────────────────────
  void _showResultDialog(RegistroAsistencia r) {
    final aprobado = r.status == 'APROBADO';
    const green = Color(0xFF8FD11B);
    final statusColor = aprobado ? green : Colors.red;

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
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)],
                ),
                child: Icon(aprobado ? Icons.check_rounded : Icons.close_rounded, color: Colors.white, size: 50),
              ),
              const SizedBox(height: 20),
              Text(
                aprobado ? '¡APROBADO!' : 'RECHAZADO',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor),
              ),
              const SizedBox(height: 6),
              Text('${r.tipo} registrada', style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Score: ${r.score.toStringAsFixed(1)}%',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: statusColor),
                ),
              ),
              if (r.motivo != null && r.motivo!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(r.motivo!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
              const SizedBox(height: 8),
              Text('${_pad(r.timestamp.hour)}:${_pad(r.timestamp.minute)}:${_pad(r.timestamp.second)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
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

  // ── Build principal ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async { _refreshData(); await _fetchLocation(); },
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
              const SizedBox(height: 16),
              _buildStatusHoy(),
              const SizedBox(height: 20),
              // Alerta de foto de referencia requerida
              if (!_checkingRefPhoto && !_hasRefPhoto) ...[
                _buildRefPhotoAlert(),
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

  // ── Header gradiente ─────────────────────────────────────────────────────────
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
              // Indicador de foto de referencia
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: const Icon(Icons.person, color: Colors.white, size: 26),
                  ),
                  if (!_checkingRefPhoto)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _hasRefPhoto ? const Color(0xFF8FD11B) : Colors.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          _hasRefPhoto ? Icons.check : Icons.priority_high,
                          color: Colors.white,
                          size: 9,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 6,
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

  // ── Tarjeta GPS con dirección ─────────────────────────────────────────────────
  Widget _buildLocationCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasLoc = _position != null;
    const green = Color(0xFF8FD11B);

    Color accuracyColor = Colors.grey;
    String accuracyLabel = '';
    if (hasLoc) {
      final acc = _position!.accuracy;
      if (acc <= 10) { accuracyColor = green; accuracyLabel = 'Alta'; }
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
                    color: hasLoc ? green : Colors.orange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ubicación GPS', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 4),

                      // Dirección legible (línea 1)
                      if (_addressLine1 != null)
                        Text(
                          _addressLine1!,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      // Barrio y ciudad (línea 2)
                      if (_addressLine2 != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            _addressLine2!,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      // Mientras no hay dirección, mostrar estado
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
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B))),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.grey, size: 20),
                    onPressed: _fetchLocation,
                    tooltip: 'Actualizar ubicación',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            // Fila inferior: coordenadas + precisión
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
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accuracyColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
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

  // ── Alerta: foto de referencia no configurada ────────────────────────────────
  Widget _buildRefPhotoAlert() {
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
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Foto de referencia requerida',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Para registrar tu asistencia necesitas configurar tu foto de referencia. '
            'Esta imagen se usará para verificar tu identidad en cada registro.',
            style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openSetupRefPhoto,
              icon: const Icon(Icons.camera_alt, size: 18),
              label: const Text('Configurar mi foto de referencia'),
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

  // ── Estado del día ───────────────────────────────────────────────────────────
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
              // Badge de foto de referencia configurada
              if (!_checkingRefPhoto)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (_hasRefPhoto ? const Color(0xFF8FD11B) : Colors.orange).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hasRefPhoto ? Icons.verified_user : Icons.person_off,
                        size: 11,
                        color: _hasRefPhoto ? const Color(0xFF8FD11B) : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _hasRefPhoto ? 'Foto configurada' : 'Sin foto base',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _hasRefPhoto ? const Color(0xFF8FD11B) : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatusItem('Entrada', _entradaHoy, Icons.login, isEntrada: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatusItem('Salida', _salidaHoy, Icons.logout, isEntrada: false)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, RegistroAsistencia? r, IconData icon, {required bool isEntrada}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final registered = r != null;
    const green = Color(0xFF8FD11B);
    final col = isEntrada ? green : Colors.blue;

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
            registered ? '${_pad(r.timestamp.hour)}:${_pad(r.timestamp.minute)}' : '--:--',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: registered ? col : Colors.grey.shade400),
          ),
          const SizedBox(height: 3),
          Text(
            registered ? '${r.score.toStringAsFixed(1)}% · ${r.latitud != null ? "GPS ✓" : "Sin GPS"}' : 'Pendiente',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ── Botón principal de registro ──────────────────────────────────────────────
  Widget _buildRegisterButton() {
    const green = Color(0xFF8FD11B);
    final tipo = _tipoRegistro;
    final enabled = !_jornadaCompleta && _hasRefPhoto && _service != null;

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: enabled ? _openRegistroSheet : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _jornadaCompleta
              ? Colors.grey.shade300
              : (!_hasRefPhoto ? Colors.orange.withValues(alpha: 0.5) : green),
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
            Icon(
              _jornadaCompleta
                  ? Icons.check_circle
                  : (!_hasRefPhoto ? Icons.lock : (tipo == 'ENTRADA' ? Icons.fingerprint : Icons.logout)),
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              _jornadaCompleta
                  ? 'Jornada Completada'
                  : (!_hasRefPhoto ? 'Configura tu foto primero' : 'Registrar ${tipo ?? ''}'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  // ── Historial ────────────────────────────────────────────────────────────────
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
        if (grupos.isEmpty)
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
                child: Text(_labelForKey(entry.key),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.6)),
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
    final aprobado = r.status == 'APROBADO';
    final isEntrada = r.tipo == 'ENTRADA';
    const green = Color(0xFF8FD11B);
    final tipoColor = isEntrada ? green : Colors.blue;
    final statusColor = aprobado ? green : Colors.red;

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
                Text(
                  '${_pad(r.timestamp.hour)}:${_pad(r.timestamp.minute)}  ·  ${r.latitud != null ? "GPS ✓" : "Sin GPS"}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
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

// ── Sheet: Configurar foto de referencia ──────────────────────────────────────
class _SetupRefPhotoSheet extends StatefulWidget {
  final void Function() onConfigured;

  const _SetupRefPhotoSheet({required this.onConfigured});

  @override
  State<_SetupRefPhotoSheet> createState() => _SetupRefPhotoSheetState();
}

class _SetupRefPhotoSheetState extends State<_SetupRefPhotoSheet> {
  XFile? _photo;
  bool _isSaving = false;
  String? _errorMsg;

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 92,
      );
      if (image != null && mounted) {
        setState(() { _photo = image; _errorMsg = null; });
      }
    } catch (_) {
      if (mounted) setState(() => _errorMsg = 'No se pudo acceder a la cámara');
    }
  }

  Future<void> _save() async {
    if (_photo == null) {
      setState(() => _errorMsg = 'Primero toma tu foto de referencia');
      return;
    }
    setState(() { _isSaving = true; _errorMsg = null; });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final refPath = '${dir.path}/reference_photo.jpg';
      await File(_photo!.path).copy(refPath);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_foto_local_path', refPath);

      if (mounted) {
        Navigator.pop(context);
        widget.onConfigured();
      }
    } catch (_) {
      if (mounted) setState(() { _isSaving = false; _errorMsg = 'Error al guardar. Inténtalo de nuevo.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

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
              // Handle
              Center(
                child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),

              // Título
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.badge_outlined, color: Colors.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Foto de Referencia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Configuración inicial requerida', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Explicación
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Esta foto se almacena localmente en tu dispositivo y se usa como imagen de referencia para comparar con tu selfie al momento de registrar asistencia. '
                        'Asegúrate de estar en un lugar bien iluminado y mirar directamente a la cámara.',
                        style: TextStyle(fontSize: 12, color: Colors.blue, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Área de captura
              if (_photo == null)
                GestureDetector(
                  onTap: _isSaving ? null : _takePhoto,
                  child: Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_outlined, size: 36, color: Colors.orange),
                        ),
                        const SizedBox(height: 14),
                        Text('Tomar foto de referencia',
                            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Cámara frontal · Buena iluminación',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(File(_photo!.path), width: double.infinity, height: 240, fit: BoxFit.cover),
                    ),
                    // Badge de aprobado
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: green.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 13),
                            SizedBox(width: 4),
                            Text('Foto lista', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: _isSaving ? null : _takePhoto,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
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
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.orange.withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSaving
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                            SizedBox(width: 12),
                            Text('Guardando...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_alt, size: 20),
                            SizedBox(width: 10),
                            Text('Guardar foto de referencia', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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

// ── Modal de registro de asistencia ──────────────────────────────────────────
class _RegistroSheet extends StatefulWidget {
  final String tipo;
  final Position? position;
  final String? addressLine1;
  final String? addressLine2;
  final AsistenciaService service;
  final void Function(RegistroAsistencia) onCompleted;

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

  Future<void> _takeSelfie() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        setState(() { _selfie = image; _errorMsg = null; });
      }
    } catch (_) {
      if (mounted) setState(() => _errorMsg = 'No se pudo acceder a la cámara');
    }
  }

  Future<void> _submit() async {
    if (_selfie == null) {
      setState(() => _errorMsg = 'Por favor toma una selfie para continuar');
      return;
    }
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final result = await widget.service.verificar(
        selfieFile: File(_selfie!.path),
        tipo: widget.tipo,
        latitud: widget.position?.latitude,
        longitud: widget.position?.longitude,
      );
      final registro = RegistroAsistencia(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        tipo: widget.tipo,
        status: result.status,
        score: result.score,
        latitud: widget.position?.latitude,
        longitud: widget.position?.longitude,
        motivo: result.motivo,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCompleted(registro);
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _errorMsg = e.toString().replaceAll('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    final now = DateTime.now();
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
              // Handle
              Center(
                child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),

              // Título
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
                        Text('${pad(now.day)}/${pad(now.month)}/${now.year}  ·  ${pad(now.hour)}:${pad(now.minute)}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // GPS con dirección
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (widget.position != null ? green : Colors.orange).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (widget.position != null ? green : Colors.orange).withValues(alpha: 0.25),
                  ),
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
                                decoration: BoxDecoration(
                                  color: green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
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
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ],
                      )
                    : const Row(
                        children: [
                          Icon(Icons.location_off, color: Colors.orange, size: 18),
                          SizedBox(width: 8),
                          Text('Sin ubicación GPS', style: TextStyle(fontSize: 12, color: Colors.orange)),
                        ],
                      ),
              ),
              const SizedBox(height: 20),

              // Selfie
              const Text('Verificación Facial', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 10),

              if (_selfie == null)
                GestureDetector(
                  onTap: _isLoading ? null : _takeSelfie,
                  child: Container(
                    width: double.infinity,
                    height: 160,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 46, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text('Tomar selfie', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Toca para abrir la cámara frontal', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
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
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: _isLoading ? null : _takeSelfie,
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
                width: double.infinity,
                height: 54,
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

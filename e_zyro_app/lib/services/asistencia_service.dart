import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asistencia_models.dart';

class AsistenciaService {
  // Actualizar esta URL cuando el FastAPI esté desplegado en producción
  static const String _asistenciaUrl =
      'https://e-zyro-production.up.railway.app/verificar-asistencia';
  static const String _historyKey = 'asistencia_historial';

  final SharedPreferences _prefs;

  AsistenciaService(this._prefs);

  String get _token => _prefs.getString('auth_token') ?? '';
  String get _userName => _prefs.getString('user_name') ?? '';

  // Verifica si el empleado tiene foto de referencia configurada (URL remota o local).
  Future<bool> tieneRefPhoto() async {
    final url = _prefs.getString('user_foto_url') ?? '';
    if (url.isNotEmpty) return true;

    final localPath = _prefs.getString('user_foto_local_path') ?? '';
    if (localPath.isNotEmpty) {
      return File(localPath).existsSync();
    }
    return false;
  }

  Future<VerificacionResponse> verificar({
    required File selfieFile,
    required String tipo,
    double? latitud,
    double? longitud,
  }) async {
    final selfieBytes = await selfieFile.readAsBytes();
    final selfieBase64 = base64Encode(selfieBytes);

    // ── Obtener imagen de referencia ──────────────────────────────────────────
    String? imagenBase;

    // 1. Intentar URL remota (foto de perfil del backend)
    final fotoUrl = _prefs.getString('user_foto_url') ?? '';
    if (fotoUrl.isNotEmpty) {
      try {
        final resp = await http
            .get(Uri.parse(fotoUrl))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          imagenBase = base64Encode(resp.bodyBytes);
        }
      } catch (_) {}
    }

    // 2. Intentar archivo local configurado por el usuario
    if (imagenBase == null) {
      final localPath = _prefs.getString('user_foto_local_path') ?? '';
      if (localPath.isNotEmpty) {
        final localFile = File(localPath);
        if (localFile.existsSync()) {
          imagenBase = base64Encode(await localFile.readAsBytes());
        }
      }
    }

    // 3. Sin foto de referencia → error claro para el usuario
    if (imagenBase == null) {
      throw Exception(
        'No tienes foto de referencia configurada. '
        'Ve a "Configurar foto" antes de registrar tu asistencia.',
      );
    }

    final response = await http
        .post(
          Uri.parse(_asistenciaUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_token',
          },
          body: jsonEncode({
            'imagen_base': imagenBase,
            'imagen_selfie': selfieBase64,
            'metadata': {
              'nombre': _userName,
              'tipo_registro': tipo,
              'latitud': latitud,
              'longitud': longitud,
              'plataforma': 'mobile',
            },
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return VerificacionResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error del servidor: ${response.statusCode}');
    }
  }

  List<RegistroAsistencia> getHistorial() {
    final raw = _prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => RegistroAsistencia.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {
      return [];
    }
  }

  Future<void> guardarRegistro(RegistroAsistencia registro) async {
    final historial = getHistorial();
    historial.insert(0, registro);
    final trimmed = historial.take(30).toList();
    await _prefs.setString(
      _historyKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  List<RegistroAsistencia> getHoy() {
    final hoy = DateTime.now();
    return getHistorial()
        .where(
          (r) =>
              r.timestamp.year == hoy.year &&
              r.timestamp.month == hoy.month &&
              r.timestamp.day == hoy.day,
        )
        .toList();
  }
}

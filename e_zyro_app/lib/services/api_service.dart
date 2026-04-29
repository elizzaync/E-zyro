import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_models.dart';
import '../models/dashboard_models.dart';

class ApiService {
  static const String baseUrl = 'https://e-zyro-production.up.railway.app';
  static const String loginEndpoint = '/auth/login';
  static const String passwordRecoveryRequestEndpoint =
      '/auth/password-recovery/request';
  static const String passwordRecoveryVerifyEndpoint =
      '/auth/password-recovery/verify';
  static const String passwordRecoveryResetEndpoint =
      '/auth/password-recovery/reset';

  final SharedPreferences _prefs;

  ApiService(this._prefs);

  // ─── LOGIN ───────────────────────────────────────────────────────────
  Future<LoginResponse> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$loginEndpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final loginResponse = LoginResponse.fromJson(jsonDecode(response.body));
        // Guardar token
        await _prefs.setString('auth_token', loginResponse.data.token);
        await _prefs.setString('user_name', loginResponse.data.nombreCompleto);
        await _prefs.setString('user_rol', loginResponse.data.rol);
        return loginResponse;
      } else if (response.statusCode == 401) {
        throw Exception('Usuario o contraseña incorrectos');
      } else {
        throw Exception('Error en el servidor: ${response.statusCode}');
      }
    } on http.ClientException {
      throw Exception('Error de conexión. Verifica tu internet.');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ─── SOLICITAR CÓDIGO ───────────────────────────────────────────────
  Future<ApiResponse> requestPasswordReset({required String email}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$passwordRecoveryRequestEndpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return ApiResponse.fromJson(jsonDecode(response.body), null);
      } else if (response.statusCode == 404) {
        throw Exception('Este correo no está registrado en el sistema.');
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Error al solicitar el código');
      }
    } on http.ClientException {
      throw Exception('Error de conexión. Verifica tu internet.');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ─── VERIFICAR CÓDIGO ───────────────────────────────────────────────
  Future<ApiResponse> verifyPasswordCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$passwordRecoveryVerifyEndpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'code': code}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return ApiResponse.fromJson(jsonDecode(response.body), null);
      } else if (response.statusCode == 400) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Código inválido o expirado');
      } else if (response.statusCode == 403) {
        throw Exception('Código bloqueado por superar límite de intentos.');
      } else if (response.statusCode == 404) {
        throw Exception('Usuario no encontrado.');
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } on http.ClientException {
      throw Exception('Error de conexión. Verifica tu internet.');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ─── RESETEAR CONTRASEÑA ────────────────────────────────────────────
  Future<ApiResponse> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$passwordRecoveryResetEndpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'code': code,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return ApiResponse.fromJson(jsonDecode(response.body), null);
      } else if (response.statusCode == 400) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Error al cambiar contraseña');
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } on http.ClientException {
      throw Exception('Error de conexión. Verifica tu internet.');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ─── AUTH HEADER ────────────────────────────────────────────────────
  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${_prefs.getString('auth_token') ?? ''}',
  };

  // ─── DASHBOARD: RESUMEN KPIs ─────────────────────────────────────────
  Future<DashboardResumen> getDashboardResumen() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/dashboard/resumen'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return DashboardResumen.fromJson(data);
      } else if (response.statusCode == 401) {
        throw Exception('Sesión expirada. Inicia sesión nuevamente.');
      } else {
        throw Exception('Error al cargar resumen: ${response.statusCode}');
      }
    } on http.ClientException {
      throw Exception('Error de conexión. Verifica tu internet.');
    } catch (e) {
      rethrow;
    }
  }

  // ─── DASHBOARD: PRÓXIMOS SERVICIOS ───────────────────────────────────
  Future<List<ProximoServicio>> getProximosServicios() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/dashboard/proximos-servicios'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((e) => ProximoServicio.fromJson(e)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Sesión expirada. Inicia sesión nuevamente.');
      } else {
        throw Exception('Error al cargar servicios: ${response.statusCode}');
      }
    } on http.ClientException {
      throw Exception('Error de conexión. Verifica tu internet.');
    } catch (e) {
      rethrow;
    }
  }

  // ─── DASHBOARD: NOTIFICACIONES ───────────────────────────────────────
  Future<List<NotificacionDashboard>> getNotificaciones() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/dashboard/notificaciones'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((e) => NotificacionDashboard.fromJson(e)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Sesión expirada. Inicia sesión nuevamente.');
      } else {
        throw Exception('Error al cargar notificaciones: ${response.statusCode}');
      }
    } on http.ClientException {
      throw Exception('Error de conexión. Verifica tu internet.');
    } catch (e) {
      rethrow;
    }
  }

  // ─── UTILIDADES ─────────────────────────────────────────────────────
  Future<String?> getToken() async {
    return _prefs.getString('auth_token');
  }

  Future<bool> isAuthenticated() async {
    return _prefs.getString('auth_token') != null;
  }

  Future<void> logout() async {
    await _prefs.remove('auth_token');
    await _prefs.remove('user_name');
    await _prefs.remove('user_rol');
  }

  String? get userName => _prefs.getString('user_name');
  String? get userRol => _prefs.getString('user_rol');
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../models/auth_models.dart';

class AuthService {
  final ApiClient _client;
  final SharedPreferences _prefs;
  AuthService(this._client, this._prefs);

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<LoginResponse> login({
    required String username,
    required String password,
  }) async {
    try {
      final r = await _client.postPublic(
        '/auth/login',
        {'username': username, 'password': password},
      );
      if (r.statusCode == 200) {
        final res = LoginResponse.fromJson(jsonDecode(r.body));
        await _prefs.setString('auth_token', res.data.token);
        await _prefs.setString('user_name', res.data.nombreCompleto);
        await _prefs.setString('user_rol', res.data.rol);
        return res;
      } else if (r.statusCode == 401) {
        throw Exception('Usuario o contraseña incorrectos');
      } else {
        throw Exception('Error en el servidor: ${r.statusCode}');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ── Password recovery ─────────────────────────────────────────────────────

  Future<ApiResponse> requestPasswordReset({required String email}) async {
    try {
      final r = await _client.postPublic(
        '/auth/password-recovery/request',
        {'email': email},
      );
      if (r.statusCode == 200) {
        return ApiResponse.fromJson(jsonDecode(r.body), null);
      } else if (r.statusCode == 404) {
        throw Exception('Este correo no está registrado en el sistema.');
      } else {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        throw Exception(body['detail'] ?? 'Error al solicitar el código');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<ApiResponse> verifyPasswordCode({
    required String email,
    required String code,
  }) async {
    try {
      final r = await _client.postPublic(
        '/auth/password-recovery/verify',
        {'email': email, 'code': code},
      );
      if (r.statusCode == 200) {
        return ApiResponse.fromJson(jsonDecode(r.body), null);
      } else if (r.statusCode == 400) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        throw Exception(body['detail'] ?? 'Código inválido o expirado');
      } else if (r.statusCode == 403) {
        throw Exception('Código bloqueado por superar límite de intentos.');
      } else if (r.statusCode == 404) {
        throw Exception('Usuario no encontrado.');
      } else {
        throw Exception('Error del servidor: ${r.statusCode}');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<ApiResponse> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final r = await _client.postPublic(
        '/auth/password-recovery/reset',
        {'email': email, 'code': code, 'new_password': newPassword},
      );
      if (r.statusCode == 200) {
        return ApiResponse.fromJson(jsonDecode(r.body), null);
      } else if (r.statusCode == 400) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        throw Exception(body['detail'] ?? 'Error al cambiar contraseña');
      } else {
        throw Exception('Error del servidor: ${r.statusCode}');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ── Session ───────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _prefs.remove('auth_token');
    await _prefs.remove('user_name');
    await _prefs.remove('user_rol');
  }

  bool get isAuthenticated => _prefs.getString('auth_token') != null;
  String? get userName => _prefs.getString('user_name');
  String? get userRol => _prefs.getString('user_rol');
}

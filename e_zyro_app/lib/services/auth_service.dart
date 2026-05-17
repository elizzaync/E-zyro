import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../models/auth_models.dart';

class AuthService {
  final ApiClient _client;
  final SharedPreferences _prefs;

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _tokenKey = 'auth_token';

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
        // SharedPreferences: acceso síncrono para ApiClient
        await _prefs.setString(_tokenKey, res.data.token);
        // SecureStorage: almacenamiento cifrado (Android Keystore / iOS Keychain)
        await _secure.write(key: _tokenKey, value: res.data.token);

        await _prefs.setString('user_name', res.data.nombreCompleto);
        await _prefs.setString('user_rol', res.data.rol);
        if (res.data.fotoUrl.isNotEmpty) {
          await _prefs.setString('user_foto_url', res.data.fotoUrl);
        }
        return res;
      } else if (r.statusCode == 401) {
        throw Exception('Usuario o contraseña incorrectos');
      } else {
        throw Exception('Error de autenticación. Intenta nuevamente.');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Error login: $e');
      throw Exception('Error al conectar. Verifica tu conexión.');
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
      } else {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        throw Exception(body['detail'] ?? 'Error al solicitar el código');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Error al conectar. Verifica tu conexión.');
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
      } else {
        throw Exception('Error al verificar el código. Intenta nuevamente.');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Error al conectar. Verifica tu conexión.');
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
        throw Exception('Error al procesar la solicitud. Intenta nuevamente.');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Error al conectar. Verifica tu conexión.');
    }
  }

  // ── Token refresh (biometric flow) ───────────────────────────────────────

  Future<void> refreshToken() async {
    final currentToken = _prefs.getString(_tokenKey);
    if (currentToken == null) throw Exception('Sin sesión activa');

    final r = await _client.postRefresh('/auth/refresh', currentToken);
    if (r.statusCode == 200) {
      final body    = jsonDecode(r.body) as Map<String, dynamic>;
      final newToken = body['data']['token'] as String;
      await _prefs.setString(_tokenKey, newToken);
      await _secure.write(key: _tokenKey, value: newToken);
    } else {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'No se pudo renovar la sesión');
    }
  }

  // ── Session ───────────────────────────────────────────────────────────────

  Future<void> logout({String? fcmToken}) async {
    if (fcmToken != null) {
      try {
        await _client.post('/notificaciones/dispositivos/desregistrar', {
          'token_push': fcmToken,
          'plataforma': _prefs.getString('device_platform') ?? 'android',
        });
      } catch (_) {}
    }
    await _prefs.remove(_tokenKey);
    await _prefs.remove('user_name');
    await _prefs.remove('user_rol');
    await _prefs.remove('user_foto_url');
    await _secure.delete(key: _tokenKey);
  }

  /// Restaura el token desde SecureStorage hacia SharedPreferences si es necesario.
  /// Llamar desde el splash screen antes de leer el token.
  static Future<void> restoreTokenIfNeeded(SharedPreferences prefs) async {
    if (prefs.getString(_tokenKey) != null) return;
    try {
      final secureToken = await _secure.read(key: _tokenKey);
      if (secureToken != null) {
        await prefs.setString(_tokenKey, secureToken);
      }
    } catch (_) {}
  }

  bool get isAuthenticated => _prefs.getString(_tokenKey) != null;
  String? get userName => _prefs.getString('user_name');
  String? get userRol => _prefs.getString('user_rol');
}

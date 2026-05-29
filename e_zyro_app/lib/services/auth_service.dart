import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../models/auth_models.dart';
import '../repositories/cache_repo.dart';
import '../utils/app_session.dart';
import 'asistencia_service.dart';
import 'dashboard_service.dart';

String get _devicePlatform {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}

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
        await _prefs.setString(_tokenKey, res.data.token);
        if (!kIsWeb) await _secure.write(key: _tokenKey, value: res.data.token);

        await _prefs.setString('user_name', res.data.nombreCompleto);
        await _prefs.setString('user_rol', res.data.rol);
        await _prefs.setStringList('user_permisos', res.data.permisos);
        if (res.data.fotoUrl.isNotEmpty) {
          await _prefs.setString('user_foto_url', res.data.fotoUrl);
        }
        await AppSession.load();
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

  // ── Validación local del JWT (sin red) ───────────────────────────────────

  /// Decodifica el JWT guardado en disco y comprueba si aún no expiró.
  /// No requiere red — solo inspecciona el campo `exp` del payload.
  bool isStoredTokenValid() {
    try {
      final token = _prefs.getString(_tokenKey);
      if (token == null) return false;
      final parts = token.split('.');
      if (parts.length != 3) return false;

      // Base64url → base64 estándar con padding correcto
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2: payload += '=='; break;
        case 3: payload += '='; break;
      }

      final data = jsonDecode(
        utf8.decode(base64Decode(payload)),
      ) as Map<String, dynamic>;

      final exp = data['exp'] as int?;
      if (exp == null) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      return DateTime.now().toUtc().isBefore(expiry);
    } catch (_) {
      return false;
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
      if (!kIsWeb) await _secure.write(key: _tokenKey, value: newToken);
    } else {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'No se pudo renovar la sesión');
    }
  }

  // ── Refresco de rol/permisos (autosana la sesión) ─────────────────────────

  /// Recarga rol + permisos desde el servidor (GET /auth/me) y los reescribe en
  /// prefs + AppSession. Best-effort: si falla (offline / 401), conserva lo
  /// cacheado y no rompe el arranque. Devuelve true si actualizó.
  Future<bool> refrescarSesion() async {
    final token = _prefs.getString(_tokenKey);
    if (token == null) return false;
    try {
      final r = await _client.get('/auth/me');
      if (r.statusCode != 200) return false;
      final data = (jsonDecode(r.body) as Map<String, dynamic>)['data']
          as Map<String, dynamic>?;
      if (data == null) return false;

      final rol = (data['rol'] ?? '') as String;
      final permisos = (data['permisos'] as List?)?.cast<String>() ?? <String>[];
      final nombre = (data['nombre_completo'] ?? '') as String;
      final fotoUrl = (data['foto_url'] ?? '') as String;

      if (rol.isNotEmpty) await _prefs.setString('user_rol', rol);
      await _prefs.setStringList('user_permisos', permisos);
      if (nombre.isNotEmpty) await _prefs.setString('user_name', nombre);
      if (fotoUrl.isNotEmpty) await _prefs.setString('user_foto_url', fotoUrl);
      await AppSession.load();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Session ───────────────────────────────────────────────────────────────

  Future<void> logout({String? fcmToken}) async {
    if (fcmToken != null) {
      try {
        await _client.post('/notificaciones/dispositivos/desregistrar', {
          'token_push': fcmToken,
          'plataforma': _devicePlatform,
        });
      } catch (_) {}
    }
    await _prefs.remove(_tokenKey);
    await _prefs.remove('user_name');
    await _prefs.remove('user_rol');
    await _prefs.remove('user_permisos');
    await _prefs.remove('user_foto_url');
    // Limpiar caché offline para no mezclar datos entre usuarios.
    for (final k in [...AsistenciaService.cacheKeys, ...DashboardService.cacheKeys]) {
      await _prefs.remove(k);
    }
    await CacheRepo().clearAll();
    if (!kIsWeb) await _secure.delete(key: _tokenKey);
    AppSession.clear();
  }

  /// Restaura el token desde SecureStorage hacia SharedPreferences si es necesario.
  /// Llamar desde el splash screen antes de leer el token.
  static Future<void> restoreTokenIfNeeded(SharedPreferences prefs) async {
    if (kIsWeb) return; // SecureStorage no aplica en web
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
  List<String> get userPermisos => _prefs.getStringList('user_permisos') ?? [];

  bool hasPermiso(String permiso) {
    final rol = (userRol ?? '').toLowerCase().trim();
    if (rol == 'admin' || rol == 'administrador' || rol == 'superadmin') return true;
    final p = permiso.toLowerCase().trim();
    return userPermisos.any((e) => e.toLowerCase().trim() == p);
  }

  static bool checkPermiso(SharedPreferences prefs, String permiso) {
    final rol = (prefs.getString('user_rol') ?? '').toLowerCase().trim();
    if (rol == 'admin' || rol == 'administrador' || rol == 'superadmin') return true;
    final p = permiso.toLowerCase().trim();
    return (prefs.getStringList('user_permisos') ?? []).any((e) => e.toLowerCase().trim() == p);
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_constants.dart';

/// Low-level HTTP client — injects auth token, applies timeout, centralises
/// error translation. All services receive an instance of this class.
class ApiClient {
  final SharedPreferences _prefs;
  final http.Client _http;

  ApiClient(this._prefs, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  String get _token => _prefs.getString('auth_token') ?? '';

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      };

  static const Map<String, String> _publicHeaders = {
    'Content-Type': 'application/json',
  };

  // ── HTTP verbs ────────────────────────────────────────────────────────────

  Future<http.Response> get(String path, {Duration? timeout}) async {
    final token = _token;
    if (token.isEmpty) {
      throw Exception('No auth token found. Please login again.');
    }
    return _http
        .get(Uri.parse('${AppConstants.baseUrl}$path'), headers: _authHeaders)
        .timeout(timeout ?? AppConstants.defaultTimeout);
  }

  Future<http.Response> put(String path, [Object? body]) async {
    final token = _token;
    if (token.isEmpty) {
      throw Exception('No auth token found. Please login again.');
    }
    return _http
        .put(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: _authHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(AppConstants.defaultTimeout);
  }

  Future<http.Response> patch(String path, [Object? body]) async {
    final token = _token;
    if (token.isEmpty) {
      throw Exception('No auth token found. Please login again.');
    }
    return _http
        .patch(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: _authHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(AppConstants.defaultTimeout);
  }

  Future<http.Response> post(
    String path,
    Object body, {
    Duration? timeout,
  }) async {
    final token = _token;
    if (token.isEmpty) {
      throw Exception('No auth token found. Please login again.');
    }
    return _http
        .post(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: _authHeaders,
          body: jsonEncode(body),
        )
        .timeout(timeout ?? AppConstants.defaultTimeout);
  }

  /// POST with an explicit Bearer token (token refresh — token may be expired).
  Future<http.Response> postRefresh(String path, String token) => _http
      .post(
        Uri.parse('${AppConstants.baseUrl}$path'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: '{}',
      )
      .timeout(AppConstants.defaultTimeout);

  /// POST multipart/form-data (photo uploads).
  Future<http.Response> postMultipart(
    String path,
    Map<String, String> fields,
    String fileField,
    String filePath,
  ) async {
    final token = _token;
    if (token.isEmpty) {
      throw Exception('No auth token found. Please login again.');
    }
    final uri = Uri.parse('${AppConstants.baseUrl}$path');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields)
      ..files.add(await http.MultipartFile.fromPath(fileField, filePath));
    final streamed = await _http.send(request).timeout(AppConstants.uploadTimeout);
    return http.Response.fromStream(streamed);
  }

  Future<http.Response> delete(String path) async {
    final token = _token;
    if (token.isEmpty) {
      throw Exception('No auth token found. Please login again.');
    }
    return _http
        .delete(Uri.parse('${AppConstants.baseUrl}$path'), headers: _authHeaders)
        .timeout(AppConstants.defaultTimeout);
  }

  /// POST without Bearer token (login, password recovery).
  Future<http.Response> postPublic(String path, Object body) => _http
      .post(
        Uri.parse('${AppConstants.baseUrl}$path'),
        headers: _publicHeaders,
        body: jsonEncode(body),
      )
      .timeout(AppConstants.defaultTimeout);

  // ── Error handling ────────────────────────────────────────────────────────

  /// Throws [Exception] with a human-readable message when status != 200.
  void checkResponse(http.Response r, {required String fallback}) {
    if (r.statusCode == 200) return;

    final String mensaje;

    if (r.statusCode == 404) {
      final detail = _extractDetail(r.body, '');
      mensaje = (detail.isEmpty || detail == 'Not Found')
          ? 'Endpoint no encontrado en el servidor.'
          : detail;
    } else if (r.statusCode == 422) {
      mensaje = _extractDetail(r.body, 'Datos inválidos enviados al servidor.');
    } else if (r.statusCode == 401 || r.statusCode == 403) {
      mensaje = 'Sesión expirada. Vuelve a iniciar sesión.';
    } else if (r.statusCode >= 500) {
      final detail = _extractDetail(r.body, '');
      mensaje = detail.isNotEmpty
          ? detail
          : 'Error interno del servidor (${r.statusCode}). Intenta nuevamente.';
    } else {
      mensaje = _extractDetail(r.body, '$fallback (${r.statusCode})');
    }

    throw Exception(mensaje);
  }

  String _extractDetail(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) {
          return (detail.first as Map)['msg']?.toString() ?? fallback;
        }
      }
    } catch (_) {}
    return fallback;
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_constants.dart';

/// Low-level HTTP client — injects auth token, applies timeout, centralises
/// error translation. All services receive an instance of this class.
class ApiClient {
  /// Cliente HTTP compartido por toda la app: reutiliza conexiones (keep-alive),
  /// evitando un handshake TLS nuevo en cada request a Railway. Antes se creaba
  /// un http.Client por servicio y nunca se cerraba (sin reúso + fuga de recursos).
  static final http.Client _sharedHttp = http.Client();

  final SharedPreferences _prefs;
  final http.Client _http;

  ApiClient(this._prefs, {http.Client? httpClient})
      : _http = httpClient ?? _sharedHttp;

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
    if (token.isEmpty) throw _sessionExpired();
    final r = await _http
        .get(Uri.parse('${AppConstants.baseUrl}$path'), headers: _authHeaders)
        .timeout(timeout ?? AppConstants.defaultTimeout);
    if (r.statusCode == 401) throw _sessionExpired();
    return r;
  }

  static Exception _sessionExpired() =>
      Exception('Sesión expirada. Por favor inicia sesión nuevamente.');

  Future<http.Response> put(String path, [Object? body]) async {
    final token = _token;
    if (token.isEmpty) throw _sessionExpired();
    final r = await _http
        .put(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: _authHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(AppConstants.defaultTimeout);
    if (r.statusCode == 401) throw _sessionExpired();
    return r;
  }

  Future<http.Response> patch(String path, [Object? body]) async {
    final token = _token;
    if (token.isEmpty) throw _sessionExpired();
    final r = await _http
        .patch(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: _authHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(AppConstants.defaultTimeout);
    if (r.statusCode == 401) throw _sessionExpired();
    return r;
  }

  Future<http.Response> post(
    String path,
    Object body, {
    Duration? timeout,
  }) async {
    final token = _token;
    if (token.isEmpty) throw _sessionExpired();
    final r = await _http
        .post(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: _authHeaders,
          body: jsonEncode(body),
        )
        .timeout(timeout ?? AppConstants.defaultTimeout);
    if (r.statusCode == 401) throw _sessionExpired();
    return r;
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

  /// MIME por extensión: MultipartFile.fromPath NO lo infiere y manda
  /// application/octet-stream, que el backend rechaza al validar evidencias.
  static const Map<String, String> _mimePorExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'pdf': 'application/pdf',
  };

  static MediaType? _mediaTypeDe(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    final mime = _mimePorExtension[ext];
    if (mime == null) return null;
    final parts = mime.split('/');
    return MediaType(parts[0], parts[1]);
  }

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
      ..files.add(await http.MultipartFile.fromPath(
        fileField,
        filePath,
        contentType: _mediaTypeDe(filePath),
      ));
    final streamed = await _http.send(request).timeout(AppConstants.uploadTimeout);
    return http.Response.fromStream(streamed);
  }

  /// POST multipart/form-data con varios archivos bajo un mismo campo
  /// (`fileField`) + un campo de texto (ej. JSON con metadatos alineados por
  /// indice a los archivos). Usado para sincronizar en lote evidencias
  /// tomadas offline en una sola request en vez de una por archivo.
  Future<http.Response> postMultipartMany(
    String path,
    Map<String, String> fields,
    String fileField,
    List<String> filePaths,
  ) async {
    final token = _token;
    if (token.isEmpty) {
      throw Exception('No auth token found. Please login again.');
    }
    final uri = Uri.parse('${AppConstants.baseUrl}$path');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields);
    for (final path in filePaths) {
      request.files.add(await http.MultipartFile.fromPath(
        fileField,
        path,
        contentType: _mediaTypeDe(path),
      ));
    }
    final streamed = await _http.send(request).timeout(AppConstants.uploadTimeout);
    return http.Response.fromStream(streamed);
  }

  /// POST multipart/form-data desde bytes en memoria (ej. un PDF generado en
  /// el cliente, sin pasar por disco).
  Future<http.Response> postMultipartBytes(
    String path,
    Map<String, String> fields,
    String fileField,
    Uint8List bytes,
    String filename, {
    String contentType = 'application/pdf',
  }) async {
    final token = _token;
    if (token.isEmpty) {
      throw Exception('No auth token found. Please login again.');
    }
    final parts = contentType.split('/');
    final uri = Uri.parse('${AppConstants.baseUrl}$path');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes(
        fileField, bytes, filename: filename,
        contentType: MediaType(parts[0], parts[1]),
      ));
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

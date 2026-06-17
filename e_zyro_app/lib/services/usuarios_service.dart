import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/usuario_admin_models.dart';

/// Cliente de Gestión de usuarios (`/usuarios`). Solo Admin / permiso
/// `usuarios:gestionar`. Todas las operaciones quedan acotadas a la empresa
/// del token en el backend.
class UsuariosService {
  final ApiClient _client;
  UsuariosService(this._client);

  Future<ApiResult<List<UsuarioAdmin>>> listar() async {
    try {
      final r = await _client.get('/usuarios');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(
            list.map((e) => UsuarioAdmin.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<RolItem>>> roles() async {
    try {
      final r = await _client.get('/usuarios/roles');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(
            list.map((e) => RolItem.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<UsuarioAdmin>> crear({
    required String nombre,
    required String apellido,
    required String email,
    required String username,
    required String password,
    required String rolId,
    bool crearFicha = false,
    String? cargo,
    String? area,
    String? tipo,
    String? codigo,
  }) async {
    try {
      final r = await _client.post('/usuarios', {
        'nombre': nombre,
        'apellido': apellido,
        'email': email,
        'username': username,
        'password': password,
        'rol_id': rolId,
        'crear_ficha': crearFicha,
        'cargo': ?cargo,
        'area': ?area,
        'tipo': ?tipo,
        'codigo': ?codigo,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(UsuarioAdmin.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<UsuarioAdmin>> cambiarRol(String usuarioId, String rolId) async {
    try {
      final r = await _client.put('/usuarios/$usuarioId/rol', {'rol_id': rolId});
      if (r.statusCode == 200) {
        return ApiResult.ok(UsuarioAdmin.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<UsuarioAdmin>> cambiarActivo(String usuarioId, bool activo) async {
    try {
      final r = await _client.put('/usuarios/$usuarioId/activo', {'activo': activo});
      if (r.statusCode == 200) {
        return ApiResult.ok(UsuarioAdmin.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> resetPassword(String usuarioId, String password) async {
    try {
      final r = await _client.post('/usuarios/$usuarioId/reset-password', {'password': password});
      if (r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

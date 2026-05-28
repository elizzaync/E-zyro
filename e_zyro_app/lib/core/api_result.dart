import 'dart:convert';
import 'package:http/http.dart' as http;

/// Clasificación de un fallo de API para que la UI muestre la causa real
/// (en vez de "No se pudo…") y decida si reintentar o pedir re-login.
enum ApiErrorKind {
  network, // sin conexión / timeout
  auth, // 401 — sesión expirada
  forbidden, // 403 — sin permiso (p. ej. solo Jefe finaliza)
  validation, // 422 — datos inválidos
  conflict, // 409 — regla de negocio (p. ej. checklist incompleto)
  notFound, // 404
  server, // 5xx
  unknown,
}

class ApiError {
  final ApiErrorKind kind;

  /// Detalle provisto por el backend (`detail`), si lo hay. Tiene prioridad.
  final String? detail;

  const ApiError(this.kind, [this.detail]);

  /// Mensaje listo para mostrar al usuario.
  String get message =>
      detail ??
      switch (kind) {
        ApiErrorKind.network =>
          'Sin conexión. Revisa tu red e inténtalo de nuevo.',
        ApiErrorKind.auth => 'Tu sesión expiró. Vuelve a iniciar sesión.',
        ApiErrorKind.forbidden => 'No tienes permiso para esta acción.',
        ApiErrorKind.validation => 'Los datos enviados no son válidos.',
        ApiErrorKind.conflict => 'La acción no cumple las reglas del servicio.',
        ApiErrorKind.notFound => 'No se encontró el recurso.',
        ApiErrorKind.server => 'Error del servidor. Inténtalo más tarde.',
        ApiErrorKind.unknown => 'Ocurrió un error. Inténtalo de nuevo.',
      };

  /// Construye el error a partir de una respuesta HTTP no exitosa.
  factory ApiError.fromResponse(http.Response r) {
    String? detail;
    try {
      final b = jsonDecode(r.body);
      if (b is Map) {
        final d = b['detail'];
        if (d is String) {
          detail = d;
        } else if (d is List && d.isNotEmpty && d.first is Map) {
          detail = (d.first as Map)['msg']?.toString();
        }
      }
    } catch (_) {}

    final kind = switch (r.statusCode) {
      401 => ApiErrorKind.auth,
      403 => ApiErrorKind.forbidden,
      404 => ApiErrorKind.notFound,
      409 => ApiErrorKind.conflict,
      422 => ApiErrorKind.validation,
      >= 500 => ApiErrorKind.server,
      _ => ApiErrorKind.unknown,
    };
    return ApiError(kind, detail);
  }
}

/// Resultado tipado de una operación de API: éxito con datos, o fallo con causa.
class ApiResult<T> {
  final T? data;
  final ApiError? error;

  /// true cuando la acción no se envió por falta de red pero quedó **encolada**
  /// localmente para reintentarse al reconectar (offline-first).
  final bool queued;

  const ApiResult.ok([this.data])
      : error = null,
        queued = false;
  const ApiResult.fail(this.error)
      : data = null,
        queued = false;
  const ApiResult.enqueued()
      : data = null,
        error = null,
        queued = true;

  /// Sin error (incluye el caso encolado: no falló, se reintentará).
  bool get ok => error == null;

  /// Mensaje de error listo para UI (cadena vacía si no hubo error).
  String get errorMessage => error?.message ?? '';
}

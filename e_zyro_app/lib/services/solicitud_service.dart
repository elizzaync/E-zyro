import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../models/solicitud_models.dart';

/// Servicio de Solicitudes Laborales: justificación de tardanza (trabajador),
/// "mis solicitudes" y bandeja de revisión RR.HH. (listar + evaluar).
class SolicitudService {
  final ApiClient _client;
  SolicitudService(this._client);

  /// POST /permisos/justificar-tardanza — crea la justificación rápida.
  /// Devuelve (ok, mensaje) para distinguir éxito de duplicado/errores.
  Future<({bool ok, String mensaje})> justificarTardanza({
    required String fecha, // yyyy-MM-dd
    String? modalidad,
    String? detalle,
    int? minutosTarde,
    String? registroId,
  }) async {
    try {
      final r = await _client.post('/permisos/justificar-tardanza', {
        'fecha': fecha,
        'modalidad': modalidad,
        'detalle': detalle,
        'minutos_tarde': minutosTarde,
        'registro_id': registroId,
      });
      if (r.statusCode == 200 || r.statusCode == 201) {
        return (ok: true, mensaje: 'Justificación enviada a RR.HH.');
      }
      String msg = 'No se pudo enviar la justificación.';
      try {
        final d = jsonDecode(r.body);
        if (d is Map && d['detail'] != null) msg = d['detail'].toString();
      } catch (_) {}
      return (ok: false, mensaje: msg);
    } catch (_) {
      return (ok: false, mensaje: 'Error de conexión al enviar la justificación.');
    }
  }

  /// GET /permisos/mis-solicitudes — solicitudes del propio trabajador.
  Future<List<SolicitudLaboral>> misSolicitudes() async {
    try {
      final r = await _client.get('/permisos/mis-solicitudes');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        final list = (body is Map ? body['data'] : body) as List? ?? [];
        return list
            .map((e) => SolicitudLaboral.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// GET /rrhh/solicitudes — bandeja de RR.HH. (excluye vacaciones por defecto).
  Future<List<SolicitudLaboral>> bandeja({
    String categoria = 'permisos',
    String? estado,
  }) async {
    try {
      final q = StringBuffer('?categoria=$categoria');
      if (estado != null && estado.isNotEmpty) q.write('&estado=$estado');
      final r = await _client.get('/rrhh/solicitudes$q');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (body['solicitudes'] as List?) ?? [];
        return list
            .map((e) => SolicitudLaboral.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// PUT /rrhh/solicitudes/{id}/evaluar — aprueba o rechaza (con observación).
  Future<({bool ok, String mensaje})> evaluar(
    String id, {
    required String estado, // aprobada | rechazada
    required String observacion,
  }) async {
    try {
      final r = await _client.put('/rrhh/solicitudes/$id/evaluar', {
        'estado': estado,
        'observacion': observacion,
      });
      if (r.statusCode == 200) {
        return (ok: true, mensaje: 'Solicitud $estado.');
      }
      String msg = 'No se pudo evaluar la solicitud.';
      try {
        final d = jsonDecode(r.body);
        if (d is Map && d['detail'] != null) msg = d['detail'].toString();
      } catch (_) {}
      return (ok: false, mensaje: msg);
    } catch (_) {
      return (ok: false, mensaje: 'Error de conexión al evaluar.');
    }
  }
}

Future<SolicitudService> getSolicitudService() async {
  final prefs = await SharedPreferences.getInstance();
  return SolicitudService(ApiClient(prefs));
}

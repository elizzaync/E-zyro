import 'dart:convert';
import '../core/api_client.dart';
import '../models/dashboard_models.dart';

class DashboardService {
  final ApiClient _client;
  DashboardService(this._client);

  Future<DashboardResumen> getResumen() async {
    try {
      final r = await _client.get('/dashboard/resumen');
      if (r.statusCode == 200) {
        return DashboardResumen.fromJson(
          jsonDecode(r.body)['data'] as Map<String, dynamic>,
        );
      } else if (r.statusCode == 401) {
        throw Exception('Sesión expirada. Inicia sesión nuevamente.');
      } else {
        throw Exception('Error al cargar resumen: ${r.statusCode}');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<List<ProximoServicio>> getProximosServicios() async {
    try {
      final r = await _client.get('/dashboard/proximos-servicios');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body)['data'] as List;
        return data.map((e) => ProximoServicio.fromJson(e as Map<String, dynamic>)).toList();
      } else if (r.statusCode == 401) {
        throw Exception('Sesión expirada. Inicia sesión nuevamente.');
      } else {
        throw Exception('Error al cargar servicios: ${r.statusCode}');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<List<NotificacionDashboard>> getNotificaciones() async {
    try {
      final r = await _client.get('/dashboard/notificaciones');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body)['data'] as List;
        return data.map((e) => NotificacionDashboard.fromJson(e as Map<String, dynamic>)).toList();
      } else if (r.statusCode == 401) {
        throw Exception('Sesión expirada. Inicia sesión nuevamente.');
      } else {
        throw Exception('Error al cargar notificaciones: ${r.statusCode}');
      }
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<CalendarioData?> getCalendario() async {
    try {
      final r = await _client.get('/dashboard/calendario');
      if (r.statusCode == 200) {
        return CalendarioData.fromJson(
          jsonDecode(r.body)['data'] as Map<String, dynamic>,
        );
      }
      _client.checkResponse(r, fallback: 'Error al cargar calendario');
      return null;
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> guardarNota(String fecha, String texto) async {
    final r = await _client.post(
      '/dashboard/calendario/nota',
      {'fecha': fecha, 'texto': texto},
    );
    _client.checkResponse(r, fallback: 'Error al guardar nota');
  }

  Future<List<DetalleServicioDia>> getDetalleServicioDia(String fecha) async {
    try {
      final r = await _client.get('/dashboard/calendario/servicio/$fecha');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body)['data'] as List;
        return data
            .map((e) => DetalleServicioDia.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      _client.checkResponse(r, fallback: 'Error al cargar detalle del día');
      return [];
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> ignorarNotificacion(String id) async {
    final r = await _client.put('/dashboard/notificaciones/$id/ignorar');
    _client.checkResponse(r, fallback: 'Error al ignorar notificación');
  }
}

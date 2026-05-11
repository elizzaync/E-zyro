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
}

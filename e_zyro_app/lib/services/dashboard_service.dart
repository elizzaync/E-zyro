import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../models/dashboard_models.dart';

class DashboardService {
  final ApiClient _client;
  DashboardService(this._client);

  // Claves de caché (offline-first). Limpiar en logout.
  static const _resumenCacheKey   = 'dashboard_resumen_cache';
  static const _serviciosCacheKey = 'dashboard_servicios_cache';
  static const List<String> cacheKeys = [_resumenCacheKey, _serviciosCacheKey];

  static bool _esSesionExpirada(Object e) =>
      e.toString().toLowerCase().contains('sesión expirada') ||
      e.toString().toLowerCase().contains('sesion expirada');

  Future<DashboardResumen> getResumen() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final r = await _client.get('/dashboard/resumen');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body)['data'] as Map<String, dynamic>;
        await prefs.setString(_resumenCacheKey, jsonEncode(data));
        return DashboardResumen.fromJson(data);
      }
      if (r.statusCode == 401) {
        throw Exception('Sesión expirada. Inicia sesión nuevamente.');
      }
      // Otros códigos → intentar caché abajo.
    } catch (e) {
      if (_esSesionExpirada(e)) rethrow; // la sesión vencida sí debe ir a login
      // Red/offline → caer al caché.
    }
    final cached = prefs.getString(_resumenCacheKey);
    if (cached != null) {
      try {
        return DashboardResumen.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {}
    }
    return const DashboardResumen(activos: 0, pendientes: 0, completados: 0);
  }

  Future<List<ProximoServicio>> getProximosServicios() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final r = await _client.get('/dashboard/proximos-servicios');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body)['data'] as List;
        await prefs.setString(_serviciosCacheKey, jsonEncode(data));
        return data.map((e) => ProximoServicio.fromJson(e as Map<String, dynamic>)).toList();
      }
      if (r.statusCode == 401) {
        throw Exception('Sesión expirada. Inicia sesión nuevamente.');
      }
    } catch (e) {
      if (_esSesionExpirada(e)) rethrow;
    }
    final cached = prefs.getString(_serviciosCacheKey);
    if (cached != null) {
      try {
        final data = jsonDecode(cached) as List;
        return data.map((e) => ProximoServicio.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    return [];
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

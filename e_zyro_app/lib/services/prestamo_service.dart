import 'dart:convert';
import '../core/api_client.dart';
import '../models/prestamo_models.dart';

class PrestamoService {
  final ApiClient _client;
  PrestamoService(this._client);

  // ── Catálogo ───────────────────────────────────────────────────────────────

  /// `clase` puede ser '', 'equipo' o 'herramienta'.
  Future<List<EquipoCatalogo>> getCatalogo({String q = '', String clase = ''}) async {
    try {
      final params = <String, String>{};
      if (q.trim().isNotEmpty) params['q'] = q.trim();
      if (clase.isNotEmpty) params['clase'] = clase;
      final query = params.isEmpty
          ? ''
          : '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      final r = await _client.get('/prestamos/equipos-catalogo$query');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => EquipoCatalogo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Vista de servicio (técnico) ────────────────────────────────────────────

  Future<List<Prestamo>> getPorServicio(String servicioId) async {
    try {
      final r = await _client.get('/prestamos/servicio/$servicioId');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => Prestamo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<PrestamoAviso>> getAvisosServicio(String servicioId) async {
    try {
      final r = await _client.get('/prestamos/servicio/$servicioId/avisos');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => PrestamoAviso.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<({bool ok, String? error, String? id, int faltanteCount})> crear(
    String servicioId, {
    required List<Map<String, dynamic>> items,
    String? observacion,
  }) async {
    try {
      final body = <String, dynamic>{
        'items': items,
        if (observacion != null && observacion.isNotEmpty) 'observacion': observacion,
      };
      final r = await _client.post('/prestamos/servicio/$servicioId', body);
      if (r.statusCode == 201 || r.statusCode == 200) {
        final m = jsonDecode(r.body) as Map<String, dynamic>;
        // Ítems sin stock suficiente que se enviaron a compra a Logística.
        final faltantes = (m['faltantes'] as List?) ?? const [];
        return (
          ok: true,
          error: null,
          id: m['prestamo_id'] as String?,
          faltanteCount: faltantes.length,
        );
      }
      return (ok: false, error: _detail(r.body), id: null, faltanteCount: 0);
    } catch (_) {
      return (ok: false, error: null, id: null, faltanteCount: 0);
    }
  }

  Future<({bool ok, String? error})> devolver(
    String prestamoId, {
    required List<Map<String, dynamic>> items,
    String? observacion,
  }) async {
    try {
      final body = <String, dynamic>{
        'items': items,
        if (observacion != null && observacion.isNotEmpty) 'observacion': observacion,
      };
      final r = await _client.post('/prestamos/$prestamoId/devolver', body);
      if (r.statusCode == 200) return (ok: true, error: null);
      return (ok: false, error: _detail(r.body));
    } catch (_) {
      return (ok: false, error: null);
    }
  }

  // ── Bandeja de logística ───────────────────────────────────────────────────

  Future<List<Prestamo>> getPrestamos({String estado = 'todos'}) async {
    try {
      final r = await _client.get('/prestamos?estado=${Uri.encodeComponent(estado)}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => Prestamo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Logística despacha el préstamo y firma como entregador → 'por_recibir'.
  Future<({bool ok, String? error})> entregar(
    String prestamoId, {
    List<Map<String, dynamic>>? items,
    String? observacion,
    String? firmaEntregadorUrl,
  }) async {
    try {
      final body = <String, dynamic>{
        'items': items ?? <Map<String, dynamic>>[],
        if (observacion != null && observacion.isNotEmpty) 'observacion': observacion,
        if (firmaEntregadorUrl != null && firmaEntregadorUrl.isNotEmpty)
          'firmaEntregadorUrl': firmaEntregadorUrl,
      };
      final r = await _client.post('/prestamos/$prestamoId/entregar', body);
      if (r.statusCode == 200) return (ok: true, error: null);
      return (ok: false, error: _detail(r.body));
    } catch (_) {
      return (ok: false, error: null);
    }
  }

  /// Cinema-seat: toma el lock para firmar la recepción. 409 si otro lo tiene
  /// (el detalle viene como `firmando_por:NOMBRE`).
  Future<({bool ok, String? error})> bloquearFirmaPrestamo(String prestamoId) async {
    try {
      final r = await _client.post('/prestamos/$prestamoId/bloquear-firma', {});
      if (r.statusCode == 200) return (ok: true, error: null);
      return (ok: false, error: _detail(r.body));
    } catch (_) {
      return (ok: false, error: null);
    }
  }

  /// Libera el lock de firma de recepción (cancelación).
  Future<void> liberarFirmaPrestamo(String prestamoId) async {
    try {
      await _client.delete('/prestamos/$prestamoId/bloquear-firma');
    } catch (_) {}
  }

  /// El equipo técnico firma la recepción → 'entregado' (doble firma completa).
  Future<({bool ok, String? error})> firmarRecepcion(
    String prestamoId, {
    required String firmaReceptorUrl,
  }) async {
    try {
      final r = await _client.post('/prestamos/$prestamoId/firmar-recepcion', {
        'firmaReceptorUrl': firmaReceptorUrl,
      });
      if (r.statusCode == 200) return (ok: true, error: null);
      return (ok: false, error: _detail(r.body));
    } catch (_) {
      return (ok: false, error: null);
    }
  }

  Future<({bool ok, String? error})> rechazar(
    String prestamoId, {
    required String observacion,
  }) async {
    try {
      final r = await _client.post('/prestamos/$prestamoId/rechazar', {
        'observacion': observacion,
      });
      if (r.statusCode == 200) return (ok: true, error: null);
      return (ok: false, error: _detail(r.body));
    } catch (_) {
      return (ok: false, error: null);
    }
  }

  Future<({bool ok, String? error})> confirmarDevolucion(
    String prestamoId, {
    bool aceptar = true,
    String? observacion,
  }) async {
    try {
      final r = await _client.post(
        '/prestamos/$prestamoId/confirmar-devolucion',
        {
          'aceptar': aceptar,
          if (observacion != null && observacion.isNotEmpty) 'observacion': observacion,
        },
      );
      if (r.statusCode == 200) return (ok: true, error: null);
      return (ok: false, error: _detail(r.body));
    } catch (_) {
      return (ok: false, error: null);
    }
  }

  String? _detail(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['detail'] as String?;
    } catch (_) {
      return null;
    }
  }
}

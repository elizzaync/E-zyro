import 'dart:convert';
import '../core/api_client.dart';
import '../models/requerimiento_models.dart';

class RequerimientoService {
  final ApiClient _client;
  RequerimientoService(this._client);

  // HU-15: Catálogo con filtros y paginación
  Future<List<CatalogoItem>> getCatalogo(
    String q, {
    String? categoria,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final params = <String, String>{
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'categoria': ?categoria,
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };
      final query = params.isEmpty
          ? ''
          : '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      final r = await _client.get('/requerimientos/catalogo$query');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        final bodyMap = body is Map ? body : null;
        final list = body is List
            ? body
            : bodyMap?['items'] as List? ?? bodyMap?['data'] as List? ?? [];
        return list
            .map((e) => CatalogoItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<MiSolicitud>> getMisSolicitudes() async {
    try {
      final r = await _client.get('/requerimientos/mis-solicitudes');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => MiSolicitud.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> crearSolicitud({
    required String proyectoId,
    required List<Map<String, dynamic>> items,
    String? observacion,
  }) async {
    try {
      final body = <String, dynamic>{
        'proyecto_id': proyectoId,
        'items': items,
        if (observacion != null && observacion.isNotEmpty)
          'observacion': observacion,
      };
      final r = await _client.post('/requerimientos/crear', body);
      return r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // Panel del encargado: resumen de inventario (KPIs + alertas de bajo stock)
  Future<InventarioResumen> getResumenInventario() async {
    try {
      final r = await _client.get('/requerimientos/inventario/resumen');
      if (r.statusCode == 200) {
        return InventarioResumen.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return const InventarioResumen();
  }

  // Bandeja del encargado: solicitudes pendientes/gestionables
  Future<List<SolicitudGestion>> getSolicitudesPendientes({
    String? estado,
  }) async {
    try {
      final query = (estado != null && estado.isNotEmpty)
          ? '?estado=${Uri.encodeComponent(estado)}'
          : '';
      final r = await _client.get('/requerimientos/pendientes$query');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => SolicitudGestion.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // Aprobar o rechazar una solicitud (accion: 'aprobar' | 'rechazar')
  Future<bool> gestionarSolicitud(
    String reqId,
    String accion, {
    String? observacion,
  }) async {
    try {
      final r = await _client.patch('/requerimientos/$reqId/gestionar', {
        'accion': accion,
        if (observacion != null && observacion.isNotEmpty)
          'observacion_logistico': observacion,
      });
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Marcar una solicitud como entregada (descuenta stock)
  Future<bool> entregarSolicitud(String reqId) async {
    try {
      final r = await _client.post('/requerimientos/$reqId/entregar', {});
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // Fase 3: ajuste manual de stock (tipo: 'entrada' | 'salida' | 'ajuste')
  Future<bool> ajustarStock({
    required String materialId,
    required String tipo,
    required int cantidad,
    String? motivo,
    String? almacenId,
  }) async {
    try {
      final r = await _client.post('/requerimientos/inventario/ajuste', {
        'material_id': materialId,
        'tipo': tipo,
        'cantidad': cantidad,
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
        'almacen_id': ?almacenId,
      });
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // Fase 3: historial de movimientos (opcional filtro por material)
  Future<List<MovimientoStock>> getMovimientos({String? materialId}) async {
    try {
      final query = (materialId != null && materialId.isNotEmpty)
          ? '?material_id=${Uri.encodeComponent(materialId)}'
          : '';
      final r = await _client.get(
        '/requerimientos/inventario/movimientos$query',
      );
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => MovimientoStock.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // Fase 4: editar material (cualquier campo opcional + cantidad_minima)
  Future<bool> editarMaterial(
    String materialId, {
    String? nombre,
    String? codigo,
    String? unidad,
    String? descripcion,
    String? categoriaId,
    int? cantidadMinima,
  }) async {
    try {
      final body = <String, dynamic>{
        'nombre': ?nombre,
        'codigo': ?codigo,
        'unidad': ?unidad,
        'descripcion': ?descripcion,
        'categoria_id': ?categoriaId,
        'cantidad_minima': ?cantidadMinima,
      };
      final r = await _client.patch(
        '/requerimientos/inventario/material/$materialId',
        body,
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Fase 4: baja lógica de material
  Future<bool> eliminarMaterial(String materialId) async {
    try {
      final r = await _client.delete(
        '/requerimientos/inventario/material/$materialId',
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Fase 4: crear categoría
  Future<bool> crearCategoria(String nombre, {String? descripcion}) async {
    try {
      final r = await _client.post('/requerimientos/categorias', {
        'nombre': nombre,
        if (descripcion != null && descripcion.isNotEmpty)
          'descripcion': descripcion,
      });
      return r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // Fase 4: eliminar categoría (falla si tiene materiales)
  Future<({bool ok, String? error})> eliminarCategoria(
    String categoriaId,
  ) async {
    try {
      final r = await _client.delete('/requerimientos/categorias/$categoriaId');
      if (r.statusCode == 200) return (ok: true, error: null);
      // intentar extraer detalle
      try {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return (ok: false, error: body['detail'] as String?);
      } catch (_) {
        return (ok: false, error: null);
      }
    } catch (_) {
      return (ok: false, error: null);
    }
  }

  // Fase 6: transferir stock entre almacenes
  Future<({bool ok, String? error})> transferirStock({
    required String materialId,
    required String almacenOrigenId,
    required String almacenDestinoId,
    required int cantidad,
    String? motivo,
  }) async {
    try {
      final r = await _client.post('/requerimientos/inventario/transferencia', {
        'material_id': materialId,
        'almacen_origen_id': almacenOrigenId,
        'almacen_destino_id': almacenDestinoId,
        'cantidad': cantidad,
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
      });
      if (r.statusCode == 200 || r.statusCode == 201) {
        return (ok: true, error: null);
      }
      try {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return (ok: false, error: body['detail'] as String?);
      } catch (_) {
        return (ok: false, error: null);
      }
    } catch (_) {
      return (ok: false, error: null);
    }
  }

  Future<List<CategoriaItem>> getCategorias() async {
    try {
      final r = await _client.get('/requerimientos/categorias');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return list
            .map((e) => CategoriaItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<AlmacenItem>> getAlmacenes() async {
    try {
      final r = await _client.get('/requerimientos/almacenes');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return list
            .map((e) => AlmacenItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> crearMaterial({
    required String nombre,
    String? codigo,
    required String unidad,
    required String categoriaId,
    String? descripcion,
    int cantidadInicial = 0,
    String? almacenId,
  }) async {
    try {
      final r = await _client.post('/requerimientos/inventario/material', {
        'nombre': nombre,
        if (codigo != null && codigo.isNotEmpty) 'codigo': codigo,
        'unidad': unidad,
        'categoria_id': categoriaId,
        if (descripcion != null && descripcion.isNotEmpty)
          'descripcion': descripcion,
        'cantidad_inicial': cantidadInicial,
        'almacen_id': ?almacenId,
      });
      return r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}

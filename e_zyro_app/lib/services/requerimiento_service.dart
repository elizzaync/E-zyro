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
        if (categoria != null) 'categoria': categoria,
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
            : bodyMap?['items'] as List? ??
                bodyMap?['data'] as List? ??
                [];
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

  Future<List<CategoriaItem>> getCategorias() async {
    try {
      final r = await _client.get('/requerimientos/categorias');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return list.map((e) => CategoriaItem.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<AlmacenItem>> getAlmacenes() async {
    try {
      final r = await _client.get('/requerimientos/almacenes');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return list.map((e) => AlmacenItem.fromJson(e as Map<String, dynamic>)).toList();
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
        if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
        'cantidad_inicial': cantidadInicial,
        if (almacenId != null) 'almacen_id': almacenId,
      });
      return r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}

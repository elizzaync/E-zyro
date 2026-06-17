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
    String tipo = 'consumible',
    String estadoStock = 'todos',   // todos | con_stock | bajo | agotado
    String orden = 'nombre',        // nombre | stock_asc | stock_desc | reciente
    String? almacenId,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final params = <String, String>{
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'categoria': ?categoria,
        'tipo': tipo,
        if (estadoStock != 'todos') 'estado_stock': estadoStock,
        if (orden != 'nombre') 'orden': orden,
        'almacen_id': ?almacenId,
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };
      final query =
          '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
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

  /// Conteos para el header del catálogo (total / con stock / bajo / agotado).
  /// Respeta búsqueda, categoría y almacén; ignora el filtro de estado.
  Future<CatalogoResumen> getCatalogoResumen({
    String q = '',
    String? categoria,
    String tipo = 'consumible',
    String? almacenId,
  }) async {
    try {
      final params = <String, String>{
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'categoria': ?categoria,
        'tipo': tipo,
        'almacen_id': ?almacenId,
      };
      final query =
          '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      final r = await _client.get('/requerimientos/catalogo/resumen$query');
      if (r.statusCode == 200) {
        return CatalogoResumen.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const CatalogoResumen();
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

  // Bandeja del encargado: solicitudes pendientes/gestionables.
  // Migrado a /logistica/requerimientos (HU-16 web). 'todos' o null = lista
  // sin filtro de estado; cualquier otro valor se reenvía tal cual.
  Future<List<SolicitudGestion>> getSolicitudesPendientes({
    String? estado,
  }) async {
    try {
      final params = <String, String>{
        'estado': (estado == null || estado.isEmpty) ? 'todos' : estado,
        'page_size': '200',
      };
      final query =
          '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      final r = await _client.get('/logistica/requerimientos$query');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (body['items'] as List? ?? []);
        return list
            .map((e) => SolicitudGestion.fromJson(
                _requerimientoToSnake(e as Map<String, dynamic>)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // Aprobar o rechazar una solicitud (accion: 'aprobar' | 'rechazar').
  // Migrado a /logistica/requerimientos/{id}/aprobar|rechazar (HU-16 web).
  // Para 'aprobar' se envía decisiones=[]: el backend auto-decide ítem por ítem
  // (lo que está en stock → aprueba; lo que no → marca 'para_compra').
  Future<bool> gestionarSolicitud(
    String reqId,
    String accion, {
    String? observacion,
  }) async {
    try {
      if (accion == 'aprobar') {
        final body = <String, dynamic>{
          'decisiones': <Map<String, dynamic>>[],
          if (observacion != null && observacion.isNotEmpty)
            'observacion': observacion,
        };
        final r = await _client.post(
          '/logistica/requerimientos/$reqId/aprobar',
          body,
        );
        return r.statusCode == 200;
      }
      if (accion == 'rechazar') {
        final r = await _client.post(
          '/logistica/requerimientos/$reqId/rechazar',
          {
            'observacion': (observacion != null && observacion.isNotEmpty)
                ? observacion
                : 'Rechazado por Logística',
          },
        );
        return r.statusCode == 200;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // Marcar una solicitud como entregada (estado 'aprobado' → 'entregado').
  // Modelo híbrido de doble firma: el técnico ya firmó la recepción (receptor)
  // y aquí logística aporta la firma del entregador. El backend exige
  // `firmaEntregadorUrl` (data-url base64 o URL guardada), si no, responde 422.
  Future<bool> entregarSolicitud(String reqId, String firmaEntregadorUrl,
      {String? notas}) async {
    try {
      final r = await _client.post(
        '/logistica/requerimientos/$reqId/entregar',
        <String, dynamic>{
          'firmaEntregadorUrl': firmaEntregadorUrl,
          if (notas != null && notas.isNotEmpty) 'notas': notas,
        },
      );
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // Convierte una respuesta RequerimientoOut (camelCase) al shape snake_case que
  // espera SolicitudGestion.fromJson, sin tocar el modelo Dart.
  Map<String, dynamic> _requerimientoToSnake(Map<String, dynamic> j) {
    final items = (j['items'] as List? ?? [])
        .map((it) {
          final m = it as Map<String, dynamic>;
          return <String, dynamic>{
            'id': m['id'],
            'material_id': m['materialId'],
            'nombre': m['nombre'],
            'unidad': m['unidad'],
            'cantidad': m['cantidad'],
            'cantidad_aprobada': m['cantidadAprobada'],
          };
        })
        .toList();
    return <String, dynamic>{
      'id': j['id'],
      'estado': j['estado'],
      'fecha': j['fecha'] ?? '',
      'observacion': j['observacion'],
      'observacion_logistico': j['observacionLogistico'],
      'proyecto_nombre': j['proyectoNombre'] ?? 'Proyecto',
      'solicitante_nombre': j['solicitanteNombre'] ?? 'Sin nombre',
      'items': items,
    };
  }

  // Fase 3: ajuste manual de stock — migrado a POST /logistica/inventario/ajuste.
  Future<bool> ajustarStock({
    required String materialId,
    required String tipo,
    required int cantidad,
    String? motivo,
    String? clasificacion,   // merma|desmedro|vencido|robo|faltante|error_conteo (pérdidas)
    String? almacenId,
    double? costoUnitario,
  }) async {
    try {
      final r = await _client.post('/logistica/inventario/ajuste', {
        'material_id': materialId,
        'tipo': tipo,
        'cantidad': cantidad,
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
        if (clasificacion != null && clasificacion.isNotEmpty) 'clasificacion': clasificacion,
        'almacen_id': ?almacenId,
        'costo_unitario': ?costoUnitario,
      });
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // Fase 3: historial de movimientos — migrado a GET /logistica/inventario/movimientos.
  Future<List<MovimientoStock>> getMovimientos({String? materialId}) async {
    try {
      final query = (materialId != null && materialId.isNotEmpty)
          ? '?material_id=${Uri.encodeComponent(materialId)}'
          : '';
      final r = await _client.get(
        '/logistica/inventario/movimientos$query',
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

  // Alertas de reposición: materiales en o bajo su stock mínimo.
  Future<List<ReposicionItem>> getReposicion({String? almacenId}) async {
    try {
      final query = (almacenId != null && almacenId.isNotEmpty)
          ? '?almacen=${Uri.encodeComponent(almacenId)}'
          : '';
      final r = await _client.get('/logistica/inventario/reposicion$query');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => ReposicionItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // Fase 4: editar material — migrado a PATCH /logistica/materiales/{id}.
  // El parámetro `unidad` se ignora aquí porque la web modela la unidad como
  // FK (unidadId) y el móvil solo conoce el string; cambiar unidad requiere
  // pasar por el flujo completo con dropdown de catálogo.
  Future<bool> editarMaterial(
    String materialId, {
    String? nombre,
    String? codigo,
    String? unidad, // ignorado intencionalmente — ver comentario arriba
    String? descripcion,
    String? categoriaId,
    int? cantidadMinima,
  }) async {
    try {
      final body = <String, dynamic>{
        'nombre': ?nombre,
        'codigo': ?codigo,
        'descripcion': ?descripcion,
        'categoriaId': ?categoriaId,
        'stockMinimo': ?cantidadMinima,
      };
      final r = await _client.patch(
        '/logistica/materiales/$materialId',
        body,
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Fase 4: baja lógica de material — migrado a DELETE /logistica/materiales/{id}.
  // La web devuelve 204 No Content.
  Future<bool> eliminarMaterial(String materialId) async {
    try {
      final r = await _client.delete('/logistica/materiales/$materialId');
      return r.statusCode == 204 || r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Fase 4: crear categoría — migrado a POST /logistica/categorias.
  // El endpoint web no acepta `descripcion`; se omite si llega.
  Future<bool> crearCategoria(String nombre, {String? descripcion}) async {
    try {
      final r = await _client.post('/logistica/categorias', {
        'nombre': nombre,
      });
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // Fase 4: eliminar categoría — migrado a DELETE /logistica/categorias/{id}.
  // Falla con 409 si la categoría tiene materiales asociados.
  Future<({bool ok, String? error})> eliminarCategoria(
    String categoriaId,
  ) async {
    try {
      final r = await _client.delete('/logistica/categorias/$categoriaId');
      if (r.statusCode == 200 || r.statusCode == 204) {
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

  // Fase 6: transferir stock entre almacenes —
  // migrado a POST /logistica/inventario/transferencia.
  Future<({bool ok, String? error})> transferirStock({
    required String materialId,
    required String almacenOrigenId,
    required String almacenDestinoId,
    required int cantidad,
    String? motivo,
  }) async {
    try {
      final r = await _client.post('/logistica/inventario/transferencia', {
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

  /// Contenido de un almacén: materiales con stock + equipos con cantidad.
  Future<List<ContenidoAlmacen>> getContenidoAlmacen(String almacenId) async {
    try {
      final r = await _client.get('/logistica/almacenes/$almacenId/contenido');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return list
            .map((e) => ContenidoAlmacen.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Transferencia en lote (1 o varios ítems, material y/o equipo).
  /// [items] = [{ fuente, id, cantidad }].
  Future<({bool ok, String? error})> transferirLote({
    required String almacenOrigenId,
    required String almacenDestinoId,
    required List<Map<String, dynamic>> items,
    String? motivo,
  }) async {
    try {
      final r = await _client.post('/logistica/inventario/transferencia-lote', {
        'almacen_origen_id': almacenOrigenId,
        'almacen_destino_id': almacenDestinoId,
        'items': items,
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

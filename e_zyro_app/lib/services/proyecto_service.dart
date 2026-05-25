import 'dart:convert';
import '../core/api_client.dart';
import '../models/proyecto_models.dart';

class ProyectoService {
  final ApiClient _client;
  ProyectoService(this._client);

  // GET /operaciones/proyectos
  Future<ProyectosConKpis?> getProyectos() async {
    try {
      final r = await _client.get('/operaciones/proyectos');
      if (r.statusCode == 200) {
        return ProyectosConKpis.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // GET /operaciones/proyecto/{proyecto_id}/servicios
  Future<List<ServicioItem>> getServiciosProyecto(String proyectoId) async {
    try {
      final r = await _client.get('/operaciones/proyecto/$proyectoId/servicios');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => ServicioItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/servicio/{servicio_id}
  Future<ServicioDetalle?> getDetalleServicio(String servicioId) async {
    try {
      final r = await _client.get('/operaciones/servicio/$servicioId');
      if (r.statusCode == 200) {
        return ServicioDetalle.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // ── Mutaciones de operaciones ───────────────────────────────────────────────

  // PATCH /operaciones/servicio/{id}/estado
  Future<bool> cambiarEstadoServicio(String servicioId, String estado) async {
    try {
      final r = await _client
          .patch('/operaciones/servicio/$servicioId/estado', {'estado': estado});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // PATCH /operaciones/procedimiento/{id}/estado
  Future<bool> toggleProcedimiento(String procId, String estado) async {
    try {
      final r = await _client
          .patch('/operaciones/procedimiento/$procId/estado', {'estado': estado});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // POST /operaciones/procedimiento/{id}/evidencia  (multipart)
  // etapa: 'antes' | 'durante' | 'despues'. Devuelve la URL subida o null.
  Future<String?> subirEvidencia(
    String procId,
    String etapa,
    String filePath, {
    String descripcion = '',
  }) async {
    try {
      final r = await _client.postMultipart(
        '/operaciones/procedimiento/$procId/evidencia',
        {'etapa': etapa, if (descripcion.isNotEmpty) 'descripcion': descripcion},
        'archivo',
        filePath,
      );
      if (r.statusCode == 200 || r.statusCode == 201) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['url'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // GET /operaciones/materiales/buscar?q=
  Future<List<MaterialBusqueda>> buscarMateriales(String q) async {
    if (q.trim().length < 2) return [];
    try {
      final r = await _client
          .get('/operaciones/materiales/buscar?q=${Uri.encodeComponent(q.trim())}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => MaterialBusqueda.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/servicio/{id}/borrador
  Future<Borrador> getBorrador(String servicioId) async {
    try {
      final r = await _client.get('/operaciones/servicio/$servicioId/borrador');
      if (r.statusCode == 200) {
        return Borrador.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const Borrador(items: []);
  }

  // POST /operaciones/servicio/{id}/borrador/item → {detalle_id, requerimiento_id}
  Future<String?> agregarItemBorrador(
    String servicioId, {
    String? materialId,
    required String nombre,
    required String unidad,
    required int cantidad,
    String? especificacion,
  }) async {
    try {
      final r = await _client.post(
        '/operaciones/servicio/$servicioId/borrador/item',
        {
          'material_id': materialId,
          'nombre': nombre,
          'unidad': unidad,
          'cantidad': cantidad,
          if (especificacion != null && especificacion.isNotEmpty)
            'especificacion': especificacion,
        },
      );
      if (r.statusCode == 200 || r.statusCode == 201) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['detalle_id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // PATCH /operaciones/requerimiento-detalle/{id}
  Future<bool> actualizarReqDetalle(
    String rdId, {
    int? cantidad,
    String? nombre,
    String? especificacion,
  }) async {
    try {
      final body = <String, dynamic>{
        if (cantidad != null) 'cantidad': cantidad,
        if (nombre != null) 'nombre': nombre,
        if (especificacion != null) 'especificacion': especificacion,
      };
      final r =
          await _client.patch('/operaciones/requerimiento-detalle/$rdId', body);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // DELETE /operaciones/borrador-detalle/{id}
  Future<bool> removerItemBorrador(String rdId) async {
    try {
      final r = await _client.delete('/operaciones/borrador-detalle/$rdId');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // POST /operaciones/servicio/{id}/borrador/enviar
  Future<bool> enviarBorrador(String servicioId) async {
    try {
      final r =
          await _client.post('/operaciones/servicio/$servicioId/borrador/enviar', {});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Gestión de equipo ──────────────────────────────────────────────────────

  // GET /operaciones/proyecto/{id}/tecnicos-disponibles
  Future<List<UsuarioTecnico>> getTecnicosDisponibles(String proyectoId) async {
    try {
      final r = await _client
          .get('/operaciones/proyecto/$proyectoId/tecnicos-disponibles');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => UsuarioTecnico.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // POST /operaciones/proyecto/{id}/equipo
  Future<bool> agregarMiembro(String proyectoId, String userId) async {
    try {
      final r = await _client
          .post('/operaciones/proyecto/$proyectoId/equipo', {'user_id': userId});
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // DELETE /operaciones/proyecto/{id}/equipo/{userId}
  Future<bool> removerMiembro(String proyectoId, String userId) async {
    try {
      final r = await _client
          .delete('/operaciones/proyecto/$proyectoId/equipo/$userId');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Legacy: usado por el dashboard
  Future<List<ProyectoServicio>> getMisServicios() async {
    try {
      final r = await _client.get('/proyectos/mis-servicios');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final list = data is Map
            ? (data['servicios'] as List? ?? [])
            : (data as List? ?? []);
        return list
            .map((e) => ProyectoServicio.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}

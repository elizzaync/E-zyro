import 'dart:convert';
import '../core/api_client.dart';
import '../models/auditoria_models.dart';

class AuditoriaService {
  final ApiClient _client;
  AuditoriaService(this._client);

  Future<List<AuditoriaItem>> getAuditoria({
    String? modulo,
    String? accion,
    String? fechaDesde,
    String? fechaHasta,
    String? usuarioId,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final params = <String>[];
      params.add('page=$page');
      params.add('page_size=$pageSize');
      if (modulo != null && modulo.isNotEmpty) params.add('modulo=$modulo');
      if (accion != null && accion.isNotEmpty) params.add('accion=$accion');
      if (fechaDesde != null) params.add('fecha_desde=$fechaDesde');
      if (fechaHasta != null) params.add('fecha_hasta=$fechaHasta');
      if (usuarioId != null) params.add('usuario_id=$usuarioId');

      final path = '/auditoria${params.isEmpty ? '' : '?${params.join('&')}'}';
      final r = await _client.get(path);
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return list.map((e) => AuditoriaItem.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }
}

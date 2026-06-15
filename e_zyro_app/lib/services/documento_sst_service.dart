import '../core/api_client.dart';
import '../models/documento_sst_models.dart';
import '../models/proyecto_models.dart' show ClienteBasico;
import '../utils/json_async.dart';

/// Repositorio de documentos de cumplimiento / SST (`/documentos-sst`).
class DocumentoSstService {
  final ApiClient _client;
  DocumentoSstService(this._client);

  Future<List<DocumentoSst>> getDocumentos({
    String? clienteId,
    String? tipo,
    String? estado,
    String? q,
  }) async {
    final params = <String, String>{};
    if (clienteId != null && clienteId.isNotEmpty) params['cliente_id'] = clienteId;
    if (tipo != null && tipo.isNotEmpty) params['tipo'] = tipo;
    if (estado != null && estado.isNotEmpty) params['estado'] = estado;
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    try {
      final r = await _client.get('/documentos-sst${qs.isNotEmpty ? '?$qs' : ''}');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => DocumentoSst.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Crea un documento. `archivoBase64`/`archivoNombre` opcionales (PDF o imagen).
  Future<bool> crear({
    required String titulo,
    required String tipo,
    String? clienteId,
    String? entidadEmisora,
    String? codigo,
    String? fechaEmision,
    String? fechaVencimiento,
    String? observaciones,
    String? archivoBase64,
    String? archivoNombre,
  }) async {
    try {
      final r = await _client.post('/documentos-sst', {
        'titulo': titulo,
        'tipo': tipo,
        'cliente_id': ?clienteId,
        'entidad_emisora': ?entidadEmisora,
        'codigo': ?codigo,
        'fecha_emision': ?fechaEmision,
        'fecha_vencimiento': ?fechaVencimiento,
        'observaciones': ?observaciones,
        'archivo_base64': ?archivoBase64,
        'archivo_nombre': ?archivoNombre,
      });
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {}
    return false;
  }

  Future<bool> editar(
    String id, {
    String? titulo,
    String? tipo,
    String? clienteId,
    String? entidadEmisora,
    String? codigo,
    String? fechaEmision,
    String? fechaVencimiento,
    String? observaciones,
    String? archivoBase64,
    String? archivoNombre,
  }) async {
    try {
      final r = await _client.put('/documentos-sst/$id', {
        'titulo': ?titulo,
        'tipo': ?tipo,
        'cliente_id': ?clienteId,
        'entidad_emisora': ?entidadEmisora,
        'codigo': ?codigo,
        'fecha_emision': ?fechaEmision,
        'fecha_vencimiento': ?fechaVencimiento,
        'observaciones': ?observaciones,
        'archivo_base64': ?archivoBase64,
        'archivo_nombre': ?archivoNombre,
      });
      return r.statusCode == 200;
    } catch (_) {}
    return false;
  }

  Future<bool> eliminar(String id) async {
    try {
      final r = await _client.delete('/documentos-sst/$id');
      return r.statusCode == 204 || r.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Clientes de la empresa para el selector (reusa /operaciones/clientes).
  Future<List<ClienteBasico>> getClientes() async {
    try {
      final r = await _client.get('/operaciones/clientes');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => ClienteBasico.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}

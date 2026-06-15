import '../core/api_client.dart';
import '../models/garantia_models.dart';
import '../models/proyecto_models.dart' show ClienteBasico;
import '../utils/json_async.dart';

/// Repositorio central de garantías (`/garantias`).
class GarantiaService {
  final ApiClient _client;
  GarantiaService(this._client);

  Future<List<Garantia>> getGarantias({
    String? clienteId,
    String? proyectoId,
    String? servicioId,
    String? estado,
    String? q,
  }) async {
    final p = <String, String>{};
    if (clienteId != null && clienteId.isNotEmpty) p['cliente_id'] = clienteId;
    if (proyectoId != null && proyectoId.isNotEmpty) p['proyecto_id'] = proyectoId;
    if (servicioId != null && servicioId.isNotEmpty) p['servicio_id'] = servicioId;
    if (estado != null && estado.isNotEmpty) p['estado'] = estado;
    if (q != null && q.trim().isNotEmpty) p['q'] = q.trim();
    final qs = p.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    try {
      final r = await _client.get('/garantias${qs.isNotEmpty ? '?$qs' : ''}');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List? ?? [];
        return list
            .map((e) => Garantia.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> crearManual({
    required String archivoBase64,
    String? archivoNombre,
    String? razonSocial,
    String? clienteId,
    String? servicioId,
    String? lugar,
    String? direccion,
    String? fechaOperatividad,
    String? vigenciaGarantia,
  }) async {
    try {
      final r = await _client.post('/garantias/manual', {
        'archivo_base64': archivoBase64,
        'archivo_nombre': ?archivoNombre,
        'razon_social': ?razonSocial,
        'cliente_id': ?clienteId,
        'servicio_id': ?servicioId,
        'lugar': ?lugar,
        'direccion': ?direccion,
        'fecha_operatividad': ?fechaOperatividad,
        'vigencia_garantia': ?vigenciaGarantia,
      });
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {}
    return false;
  }

  Future<bool> eliminar(String id) async {
    try {
      final r = await _client.delete('/garantias/$id');
      return r.statusCode == 204 || r.statusCode == 200;
    } catch (_) {}
    return false;
  }

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

import 'dart:convert';
import '../core/api_client.dart';
import '../models/ingreso_directo_models.dart';

/// Servicio del módulo "Ingreso Directo" de Logística
/// (`/logistica/form-schema`, `/logistica/articulos/by-codigo`,
/// `/logistica/ingreso-directo`). Reutiliza [ApiClient] para auth/baseURL/timeout.
class IngresoDirectoService {
  final ApiClient _client;
  IngresoDirectoService(this._client);

  /// Esquema dinámico del formulario para una clase de artículo.
  /// clase ∈ {material, equipo, herramienta, equipo_tecnologico}.
  Future<FormSchemaOut> formSchema(String clase) async {
    final r = await _client.get('/logistica/form-schema/$clase');
    _client.checkResponse(r, fallback: 'No se pudo cargar el formulario');
    return FormSchemaOut.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Busca un artículo existente por código o número de serie (escanear/clonar).
  /// Devuelve null si no existe (404).
  Future<ArticuloPorCodigo?> buscarPorCodigo(String codigo) async {
    final r = await _client
        .get('/logistica/articulos/by-codigo/${Uri.encodeComponent(codigo)}');
    if (r.statusCode == 404) return null;
    _client.checkResponse(r, fallback: 'No se pudo buscar el artículo');
    return ArticuloPorCodigo.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Registra un ingreso directo (uno o varios ítems) a stock/servicio/correctivo.
  Future<IngresoDirectoResult> registrarIngresoDirecto(
      IngresoDirectoRequest req) async {
    final r = await _client.post('/logistica/ingreso-directo', req.toJson());
    if (r.statusCode != 200 && r.statusCode != 201) {
      _client.checkResponse(r, fallback: 'No se pudo registrar el ingreso');
    }
    return IngresoDirectoResult.fromJson(
        jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Modelos pertenecientes a una marca (catálogo dependiente de `marcaId`).
  /// Alimenta dinámicamente las `opciones` del campo `modeloId` del FormSchema,
  /// que el backend devuelve vacío por depender de la marca elegida.
  /// Tolerante a id/nombre en camelCase o snake_case.
  Future<List<FormOpcion>> modelosPorMarca(String marcaId) async {
    final r = await _client
        .get('/logistica/modelos?marcaId=${Uri.encodeComponent(marcaId)}');
    _client.checkResponse(r, fallback: 'No se pudieron cargar los modelos');
    final list = jsonDecode(r.body) as List? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      final id = (m['id'] ?? m['modeloId'] ?? m['modelo_id'])?.toString() ?? '';
      final nombre =
          (m['nombre'] ?? m['modelo'] ?? m['label'])?.toString() ?? id;
      return FormOpcion(id: id, nombre: nombre);
    }).toList();
  }
}

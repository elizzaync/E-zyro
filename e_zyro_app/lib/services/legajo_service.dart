import 'dart:convert';
import 'dart:typed_data';

import '../core/api_client.dart';
import '../models/legajo_models.dart';

/// Legajo Digital de RR.HH. (`/rrhh/legajo/*`, `/rrhh/documento/*`) — vista
/// admin/RRHH de los documentos de cualquier empleado. Para "mis documentos"
/// propios (empleado logueado) ver DashboardService.getMisDocumentos.
class LegajoService {
  final ApiClient _client;
  LegajoService(this._client);

  Future<({List<LegajoEmpleadoResumen> empleados, int total, int totalPaginas})> getEmpleados({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final r = await _client.get('/rrhh/legajo/empleados?page=$page&limit=$limit');
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final empleados = ((j['empleados'] ?? []) as List)
            .map((e) => LegajoEmpleadoResumen.fromJson(e as Map<String, dynamic>))
            .toList();
        return (
          empleados: empleados,
          total: (j['total'] as num?)?.toInt() ?? 0,
          totalPaginas: (j['total_paginas'] as num?)?.toInt() ?? 1,
        );
      }
    } catch (_) {}
    return (empleados: <LegajoEmpleadoResumen>[], total: 0, totalPaginas: 1);
  }

  Future<LegajoEmpleadoDetalle?> getDetalle(String empleadoId) async {
    try {
      final r = await _client.get('/rrhh/legajo/$empleadoId');
      if (r.statusCode == 200) {
        return LegajoEmpleadoDetalle.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> subirDocumento(
    String empleadoId, {
    required String tipo,
    required String nombre,
    required String fechaEmision, // YYYY-MM-DD
    required bool requiereFirma,
    int? mes,
    int? anio,
    required Uint8List archivoBytes,
    required String archivoNombre,
  }) async {
    try {
      final r = await _client.postMultipartBytes(
        '/rrhh/legajo/$empleadoId/documento',
        {
          'tipo': tipo,
          'nombre': nombre,
          'fecha_emision': fechaEmision,
          'requiere_firma': requiereFirma.toString(),
          if (mes != null) 'mes': '$mes',
          if (anio != null) 'anio': '$anio',
        },
        'archivo',
        archivoBytes,
        archivoNombre,
      );
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {}
    return false;
  }

  Future<bool> eliminarDocumento(String docId) async {
    try {
      final r = await _client.delete('/rrhh/documento/$docId');
      return r.statusCode == 200 || r.statusCode == 204;
    } catch (_) {}
    return false;
  }
}

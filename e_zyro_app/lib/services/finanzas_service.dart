import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/finanzas_models.dart';

/// Cliente consolidado del módulo de Finanzas/ERP contable. Cada sección
/// corresponde a un router del backend (contabilidad, AP, AR, reportes,
/// activos fijos, planilla, tributario). Devuelve siempre ApiResult tipado.
class FinanzasService {
  final ApiClient _client;
  FinanzasService(this._client);

  // Helper genérico para GET que devuelve lista.
  Future<ApiResult<List<T>>> _getList<T>(
      String path, T Function(Map<String, dynamic>) parse) async {
    try {
      final r = await _client.get(path);
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => parse(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<T>> _getObj<T>(
      String path, T Function(Map<String, dynamic>) parse) async {
    try {
      final r = await _client.get(path);
      if (r.statusCode == 200) {
        return ApiResult.ok(parse(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Contabilidad ───────────────────────────────────────────────────────────
  Future<ApiResult<List<CuentaContable>>> planCuentas({String? nivel, bool soloActivas = true}) {
    final params = <String, String>{
      'nivel': ?nivel,
      if (soloActivas) 'activo': 'true',
    };
    final qs = Uri(queryParameters: params).query;
    return _getList('/contabilidad/plan-cuentas${qs.isEmpty ? '' : '?$qs'}', CuentaContable.fromJson);
  }

  // ── Cuentas por Pagar ──────────────────────────────────────────────────────
  Future<ApiResult<List<Factura>>> facturasProveedor({String? estado}) {
    final qs = estado != null ? '?estado=$estado' : '';
    return _getList('/cuentas-por-pagar/facturas$qs', Factura.fromJson);
  }

  Future<ApiResult<Factura>> registrarFacturaProveedor({
    required String proveedorId,
    required String numeroDocumento,
    required String tipoDocumento,
    required String fechaEmision,
    required String fechaVencimiento,
    required double subtotal,
    required double igv,
  }) async {
    try {
      final r = await _client.post('/cuentas-por-pagar/facturas', {
        'proveedor_id': proveedorId,
        'numero_documento': numeroDocumento,
        'tipo_documento': tipoDocumento,
        'fecha_emision': fechaEmision,
        'fecha_vencimiento': fechaVencimiento,
        'subtotal': subtotal,
        'igv': igv,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(Factura.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Factura>> anularFacturaProveedor(String id) async {
    try {
      final r = await _client.post('/cuentas-por-pagar/facturas/$id/anular', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(Factura.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult> registrarPagoProveedor({
    required String proveedorId,
    required String fechaPago,
    required String medioPago,
    required List<Map<String, dynamic>> aplicaciones,
    String? referencia,
  }) async {
    try {
      final r = await _client.post('/cuentas-por-pagar/pagos', {
        'proveedor_id': proveedorId,
        'fecha_pago': fechaPago,
        'medio_pago': medioPago,
        'aplicaciones': aplicaciones,
        if (referencia != null && referencia.isNotEmpty) 'referencia': referencia,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(jsonDecode(r.body));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<SaldoTercero>>> saldosProveedor() =>
      _getList('/cuentas-por-pagar/reporte-saldos', SaldoTercero.fromJson);

  Future<ApiResult<List<AntiguedadFila>>> antiguedadProveedor() =>
      _getList('/cuentas-por-pagar/reporte-antiguedad', AntiguedadFila.fromJson);

  // ── Cuentas por Cobrar ─────────────────────────────────────────────────────
  Future<ApiResult<List<Factura>>> facturasCliente({String? estado}) {
    final qs = estado != null ? '?estado=$estado' : '';
    return _getList('/cuentas-por-cobrar/facturas$qs', Factura.fromJson);
  }

  Future<ApiResult<Factura>> emitirComprobante({
    required String clienteId,
    required String numeroDocumento,
    required String tipoDocumento,
    required String fechaEmision,
    String? fechaVencimiento,
    required double subtotal,
    required double igv,
    bool alContado = false,
  }) async {
    try {
      final r = await _client.post('/cuentas-por-cobrar/facturas', {
        'cliente_id': clienteId,
        'numero_documento': numeroDocumento,
        'tipo_documento': tipoDocumento,
        'fecha_emision': fechaEmision,
        'fecha_vencimiento': ?fechaVencimiento,
        'subtotal': subtotal,
        'igv': igv,
        'al_contado': alContado,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(Factura.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult> registrarCobro({
    required String clienteId,
    required String fechaCobro,
    required String medioPago,
    required List<Map<String, dynamic>> aplicaciones,
    String? referencia,
  }) async {
    try {
      final r = await _client.post('/cuentas-por-cobrar/cobros', {
        'cliente_id': clienteId,
        'fecha_cobro': fechaCobro,
        'medio_pago': medioPago,
        'aplicaciones': aplicaciones,
        if (referencia != null && referencia.isNotEmpty) 'referencia': referencia,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(jsonDecode(r.body));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<SaldoTercero>>> saldosCliente() =>
      _getList('/cuentas-por-cobrar/reporte-saldos', SaldoTercero.fromJson);

  Future<ApiResult<List<AntiguedadFila>>> antiguedadCliente() =>
      _getList('/cuentas-por-cobrar/reporte-antiguedad', AntiguedadFila.fromJson);

  // ── Reportes financieros ───────────────────────────────────────────────────
  Future<ApiResult<BalanceComprobacion>> balanceComprobacion(String periodo) =>
      _getObj('/reportes-financieros/balance-comprobacion?periodo=$periodo', BalanceComprobacion.fromJson);

  Future<ApiResult<BalanceGeneral>> balanceGeneral(String fecha) =>
      _getObj('/reportes-financieros/balance-general?fecha=$fecha', BalanceGeneral.fromJson);

  Future<ApiResult<EstadoResultados>> estadoResultados(String desde, String hasta) =>
      _getObj('/reportes-financieros/estado-resultados?desde=$desde&hasta=$hasta', EstadoResultados.fromJson);

  // ── Activos fijos ──────────────────────────────────────────────────────────
  Future<ApiResult<List<ActivoFijo>>> activosFijos({String? estado}) {
    final qs = estado != null ? '?estado=$estado' : '';
    return _getList('/activos-fijos$qs', ActivoFijo.fromJson);
  }

  Future<ApiResult<ActivoFijo>> crearActivoFijo({
    required String nombre,
    required String fechaAdquisicion,
    required double valorAdquisicion,
    required int vidaUtilMeses,
    double valorResidual = 0,
  }) async {
    try {
      final r = await _client.post('/activos-fijos', {
        'nombre': nombre,
        'fecha_adquisicion': fechaAdquisicion,
        'valor_adquisicion': valorAdquisicion,
        'vida_util_meses': vidaUtilMeses,
        'valor_residual': valorResidual,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(ActivoFijo.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Map<String, dynamic>>> procesarDepreciacion(String periodo) async {
    try {
      final r = await _client.post('/activos-fijos/procesar-depreciacion?periodo=$periodo', {});
      if (r.statusCode == 200 || r.statusCode == 201) {
        return ApiResult.ok(jsonDecode(r.body) as Map<String, dynamic>);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Planilla ───────────────────────────────────────────────────────────────
  Future<ApiResult<List<Planilla>>> planillas() => _getList('/planilla', Planilla.fromJson);

  Future<ApiResult<Planilla>> calcularPlanilla(String periodo) async {
    try {
      final r = await _client.post('/planilla/calcular?periodo=$periodo', {});
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(Planilla.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Planilla>> _accionPlanilla(String id, String accion) async {
    try {
      final r = await _client.post('/planilla/$id/$accion', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(Planilla.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Planilla>> aprobarPlanilla(String id) => _accionPlanilla(id, 'aprobar');
  Future<ApiResult<Planilla>> pagarPlanilla(String id) => _accionPlanilla(id, 'marcar-pagada');

  // ── Tributario ─────────────────────────────────────────────────────────────
  Future<ApiResult<List<RegistroTributarioFila>>> registroCompras(String periodo) =>
      _getList('/tributario/registro-compras?periodo=$periodo', RegistroTributarioFila.fromJson);

  Future<ApiResult<List<RegistroTributarioFila>>> registroVentas(String periodo) =>
      _getList('/tributario/registro-ventas?periodo=$periodo', RegistroTributarioFila.fromJson);

  // ── Terceros (selects de proveedores/clientes) ─────────────────────────────
  Future<ApiResult<List<Tercero>>> proveedores() =>
      _getList('/logistica/proveedores', Tercero.fromJson);

  Future<ApiResult<List<Tercero>>> clientes() =>
      _getList('/operaciones/clientes', Tercero.fromJson);
}

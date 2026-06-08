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

  Future<ApiResult<List<PeriodoContable>>> periodos() =>
      _getList('/contabilidad/periodos', PeriodoContable.fromJson);

  Future<ApiResult<PeriodoContable>> abrirPeriodo(int anio, int mes) async {
    try {
      final r = await _client.post('/contabilidad/periodos', {'anio': anio, 'mes': mes});
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(PeriodoContable.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<PeriodoContable>> _accionPeriodo(String id, String accion) async {
    try {
      final r = await _client.post('/contabilidad/periodos/$id/$accion', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(PeriodoContable.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<PeriodoContable>> cerrarPeriodo(String id) => _accionPeriodo(id, 'cerrar');
  Future<ApiResult<PeriodoContable>> reabrirPeriodo(String id) => _accionPeriodo(id, 'reabrir');

  Future<ApiResult<List<AsientoContable>>> asientos({String? periodoId, String? origen}) {
    final params = <String, String>{
      'periodo_id': ?periodoId,
      'origen': ?origen,
    };
    final qs = Uri(queryParameters: params).query;
    return _getList('/contabilidad/asientos${qs.isEmpty ? '' : '?$qs'}', AsientoContable.fromJson);
  }

  Future<ApiResult<AsientoContable>> obtenerAsiento(String id) =>
      _getObj('/contabilidad/asientos/$id', AsientoContable.fromJson);

  Future<ApiResult<AsientoContable>> crearAsientoManual({
    required String fecha,
    required String descripcion,
    required List<Map<String, dynamic>> lineas,
    String? referenciaId,
  }) async {
    try {
      final r = await _client.post('/contabilidad/asientos/manual', {
        'fecha': fecha,
        'descripcion': descripcion,
        'lineas': lineas,
        if (referenciaId != null) 'referencia_id': referenciaId,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(AsientoContable.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
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

  Future<ApiResult<List<PagoProveedor>>> listarPagos({String? proveedorId}) {
    final qs = proveedorId != null ? '?proveedor_id=$proveedorId' : '';
    return _getList('/cuentas-por-pagar/pagos$qs', PagoProveedor.fromJson);
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

  Future<ApiResult<Factura>> anularComprobante(String id) async {
    try {
      final r = await _client.post('/cuentas-por-cobrar/facturas/$id/anular', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(Factura.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<CobroCliente>>> listarCobros({String? clienteId}) {
    final qs = clienteId != null ? '?cliente_id=$clienteId' : '';
    return _getList('/cuentas-por-cobrar/cobros$qs', CobroCliente.fromJson);
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

  Future<ApiResult<Map<String, dynamic>>> flujoEfectivo(String periodo) async {
    try {
      final r = await _client.get('/reportes-financieros/flujo-efectivo?periodo=$periodo');
      if (r.statusCode == 200) {
        return ApiResult.ok(jsonDecode(r.body) as Map<String, dynamic>);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<dynamic>>> libroDiario(String periodo) async {
    try {
      final r = await _client.get('/reportes-financieros/libro-diario?periodo=$periodo');
      if (r.statusCode == 200) {
        return ApiResult.ok(jsonDecode(r.body) as List<dynamic>);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Map<String, dynamic>>> libroMayor(String cuentaId, String periodo) async {
    try {
      final r = await _client.get('/reportes-financieros/libro-mayor/$cuentaId?periodo=$periodo');
      if (r.statusCode == 200) {
        return ApiResult.ok(jsonDecode(r.body) as Map<String, dynamic>);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

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

  Future<ApiResult<ActivoFijo>> actualizarActivoFijo({
    required String id,
    String? nombre,
    double? valorResidual,
    String? centroCostoId,
  }) async {
    try {
      final r = await _client.put('/activos-fijos/$id', {
        if (nombre != null) 'nombre': nombre,
        if (valorResidual != null) 'valor_residual': valorResidual,
        if (centroCostoId != null) 'centro_costo_id': centroCostoId,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(ActivoFijo.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<ActivoFijo>> darDeBajaActivo(String id) async {
    try {
      final r = await _client.post('/activos-fijos/$id/dar-de-baja', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(ActivoFijo.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<DepreciacionFila>>> historialDepreciacion(String activoId) =>
      _getList('/activos-fijos/$activoId/depreciacion', DepreciacionFila.fromJson);

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
  Future<ApiResult<List<ConceptoRemunerativo>>> conceptosPlanilla() =>
      _getList('/planilla/conceptos', ConceptoRemunerativo.fromJson);

  Future<ApiResult<ConceptoRemunerativo>> crearConceptoPlanilla({
    required String codigo,
    required String nombre,
    required String tipo,
    double? montoReferencial,
  }) async {
    try {
      final r = await _client.post('/planilla/conceptos', {
        'codigo': codigo,
        'nombre': nombre,
        'tipo': tipo,
        if (montoReferencial != null) 'monto_referencial': montoReferencial,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(ConceptoRemunerativo.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<Planilla>>> planillas() => _getList('/planilla', Planilla.fromJson);

  Future<ApiResult<Planilla>> obtenerPlanilla(String id) =>
      _getObj('/planilla/$id', Planilla.fromJson);

  Future<ApiResult<List<BoletaPago>>> listarBoletas(String planillaId) =>
      _getList('/planilla/$planillaId/boletas', BoletaPago.fromJson);

  Future<ApiResult<Planilla>> anularPlanilla(String id) async {
    try {
      final r = await _client.post('/planilla/$id/anular', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(Planilla.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

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
  Future<ApiResult<List<RegimenTributario>>> regimenesTributarios() =>
      _getList('/tributario/regimenes', RegimenTributario.fromJson);

  Future<ApiResult<ConfiguracionTributaria>> configuracionTributaria() =>
      _getObj('/tributario/configuracion', ConfiguracionTributaria.fromJson);

  Future<ApiResult<ConfiguracionTributaria>> actualizarConfiguracionTributaria({
    String? regimenId,
    String? cuentaIgvCreditoFiscalId,
    String? cuentaIgvDebitoFiscalId,
  }) async {
    try {
      final r = await _client.put('/tributario/configuracion', {
        if (regimenId != null) 'regimen_id': regimenId,
        if (cuentaIgvCreditoFiscalId != null) 'cuenta_igv_credito_fiscal_id': cuentaIgvCreditoFiscalId,
        if (cuentaIgvDebitoFiscalId != null) 'cuenta_igv_debito_fiscal_id': cuentaIgvDebitoFiscalId,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(ConfiguracionTributaria.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<RegistroTributarioFila>>> registroCompras(String periodo) =>
      _getList('/tributario/registro-compras?periodo=$periodo', RegistroTributarioFila.fromJson);

  Future<ApiResult<List<RegistroTributarioFila>>> registroVentas(String periodo) =>
      _getList('/tributario/registro-ventas?periodo=$periodo', RegistroTributarioFila.fromJson);

  // ── Terceros (selects de proveedores/clientes) ─────────────────────────────
  Future<ApiResult<List<Tercero>>> proveedores() =>
      _getList('/logistica/proveedores', Tercero.fromJson);

  Future<ApiResult<List<Tercero>>> clientes() =>
      _getList('/operaciones/clientes', Tercero.fromJson);

  // ── Controlling / centros de costo ─────────────────────────────────────────
  Future<ApiResult<List<CentroCosto>>> centrosCosto({String? tipoReferencia, bool? activo}) {
    final params = <String, String>{
      'tipo_referencia': ?tipoReferencia,
      'activo': ?activo?.toString(),
    };
    final qs = Uri(queryParameters: params).query;
    return _getList('/controlling/centros-costo${qs.isEmpty ? '' : '?$qs'}', CentroCosto.fromJson);
  }

  Future<ApiResult<CentroCosto>> crearCentroCosto({
    required String codigo,
    required String nombre,
    String tipoReferencia = 'libre',
    String? referenciaId,
    double? presupuestoReferencial,
  }) async {
    try {
      final r = await _client.post('/controlling/centros-costo', {
        'codigo': codigo,
        'nombre': nombre,
        'tipo_referencia': tipoReferencia,
        if (referenciaId != null) 'referencia_id': referenciaId,
        if (presupuestoReferencial != null) 'presupuesto_referencial': presupuestoReferencial,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(CentroCosto.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<CentroCosto>> actualizarCentroCosto({
    required String id,
    String? nombre,
    String? tipoReferencia,
    double? presupuestoReferencial,
    bool? activo,
  }) async {
    try {
      final r = await _client.put('/controlling/centros-costo/$id', {
        if (nombre != null) 'nombre': nombre,
        if (tipoReferencia != null) 'tipo_referencia': tipoReferencia,
        if (presupuestoReferencial != null) 'presupuesto_referencial': presupuestoReferencial,
        if (activo != null) 'activo': activo,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(CentroCosto.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<CentroCosto>> desactivarCentroCosto(String id) async {
    try {
      final r = await _client.delete('/controlling/centros-costo/$id');
      if (r.statusCode == 200) {
        return ApiResult.ok(CentroCosto.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<CostoRealCentro>> costoRealCentro(String centroId, {String? desde, String? hasta}) {
    final params = <String, String>{'desde': ?desde, 'hasta': ?hasta};
    final qs = Uri(queryParameters: params).query;
    return _getObj('/controlling/centros-costo/$centroId/costo-real${qs.isEmpty ? '' : '?$qs'}',
        CostoRealCentro.fromJson);
  }

  Future<ApiResult<ComparativoCentro>> comparativoCentro(String centroId, {String? desde, String? hasta}) {
    final params = <String, String>{'desde': ?desde, 'hasta': ?hasta};
    final qs = Uri(queryParameters: params).query;
    return _getObj('/controlling/centros-costo/$centroId/comparativo${qs.isEmpty ? '' : '?$qs'}',
        ComparativoCentro.fromJson);
  }

  // ── Inventario valorizado ───────────────────────────────────────────────────
  Future<ApiResult<List<KardexFila>>> kardexValorizado({String? almacen, String? material}) {
    final params = <String, String>{'almacen': ?almacen, 'material': ?material};
    final qs = Uri(queryParameters: params).query;
    return _getList('/logistica/inventario/valorizacion${qs.isEmpty ? '' : '?$qs'}', KardexFila.fromJson);
  }

  Future<ApiResult<CostoPromedio>> costoPromedio(String materialId, String almacenId) =>
      _getObj('/logistica/inventario/costo-promedio/$materialId?almacen_id=$almacenId', CostoPromedio.fromJson);

  Future<ApiResult<MovimientoValorizado>> registrarIngresoValorizado({
    required String materialId,
    required String almacenId,
    required int cantidad,
    required double costoUnitario,
    String? motivo,
  }) async {
    try {
      final r = await _client.post('/logistica/inventario/ingresos', {
        'material_id': materialId,
        'almacen_id': almacenId,
        'cantidad': cantidad,
        'costo_unitario': costoUnitario,
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(MovimientoValorizado.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<MovimientoValorizado>> registrarSalidaValorizada({
    required String materialId,
    required String almacenId,
    required int cantidad,
    String? motivo,
  }) async {
    try {
      final r = await _client.post('/logistica/inventario/salidas', {
        'material_id': materialId,
        'almacen_id': almacenId,
        'cantidad': cantidad,
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(MovimientoValorizado.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

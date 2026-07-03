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
  Future<ApiResult<List<CuentaContable>>> planCuentas({String? tipo, String? nivel, bool soloActivas = true}) {
    final params = <String, String>{
      'tipo': ?tipo,
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
        'referencia_id': ?referenciaId,
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
    String? cuentaGastoId,
    String? documentoAfectadoId, // nota de crédito: factura cuyo saldo rebaja
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
        'cuenta_gasto_id': ?cuentaGastoId,
        'documento_afectado_id': ?documentoAfectadoId,
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
    String? documentoAfectadoId, // nota de crédito: comprobante cuyo saldo rebaja
    String? moneda,
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
        'documento_afectado_id': ?documentoAfectadoId,
        'moneda': ?moneda,
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

  /// Servicios COMPLETADOS sin factura vigente, candidatos a facturarse.
  Future<ApiResult<List<ServicioFacturable>>> serviciosFacturables() =>
      _getList('/cuentas-por-cobrar/servicios-facturables', ServicioFacturable.fromJson);

  /// Emite el comprobante de un servicio completado. El cliente se deriva en el
  /// backend del proyecto del servicio (no se envía). moneda se inyecta como null.
  Future<ApiResult<Factura>> facturarServicio({
    required String servicioId,
    required String numeroDocumento,
    required String tipoDocumento,
    required String fechaEmision,
    String? fechaVencimiento,
    required double subtotal,
    required double igv,
    bool alContado = false,
  }) async {
    try {
      final r = await _client.post('/cuentas-por-cobrar/facturar-servicio', {
        'servicio_id': servicioId,
        'numero_documento': numeroDocumento,
        'tipo_documento': tipoDocumento,
        'fecha_emision': fechaEmision,
        'fecha_vencimiento': ?fechaVencimiento,
        'subtotal': subtotal,
        'igv': igv,
        'moneda': null,
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
        'nombre': ?nombre,
        'valor_residual': ?valorResidual,
        'centro_costo_id': ?centroCostoId,
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
        'monto_referencial': ?montoReferencial,
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

  /// Marca/ajusta un concepto. El uso principal aquí es marcar el concepto
  /// base (sueldo) con [esBase]=true; el backend garantiza base único.
  Future<ApiResult<ConceptoRemunerativo>> actualizarConceptoPlanilla(
    String conceptoId, {
    String? nombre,
    double? montoReferencial,
    bool? activo,
    bool? esBase,
  }) async {
    try {
      final r = await _client.patch('/planilla/conceptos/$conceptoId', {
        'nombre': ?nombre,
        'monto_referencial': ?montoReferencial,
        'activo': ?activo,
        'es_base': ?esBase,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(ConceptoRemunerativo.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<ConceptoRemunerativo>> marcarConceptoBase(String conceptoId, bool esBase) =>
      actualizarConceptoPlanilla(conceptoId, esBase: esBase);

  /// Configuración global de planilla (por ahora: descuento de tardanzas auto).
  Future<ApiResult<bool>> getDescuentoTardanzaAuto() async {
    try {
      final r = await _client.get('/planilla/config');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return ApiResult.ok(body['descuento_tardanza_auto'] == true);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<bool>> setDescuentoTardanzaAuto(bool v) async {
    try {
      final r = await _client.patch('/planilla/config', {'descuento_tardanza_auto': v});
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return ApiResult.ok(body['descuento_tardanza_auto'] == true);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<BoletaPago>>> listarBoletas(String planillaId) =>
      _getList('/planilla/$planillaId/boletas', BoletaPago.fromJson);

  /// Override del monto de un concepto en una boleta (monto=0 lo elimina).
  /// Solo si la planilla está 'calculada'. Devuelve la planilla con totales
  /// recalculados.
  Future<ApiResult<Planilla>> editarDetalleBoleta(
      String planillaId, String boletaId, String conceptoId, double monto) async {
    try {
      final r = await _client.patch(
        '/planilla/$planillaId/boletas/$boletaId/detalle',
        {'concepto_id': conceptoId, 'monto': monto},
      );
      if (r.statusCode == 200) {
        return ApiResult.ok(Planilla.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Sueldos por empleado (asignación de montos por concepto) ───────────────
  Future<ApiResult<List<EmpleadoPlanilla>>> empleadosPlanilla() =>
      _getList('/planilla/empleados', EmpleadoPlanilla.fromJson);

  Future<ApiResult<List<AsignacionConcepto>>> asignacionesPlanilla() =>
      _getList('/planilla/asignaciones', AsignacionConcepto.fromJson);

  /// Guarda los montos por concepto de un empleado. Cada item:
  /// {'concepto_id': ..., 'monto': double?}. monto null elimina el override.
  Future<ApiResult<List<AsignacionConcepto>>> guardarAsignaciones(
      String empleadoId, List<Map<String, dynamic>> items) async {
    try {
      final r = await _client.put('/planilla/empleados/$empleadoId/asignaciones', items);
      if (r.statusCode == 200) {
        final data = (jsonDecode(r.body) as List)
            .map((e) => AsignacionConcepto.fromJson(e as Map<String, dynamic>))
            .toList();
        return ApiResult.ok(data);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

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

  /// Tasa de IGV vigente (porcentaje, p. ej. 18.0) leída de la configuración
  /// tributaria. Devuelve 18.0 por defecto si el endpoint falla. Pensado para
  /// auto-calcular el IGV de comprobantes desde Logística.
  Future<double> getTasaIgv() async {
    final res = await configuracionTributaria();
    if (res.ok && res.data != null && res.data!.tasaIgv > 0) {
      return res.data!.tasaIgv;
    }
    return 18.0;
  }

  Future<ApiResult<ConfiguracionTributaria>> actualizarConfiguracionTributaria({
    String? regimenId,
    String? cuentaIgvCreditoFiscalId,
    String? cuentaIgvDebitoFiscalId,
  }) async {
    try {
      final r = await _client.put('/tributario/configuracion', {
        'regimen_id': ?regimenId,
        'cuenta_igv_credito_fiscal_id': ?cuentaIgvCreditoFiscalId,
        'cuenta_igv_debito_fiscal_id': ?cuentaIgvDebitoFiscalId,
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
        'referencia_id': ?referenciaId,
        'presupuesto_referencial': ?presupuestoReferencial,
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
        'nombre': ?nombre,
        'tipo_referencia': ?tipoReferencia,
        'presupuesto_referencial': ?presupuestoReferencial,
        'activo': ?activo,
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

  // ── Configuración ERP: facturación electrónica ──────────────────────────────
  Future<ApiResult<ConfigFE>> configFE() =>
      _getObj('/facturacion-electronica/configuracion', ConfigFE.fromJson);

  Future<ApiResult<ConfigFE>> actualizarConfigFE({
    bool? habilitado, String? apiUrl, String? apiToken,
    String? serieFactura, String? serieBoleta,
  }) async {
    try {
      final r = await _client.put('/facturacion-electronica/configuracion', {
        'habilitado': ?habilitado,
        'api_url': ?apiUrl,
        'api_token': ?apiToken,
        'serie_factura': ?serieFactura,
        'serie_boleta': ?serieBoleta,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(ConfigFE.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Factura>> reintentarCpe(String facturaId) async {
    try {
      final r = await _client.post(
          '/cuentas-por-cobrar/facturas/$facturaId/emitir-cpe', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(Factura.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Tipo de cambio (multimoneda) ─────────────────────────────────────────────
  Future<ApiResult<List<TipoCambioDia>>> tiposCambio({int dias = 30}) =>
      _getList('/contabilidad/tipo-cambio?dias=$dias', TipoCambioDia.fromJson);

  Future<ApiResult<TipoCambioDia>> actualizarTipoCambioHoy() async {
    try {
      final r = await _client.post('/contabilidad/tipo-cambio/actualizar', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(TipoCambioDia.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<TipoCambioDia>> registrarTipoCambio(
      String fecha, double venta, {double? compra}) async {
    try {
      final r = await _client.post('/contabilidad/tipo-cambio', {
        'fecha': fecha,
        'venta': venta,
        'compra': ?compra,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(TipoCambioDia.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Presupuesto anual ────────────────────────────────────────────────────────
  Future<ApiResult<PresupuestoAnual>> presupuesto(int anio) =>
      _getObj('/presupuesto/$anio', PresupuestoAnual.fromJson);

  Future<ApiResult<PresupuestoAnual>> guardarPresupuesto(
      int anio, List<Map<String, dynamic>> lineas) async {
    try {
      final r = await _client.put('/presupuesto/$anio', {'lineas': lineas});
      if (r.statusCode == 200) {
        return ApiResult.ok(PresupuestoAnual.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Export Excel de reportes ─────────────────────────────────────────────────
  /// Devuelve la URL del XLSX generado, o null si falló.
  Future<String?> excelReporte(String pathConQuery) async {
    try {
      final r = await _client.get('/reportes-financieros/$pathConQuery');
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as Map<String, dynamic>)['url']?.toString();
    } catch (_) {
      return null;
    }
  }

  // ── Rentabilidad por proyecto ───────────────────────────────────────────────
  Future<ApiResult<List<RentabilidadProyecto>>> rentabilidadProyectos({String? desde, String? hasta}) {
    final params = <String, String>{'desde': ?desde, 'hasta': ?hasta};
    final qs = Uri(queryParameters: params).query;
    return _getList('/controlling/rentabilidad${qs.isEmpty ? '' : '?$qs'}',
        RentabilidadProyecto.fromJson);
  }

  Future<ApiResult<RentabilidadProyecto>> rentabilidadProyecto(String proyectoId,
      {String? desde, String? hasta}) {
    final params = <String, String>{'desde': ?desde, 'hasta': ?hasta};
    final qs = Uri(queryParameters: params).query;
    return _getObj('/controlling/rentabilidad/$proyectoId${qs.isEmpty ? '' : '?$qs'}',
        RentabilidadProyecto.fromJson);
  }

  // ── Inventario valorizado ───────────────────────────────────────────────────
  Future<ApiResult<List<KardexFila>>> kardexValorizado({String? almacen, String? material}) {
    final params = <String, String>{'almacen': ?almacen, 'material': ?material};
    final qs = Uri(queryParameters: params).query;
    return _getList('/logistica/inventario/valorizacion${qs.isEmpty ? '' : '?$qs'}', KardexFila.fromJson);
  }

  Future<ApiResult<CostoPromedio>> costoPromedio(String materialId, String almacenId) =>
      _getObj('/logistica/inventario/costo-promedio/$materialId?almacen_id=$almacenId', CostoPromedio.fromJson);

  // Los movimientos valorizados ya no se registran desde la app: el inventario
  // se mueve desde Logística, que valoriza y contabiliza automáticamente.

  // ── Caja Chica ─────────────────────────────────────────────────────────────
  Future<ApiResult<List<CajaChica>>> cajasChicas({String? estado}) {
    final qs = (estado != null && estado.isNotEmpty) ? '?estado=$estado' : '';
    return _getList('/caja-chica$qs', CajaChica.fromJson);
  }

  Future<ApiResult<CajaChica>> obtenerCajaChica(String id) =>
      _getObj('/caja-chica/$id', CajaChica.fromJson);

  Future<ApiResult<CajaChica>> crearCajaChica({
    required String nombre,
    String? descripcion,
    double? montoAsignado,
    String? proyectoId,
    String? responsableId,
  }) async {
    try {
      final r = await _client.post('/caja-chica', {
        'nombre': nombre,
        if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
        'monto_asignado_referencial': ?montoAsignado,
        'proyecto_id': ?proyectoId,
        'responsable_id': ?responsableId,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(CajaChica.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<CajaChica>> cerrarCajaChica(String id) async {
    try {
      final r = await _client.post('/caja-chica/$id/cerrar', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(CajaChica.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<MovimientoCaja>>> movimientosCaja(String cajaId) =>
      _getList('/caja-chica/$cajaId/movimientos', MovimientoCaja.fromJson);

  Future<ApiResult<MovimientoCaja>> registrarMovimientoCaja({
    required String cajaId,
    required String tipo,            // ingreso | egreso
    required double monto,
    required String descripcion,
    String? concepto,
    String? cuentaCodigo,
    String? comprobanteUrl,
  }) async {
    try {
      final r = await _client.post('/caja-chica/$cajaId/movimientos', {
        'tipo': tipo,
        'monto': monto,
        'descripcion': descripcion,
        if (concepto != null && concepto.isNotEmpty) 'concepto': concepto,
        if (cuentaCodigo != null && cuentaCodigo.isNotEmpty) 'cuenta_codigo': cuentaCodigo,
        if (comprobanteUrl != null && comprobanteUrl.isNotEmpty) 'comprobante_url': comprobanteUrl,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(MovimientoCaja.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Conciliación bancaria ──────────────────────────────────────────────────
  Future<ApiResult<List<CuentaBancaria>>> cuentasBancarias({bool soloActivas = false}) {
    final qs = soloActivas ? '?solo_activas=true' : '';
    return _getList('/conciliacion-bancaria/cuentas$qs', CuentaBancaria.fromJson);
  }

  Future<ApiResult<CuentaBancaria>> obtenerCuentaBancaria(String id) =>
      _getObj('/conciliacion-bancaria/cuentas/$id', CuentaBancaria.fromJson);

  Future<ApiResult<CuentaBancaria>> crearCuentaBancaria({
    required String banco,
    required String numeroCuenta,
    required String cuentaContableId,
    String moneda = 'PEN',
    String? alias,
  }) async {
    try {
      final r = await _client.post('/conciliacion-bancaria/cuentas', {
        'banco': banco,
        'numero_cuenta': numeroCuenta,
        'cuenta_contable_id': cuentaContableId,
        'moneda': moneda,
        if (alias != null && alias.isNotEmpty) 'alias': alias,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(CuentaBancaria.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<ResumenConciliacion>> resumenConciliacion(String cuentaId) =>
      _getObj('/conciliacion-bancaria/cuentas/$cuentaId/resumen', ResumenConciliacion.fromJson);

  Future<ApiResult<List<MovimientoBancario>>> movimientosBancarios(
      String cuentaId, {String? estado}) {
    final qs = (estado != null && estado.isNotEmpty) ? '?estado=$estado' : '';
    return _getList('/conciliacion-bancaria/cuentas/$cuentaId/movimientos$qs',
        MovimientoBancario.fromJson);
  }

  Future<ApiResult<MovimientoBancario>> registrarMovimientoBancario({
    required String cuentaId,
    required String fecha,        // YYYY-MM-DD
    required String descripcion,
    required String tipo,         // cargo | abono
    required double monto,
    String? referencia,
  }) async {
    try {
      final r = await _client.post('/conciliacion-bancaria/cuentas/$cuentaId/movimientos', {
        'fecha': fecha,
        'descripcion': descripcion,
        'tipo': tipo,
        'monto': monto,
        if (referencia != null && referencia.isNotEmpty) 'referencia': referencia,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(MovimientoBancario.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Importa el extracto: el cliente ya parseó el CSV en filas
  /// {fecha, descripcion, tipo, monto, referencia?}. Devuelve cuántos se crearon.
  Future<ApiResult<int>> importarMovimientosBancarios(
      String cuentaId, List<Map<String, dynamic>> movimientos) async {
    try {
      final r = await _client.post(
          '/conciliacion-bancaria/cuentas/$cuentaId/movimientos/importar',
          {'movimientos': movimientos});
      if (r.statusCode == 201 || r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return ApiResult.ok(_toIntSvc(body['importados']));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<SugerenciaAsiento>>> sugerenciasConciliacion(String movimientoId) =>
      _getList('/conciliacion-bancaria/movimientos/$movimientoId/sugerencias',
          SugerenciaAsiento.fromJson);

  Future<ApiResult<MovimientoBancario>> conciliarMovimiento(
      String movimientoId, String asientoId) async {
    try {
      final r = await _client.post(
          '/conciliacion-bancaria/movimientos/$movimientoId/conciliar',
          {'asiento_id': asientoId});
      if (r.statusCode == 200) {
        return ApiResult.ok(MovimientoBancario.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<MovimientoBancario>> desconciliarMovimiento(String movimientoId) async {
    try {
      final r = await _client.post(
          '/conciliacion-bancaria/movimientos/$movimientoId/desconciliar', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(MovimientoBancario.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Resumen financiero (dashboard) ─────────────────────────────────────────
  Future<ApiResult<ResumenFinanciero>> resumenFinanciero() =>
      _getObj('/reportes-financieros/resumen', ResumenFinanciero.fromJson);

  // ── Configuración contable + cierre de ejercicio ───────────────────────────
  Future<ApiResult<ConfigContable>> configContable() =>
      _getObj('/contabilidad/configuracion', ConfigContable.fromJson);

  Future<ApiResult<ConfigContable>> actualizarConfigContable({
    String? cuentaCierreCodigo,
    String? cuentaUtilidadCodigo,
    String? cuentaPerdidaCodigo,
    bool? multimoneda,
  }) async {
    try {
      final r = await _client.put('/contabilidad/configuracion', {
        'cuenta_cierre_codigo': ?cuentaCierreCodigo,
        'cuenta_utilidad_codigo': ?cuentaUtilidadCodigo,
        'cuenta_perdida_codigo': ?cuentaPerdidaCodigo,
        'multimoneda': ?multimoneda,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(ConfigContable.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EstadoEjercicio>> estadoEjercicio(int anio) =>
      _getObj('/contabilidad/ejercicios/$anio', EstadoEjercicio.fromJson);

  Future<ApiResult<Map<String, dynamic>>> _accionEjercicio(int anio, String accion) async {
    try {
      final r = await _client.post('/contabilidad/ejercicios/$anio/$accion', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(jsonDecode(r.body) as Map<String, dynamic>);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Map<String, dynamic>>> cerrarEjercicio(int anio) =>
      _accionEjercicio(anio, 'cerrar');
  Future<ApiResult<Map<String, dynamic>>> revertirCierreEjercicio(int anio) =>
      _accionEjercicio(anio, 'revertir-cierre');

  // ── Export PLE SUNAT (TXT) ─────────────────────────────────────────────────
  Future<ApiResult<PleArchivo>> registroComprasPle(String periodo) =>
      _getObj('/tributario/registro-compras/ple?periodo=$periodo', PleArchivo.fromJson);
  Future<ApiResult<PleArchivo>> registroVentasPle(String periodo) =>
      _getObj('/tributario/registro-ventas/ple?periodo=$periodo', PleArchivo.fromJson);

  // ── Saldos iniciales / asiento de apertura ─────────────────────────────────
  Future<ApiResult<EstadoApertura>> estadoApertura() =>
      _getObj('/contabilidad/apertura', EstadoApertura.fromJson);

  Future<ApiResult<Map<String, dynamic>>> cargarApertura({
    required String fecha,
    required List<Map<String, dynamic>> lineas, // {cuenta_codigo, monto}
  }) async {
    try {
      final r = await _client.post('/contabilidad/apertura',
          {'fecha': fecha, 'lineas': lineas});
      if (r.statusCode == 200) {
        return ApiResult.ok(jsonDecode(r.body) as Map<String, dynamic>);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Map<String, dynamic>>> revertirApertura() async {
    try {
      final r = await _client.post('/contabilidad/apertura/revertir', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(jsonDecode(r.body) as Map<String, dynamic>);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}

int _toIntSvc(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

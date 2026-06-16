// Modelos del módulo de Finanzas (consumen el backend ERP-Finanzas).
// Todos parsean el JSON expuesto por los routers /contabilidad, /cuentas-por-pagar,
// /cuentas-por-cobrar, /reportes-financieros, /activos-fijos, /planilla, /tributario.

/// Convierte de forma segura un valor JSON (num/String/null) a double.
double _toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _toI(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

// ── Contabilidad ─────────────────────────────────────────────────────────────
class CuentaContable {
  final String id, codigo, nombre, tipo, naturaleza, nivel;
  final bool activo;
  CuentaContable({
    required this.id, required this.codigo, required this.nombre,
    required this.tipo, required this.naturaleza, required this.nivel,
    required this.activo,
  });
  factory CuentaContable.fromJson(Map<String, dynamic> j) => CuentaContable(
        id: j['id'].toString(),
        codigo: j['codigo']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        tipo: j['tipo']?.toString() ?? '',
        naturaleza: j['naturaleza']?.toString() ?? '',
        nivel: j['nivel']?.toString() ?? '',
        activo: j['activo'] == true,
      );
  bool get esDetalle => nivel == 'detalle';
}

class BalanceFila {
  final String codigo, nombre;
  final double totalDebito, totalCredito, saldoDeudor, saldoAcreedor;
  BalanceFila({
    required this.codigo, required this.nombre, required this.totalDebito,
    required this.totalCredito, required this.saldoDeudor, required this.saldoAcreedor,
  });
  factory BalanceFila.fromJson(Map<String, dynamic> j) => BalanceFila(
        codigo: j['codigo']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        totalDebito: _toD(j['total_debito']),
        totalCredito: _toD(j['total_credito']),
        saldoDeudor: _toD(j['saldo_deudor']),
        saldoAcreedor: _toD(j['saldo_acreedor']),
      );
}

class BalanceComprobacion {
  final String periodo;
  final List<BalanceFila> cuentas;
  final double totalDeudor, totalAcreedor;
  final bool cuadrado;
  BalanceComprobacion({
    required this.periodo, required this.cuentas, required this.totalDeudor,
    required this.totalAcreedor, required this.cuadrado,
  });
  factory BalanceComprobacion.fromJson(Map<String, dynamic> j) => BalanceComprobacion(
        periodo: j['periodo']?.toString() ?? '',
        cuentas: ((j['cuentas'] ?? []) as List)
            .map((e) => BalanceFila.fromJson(e as Map<String, dynamic>)).toList(),
        totalDeudor: _toD(j['total_deudor']),
        totalAcreedor: _toD(j['total_acreedor']),
        cuadrado: j['cuadrado'] == true,
      );
}

// ── Cuentas por Pagar / Cobrar ───────────────────────────────────────────────
class Factura {
  final String id, numeroDocumento, tipoDocumento, estado, fechaEmision, fechaVencimiento;
  final double subtotal, igv, total, saldoPendiente;
  final String? asientoId, terceroId;
  Factura({
    required this.id, required this.numeroDocumento, required this.tipoDocumento,
    required this.estado, required this.fechaEmision, required this.fechaVencimiento,
    required this.subtotal, required this.igv, required this.total,
    required this.saldoPendiente, this.asientoId, this.terceroId,
  });
  factory Factura.fromJson(Map<String, dynamic> j) => Factura(
        id: j['id'].toString(),
        numeroDocumento: j['numero_documento']?.toString() ?? '',
        tipoDocumento: j['tipo_documento']?.toString() ?? '',
        estado: j['estado']?.toString() ?? '',
        fechaEmision: j['fecha_emision']?.toString() ?? '',
        fechaVencimiento: j['fecha_vencimiento']?.toString() ?? '',
        subtotal: _toD(j['subtotal']),
        igv: _toD(j['igv']),
        total: _toD(j['total']),
        saldoPendiente: _toD(j['saldo_pendiente']),
        asientoId: j['asiento_id']?.toString(),
        terceroId: (j['proveedor_id'] ?? j['cliente_id'])?.toString(),
      );
}

class SaldoTercero {
  final String terceroId, nombre;
  final int facturasAbiertas;
  final double saldoTotal;
  SaldoTercero({
    required this.terceroId, required this.nombre,
    required this.facturasAbiertas, required this.saldoTotal,
  });
  factory SaldoTercero.fromJson(Map<String, dynamic> j) => SaldoTercero(
        terceroId: (j['proveedor_id'] ?? j['cliente_id'])?.toString() ?? '',
        nombre: (j['proveedor'] ?? j['cliente'])?.toString() ?? '—',
        facturasAbiertas: _toI(j['facturas_abiertas']),
        saldoTotal: _toD(j['saldo_total']),
      );
}

class AntiguedadFila {
  final String terceroId, nombre;
  final double porVencer, d0_30, d31_60, d61_90, dMas90, total;
  AntiguedadFila({
    required this.terceroId, required this.nombre, required this.porVencer,
    required this.d0_30, required this.d31_60, required this.d61_90,
    required this.dMas90, required this.total,
  });
  factory AntiguedadFila.fromJson(Map<String, dynamic> j) => AntiguedadFila(
        terceroId: (j['proveedor_id'] ?? j['cliente_id'])?.toString() ?? '',
        nombre: (j['proveedor'] ?? j['cliente'])?.toString() ?? '—',
        porVencer: _toD(j['por_vencer']),
        d0_30: _toD(j['d_0_30']),
        d31_60: _toD(j['d_31_60']),
        d61_90: _toD(j['d_61_90']),
        dMas90: _toD(j['d_mas_90']),
        total: _toD(j['total']),
      );
}

/// Tercero genérico (proveedor o cliente) para selects.
/// El backend no es uniforme: /logistica/proveedores expone el nombre como
/// `nombre`, mientras /operaciones/clientes lo expone como `razon_social`.
/// Aceptamos ambos para que el select funcione con cualquiera de los dos.
class Tercero {
  final String id, razonSocial;
  final String? ruc;
  Tercero({required this.id, required this.razonSocial, this.ruc});
  factory Tercero.fromJson(Map<String, dynamic> j) => Tercero(
        id: j['id'].toString(),
        razonSocial: (j['razon_social'] ?? j['nombre'])?.toString() ?? '',
        ruc: j['ruc']?.toString(),
      );
}

/// Servicio completado pendiente de facturar (CxC). El backend deriva el
/// cliente del proyecto del servicio; aquí solo lo mostramos como referencia.
class ServicioFacturable {
  final String servicioId, servicioNombre;
  final String? proyectoId, proyectoNombre, clienteId, clienteNombre, nroDocumentoCliente;
  ServicioFacturable({
    required this.servicioId,
    required this.servicioNombre,
    this.proyectoId,
    this.proyectoNombre,
    this.clienteId,
    this.clienteNombre,
    this.nroDocumentoCliente,
  });
  factory ServicioFacturable.fromJson(Map<String, dynamic> j) => ServicioFacturable(
        servicioId: (j['servicio_id'] ?? j['id'])?.toString() ?? '',
        servicioNombre: (j['servicio_nombre'] ?? j['nombre'])?.toString() ?? '',
        proyectoId: j['proyecto_id']?.toString(),
        proyectoNombre: j['proyecto_nombre']?.toString(),
        clienteId: j['cliente_id']?.toString(),
        clienteNombre: j['cliente_nombre']?.toString(),
        nroDocumentoCliente: j['nro_documento_cliente']?.toString(),
      );
}

// ── Reportes financieros ─────────────────────────────────────────────────────
class SeccionSaldo {
  final String codigo, nombre;
  final double saldo;
  SeccionSaldo({required this.codigo, required this.nombre, required this.saldo});
  factory SeccionSaldo.fromJson(Map<String, dynamic> j) => SeccionSaldo(
        codigo: j['codigo']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        saldo: _toD(j['saldo']),
      );
}

class BalanceGeneral {
  final List<SeccionSaldo> activo, pasivo, patrimonio;
  final double totalActivo, totalPasivo, totalPatrimonio, totalPasivoPatrimonio;
  final bool cuadrado;
  BalanceGeneral({
    required this.activo, required this.pasivo, required this.patrimonio,
    required this.totalActivo, required this.totalPasivo, required this.totalPatrimonio,
    required this.totalPasivoPatrimonio, required this.cuadrado,
  });
  factory BalanceGeneral.fromJson(Map<String, dynamic> j) {
    List<SeccionSaldo> sec(String k) => ((j[k] ?? []) as List)
        .map((e) => SeccionSaldo.fromJson(e as Map<String, dynamic>)).toList();
    return BalanceGeneral(
      activo: sec('activo'), pasivo: sec('pasivo'), patrimonio: sec('patrimonio'),
      totalActivo: _toD(j['total_activo']),
      totalPasivo: _toD(j['total_pasivo']),
      totalPatrimonio: _toD(j['total_patrimonio']),
      totalPasivoPatrimonio: _toD(j['total_pasivo_patrimonio']),
      cuadrado: j['cuadrado'] == true,
    );
  }
}

class LineaResultado {
  final String codigo, nombre;
  final double monto;
  LineaResultado({required this.codigo, required this.nombre, required this.monto});
  factory LineaResultado.fromJson(Map<String, dynamic> j) => LineaResultado(
        codigo: j['codigo']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        monto: _toD(j['monto']),
      );
}

class EstadoResultados {
  final List<LineaResultado> ingresos, gastos;
  final double totalIngresos, totalGastos, resultado;
  EstadoResultados({
    required this.ingresos, required this.gastos, required this.totalIngresos,
    required this.totalGastos, required this.resultado,
  });
  factory EstadoResultados.fromJson(Map<String, dynamic> j) => EstadoResultados(
        ingresos: ((j['ingresos'] ?? []) as List)
            .map((e) => LineaResultado.fromJson(e as Map<String, dynamic>)).toList(),
        gastos: ((j['gastos'] ?? []) as List)
            .map((e) => LineaResultado.fromJson(e as Map<String, dynamic>)).toList(),
        totalIngresos: _toD(j['total_ingresos']),
        totalGastos: _toD(j['total_gastos']),
        resultado: _toD(j['resultado']),
      );
}

// ── Activos fijos ────────────────────────────────────────────────────────────
class ActivoFijo {
  final String id, nombre, estado, fechaAdquisicion, metodoDepreciacion;
  final double valorAdquisicion, valorResidual, depreciacionAcumulada, valorEnLibros;
  final int vidaUtilMeses;
  ActivoFijo({
    required this.id, required this.nombre, required this.estado,
    required this.fechaAdquisicion, required this.metodoDepreciacion,
    required this.valorAdquisicion, required this.valorResidual,
    required this.depreciacionAcumulada, required this.valorEnLibros,
    required this.vidaUtilMeses,
  });
  factory ActivoFijo.fromJson(Map<String, dynamic> j) => ActivoFijo(
        id: j['id'].toString(),
        nombre: j['nombre']?.toString() ?? '',
        estado: j['estado']?.toString() ?? '',
        fechaAdquisicion: j['fecha_adquisicion']?.toString() ?? '',
        metodoDepreciacion: j['metodo_depreciacion']?.toString() ?? '',
        valorAdquisicion: _toD(j['valor_adquisicion']),
        valorResidual: _toD(j['valor_residual']),
        depreciacionAcumulada: _toD(j['depreciacion_acumulada']),
        valorEnLibros: _toD(j['valor_en_libros']),
        vidaUtilMeses: _toI(j['vida_util_meses']),
      );
}

// ── Activos fijos: historial de depreciación ─────────────────────────────────
class DepreciacionFila {
  final String periodoId;
  final double montoDepreciado, valorEnLibrosResultante;
  final String? asientoId;
  DepreciacionFila({
    required this.periodoId, required this.montoDepreciado,
    required this.valorEnLibrosResultante, this.asientoId,
  });
  factory DepreciacionFila.fromJson(Map<String, dynamic> j) => DepreciacionFila(
        periodoId: j['periodo_id']?.toString() ?? '',
        montoDepreciado: _toD(j['monto_depreciado']),
        valorEnLibrosResultante: _toD(j['valor_en_libros_resultante']),
        asientoId: j['asiento_id']?.toString(),
      );
}

// ── Contabilidad: periodos y asientos ────────────────────────────────────────
class PeriodoContable {
  final String id;
  final int anio, mes;
  final String estado;
  final String? cerradoAt;
  PeriodoContable({
    required this.id, required this.anio, required this.mes,
    required this.estado, this.cerradoAt,
  });
  factory PeriodoContable.fromJson(Map<String, dynamic> j) => PeriodoContable(
        id: j['id'].toString(),
        anio: _toI(j['anio']),
        mes: _toI(j['mes']),
        estado: j['estado']?.toString() ?? '',
        cerradoAt: j['cerrado_at']?.toString(),
      );
  String get periodo => '$anio-${mes.toString().padLeft(2, '0')}';
}

class AsientoLinea {
  final String id, cuentaId;
  final String? cuentaCodigo, centroCostoId, glosa;
  final double debito, credito;
  AsientoLinea({
    required this.id, required this.cuentaId, this.cuentaCodigo,
    this.centroCostoId, this.glosa, required this.debito, required this.credito,
  });
  factory AsientoLinea.fromJson(Map<String, dynamic> j) => AsientoLinea(
        id: j['id'].toString(),
        cuentaId: j['cuenta_id'].toString(),
        cuentaCodigo: j['cuenta_codigo']?.toString(),
        centroCostoId: j['centro_costo_id']?.toString(),
        glosa: j['glosa']?.toString(),
        debito: _toD(j['debito']),
        credito: _toD(j['credito']),
      );
}

class AsientoContable {
  final String id, numero, fecha, periodoId, descripcion, origen;
  final String? referenciaId;
  final List<AsientoLinea> lineas;
  AsientoContable({
    required this.id, required this.numero, required this.fecha,
    required this.periodoId, required this.descripcion, required this.origen,
    this.referenciaId, required this.lineas,
  });
  factory AsientoContable.fromJson(Map<String, dynamic> j) => AsientoContable(
        id: j['id'].toString(),
        numero: j['numero']?.toString() ?? '',
        fecha: j['fecha']?.toString() ?? '',
        periodoId: j['periodo_id']?.toString() ?? '',
        descripcion: j['descripcion']?.toString() ?? '',
        origen: j['origen']?.toString() ?? '',
        referenciaId: j['referencia_id']?.toString(),
        lineas: ((j['lineas'] ?? []) as List)
            .map((e) => AsientoLinea.fromJson(e as Map<String, dynamic>)).toList(),
      );
  double get totalDebito => lineas.fold(0.0, (s, l) => s + l.debito);
  double get totalCredito => lineas.fold(0.0, (s, l) => s + l.credito);
}

// ── Tributario: regímenes y configuración ────────────────────────────────────
class RegimenTributario {
  final String id, codigo, nombre;
  final double tasaIgv;
  final double? tasaRentaReferencial;
  final bool activo;
  RegimenTributario({
    required this.id, required this.codigo, required this.nombre,
    required this.tasaIgv, this.tasaRentaReferencial, required this.activo,
  });
  factory RegimenTributario.fromJson(Map<String, dynamic> j) => RegimenTributario(
        id: j['id'].toString(),
        codigo: j['codigo']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        tasaIgv: _toD(j['tasa_igv']),
        tasaRentaReferencial: j['tasa_renta_referencial'] != null ? _toD(j['tasa_renta_referencial']) : null,
        activo: j['activo'] == true,
      );
}

class ConfiguracionTributaria {
  final String regimenId, regimenCodigo;
  final double tasaIgv;
  final String? cuentaIgvCreditoFiscalId, cuentaIgvDebitoFiscalId;
  ConfiguracionTributaria({
    required this.regimenId, required this.regimenCodigo, required this.tasaIgv,
    this.cuentaIgvCreditoFiscalId, this.cuentaIgvDebitoFiscalId,
  });
  factory ConfiguracionTributaria.fromJson(Map<String, dynamic> j) => ConfiguracionTributaria(
        regimenId: j['regimen_id']?.toString() ?? '',
        regimenCodigo: j['regimen_codigo']?.toString() ?? '',
        tasaIgv: _toD(j['tasa_igv']),
        cuentaIgvCreditoFiscalId: j['cuenta_igv_credito_fiscal_id']?.toString(),
        cuentaIgvDebitoFiscalId: j['cuenta_igv_debito_fiscal_id']?.toString(),
      );
}

// ── Planilla ─────────────────────────────────────────────────────────────────
class ConceptoRemunerativo {
  final String id, codigo, nombre, tipo;
  final double? montoReferencial;
  final bool activo;
  final bool esBase;
  ConceptoRemunerativo({
    required this.id, required this.codigo, required this.nombre,
    required this.tipo, this.montoReferencial, required this.activo,
    this.esBase = false,
  });
  factory ConceptoRemunerativo.fromJson(Map<String, dynamic> j) => ConceptoRemunerativo(
        id: j['id'].toString(),
        codigo: j['codigo']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        tipo: j['tipo']?.toString() ?? '',
        montoReferencial: j['monto_referencial'] != null ? _toD(j['monto_referencial']) : null,
        activo: j['activo'] == true,
        esBase: j['es_base'] == true,
      );
}

class BoletaPagoDetalle {
  final String conceptoId;
  final String? conceptoNombre, conceptoCodigo;
  final double monto;
  BoletaPagoDetalle({
    required this.conceptoId, this.conceptoNombre, this.conceptoCodigo, required this.monto,
  });
  factory BoletaPagoDetalle.fromJson(Map<String, dynamic> j) => BoletaPagoDetalle(
        conceptoId: j['concepto_id'].toString(),
        conceptoNombre: j['concepto_nombre']?.toString(),
        conceptoCodigo: j['concepto_codigo']?.toString(),
        monto: _toD(j['monto']),
      );
}

class BoletaPago {
  final String id, empleadoId;
  final String? empleadoNombre;
  final double totalIngresos, totalDescuentos, totalAportes, totalNeto;
  final List<BoletaPagoDetalle> detalles;
  BoletaPago({
    required this.id, required this.empleadoId, this.empleadoNombre, required this.totalIngresos,
    required this.totalDescuentos, required this.totalAportes, required this.totalNeto,
    required this.detalles,
  });
  factory BoletaPago.fromJson(Map<String, dynamic> j) => BoletaPago(
        id: j['id'].toString(),
        empleadoId: j['empleado_id'].toString(),
        empleadoNombre: j['empleado_nombre']?.toString(),
        totalIngresos: _toD(j['total_ingresos']),
        totalDescuentos: _toD(j['total_descuentos']),
        totalAportes: _toD(j['total_aportes']),
        totalNeto: _toD(j['total_neto']),
        detalles: ((j['detalles'] ?? []) as List)
            .map((e) => BoletaPagoDetalle.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Empleado activo para asignarle montos por concepto en Planilla.
class EmpleadoPlanilla {
  final String id;
  final String? nombre, cargo;
  EmpleadoPlanilla({required this.id, this.nombre, this.cargo});
  factory EmpleadoPlanilla.fromJson(Map<String, dynamic> j) => EmpleadoPlanilla(
        id: j['id'].toString(),
        nombre: j['nombre']?.toString(),
        cargo: j['cargo']?.toString(),
      );
}

/// Monto de un concepto asignado a un empleado concreto (sueldo individual).
class AsignacionConcepto {
  final String empleadoId, conceptoId;
  final double monto;
  AsignacionConcepto({required this.empleadoId, required this.conceptoId, required this.monto});
  factory AsignacionConcepto.fromJson(Map<String, dynamic> j) => AsignacionConcepto(
        empleadoId: j['empleado_id'].toString(),
        conceptoId: j['concepto_id'].toString(),
        monto: _toD(j['monto']),
      );
}

class Planilla {
  final String id, periodoId, fechaProceso, estado;
  final double totalIngresos, totalDescuentos, totalAportes, totalNeto;
  final String? asientoProvisionId, asientoPagoId;
  Planilla({
    required this.id, required this.periodoId, required this.fechaProceso,
    required this.estado, required this.totalIngresos, required this.totalDescuentos,
    required this.totalAportes, required this.totalNeto,
    this.asientoProvisionId, this.asientoPagoId,
  });
  factory Planilla.fromJson(Map<String, dynamic> j) => Planilla(
        id: j['id'].toString(),
        periodoId: j['periodo_id']?.toString() ?? '',
        fechaProceso: j['fecha_proceso']?.toString() ?? '',
        estado: j['estado']?.toString() ?? '',
        totalIngresos: _toD(j['total_ingresos']),
        totalDescuentos: _toD(j['total_descuentos']),
        totalAportes: _toD(j['total_aportes']),
        totalNeto: _toD(j['total_neto']),
        asientoProvisionId: j['asiento_provision_id']?.toString(),
        asientoPagoId: j['asiento_pago_id']?.toString(),
      );
}

// ── Pagos y Cobros ───────────────────────────────────────────────────────────
class AplicacionPago {
  final String facturaId;
  final double montoAplicado;
  AplicacionPago({required this.facturaId, required this.montoAplicado});
  factory AplicacionPago.fromJson(Map<String, dynamic> j) => AplicacionPago(
        facturaId: j['factura_id'].toString(),
        montoAplicado: _toD(j['monto_aplicado']),
      );
}

class PagoProveedor {
  final String id, proveedorId, fechaPago, medioPago;
  final double monto;
  final String? referencia, asientoId;
  final List<AplicacionPago> aplicaciones;
  PagoProveedor({
    required this.id, required this.proveedorId, required this.fechaPago,
    required this.medioPago, required this.monto, this.referencia,
    this.asientoId, required this.aplicaciones,
  });
  factory PagoProveedor.fromJson(Map<String, dynamic> j) => PagoProveedor(
        id: j['id'].toString(),
        proveedorId: j['proveedor_id'].toString(),
        fechaPago: j['fecha_pago']?.toString() ?? '',
        medioPago: j['medio_pago']?.toString() ?? '',
        monto: _toD(j['monto']),
        referencia: j['referencia']?.toString(),
        asientoId: j['asiento_id']?.toString(),
        aplicaciones: ((j['aplicaciones'] ?? []) as List)
            .map((e) => AplicacionPago.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class AplicacionCobro {
  final String facturaId;
  final double montoAplicado;
  AplicacionCobro({required this.facturaId, required this.montoAplicado});
  factory AplicacionCobro.fromJson(Map<String, dynamic> j) => AplicacionCobro(
        facturaId: j['factura_id'].toString(),
        montoAplicado: _toD(j['monto_aplicado']),
      );
}

class CobroCliente {
  final String id, clienteId, fechaCobro, medioPago;
  final double monto;
  final String? referencia, asientoId;
  final List<AplicacionCobro> aplicaciones;
  CobroCliente({
    required this.id, required this.clienteId, required this.fechaCobro,
    required this.medioPago, required this.monto, this.referencia,
    this.asientoId, required this.aplicaciones,
  });
  factory CobroCliente.fromJson(Map<String, dynamic> j) => CobroCliente(
        id: j['id'].toString(),
        clienteId: j['cliente_id'].toString(),
        fechaCobro: j['fecha_cobro']?.toString() ?? '',
        medioPago: j['medio_pago']?.toString() ?? '',
        monto: _toD(j['monto']),
        referencia: j['referencia']?.toString(),
        asientoId: j['asiento_id']?.toString(),
        aplicaciones: ((j['aplicaciones'] ?? []) as List)
            .map((e) => AplicacionCobro.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

// ── Tributario ───────────────────────────────────────────────────────────────
class RegistroTributarioFila {
  final String fecha, tipoDocumento, numeroDocumento, tercero;
  final String? ruc;
  final double baseImponible, igv, total;
  RegistroTributarioFila({
    required this.fecha, required this.tipoDocumento, required this.numeroDocumento,
    required this.tercero, this.ruc, required this.baseImponible,
    required this.igv, required this.total,
  });
  factory RegistroTributarioFila.fromJson(Map<String, dynamic> j) => RegistroTributarioFila(
        fecha: j['fecha']?.toString() ?? '',
        tipoDocumento: j['tipo_documento']?.toString() ?? '',
        numeroDocumento: j['numero_documento']?.toString() ?? '',
        tercero: (j['proveedor'] ?? j['cliente'])?.toString() ?? '—',
        ruc: j['ruc']?.toString(),
        baseImponible: _toD(j['base_imponible']),
        igv: _toD(j['igv']),
        total: _toD(j['total']),
      );
}

// ── Controlling / centros de costo ───────────────────────────────────────────
class CentroCosto {
  final String id, codigo, nombre, tipoReferencia;
  final String? referenciaId;
  final double? presupuestoReferencial;
  final bool activo;
  CentroCosto({
    required this.id, required this.codigo, required this.nombre,
    required this.tipoReferencia, this.referenciaId, this.presupuestoReferencial,
    required this.activo,
  });
  factory CentroCosto.fromJson(Map<String, dynamic> j) => CentroCosto(
        id: j['id'].toString(),
        codigo: j['codigo']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        tipoReferencia: j['tipo_referencia']?.toString() ?? 'libre',
        referenciaId: j['referencia_id']?.toString(),
        presupuestoReferencial: j['presupuesto_referencial'] == null ? null : _toD(j['presupuesto_referencial']),
        activo: j['activo'] == true,
      );
}

class CostoRealCentro {
  final String centroCostoId;
  final double totalDebito, totalCredito, costoReal;
  CostoRealCentro({
    required this.centroCostoId, required this.totalDebito,
    required this.totalCredito, required this.costoReal,
  });
  factory CostoRealCentro.fromJson(Map<String, dynamic> j) => CostoRealCentro(
        centroCostoId: j['centro_costo_id'].toString(),
        totalDebito: _toD(j['total_debito']),
        totalCredito: _toD(j['total_credito']),
        costoReal: _toD(j['costo_real']),
      );
}

class ComparativoCentro {
  final String centroCostoId, codigo, nombre;
  final double? presupuestoReferencial, desviacion, ejecucionPct;
  final double costoReal;
  ComparativoCentro({
    required this.centroCostoId, required this.codigo, required this.nombre,
    this.presupuestoReferencial, required this.costoReal, this.desviacion, this.ejecucionPct,
  });
  factory ComparativoCentro.fromJson(Map<String, dynamic> j) => ComparativoCentro(
        centroCostoId: j['centro_costo_id'].toString(),
        codigo: j['codigo']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        presupuestoReferencial: j['presupuesto_referencial'] == null ? null : _toD(j['presupuesto_referencial']),
        costoReal: _toD(j['costo_real']),
        desviacion: j['desviacion'] == null ? null : _toD(j['desviacion']),
        ejecucionPct: j['ejecucion_pct'] == null ? null : _toD(j['ejecucion_pct']),
      );
}

// ── Inventario valorizado ────────────────────────────────────────────────────
class MovimientoValorizado {
  final String id, materialId, tipo;
  final String? almacenId, asientoId;
  final int cantidad;
  final double? costoUnitario, valorTotal;
  MovimientoValorizado({
    required this.id, required this.materialId, this.almacenId, required this.tipo,
    required this.cantidad, this.costoUnitario, this.valorTotal, this.asientoId,
  });
  factory MovimientoValorizado.fromJson(Map<String, dynamic> j) => MovimientoValorizado(
        id: j['id'].toString(),
        materialId: j['material_id'].toString(),
        almacenId: j['almacen_id']?.toString(),
        tipo: j['tipo']?.toString() ?? '',
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
        costoUnitario: j['costo_unitario'] == null ? null : _toD(j['costo_unitario']),
        valorTotal: j['valor_total'] == null ? null : _toD(j['valor_total']),
        asientoId: j['asiento_id']?.toString(),
      );
}

class CostoPromedio {
  final String materialId, almacenId;
  final double cantidadActual, costoPromedioActual, valorActual;
  CostoPromedio({
    required this.materialId, required this.almacenId, required this.cantidadActual,
    required this.costoPromedioActual, required this.valorActual,
  });
  factory CostoPromedio.fromJson(Map<String, dynamic> j) => CostoPromedio(
        materialId: j['material_id'].toString(),
        almacenId: j['almacen_id'].toString(),
        cantidadActual: _toD(j['cantidad_actual']),
        costoPromedioActual: _toD(j['costo_promedio_actual']),
        valorActual: _toD(j['valor_actual']),
      );
}

class KardexFila {
  final String materialId;
  final String? materialNombre, materialCodigo;
  final String? almacenId, almacenNombre;
  final double saldoValorizado;
  KardexFila({
    required this.materialId, this.materialNombre, this.materialCodigo,
    this.almacenId, this.almacenNombre, required this.saldoValorizado,
  });
  factory KardexFila.fromJson(Map<String, dynamic> j) => KardexFila(
        materialId: j['material_id'].toString(),
        materialNombre: j['material_nombre']?.toString(),
        materialCodigo: j['material_codigo']?.toString(),
        almacenId: j['almacen_id']?.toString(),
        almacenNombre: j['almacen_nombre']?.toString(),
        saldoValorizado: _toD(j['saldo_valorizado']),
      );
}

// ── Caja Chica ───────────────────────────────────────────────────────────────
class CajaChica {
  final String id, nombre, estado, responsableId;
  final String? descripcion, responsableNombre, proyectoId, fechaApertura, fechaCierre;
  final double? montoAsignado;
  final double totalIngresos, totalEgresos, saldoActual;
  final int nMovimientos;
  CajaChica({
    required this.id, required this.nombre, required this.estado,
    required this.responsableId, this.descripcion, this.responsableNombre,
    this.proyectoId, this.fechaApertura, this.fechaCierre, this.montoAsignado,
    required this.totalIngresos, required this.totalEgresos,
    required this.saldoActual, required this.nMovimientos,
  });
  factory CajaChica.fromJson(Map<String, dynamic> j) => CajaChica(
        id: j['id'].toString(),
        nombre: j['nombre']?.toString() ?? '',
        estado: j['estado']?.toString() ?? 'abierta',
        responsableId: j['responsable_id']?.toString() ?? '',
        descripcion: j['descripcion']?.toString(),
        responsableNombre: j['responsable_nombre']?.toString(),
        proyectoId: j['proyecto_id']?.toString(),
        fechaApertura: j['fecha_apertura']?.toString(),
        fechaCierre: j['fecha_cierre']?.toString(),
        montoAsignado: j['monto_asignado_referencial'] == null
            ? null : _toD(j['monto_asignado_referencial']),
        totalIngresos: _toD(j['total_ingresos']),
        totalEgresos: _toD(j['total_egresos']),
        saldoActual: _toD(j['saldo_actual']),
        nMovimientos: _toI(j['n_movimientos']),
      );
  bool get abierta => estado == 'abierta';
}

class MovimientoCaja {
  final String id, cajaId, tipo, descripcion, fecha;
  final double monto;
  final String? concepto, comprobanteUrl, registradoPorNombre, asientoId;
  MovimientoCaja({
    required this.id, required this.cajaId, required this.tipo,
    required this.descripcion, required this.fecha, required this.monto,
    this.concepto, this.comprobanteUrl, this.registradoPorNombre, this.asientoId,
  });
  factory MovimientoCaja.fromJson(Map<String, dynamic> j) => MovimientoCaja(
        id: j['id'].toString(),
        cajaId: j['caja_id'].toString(),
        tipo: j['tipo']?.toString() ?? '',
        descripcion: j['descripcion']?.toString() ?? '',
        fecha: j['fecha']?.toString() ?? '',
        monto: _toD(j['monto']),
        concepto: j['concepto']?.toString(),
        comprobanteUrl: j['comprobante_url']?.toString(),
        registradoPorNombre: j['registrado_por_nombre']?.toString(),
        asientoId: j['asiento_id']?.toString(),
      );
  bool get esIngreso => tipo == 'ingreso';
}

// ── Conciliación bancaria ─────────────────────────────────────────────────────
class CuentaBancaria {
  final String id, banco, numeroCuenta, moneda, cuentaContableId;
  final String? cuentaContableCodigo, cuentaContableNombre, alias;
  final bool activo;
  final double saldoBanco, saldoLibros, diferencia;
  final int nPendientes;
  CuentaBancaria({
    required this.id, required this.banco, required this.numeroCuenta,
    required this.moneda, required this.cuentaContableId, this.cuentaContableCodigo,
    this.cuentaContableNombre, this.alias, required this.activo,
    required this.saldoBanco, required this.saldoLibros, required this.diferencia,
    required this.nPendientes,
  });
  factory CuentaBancaria.fromJson(Map<String, dynamic> j) => CuentaBancaria(
        id: j['id'].toString(),
        banco: j['banco']?.toString() ?? '',
        numeroCuenta: j['numero_cuenta']?.toString() ?? '',
        moneda: j['moneda']?.toString() ?? 'PEN',
        cuentaContableId: j['cuenta_contable_id']?.toString() ?? '',
        cuentaContableCodigo: j['cuenta_contable_codigo']?.toString(),
        cuentaContableNombre: j['cuenta_contable_nombre']?.toString(),
        alias: j['alias']?.toString(),
        activo: j['activo'] == true,
        saldoBanco: _toD(j['saldo_banco']),
        saldoLibros: _toD(j['saldo_libros']),
        diferencia: _toD(j['diferencia']),
        nPendientes: _toI(j['n_pendientes']),
      );
  bool get cuadrada => diferencia.abs() < 0.005;
}

class MovimientoBancario {
  final String id, cuentaBancariaId, fecha, descripcion, tipo, estado, origenCarga;
  final double monto;
  final String? referencia, asientoId, asientoNumero, conciliadoPorNombre, conciliadoAt;
  MovimientoBancario({
    required this.id, required this.cuentaBancariaId, required this.fecha,
    required this.descripcion, required this.tipo, required this.estado,
    required this.origenCarga, required this.monto, this.referencia,
    this.asientoId, this.asientoNumero, this.conciliadoPorNombre, this.conciliadoAt,
  });
  factory MovimientoBancario.fromJson(Map<String, dynamic> j) => MovimientoBancario(
        id: j['id'].toString(),
        cuentaBancariaId: j['cuenta_bancaria_id'].toString(),
        fecha: j['fecha']?.toString() ?? '',
        descripcion: j['descripcion']?.toString() ?? '',
        tipo: j['tipo']?.toString() ?? '',
        estado: j['estado']?.toString() ?? 'pendiente',
        origenCarga: j['origen_carga']?.toString() ?? 'manual',
        monto: _toD(j['monto']),
        referencia: j['referencia']?.toString(),
        asientoId: j['asiento_id']?.toString(),
        asientoNumero: j['asiento_numero']?.toString(),
        conciliadoPorNombre: j['conciliado_por_nombre']?.toString(),
        conciliadoAt: j['conciliado_at']?.toString(),
      );
  bool get esAbono => tipo == 'abono';
  bool get conciliado => estado == 'conciliado';
}

class SugerenciaAsiento {
  final String asientoId, numero, fecha, descripcion, origen;
  final double monto;
  final int diasDiferencia;
  SugerenciaAsiento({
    required this.asientoId, required this.numero, required this.fecha,
    required this.descripcion, required this.origen, required this.monto,
    required this.diasDiferencia,
  });
  factory SugerenciaAsiento.fromJson(Map<String, dynamic> j) => SugerenciaAsiento(
        asientoId: j['asiento_id'].toString(),
        numero: j['numero']?.toString() ?? '',
        fecha: j['fecha']?.toString() ?? '',
        descripcion: j['descripcion']?.toString() ?? '',
        origen: j['origen']?.toString() ?? '',
        monto: _toD(j['monto']),
        diasDiferencia: _toI(j['dias_diferencia']),
      );
}

class ResumenConciliacion {
  final String cuentaBancariaId;
  final double saldoBanco, saldoLibros, diferencia, importePendiente;
  final int totalMovimientos, conciliados, pendientes;
  ResumenConciliacion({
    required this.cuentaBancariaId, required this.saldoBanco, required this.saldoLibros,
    required this.diferencia, required this.importePendiente,
    required this.totalMovimientos, required this.conciliados, required this.pendientes,
  });
  factory ResumenConciliacion.fromJson(Map<String, dynamic> j) => ResumenConciliacion(
        cuentaBancariaId: j['cuenta_bancaria_id'].toString(),
        saldoBanco: _toD(j['saldo_banco']),
        saldoLibros: _toD(j['saldo_libros']),
        diferencia: _toD(j['diferencia']),
        importePendiente: _toD(j['importe_pendiente']),
        totalMovimientos: _toI(j['total_movimientos']),
        conciliados: _toI(j['conciliados']),
        pendientes: _toI(j['pendientes']),
      );
}

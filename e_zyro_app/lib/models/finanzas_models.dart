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

// ── Planilla ─────────────────────────────────────────────────────────────────
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

import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

// ── Contabilidad ────────────────────────────────────────────────────────────
export interface CuentaContable {
  id: string; codigo: string; nombre: string; tipo: string;
  nivel: number; activo: boolean;
}
export interface PeriodoContable {
  id: string; anio: number; mes: number;
  estado: 'abierto' | 'cerrado'; nombre?: string;
}
export interface AsientoLinea {
  id?: string; cuenta_id: string; cuenta_codigo?: string;
  nombre_cuenta?: string; debito: number; credito: number;
  centro_costo_id?: string | null; glosa?: string;
}
export interface Asiento {
  id: string; fecha: string; descripcion: string; referencia_id?: string;
  origen: string; lineas: AsientoLinea[]; total_debe: number; total_haber: number;
}
export interface AsientoCreate {
  fecha: string; descripcion: string; referencia_id?: string;
  lineas: AsientoLinea[];
}
export interface BalanceComprobacion {
  filas: { cuenta_codigo: string; nombre: string; debe: number; haber: number; saldo: number }[];
  total_deudor: number; total_acreedor: number; cuadra: boolean;
}

// ── CxC ─────────────────────────────────────────────────────────────────────
export interface FacturaCxC {
  id: string; cliente_id: string; cliente_nombre?: string;
  numero_documento: string; tipo_documento: string;
  fecha: string; fecha_vencimiento?: string;
  subtotal: number; igv: number; total: number;
  saldo_pendiente: number; estado: string; moneda: string;
  proyecto_id?: string; proyecto_nombre?: string;
}
export interface CobroCxC {
  id: string; cliente_id: string; cliente_nombre?: string;
  fecha_cobro: string; monto: number; medio_pago: string; referencia?: string;
}
export interface SaldoCliente {
  cliente_id: string; cliente_nombre: string; total_pendiente: number;
}

// ── CxP ─────────────────────────────────────────────────────────────────────
export interface FacturaCxP {
  id: string; proveedor_id: string; proveedor_nombre?: string;
  numero_documento: string; tipo_documento: string;
  fecha: string; fecha_vencimiento?: string;
  subtotal: number; igv: number; total: number;
  saldo_pendiente: number; estado: string; moneda: string;
}
export interface PagoCxP {
  id: string; proveedor_id: string; proveedor_nombre?: string;
  fecha_pago: string; monto: number; medio_pago: string; referencia?: string;
}
export interface SaldoProveedor {
  proveedor_id: string; proveedor_nombre: string; total_pendiente: number;
}

// ── Reportes Financieros ─────────────────────────────────────────────────────
export interface FilaReporte {
  cuenta_codigo?: string; descripcion: string;
  importe?: number; saldo?: number; debe?: number; haber?: number;
  nivel?: number; es_titulo?: boolean;
}
export interface ReporteFinanciero { titulo: string; filas: FilaReporte[]; total?: number; }

// ── Planilla ─────────────────────────────────────────────────────────────────
export interface PlanillaItem {
  id: string; periodo: string; estado: 'borrador' | 'aprobada' | 'pagada' | 'anulada';
  total_bruto: number; total_descuentos: number; total_neto: number;
  total_aportes_empleador: number; n_empleados: number;
  fecha_calculo?: string; fecha_aprobacion?: string;
}
export interface BolетaPago {
  id: string; empleado_id: string; empleado_nombre?: string;
  total_ingresos: number; total_descuentos: number; neto: number;
}
export interface ConceptoPlanilla {
  id: string; nombre: string; tipo: 'ingreso' | 'descuento' | 'aporte';
  es_base: boolean; activo: boolean;
}

// ── Controlling ──────────────────────────────────────────────────────────────
export interface CentroCosto {
  id: string; nombre: string; tipo_referencia?: string;
  presupuesto?: number; activo: boolean;
}
export interface ComparativoCentro {
  centro_id: string; nombre: string;
  presupuesto: number; costo_real: number; diferencia: number; porcentaje: number;
}

// ── Tributario ───────────────────────────────────────────────────────────────
export interface ConfiguracionTributaria {
  regimen_id: string; regimen_nombre: string; tasa_igv: number; tasa_renta: number;
  cuenta_igv_credito_fiscal_id?: string; cuenta_igv_debito_fiscal_id?: string;
}
export interface RegistroFila {
  fecha: string; ruc: string; razon_social: string;
  numero_doc: string; tipo_doc: string; base_imponible: number; igv: number; total: number;
}

// ── Caja Chica ───────────────────────────────────────────────────────────────
export interface CajaChica {
  id: string; nombre: string; responsable_nombre?: string;
  saldo_inicial: number; saldo_actual: number; estado: 'abierta' | 'cerrada';
  n_movimientos: number;
}
export interface MovimientoCaja {
  id: string; tipo: 'ingreso' | 'egreso'; monto: number;
  descripcion: string; concepto?: string; fecha: string;
}

// ── Conciliación Bancaria ─────────────────────────────────────────────────────
export interface CuentaBancaria {
  id: string; banco: string; numero_cuenta: string; moneda: string;
  saldo_banco: number; saldo_libros: number; diferencia: number;
  n_pendientes: number; activa: boolean;
}
export interface MovimientoBancario {
  id: string; fecha: string; descripcion: string;
  monto: number; tipo: 'credito' | 'debito';
  estado: 'pendiente' | 'conciliado';
}

// ── Activos Fijos ─────────────────────────────────────────────────────────────
export interface ActivoFijo {
  id: string; nombre: string; fecha_adquisicion: string;
  valor_adquisicion: number; valor_residual: number;
  vida_util_meses: number; depreciacion_acumulada: number;
  valor_en_libros: number; estado: 'activo' | 'dado_de_baja';
  centro_costo_id?: string; centro_costo_nombre?: string;
}

// ─────────────────────────────────────────────────────────────────────────────
@Injectable({ providedIn: 'root' })
export class AdministracionService {
  private http = inject(HttpClient);
  private base = environment.apiUrl;

  // ── Contabilidad ──────────────────────────────────────────────────────────
  getPlanCuentas(filtros?: { tipo?: string; nivel?: number; activo?: boolean }): Observable<CuentaContable[]> {
    let params = new HttpParams();
    if (filtros?.tipo) params = params.set('tipo', filtros.tipo);
    if (filtros?.nivel != null) params = params.set('nivel', filtros.nivel.toString());
    if (filtros?.activo != null) params = params.set('activo', filtros.activo.toString());
    return this.http.get<CuentaContable[]>(`${this.base}/contabilidad/plan-cuentas`, { params });
  }

  activarCuenta(id: string, activo: boolean): Observable<any> {
    return this.http.put(`${this.base}/contabilidad/plan-cuentas/${id}`, { activo });
  }

  getPeriodos(): Observable<PeriodoContable[]> {
    return this.http.get<PeriodoContable[]>(`${this.base}/contabilidad/periodos`);
  }

  crearPeriodo(anio: number, mes: number): Observable<PeriodoContable> {
    return this.http.post<PeriodoContable>(`${this.base}/contabilidad/periodos`, { anio, mes });
  }

  cerrarPeriodo(id: string): Observable<any> {
    return this.http.post(`${this.base}/contabilidad/periodos/${id}/cerrar`, {});
  }

  reabrirPeriodo(id: string): Observable<any> {
    return this.http.post(`${this.base}/contabilidad/periodos/${id}/reabrir`, {});
  }

  getAsientos(filtros?: { periodo_id?: string; desde?: string; hasta?: string }): Observable<Asiento[]> {
    let params = new HttpParams();
    if (filtros?.periodo_id) params = params.set('periodo_id', filtros.periodo_id);
    if (filtros?.desde) params = params.set('desde', filtros.desde);
    if (filtros?.hasta) params = params.set('hasta', filtros.hasta);
    return this.http.get<Asiento[]>(`${this.base}/contabilidad/asientos`, { params });
  }

  getAsiento(id: string): Observable<Asiento> {
    return this.http.get<Asiento>(`${this.base}/contabilidad/asientos/${id}`);
  }

  crearAsientoManual(body: AsientoCreate): Observable<Asiento> {
    return this.http.post<Asiento>(`${this.base}/contabilidad/asientos/manual`, body);
  }

  getBalanceComprobacion(periodo_id: string): Observable<BalanceComprobacion> {
    return this.http.get<BalanceComprobacion>(
      `${this.base}/contabilidad/balance-comprobacion`, { params: { periodo_id } }
    );
  }

  // ── Cuentas por Cobrar ─────────────────────────────────────────────────────
  getFacturasCxC(filtros?: { cliente_id?: string; estado?: string; vence_hasta?: string }): Observable<FacturaCxC[]> {
    let params = new HttpParams();
    if (filtros?.cliente_id) params = params.set('cliente_id', filtros.cliente_id);
    if (filtros?.estado) params = params.set('estado', filtros.estado);
    if (filtros?.vence_hasta) params = params.set('vence_hasta', filtros.vence_hasta);
    return this.http.get<FacturaCxC[]>(`${this.base}/cuentas-por-cobrar/facturas`, { params });
  }

  anularFacturaCxC(id: string): Observable<any> {
    return this.http.post(`${this.base}/cuentas-por-cobrar/facturas/${id}/anular`, {});
  }

  getCobros(cliente_id?: string): Observable<CobroCxC[]> {
    let params = new HttpParams();
    if (cliente_id) params = params.set('cliente_id', cliente_id);
    return this.http.get<CobroCxC[]>(`${this.base}/cuentas-por-cobrar/cobros`, { params });
  }

  getSaldosCxC(): Observable<SaldoCliente[]> {
    return this.http.get<SaldoCliente[]>(`${this.base}/cuentas-por-cobrar/reporte-saldos`);
  }

  getAntiguedadCxC(corte?: string): Observable<any[]> {
    let params = new HttpParams();
    if (corte) params = params.set('corte', corte);
    return this.http.get<any[]>(`${this.base}/cuentas-por-cobrar/reporte-antiguedad`, { params });
  }

  // ── Cuentas por Pagar ──────────────────────────────────────────────────────
  getFacturasCxP(filtros?: { proveedor_id?: string; estado?: string; vence_hasta?: string }): Observable<FacturaCxP[]> {
    let params = new HttpParams();
    if (filtros?.proveedor_id) params = params.set('proveedor_id', filtros.proveedor_id);
    if (filtros?.estado) params = params.set('estado', filtros.estado);
    if (filtros?.vence_hasta) params = params.set('vence_hasta', filtros.vence_hasta);
    return this.http.get<FacturaCxP[]>(`${this.base}/cuentas-por-pagar/facturas`, { params });
  }

  anularFacturaCxP(id: string): Observable<any> {
    return this.http.post(`${this.base}/cuentas-por-pagar/facturas/${id}/anular`, {});
  }

  getPagos(proveedor_id?: string): Observable<PagoCxP[]> {
    let params = new HttpParams();
    if (proveedor_id) params = params.set('proveedor_id', proveedor_id);
    return this.http.get<PagoCxP[]>(`${this.base}/cuentas-por-pagar/pagos`, { params });
  }

  getSaldosCxP(): Observable<SaldoProveedor[]> {
    return this.http.get<SaldoProveedor[]>(`${this.base}/cuentas-por-pagar/reporte-saldos`);
  }

  // ── Reportes Financieros ───────────────────────────────────────────────────
  getBalanceGeneral(fecha: string): Observable<any> {
    return this.http.get<any>(`${this.base}/reportes-financieros/balance-general`, { params: { fecha } });
  }

  getEstadoResultados(desde: string, hasta: string): Observable<any> {
    return this.http.get<any>(`${this.base}/reportes-financieros/estado-resultados`, { params: { desde, hasta } });
  }

  getFlujoEfectivo(periodo: string): Observable<any> {
    return this.http.get<any>(`${this.base}/reportes-financieros/flujo-efectivo`, { params: { periodo } });
  }

  getLibroDiario(periodo: string): Observable<any[]> {
    return this.http.get<any[]>(`${this.base}/reportes-financieros/libro-diario`, { params: { periodo } });
  }

  getLibroMayor(cuenta_id: string, desde: string, hasta: string): Observable<any> {
    return this.http.get<any>(`${this.base}/reportes-financieros/libro-mayor/${cuenta_id}`, { params: { desde, hasta } });
  }

  // ── Planilla ───────────────────────────────────────────────────────────────
  getPlanillas(): Observable<PlanillaItem[]> {
    return this.http.get<PlanillaItem[]>(`${this.base}/planilla`);
  }

  calcularPlanilla(periodo: string): Observable<PlanillaItem> {
    return this.http.post<PlanillaItem>(`${this.base}/planilla/calcular`, null, { params: { periodo } });
  }

  aprobarPlanilla(id: string): Observable<any> {
    return this.http.post(`${this.base}/planilla/${id}/aprobar`, {});
  }

  marcarPagadaPlanilla(id: string): Observable<any> {
    return this.http.post(`${this.base}/planilla/${id}/marcar-pagada`, {});
  }

  anularPlanilla(id: string): Observable<any> {
    return this.http.post(`${this.base}/planilla/${id}/anular`, {});
  }

  getBoletas(planilla_id: string): Observable<BolетaPago[]> {
    return this.http.get<BolетaPago[]>(`${this.base}/planilla/${planilla_id}/boletas`);
  }

  getConceptosPlanilla(): Observable<ConceptoPlanilla[]> {
    return this.http.get<ConceptoPlanilla[]>(`${this.base}/planilla/conceptos`);
  }

  getEmpleadosPlanilla(): Observable<any[]> {
    return this.http.get<any[]>(`${this.base}/planilla/empleados`);
  }

  // ── Controlling ────────────────────────────────────────────────────────────
  getCentrosCosto(): Observable<CentroCosto[]> {
    return this.http.get<CentroCosto[]>(`${this.base}/controlling/centros-costo`);
  }

  crearCentroCosto(body: Partial<CentroCosto>): Observable<CentroCosto> {
    return this.http.post<CentroCosto>(`${this.base}/controlling/centros-costo`, body);
  }

  actualizarCentroCosto(id: string, body: Partial<CentroCosto>): Observable<CentroCosto> {
    return this.http.put<CentroCosto>(`${this.base}/controlling/centros-costo/${id}`, body);
  }

  eliminarCentroCosto(id: string): Observable<any> {
    return this.http.delete(`${this.base}/controlling/centros-costo/${id}`);
  }

  getComparativoCentro(id: string, desde: string, hasta: string): Observable<ComparativoCentro> {
    return this.http.get<ComparativoCentro>(
      `${this.base}/controlling/centros-costo/${id}/comparativo`, { params: { desde, hasta } }
    );
  }

  // ── Tributario ─────────────────────────────────────────────────────────────
  getConfiguracionTributaria(): Observable<ConfiguracionTributaria> {
    return this.http.get<ConfiguracionTributaria>(`${this.base}/tributario/configuracion`);
  }

  actualizarConfiguracionTributaria(body: Partial<ConfiguracionTributaria>): Observable<any> {
    return this.http.put(`${this.base}/tributario/configuracion`, body);
  }

  getRegistroCompras(periodo: string): Observable<RegistroFila[]> {
    return this.http.get<RegistroFila[]>(`${this.base}/tributario/registro-compras`, { params: { periodo } });
  }

  getRegistroVentas(periodo: string): Observable<RegistroFila[]> {
    return this.http.get<RegistroFila[]>(`${this.base}/tributario/registro-ventas`, { params: { periodo } });
  }

  // ── Caja Chica ─────────────────────────────────────────────────────────────
  getCajas(): Observable<CajaChica[]> {
    return this.http.get<CajaChica[]>(`${this.base}/caja-chica`);
  }

  crearCaja(nombre: string, saldo_inicial: number): Observable<CajaChica> {
    return this.http.post<CajaChica>(`${this.base}/caja-chica`, { nombre, saldo_inicial });
  }

  cerrarCaja(id: string): Observable<any> {
    return this.http.post(`${this.base}/caja-chica/${id}/cerrar`, {});
  }

  getMovimientosCaja(caja_id: string): Observable<MovimientoCaja[]> {
    return this.http.get<MovimientoCaja[]>(`${this.base}/caja-chica/${caja_id}/movimientos`);
  }

  registrarMovimientoCaja(caja_id: string, body: Partial<MovimientoCaja>): Observable<MovimientoCaja> {
    return this.http.post<MovimientoCaja>(`${this.base}/caja-chica/${caja_id}/movimientos`, body);
  }

  // ── Conciliación Bancaria ──────────────────────────────────────────────────
  getCuentasBancarias(): Observable<CuentaBancaria[]> {
    return this.http.get<CuentaBancaria[]>(`${this.base}/conciliacion-bancaria/cuentas`);
  }

  crearCuentaBancaria(body: Partial<CuentaBancaria>): Observable<CuentaBancaria> {
    return this.http.post<CuentaBancaria>(`${this.base}/conciliacion-bancaria/cuentas`, body);
  }

  getMovimientosBancarios(cuenta_id: string, estado?: string): Observable<MovimientoBancario[]> {
    const params: any = {};
    if (estado) params['estado'] = estado;
    return this.http.get<MovimientoBancario[]>(
      `${this.base}/conciliacion-bancaria/cuentas/${cuenta_id}/movimientos`, { params }
    );
  }

  conciliarMovimiento(mov_id: string, asiento_id: string): Observable<any> {
    return this.http.post(`${this.base}/conciliacion-bancaria/movimientos/${mov_id}/conciliar`, { asiento_id });
  }

  desconciliarMovimiento(mov_id: string): Observable<any> {
    return this.http.post(`${this.base}/conciliacion-bancaria/movimientos/${mov_id}/desconciliar`, {});
  }

  // ── Activos Fijos ──────────────────────────────────────────────────────────
  getActivosFijos(filtros?: { estado?: string; centro_costo?: string }): Observable<ActivoFijo[]> {
    let params = new HttpParams();
    if (filtros?.estado) params = params.set('estado', filtros.estado);
    if (filtros?.centro_costo) params = params.set('centro_costo', filtros.centro_costo);
    return this.http.get<ActivoFijo[]>(`${this.base}/activos-fijos`, { params });
  }

  crearActivoFijo(body: Partial<ActivoFijo>): Observable<ActivoFijo> {
    return this.http.post<ActivoFijo>(`${this.base}/activos-fijos`, body);
  }

  actualizarActivoFijo(id: string, body: Partial<ActivoFijo>): Observable<ActivoFijo> {
    return this.http.put<ActivoFijo>(`${this.base}/activos-fijos/${id}`, body);
  }

  darDeBajaActivo(id: string): Observable<any> {
    return this.http.post(`${this.base}/activos-fijos/${id}/dar-de-baja`, {});
  }

  getDepreciacionActivo(id: string): Observable<any[]> {
    return this.http.get<any[]>(`${this.base}/activos-fijos/${id}/depreciacion`);
  }

  procesarDepreciacion(periodo: string): Observable<any> {
    return this.http.post(`${this.base}/activos-fijos/procesar-depreciacion`, null, { params: { periodo } });
  }
}

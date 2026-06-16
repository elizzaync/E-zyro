import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RrhhService, ResumenEmpleadoDto, PeriodoDto } from '../../../core/services/rrhh.service';
import { ToastService } from '../../../core/services/toast.service';
import { AuthService } from '../../../core/services/auth.service';
import html2pdf from 'html2pdf.js';

const SUELDO_KEY   = 'ezp_sueldos_v1';
const REGIMEN_KEY  = 'ezp_regimen_v1';
const PENSION_KEY  = 'ezp_pensiones_v1';
const AFP_KEY      = 'ezp_afp_entidad_v1';
const ESQUEMA_KEY  = 'ezp_esquema_pago_v1';
const PER_PAGE     = 10;

const MESES_ES = [
  '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

// ── Parámetros legales (Perú: Ley 28015/D.L. 1086 MYPE, D.L. 854 jornada,
//    D.L. 19990 ONP, Ley 28518 modalidades formativas). Tasas de AFP/ONP y RMV
//    son referenciales — deben verificarse vigentes en SBS/SUNAT/SUNAFIL antes
//    de procesar planilla real. ───────────────────────────────────────────────
const PENSION_ONP_PCT       = 0.13;    // ONP, tasa fija (D.L. 19990)
const AFP_APORTE_PCT        = 0.10;    // Aporte obligatorio a cuenta individual
const AFP_SEGURO_PCT        = 0.0117;  // Prima de seguro (invalidez/sobrevivencia), referencial SBS
const ESSALUD_PCT           = 0.09;    // Aporte patronal — NO se descuenta al trabajador
const RMV_VIGENTE           = 1025;    // Remuneración Mínima Vital S/ referencial — verificar vigencia SUNAFIL/MTPE
const CTS_PEQUENA_FACTOR    = 1 / 24;  // 15 remun. diarias/año, mensualizado (Pequeña Empresa)
const GRATIF_PEQUENA_FACTOR = 1 / 12;  // medio sueldo × 2 semestres/año, mensualizado (Pequeña Empresa)
const CTS_GENERAL_FACTOR    = 1 / 12;  // 1 remuneración/año, mensualizado (Régimen General)
const GRATIF_GENERAL_FACTOR = 1 / 6;   // 1 sueldo × 2 semestres/año, mensualizado (Régimen General)
const VACACIONES_DIAS_MYPE  = 15;
const VACACIONES_DIAS_GENERAL = 30;

// Comisión por flujo de cada AFP sobre la remuneración (referencial, verificar SBS)
const AFP_COMISIONES: Record<AfpEntidad, number> = {
  integra:    0.0155,
  prima:      0.0160,
  profuturo:  0.0169,
  habitat:    0.0147,
};

type Regimen = 'micro' | 'pequena' | 'general';
type Pension = 'onp' | 'afp';
type AfpEntidad = 'integra' | 'prima' | 'profuturo' | 'habitat';
type PeriodoPago = 'q1' | 'q2' | 'mes';
type EsquemaPago = 'quincenal' | 'mensual';

@Component({
  selector: 'app-planillas',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './planillas.component.html',
  styleUrls: ['./planillas.component.css']
})
export class PlanillasComponent implements OnInit {
  private svc   = inject(RrhhService);
  private toast = inject(ToastService);
  private auth  = inject(AuthService);

  // ── Período ───────────────────────────────────────────────────────────────
  selectedYear  = new Date().getFullYear();
  selectedMonth = new Date().getMonth() + 1;     // 1-12
  periodo: PeriodoDto | null = null;

  // Esquema de pago de la empresa: quincenal (adelanto 15 + liquidación fin de
  // mes) o simplemente mensual. Configurable y persistido — si es "mensual" no
  // se muestra el selector de quincenas.
  esquemaPago: EsquemaPago = 'quincenal';

  // Pago por quincena (1-15 / 16-fin de mes) o mes completo. La boleta oficial
  // (PDF + envío a Legajo Digital) solo se emite en vista "Mes Completo"; las
  // quincenas son cálculos de adelanto proporcional sobre el mismo sueldo base.
  periodoPago: PeriodoPago = 'mes';

  // ── Empleados / asistencia ────────────────────────────────────────────────
  empleados:     ResumenEmpleadoDto[] = [];
  totalRegistros = 0;
  totalPaginas   = 1;
  currentPage    = 1;
  cargando       = false;
  error          = '';

  // ── Sueldos base (localStorage) ───────────────────────────────────────────
  sueldoMap: Record<string, number> = {};
  guardando = false;

  // ── Régimen de la empresa: MYPE (Micro/Pequeña) o Régimen General ───────────
  regimenEmpresa: Regimen = 'micro';

  // ── Sistema de pensión por trabajador (solo planilla/contrato) ─────────────
  pensionMap: Record<string, Pension> = {};
  afpEntidadMap: Record<string, AfpEntidad> = {};

  // ── Modal boleta individual ───────────────────────────────────────────────
  boletaEmp: ResumenEmpleadoDto | null = null;
  generandoPdf = false;

  get puedeEditar(): boolean {
    const rol = (this.auth.getUsuario()?.rol || '').trim().toLowerCase().replace(/\s+/g, '');
    return !['técnicodecampo', 'clienteexterno'].includes(rol);
  }

  get isAdmin(): boolean {
    const rol = (this.auth.getUsuario()?.rol || '').trim();
    return rol === 'Administrador' || rol === 'administrador' || rol === 'SuperAdmin' || rol === 'superadmin';
  }

  // ── Ciclo de vida ─────────────────────────────────────────────────────────

  ngOnInit(): void {
    this.sueldoMap      = JSON.parse(localStorage.getItem(SUELDO_KEY) ?? '{}');
    this.pensionMap     = JSON.parse(localStorage.getItem(PENSION_KEY) ?? '{}');
    this.afpEntidadMap  = JSON.parse(localStorage.getItem(AFP_KEY) ?? '{}');
    this.regimenEmpresa = (localStorage.getItem(REGIMEN_KEY) as Regimen) || 'micro';
    this.esquemaPago    = (localStorage.getItem(ESQUEMA_KEY) as EsquemaPago) || 'quincenal';
    if (this.esquemaPago === 'mensual') this.periodoPago = 'mes';
    this.cargar();
  }

  // ── Período ───────────────────────────────────────────────────────────────

  get labelPeriodo(): string {
    return new Date(this.selectedYear, this.selectedMonth - 1, 1)
      .toLocaleDateString('es-PE', { month: 'long', year: 'numeric' });
  }

  get fechaInicio(): string {
    const dia = this.periodoPago === 'q2' ? 16 : 1;
    return `${this.selectedYear}-${String(this.selectedMonth).padStart(2, '0')}-${String(dia).padStart(2, '0')}`;
  }

  get fechaFin(): string {
    if (this.periodoPago === 'q1') {
      return `${this.selectedYear}-${String(this.selectedMonth).padStart(2, '0')}-15`;
    }
    const d = new Date(this.selectedYear, this.selectedMonth, 0); // último día del mes
    return d.toISOString().split('T')[0];
  }

  // ── Período de pago: 1ra Quincena / 2da Quincena / Mes Completo ────────────

  setPeriodoPago(val: PeriodoPago): void {
    this.periodoPago = val;
    this.currentPage = 1;
    this.cerrarBoleta();
    this.cargar();
  }

  get esVistaMensual(): boolean {
    return this.periodoPago === 'mes';
  }

  get labelRangoQuincena(): string {
    if (this.periodoPago === 'q1') return '01–15';
    if (this.periodoPago === 'q2') {
      const ultimo = new Date(this.selectedYear, this.selectedMonth, 0).getDate();
      return `16–${ultimo}`;
    }
    return '';
  }

  // Monto correspondiente al período visualizado: la mitad del sueldo mensual
  // en cada quincena, el sueldo completo en vista de mes.
  sueldoPeriodo(empId: string): number {
    const base = this.getSueldo(empId);
    return this.periodoPago === 'mes' ? base : base / 2;
  }

  // ── Esquema de pago de la empresa: Quincenal o Mensual ──────────────────────

  setEsquemaPago(val: EsquemaPago): void {
    this.esquemaPago = val;
    localStorage.setItem(ESQUEMA_KEY, val);
    if (val === 'mensual') this.setPeriodoPago('mes');
  }

  irMesAnterior(): void {
    if (this.selectedMonth === 1) { this.selectedMonth = 12; this.selectedYear--; }
    else this.selectedMonth--;
    this.currentPage = 1;
    this.cargar();
  }

  irMesSiguiente(): void {
    const hoy = new Date();
    if (this.selectedYear === hoy.getFullYear() && this.selectedMonth === hoy.getMonth() + 1) return;
    if (this.selectedMonth === 12) { this.selectedMonth = 1; this.selectedYear++; }
    else this.selectedMonth++;
    this.currentPage = 1;
    this.cargar();
  }

  get esMesActual(): boolean {
    const hoy = new Date();
    return this.selectedYear === hoy.getFullYear() && this.selectedMonth === hoy.getMonth() + 1;
  }

  // ── Carga de datos (boleta = ciclo mensual completo) ────────────────────────

  cargar(): void {
    this.cargando = true;
    this.error = '';
    this.svc.getResumenAsistencia({
      fecha_inicio: this.fechaInicio,
      fecha_fin:    this.fechaFin,
      page:         this.currentPage,
      limit:        PER_PAGE,
    }).subscribe({
      next: (res) => {
        this.periodo        = res.periodo;
        this.empleados      = res.empleados;
        this.totalRegistros = res.total;
        this.totalPaginas   = res.total_paginas;
        this.cargando       = false;
      },
      error: () => {
        this.error   = 'No se pudo cargar la nómina de este período.';
        this.cargando = false;
      }
    });
  }

  irPagina(p: number): void {
    if (p < 1 || p > this.totalPaginas) return;
    this.currentPage = p;
    this.cargar();
  }

  get paginasBotones(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(1, this.currentPage - 2); i <= Math.min(this.totalPaginas, this.currentPage + 2); i++) pages.push(i);
    return pages;
  }

  get rangoMostrando() {
    const desde = (this.currentPage - 1) * PER_PAGE + 1;
    const hasta  = Math.min(this.currentPage * PER_PAGE, this.totalRegistros);
    return { desde, hasta, total: this.totalRegistros };
  }

  // ── Régimen de la empresa: Microempresa / Pequeña Empresa / Régimen General ─

  setRegimen(val: Regimen): void {
    this.regimenEmpresa = val;
    localStorage.setItem(REGIMEN_KEY, val);
  }

  get regimenLabel(): string {
    const map: Record<Regimen, string> = {
      micro:   'Microempresa',
      pequena: 'Pequeña Empresa',
      general: 'Régimen General',
    };
    return map[this.regimenEmpresa];
  }

  get esRegimenMype(): boolean {
    return this.regimenEmpresa !== 'general';
  }

  get diasVacaciones(): number {
    return this.regimenEmpresa === 'general' ? VACACIONES_DIAS_GENERAL : VACACIONES_DIAS_MYPE;
  }

  // ── Modalidad del trabajador (viene de la BD: empleado.tipo) ────────────────

  esDependiente(emp: ResumenEmpleadoDto): boolean {
    return emp.tipo_contrato === 'planilla' || emp.tipo_contrato === 'contrato';
  }

  esPracticante(emp: ResumenEmpleadoDto): boolean {
    return emp.tipo_contrato === 'practicante';
  }

  modalidadLabel(emp: ResumenEmpleadoDto): string {
    const map: Record<string, string> = {
      planilla:    'Planilla',
      contrato:    'Contrato',
      practicante: 'Practicante',
    };
    return map[emp.tipo_contrato] ?? emp.tipo_contrato;
  }

  modalidadClass(emp: ResumenEmpleadoDto): string {
    const map: Record<string, string> = {
      planilla:    'tipo-planilla',
      contrato:    'tipo-contrato',
      practicante: 'tipo-practicante',
    };
    return map[emp.tipo_contrato] ?? 'tipo-planilla';
  }

  // RRHH asigna la modalidad real de cada trabajador (afecta el cálculo legal:
  // pensión, recargo de horas extra, CTS/gratificación).
  onModalidadChange(emp: ResumenEmpleadoDto, nuevoTipo: string): void {
    const anterior = emp.tipo_contrato;
    if (anterior === nuevoTipo) return;
    emp.tipo_contrato = nuevoTipo;
    this.svc.actualizarModalidad(emp.id, nuevoTipo as any).subscribe({
      next: () => this.toast.mostrar(`Modalidad de ${emp.nombreCompleto} actualizada a ${this.modalidadLabel(emp)}`, 'success'),
      error: (err) => {
        emp.tipo_contrato = anterior;
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar la modalidad', 'error');
      }
    });
  }

  // ── Sueldos ───────────────────────────────────────────────────────────────

  getSueldo(empId: string): number {
    return this.sueldoMap[empId] ?? 0;
  }

  onSueldoChange(empId: string, raw: string): void {
    const val = parseFloat(raw.replace(/[^0-9.]/g, '')) || 0;
    this.sueldoMap[empId] = val;
  }

  guardarSueldos(): void {
    this.guardando = true;
    setTimeout(() => {
      localStorage.setItem(SUELDO_KEY, JSON.stringify(this.sueldoMap));
      this.guardando = false;
      this.toast.mostrar('Sueldos guardados correctamente', 'success');
    }, 400);
  }

  // ── Sistema de pensión (solo planilla/contrato): ONP o AFP + entidad ────────

  readonly afpEntidades: { value: AfpEntidad; label: string }[] = [
    { value: 'integra',   label: 'AFP Integra' },
    { value: 'prima',     label: 'AFP Prima' },
    { value: 'profuturo', label: 'Profuturo AFP' },
    { value: 'habitat',   label: 'AFP Habitat' },
  ];

  getPension(empId: string): Pension {
    return this.pensionMap[empId] ?? 'onp';
  }

  onPensionChange(empId: string, val: Pension): void {
    this.pensionMap[empId] = val;
    localStorage.setItem(PENSION_KEY, JSON.stringify(this.pensionMap));
  }

  getAfpEntidad(empId: string): AfpEntidad {
    return this.afpEntidadMap[empId] ?? 'integra';
  }

  onAfpEntidadChange(empId: string, val: AfpEntidad): void {
    this.afpEntidadMap[empId] = val;
    localStorage.setItem(AFP_KEY, JSON.stringify(this.afpEntidadMap));
  }

  afpEntidadLabel(empId: string): string {
    return this.afpEntidades.find(a => a.value === this.getAfpEntidad(empId))?.label ?? 'AFP Integra';
  }

  pensionLabel(emp: ResumenEmpleadoDto): string {
    if (this.getPension(emp.id) === 'onp') return 'ONP (13%)';
    const pct = (this.pensionPct(emp) * 100).toFixed(2);
    return `${this.afpEntidadLabel(emp.id)} (≈${pct}%)`;
  }

  pensionPct(emp: ResumenEmpleadoDto): number {
    if (this.getPension(emp.id) === 'onp') return PENSION_ONP_PCT;
    const comision = AFP_COMISIONES[this.getAfpEntidad(emp.id)];
    return AFP_APORTE_PCT + AFP_SEGURO_PCT + comision;
  }

  // ── Cumplimiento SUNAFIL: Remuneración Mínima Vital ─────────────────────────

  bajoRmv(emp: ResumenEmpleadoDto): boolean {
    const sueldo = this.getSueldo(emp.id);
    return sueldo > 0 && sueldo < RMV_VIGENTE;
  }

  get rmvVigente(): number {
    return RMV_VIGENTE;
  }

  // ── Cálculos de nómina (MYPE Perú: DL 854 + Ley 28015/DL 1086 + Ley 28518) ──

  valorHora(emp: ResumenEmpleadoDto): number {
    const sueldo = this.sueldoPeriodo(emp.id);
    const meta   = emp.meta_horas || 1;
    return sueldo / meta;
  }

  horasExtra(emp: ResumenEmpleadoDto): number {
    return Math.max(0, emp.horas_reales - emp.meta_horas);
  }

  // Horas extra: recargo legal 25%/35% solo aplica a trabajadores en planilla/contrato
  // (DL 854). Los practicantes no tienen "sobretiempo" legal; se reconoce a tarifa simple.
  pagoHorasExtra(emp: ResumenEmpleadoDto): number {
    const vh     = this.valorHora(emp);
    const extras = this.horasExtra(emp);
    if (extras <= 0) return 0;
    if (this.esPracticante(emp)) return extras * vh; // tarifa simple, sin recargo
    const h1 = Math.min(extras, 2) * vh * 1.25;
    const h2 = Math.max(0, extras - 2) * vh * 1.35;
    return h1 + h2;
  }

  descuentoFaltas(emp: ResumenEmpleadoDto): number {
    return emp.horas_faltantes * this.valorHora(emp);
  }

  // Descuento por sistema de pensiones (ONP/AFP): obligatorio solo para
  // trabajadores dependientes (planilla/contrato). Los practicantes, bajo la
  // Ley de Modalidades Formativas (28518), no tienen relación laboral y no
  // están afiliados obligatoriamente.
  descuentoPension(emp: ResumenEmpleadoDto): number {
    if (!this.esDependiente(emp)) return 0;
    const base = this.sueldoPeriodo(emp.id) - this.descuentoFaltas(emp) + this.pagoHorasExtra(emp);
    return Math.max(0, base) * this.pensionPct(emp);
  }

  // Aporte EsSalud: costo del empleador, NO se descuenta del trabajador.
  // Aplica a ambas modalidades (seguro de salud obligatorio).
  aporteEssalud(emp: ResumenEmpleadoDto): number {
    return this.sueldoPeriodo(emp.id) * ESSALUD_PCT;
  }

  // CTS y Gratificación: en Microempresa la ley exonera ambos beneficios; en
  // Pequeña Empresa corresponde la mitad; en Régimen General corresponden
  // completos. Solo para dependientes (planilla/contrato). Se muestran como
  // provisión informativa: no afectan el neto de este mes (se acumulan/pagan
  // en su fecha legal — CTS mayo/noviembre, gratificación julio/diciembre).
  provisionCTS(emp: ResumenEmpleadoDto): number {
    if (!this.esDependiente(emp) || this.regimenEmpresa === 'micro') return 0;
    const factor = this.regimenEmpresa === 'general' ? CTS_GENERAL_FACTOR : CTS_PEQUENA_FACTOR;
    return this.sueldoPeriodo(emp.id) * factor;
  }

  provisionGratificacion(emp: ResumenEmpleadoDto): number {
    if (!this.esDependiente(emp) || this.regimenEmpresa === 'micro') return 0;
    const factor = this.regimenEmpresa === 'general' ? GRATIF_GENERAL_FACTOR : GRATIF_PEQUENA_FACTOR;
    return this.sueldoPeriodo(emp.id) * factor;
  }

  // Provisión vacacional informativa: 15 días/año (MYPE) o 30 días/año
  // (Régimen General), mensualizada. No afecta el neto (se goza como descanso
  // pagado, no como pago adicional en la boleta mensual).
  provisionVacaciones(emp: ResumenEmpleadoDto): number {
    if (!this.esDependiente(emp)) return 0;
    return this.sueldoPeriodo(emp.id) * (this.diasVacaciones / 360);
  }

  netoAPagar(emp: ResumenEmpleadoDto): number {
    const sueldo = this.sueldoPeriodo(emp.id);
    if (sueldo <= 0) return 0;
    return Math.max(0,
      sueldo
      - this.descuentoFaltas(emp)
      + this.pagoHorasExtra(emp)
      - this.descuentoPension(emp)
    );
  }

  totalDescuentosLegales(emp: ResumenEmpleadoDto): number {
    return this.descuentoFaltas(emp) + this.descuentoPension(emp);
  }

  // ── KPIs ──────────────────────────────────────────────────────────────────

  get kpis() {
    const sinSueldo = this.empleados.filter(e => this.getSueldo(e.id) === 0).length;
    const totalNeto = this.empleados.reduce((s, e) => s + this.netoAPagar(e), 0);
    const totalDesc = this.empleados.reduce((s, e) => s + this.totalDescuentosLegales(e), 0);
    const totalExt  = this.empleados.reduce((s, e) => s + this.pagoHorasExtra(e), 0);
    const enPlanilla = this.empleados.filter(e => this.esDependiente(e)).length;
    const practicantes = this.empleados.filter(e => this.esPracticante(e)).length;
    const bajoRmvCount = this.empleados.filter(e => this.bajoRmv(e)).length;
    return { totalEmpleados: this.totalRegistros, totalNeto, totalDesc, totalExt, sinSueldo, enPlanilla, practicantes, bajoRmvCount };
  }

  // ── Boleta individual ─────────────────────────────────────────────────────

  verBoleta(emp: ResumenEmpleadoDto): void { this.boletaEmp = emp; }
  cerrarBoleta(): void { this.boletaEmp = null; }

  // ── Generar PDF de la boleta y enviarla a Legajo Digital ────────────────────

  private construirVoucherHtml(emp: ResumenEmpleadoDto): string {
    const dependiente = this.esDependiente(emp);
    const sueldo       = this.sueldoPeriodo(emp.id);
    const extra        = this.pagoHorasExtra(emp);
    const descFaltas    = this.descuentoFaltas(emp);
    const descPension   = this.descuentoPension(emp);
    const neto          = this.netoAPagar(emp);
    const essalud       = this.aporteEssalud(emp);
    const cts            = this.provisionCTS(emp);
    const grati          = this.provisionGratificacion(emp);
    const vacaciones      = this.provisionVacaciones(emp);

    const filaIngreso = (label: string, detalle: string, monto: number) => `
      <tr style="background:#f0fdf4;">
        <td style="padding:8px 10px;font-size:11px;color:#1e293b;">${label}</td>
        <td style="padding:8px 10px;font-size:10px;color:#64748b;text-align:right;">${detalle}</td>
        <td style="padding:8px 10px;font-size:11px;font-weight:700;color:#16a34a;text-align:right;">+${this.formatMonto(monto)}</td>
      </tr>`;
    const filaDescuento = (label: string, detalle: string, monto: number) => `
      <tr style="background:#fef2f2;">
        <td style="padding:8px 10px;font-size:11px;color:#1e293b;">${label}</td>
        <td style="padding:8px 10px;font-size:10px;color:#64748b;text-align:right;">${detalle}</td>
        <td style="padding:8px 10px;font-size:11px;font-weight:700;color:#dc2626;text-align:right;">−${this.formatMonto(monto)}</td>
      </tr>`;
    const filaInfo = (label: string, detalle: string, monto: number) => `
      <tr style="background:#f8fafc;">
        <td style="padding:8px 10px;font-size:11px;color:#64748b;">${label}</td>
        <td style="padding:8px 10px;font-size:10px;color:#94a3b8;text-align:right;">${detalle}</td>
        <td style="padding:8px 10px;font-size:11px;font-weight:600;color:#64748b;text-align:right;">${this.formatMonto(monto)}</td>
      </tr>`;

    let filasIngresos = filaIngreso('Sueldo Base', `${this.formatH(emp.meta_horas)} estándar`, sueldo);
    if (extra > 0) {
      const detalleExtra = dependiente
        ? (this.horasExtra(emp) <= 2 ? `${this.formatH(this.horasExtra(emp))} × 25%` : `2h×25% + ${this.formatH(this.horasExtra(emp) - 2)}×35%`)
        : `${this.formatH(this.horasExtra(emp))} tarifa simple`;
      filasIngresos += filaIngreso(`Horas Extra (${this.formatH(this.horasExtra(emp))})`, detalleExtra, extra);
    }

    let filasDescuentos = '';
    if (descFaltas > 0) {
      filasDescuentos += filaDescuento('Descuento por Faltas/Tardanzas', `${this.formatH(emp.horas_faltantes)} × ${this.formatMonto(this.valorHora(emp))}/h`, descFaltas);
    }
    if (descPension > 0) {
      filasDescuentos += filaDescuento(`Sistema de Pensión (${this.pensionLabel(emp)})`, 'Ley N.° 19990 / D.L. 25897', descPension);
    }

    let filasInformativas = filaInfo('Aporte EsSalud (empleador)', 'No descontado al trabajador', essalud);
    if (cts > 0)   filasInformativas += filaInfo('Provisión CTS', `${this.regimenLabel} · ${this.regimenEmpresa === 'general' ? '1 remuneración/año' : '15 rem. diarias/año'}`, cts);
    if (grati > 0) filasInformativas += filaInfo('Provisión Gratificación', `${this.regimenLabel} · ${this.regimenEmpresa === 'general' ? 'sueldo completo/semestre' : 'medio sueldo/semestre'}`, grati);
    if (vacaciones > 0) filasInformativas += filaInfo('Provisión Vacacional', `${this.diasVacaciones} días/año`, vacaciones);

    const empresaNombre = 'E-zyro TIC';
    const fechaEmision = new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' });

    return `
    <div style="font-family:Arial,Helvetica,sans-serif;width:680px;padding:28px;color:#1e293b;">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #22c55e;padding-bottom:14px;margin-bottom:18px;">
        <div>
          <div style="font-size:18px;font-weight:800;color:#16a34a;">${empresaNombre}</div>
          <div style="font-size:11px;color:#64748b;">Boleta de Pago — Régimen Laboral MYPE (${this.regimenLabel})</div>
        </div>
        <div style="text-align:right;font-size:11px;color:#64748b;">
          <div><strong>Período:</strong> ${this.titleCase(this.labelPeriodo)}</div>
          <div><strong>Emisión:</strong> ${fechaEmision}</div>
        </div>
      </div>

      <table style="width:100%;border-collapse:collapse;margin-bottom:16px;">
        <tr>
          <td style="padding:4px 0;font-size:12px;"><strong>Trabajador:</strong> ${emp.nombreCompleto}</td>
          <td style="padding:4px 0;font-size:12px;text-align:right;"><strong>Cargo:</strong> ${emp.cargo}</td>
        </tr>
        <tr>
          <td style="padding:4px 0;font-size:12px;"><strong>Modalidad:</strong> ${this.modalidadLabel(emp)}</td>
          <td style="padding:4px 0;font-size:12px;text-align:right;"><strong>Área:</strong> ${emp.area || '—'}</td>
        </tr>
      </table>

      <table style="width:100%;border-collapse:collapse;border:1px solid #e2e8f0;border-radius:8px;overflow:hidden;">
        <tr style="background:#1e293b;">
          <td style="padding:8px 10px;font-size:10px;font-weight:700;color:#fff;text-transform:uppercase;">Concepto</td>
          <td style="padding:8px 10px;font-size:10px;font-weight:700;color:#fff;text-transform:uppercase;text-align:right;">Detalle</td>
          <td style="padding:8px 10px;font-size:10px;font-weight:700;color:#fff;text-transform:uppercase;text-align:right;">Monto</td>
        </tr>
        ${filasIngresos}
        ${filasDescuentos}
        <tr style="background:#dcfce7;border-top:2px solid #16a34a;">
          <td style="padding:10px 10px;font-size:13px;font-weight:800;color:#1e293b;">NETO A PAGAR</td>
          <td style="padding:10px 10px;font-size:10px;color:#64748b;text-align:right;">${this.formatH(emp.horas_total)} trabajadas</td>
          <td style="padding:10px 10px;font-size:15px;font-weight:800;color:#16a34a;text-align:right;">${this.formatMonto(neto)}</td>
        </tr>
      </table>

      <div style="margin-top:14px;font-size:10px;font-weight:700;text-transform:uppercase;color:#94a3b8;letter-spacing:0.4px;">Información adicional (no afecta el neto)</div>
      <table style="width:100%;border-collapse:collapse;border:1px solid #e2e8f0;border-radius:8px;overflow:hidden;margin-top:4px;">
        ${filasInformativas}
      </table>

      <div style="margin-top:18px;font-size:9px;color:#94a3b8;line-height:1.5;border-top:1px solid #e2e8f0;padding-top:10px;">
        Cálculo conforme al Régimen ${this.regimenLabel} ${this.esRegimenMype ? '(Ley N.° 28015 / D.L. N.° 1086)' : '(Régimen Laboral General)'} y D.L. N.° 854 (jornada y sobretiempo). Vacaciones: ${this.diasVacaciones} días/año.
        ${this.esPracticante(emp) ? 'El trabajador se encuentra bajo Convenio de Modalidad Formativa (Ley N.° 28518): no genera CTS, gratificación ni aporte obligatorio a pensión.' : ''}
        ${dependiente && this.regimenEmpresa === 'micro' ? 'Como Microempresa, no corresponde CTS ni gratificación (exoneración legal MYPE).' : ''}
        ${this.bajoRmv(emp) ? `<strong style="color:#dc2626;">ATENCIÓN: el sueldo base registrado está por debajo de la RMV vigente (S/ ${this.rmvVigente}). Verificar cumplimiento ante SUNAFIL.</strong>` : ''}
      </div>

      <table style="width:100%;margin-top:36px;">
        <tr>
          <td style="width:50%;text-align:center;font-size:10px;color:#64748b;">
            <div style="border-top:1px solid #94a3b8;width:80%;margin:0 auto 4px;"></div>
            Firma del Trabajador
          </td>
          <td style="width:50%;text-align:center;font-size:10px;color:#64748b;">
            <div style="border-top:1px solid #94a3b8;width:80%;margin:0 auto 4px;"></div>
            Firma del Empleador
          </td>
        </tr>
      </table>
    </div>`;
  }

  private titleCase(s: string): string {
    return s.replace(/\b\w/g, c => c.toUpperCase());
  }

  descargarPdf(emp: ResumenEmpleadoDto): void {
    if (!this.esVistaMensual) {
      this.toast.mostrar('La boleta oficial se genera en la vista "Mes Completo"', 'error');
      return;
    }
    if (this.getSueldo(emp.id) <= 0) {
      this.toast.mostrar('Ingresa el sueldo base antes de generar la boleta', 'error');
      return;
    }
    this.generandoPdf = true;
    const div = document.createElement('div');
    div.style.position = 'fixed';
    div.style.left = '-9999px';
    div.innerHTML = this.construirVoucherHtml(emp);
    document.body.appendChild(div);

    const filename = `Boleta_${emp.nombreCompleto.replace(/\s+/g, '_')}_${this.selectedYear}-${String(this.selectedMonth).padStart(2, '0')}.pdf`;

    html2pdf().set({
      margin: 0,
      filename,
      html2canvas: { scale: 2 },
      jsPDF: { unit: 'pt', format: 'a4', orientation: 'portrait' },
    }).from(div).save().then(() => {
      document.body.removeChild(div);
      this.generandoPdf = false;
      this.toast.mostrar('Boleta PDF generada', 'success');
    }).catch(() => {
      document.body.removeChild(div);
      this.generandoPdf = false;
      this.toast.mostrar('Error al generar el PDF', 'error');
    });
  }

  enviarALegajo(emp: ResumenEmpleadoDto): void {
    if (!this.esVistaMensual) {
      this.toast.mostrar('La boleta oficial se genera en la vista "Mes Completo"', 'error');
      return;
    }
    if (!this.isAdmin) {
      this.toast.mostrar('Solo un administrador puede enviar boletas al legajo digital', 'error');
      return;
    }
    if (this.getSueldo(emp.id) <= 0) {
      this.toast.mostrar('Ingresa el sueldo base antes de generar la boleta', 'error');
      return;
    }
    this.generandoPdf = true;
    const div = document.createElement('div');
    div.style.position = 'fixed';
    div.style.left = '-9999px';
    div.innerHTML = this.construirVoucherHtml(emp);
    document.body.appendChild(div);

    html2pdf().set({
      margin: 0,
      html2canvas: { scale: 2 },
      jsPDF: { unit: 'pt', format: 'a4', orientation: 'portrait' },
    }).from(div).outputPdf('blob').then((blob: Blob) => {
      document.body.removeChild(div);
      const mesLabel = MESES_ES[this.selectedMonth];
      const nombreDoc = `Boleta de Pago - ${mesLabel} ${this.selectedYear}`;
      const archivo = new File([blob], `${nombreDoc}.pdf`, { type: 'application/pdf' });

      const form = new FormData();
      form.append('tipo', 'Boleta Mensual');
      form.append('nombre', nombreDoc);
      form.append('fecha_emision', `${this.selectedYear}-${String(this.selectedMonth).padStart(2, '0')}-01`);
      form.append('requiere_firma', 'true');
      form.append('mes', String(this.selectedMonth));
      form.append('anio', String(this.selectedYear));
      form.append('archivo', archivo);

      this.svc.subirDocumento(emp.id, form).subscribe({
        next: () => {
          this.generandoPdf = false;
          this.toast.mostrar(`Boleta enviada al legajo digital de ${emp.nombreCompleto}`, 'success');
        },
        error: (err) => {
          this.generandoPdf = false;
          this.toast.mostrar(err?.error?.detail || 'Error al enviar la boleta al legajo', 'error');
        }
      });
    }).catch(() => {
      document.body.removeChild(div);
      this.generandoPdf = false;
      this.toast.mostrar('Error al generar el PDF', 'error');
    });
  }

  // ── Helpers visuales ──────────────────────────────────────────────────────

  iniciales(nombre: string): string {
    if (!nombre) return '?';
    return nombre.split(' ').slice(0, 2).map(w => w[0]).join('').toUpperCase();
  }

  estadoClass(emp: ResumenEmpleadoDto): string {
    if (this.getSueldo(emp.id) === 0) return 'badge-sin-sueldo';
    if (emp.horas_faltantes === 0)    return 'badge-success';
    if (emp.porcentaje >= 75)         return 'badge-warning';
    return 'badge-danger';
  }

  estadoLabel(emp: ResumenEmpleadoDto): string {
    if (this.getSueldo(emp.id) === 0) return 'Sin sueldo';
    if (emp.horas_faltantes === 0)    return 'Completo';
    return `−${emp.horas_faltantes.toFixed(1)}h`;
  }

  formatMonto(n: number): string {
    return new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN', minimumFractionDigits: 2 }).format(n ?? 0);
  }

  formatH(n: number): string {
    return n > 0 ? `${n.toFixed(1)}h` : '—';
  }

  private _uuidRx = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  safeArea(s: string): string {
    if (!s || this._uuidRx.test(s.trim())) return '';
    return ` · ${s}`;
  }
}

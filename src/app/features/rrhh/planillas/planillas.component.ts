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
const ASIGFAM_KEY  = 'ezp_asigfam_v1';
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
const ASIG_FAMILIAR_PCT     = 0.10;    // 10% de la RMV vigente (D.S. 035-90-TR)
const UIT_VIGENTE           = 5350;    // S/ por UIT, referencial — verificar SUNAT vigente
const RENTA_5TA_DEDUCCION_UIT = 7;     // deducción anual fija (7 UIT)
// Tramos progresivos de Renta de 5ta Categoría (sobre la base imponible anual,
// en UIT). Referencial — confirmar tasas/tramos vigentes con SUNAT.
const RENTA_5TA_TRAMOS: { limiteUit: number; tasa: number }[] = [
  { limiteUit: 5,  tasa: 0.08 },
  { limiteUit: 20, tasa: 0.14 },
  { limiteUit: 35, tasa: 0.17 },
  { limiteUit: 45, tasa: 0.20 },
  { limiteUit: Infinity, tasa: 0.30 },
];

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

  // ── Asignación Familiar (10% RMV, trabajadores con hijos a cargo) ──────────
  asigFamiliarMap: Record<string, boolean> = {};

  // ── Datos de la empresa (para el encabezado de la Planilla Mensual PDF) ────
  empresaInfo: { razon_social: string; ruc: string; regimen_tributario: string } | null = null;

  // ── Modal boleta individual ───────────────────────────────────────────────
  boletaEmp: ResumenEmpleadoDto | null = null;
  generandoPdf = false;
  generandoPlanillaPdf = false;

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
    this.asigFamiliarMap = JSON.parse(localStorage.getItem(ASIGFAM_KEY) ?? '{}');
    this.regimenEmpresa = (localStorage.getItem(REGIMEN_KEY) as Regimen) || 'micro';
    this.esquemaPago    = (localStorage.getItem(ESQUEMA_KEY) as EsquemaPago) || 'quincenal';
    if (this.esquemaPago === 'mensual') this.periodoPago = 'mes';
    this.svc.getEmpresaInfo().subscribe({
      next: (res) => { this.empresaInfo = res; },
      error: () => { this.empresaInfo = null; },
    });
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

  // ── Asignación Familiar (10% RMV, solo dependientes con hijos a cargo) ──────

  getAsigFamiliar(empId: string): boolean {
    return !!this.asigFamiliarMap[empId];
  }

  onAsigFamiliarChange(empId: string, val: boolean): void {
    this.asigFamiliarMap[empId] = val;
    localStorage.setItem(ASIGFAM_KEY, JSON.stringify(this.asigFamiliarMap));
  }

  // Monto mensual de Asignación Familiar = 10% de la RMV vigente; en vista de
  // quincena se prorratea igual que el resto de la remuneración.
  asignacionFamiliar(emp: ResumenEmpleadoDto): number {
    if (!this.esDependiente(emp) || !this.getAsigFamiliar(emp.id)) return 0;
    const mensual = RMV_VIGENTE * ASIG_FAMILIAR_PCT;
    return this.periodoPago === 'mes' ? mensual : mensual / 2;
  }

  // ── Impuesto a la Renta de 5ta Categoría (trabajadores dependientes) ────────
  // Cálculo simplificado por proyección anual: (sueldo mensual + asignación
  // familiar) × 12 − 7 UIT de deducción, tramos progresivos, entre 12. Las
  // gratificaciones están exoneradas (Ley 30334) y no se incluyen en la base.
  // Referencial — un contador debe validar la retención real de cada caso.
  impuestoQuintaCategoria(emp: ResumenEmpleadoDto): number {
    if (!this.esDependiente(emp)) return 0;
    const sueldoMensual = this.getSueldo(emp.id);
    if (sueldoMensual <= 0) return 0;
    const asigMensual = this.esDependiente(emp) && this.getAsigFamiliar(emp.id) ? RMV_VIGENTE * ASIG_FAMILIAR_PCT : 0;
    const rentaAnual = (sueldoMensual + asigMensual) * 12;
    const deduccion  = RENTA_5TA_DEDUCCION_UIT * UIT_VIGENTE;
    let baseImponible = Math.max(0, rentaAnual - deduccion);
    if (baseImponible === 0) return 0;

    let impuestoAnual = 0;
    let limiteAnterior = 0;
    for (const tramo of RENTA_5TA_TRAMOS) {
      const limiteUitSoles = tramo.limiteUit * UIT_VIGENTE;
      const montoEnTramo = Math.max(0, Math.min(baseImponible, limiteUitSoles) - limiteAnterior);
      impuestoAnual += montoEnTramo * tramo.tasa;
      limiteAnterior = limiteUitSoles;
      if (baseImponible <= limiteUitSoles) break;
    }

    const impuestoMensual = impuestoAnual / 12;
    return this.periodoPago === 'mes' ? impuestoMensual : impuestoMensual / 2;
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
    const base = this.sueldoPeriodo(emp.id) - this.descuentoFaltas(emp) + this.pagoHorasExtra(emp) + this.asignacionFamiliar(emp);
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

  // ── Motivos (por qué un beneficio sí/no aplica) — reactivos a modalidad y
  //    régimen, usados en tabla, modal "Ver" y PDF para mostrar SIEMPRE el
  //    concepto, nunca ocultarlo sin explicación. ─────────────────────────────

  motivoCTS(emp: ResumenEmpleadoDto): string {
    if (this.esPracticante(emp)) return 'No aplica — Practicante (Ley 28518)';
    if (this.regimenEmpresa === 'micro') return 'No corresponde — Microempresa (exoneración MYPE)';
    if (this.regimenEmpresa === 'general') return 'Completo — 1 remuneración/año (mayo y noviembre)';
    return 'Medio — 15 remun. diarias/año (mayo y noviembre)';
  }

  motivoGratificacion(emp: ResumenEmpleadoDto): string {
    if (this.esPracticante(emp)) return 'No aplica — Practicante (Ley 28518)';
    if (this.regimenEmpresa === 'micro') return 'No corresponde — Microempresa (exoneración MYPE)';
    if (this.regimenEmpresa === 'general') return 'Completa — 1 sueldo × semestre (julio y diciembre)';
    return 'Media — medio sueldo × semestre (julio y diciembre)';
  }

  motivoVacaciones(emp: ResumenEmpleadoDto): string {
    if (this.esPracticante(emp)) return 'Descanso de 30 días/año (sin provisión monetaria)';
    return `${this.diasVacaciones} días/año, mensualizado`;
  }

  motivoPension(emp: ResumenEmpleadoDto): string {
    if (this.esPracticante(emp)) return 'No aplica — sin afiliación obligatoria (Ley 28518)';
    return this.pensionLabel(emp);
  }

  // Resumen compacto para la columna "Beneficios" de la tabla — cambia en vivo
  // según régimen y modalidad sin recargar datos.
  beneficiosResumen(emp: ResumenEmpleadoDto): { cts: boolean; grati: boolean; vac: number; aplica: boolean } {
    return {
      cts:    this.provisionCTS(emp) > 0,
      grati:  this.provisionGratificacion(emp) > 0,
      vac:    this.esDependiente(emp) ? this.diasVacaciones : 30,
      aplica: this.esDependiente(emp),
    };
  }

  netoAPagar(emp: ResumenEmpleadoDto): number {
    const sueldo = this.sueldoPeriodo(emp.id);
    if (sueldo <= 0) return 0;
    return Math.max(0, this.totalIngresos(emp) - this.totalDescuentosLegales(emp));
  }

  totalDescuentosLegales(emp: ResumenEmpleadoDto): number {
    return this.descuentoFaltas(emp) + this.descuentoPension(emp) + this.impuestoQuintaCategoria(emp);
  }

  totalIngresos(emp: ResumenEmpleadoDto): number {
    return this.sueldoPeriodo(emp.id) + this.pagoHorasExtra(emp) + this.asignacionFamiliar(emp);
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

    const asig = this.asignacionFamiliar(emp);
    const renta = this.impuestoQuintaCategoria(emp);

    let filasIngresos = filaIngreso('Sueldo Base', `${this.formatH(emp.meta_horas)} estándar`, sueldo);
    if (extra > 0) {
      const detalleExtra = dependiente
        ? (this.horasExtra(emp) <= 2 ? `${this.formatH(this.horasExtra(emp))} × 25%` : `2h×25% + ${this.formatH(this.horasExtra(emp) - 2)}×35%`)
        : `${this.formatH(this.horasExtra(emp))} tarifa simple`;
      filasIngresos += filaIngreso(`Horas Extra (${this.formatH(this.horasExtra(emp))})`, detalleExtra, extra);
    }
    if (asig > 0) {
      filasIngresos += filaIngreso('Asignación Familiar', '10% RMV vigente', asig);
    }

    const filaSinMonto = (label: string, motivo: string) => `
      <tr style="background:#f8fafc;">
        <td style="padding:8px 10px;font-size:11px;color:#94a3b8;">${label}</td>
        <td style="padding:8px 10px;font-size:10px;color:#94a3b8;text-align:right;" colspan="2">${motivo}</td>
      </tr>`;

    let filasDescuentos = '';
    if (descFaltas > 0) {
      filasDescuentos += filaDescuento('Descuento por Faltas/Tardanzas', `${this.formatH(emp.horas_faltantes)} × ${this.formatMonto(this.valorHora(emp))}/h`, descFaltas);
    }
    // Pensión: SIEMPRE se muestra, con monto o con el motivo por el que no aplica.
    if (descPension > 0) {
      filasDescuentos += filaDescuento(`Sistema de Pensión (${this.pensionLabel(emp)})`, 'Ley N.° 19990 / D.L. 25897', descPension);
    } else {
      filasDescuentos += filaSinMonto('Sistema de Pensión', this.motivoPension(emp));
    }
    if (renta > 0) {
      filasDescuentos += filaDescuento('Renta de 5ta Categoría', 'Referencial — verificar con contador', renta);
    }

    // Aportes patronales y provisiones: SIEMPRE visibles (con monto o motivo).
    let filasInformativas = filaInfo('Aporte EsSalud (empleador)', 'No descontado al trabajador', essalud);
    filasInformativas += cts > 0
      ? filaInfo('Provisión CTS', `${this.regimenLabel} · ${this.regimenEmpresa === 'general' ? '1 remuneración/año' : '15 rem. diarias/año'}`, cts)
      : filaSinMonto('Provisión CTS', this.motivoCTS(emp));
    filasInformativas += grati > 0
      ? filaInfo('Provisión Gratificación', `${this.regimenLabel} · ${this.regimenEmpresa === 'general' ? 'sueldo completo/semestre' : 'medio sueldo/semestre'}`, grati)
      : filaSinMonto('Provisión Gratificación', this.motivoGratificacion(emp));
    filasInformativas += vacaciones > 0
      ? filaInfo('Provisión Vacacional', `${this.diasVacaciones} días/año`, vacaciones)
      : filaSinMonto('Provisión Vacacional', this.motivoVacaciones(emp));

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

      <div style="font-size:10px;font-weight:700;text-transform:uppercase;color:#16a34a;letter-spacing:0.4px;margin-bottom:4px;">Ingresos</div>
      <table style="width:100%;border-collapse:collapse;border:1px solid #e2e8f0;border-radius:8px;overflow:hidden;margin-bottom:14px;">
        <tr style="background:#1e293b;">
          <td style="padding:8px 10px;font-size:10px;font-weight:700;color:#fff;text-transform:uppercase;">Concepto</td>
          <td style="padding:8px 10px;font-size:10px;font-weight:700;color:#fff;text-transform:uppercase;text-align:right;">Detalle</td>
          <td style="padding:8px 10px;font-size:10px;font-weight:700;color:#fff;text-transform:uppercase;text-align:right;">Monto</td>
        </tr>
        ${filasIngresos}
        <tr style="background:#f0fdf4;border-top:1px solid #bbf7d0;">
          <td style="padding:8px 10px;font-size:11px;font-weight:800;color:#1e293b;" colspan="2">TOTAL INGRESOS</td>
          <td style="padding:8px 10px;font-size:12px;font-weight:800;color:#16a34a;text-align:right;">${this.formatMonto(this.totalIngresos(emp))}</td>
        </tr>
      </table>

      <div style="font-size:10px;font-weight:700;text-transform:uppercase;color:#dc2626;letter-spacing:0.4px;margin-bottom:4px;">Descuentos</div>
      <table style="width:100%;border-collapse:collapse;border:1px solid #e2e8f0;border-radius:8px;overflow:hidden;margin-bottom:14px;">
        <tr style="background:#1e293b;">
          <td style="padding:8px 10px;font-size:10px;font-weight:700;color:#fff;text-transform:uppercase;">Concepto</td>
          <td style="padding:8px 10px;font-size:10px;font-weight:700;color:#fff;text-transform:uppercase;text-align:right;">Detalle</td>
          <td style="padding:8px 10px;font-size:10px;font-weight:700;color:#fff;text-transform:uppercase;text-align:right;">Monto</td>
        </tr>
        ${filasDescuentos}
        <tr style="background:#fef2f2;border-top:1px solid #fecaca;">
          <td style="padding:8px 10px;font-size:11px;font-weight:800;color:#1e293b;" colspan="2">TOTAL DESCUENTOS</td>
          <td style="padding:8px 10px;font-size:12px;font-weight:800;color:#dc2626;text-align:right;">−${this.formatMonto(this.totalDescuentosLegales(emp))}</td>
        </tr>
      </table>

      <table style="width:100%;border-collapse:collapse;border:2px solid #16a34a;border-radius:8px;overflow:hidden;margin-bottom:14px;">
        <tr style="background:#dcfce7;">
          <td style="padding:12px 14px;font-size:14px;font-weight:800;color:#1e293b;">NETO A PAGAR</td>
          <td style="padding:12px 14px;font-size:10px;color:#64748b;text-align:right;">${this.formatH(emp.horas_total)} trabajadas</td>
          <td style="padding:12px 14px;font-size:17px;font-weight:800;color:#16a34a;text-align:right;">${this.formatMonto(neto)}</td>
        </tr>
      </table>

      <div style="margin-top:6px;font-size:10px;font-weight:700;text-transform:uppercase;color:#94a3b8;letter-spacing:0.4px;">Beneficios y aportes (no afectan el neto)</div>
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

  // Crea el nodo del voucher y espera a que el navegador termine el
  // layout/paint antes de devolverlo. IMPORTANTE: html2canvas tiene un bug
  // conocido al capturar elementos con `position: fixed` combinados con
  // opacidad casi cero — el resultado es un PDF en blanco. Por eso el nodo
  // se agrega en flujo normal (sin position/opacity), simplemente al final
  // del body: queda fuera de la vista (debajo del contenido visible) sin
  // necesidad de trucos que rompan la captura.
  private async crearDivVoucher(emp: ResumenEmpleadoDto): Promise<HTMLElement> {
    const div = document.createElement('div');
    div.style.pointerEvents = 'none';
    div.innerHTML = this.construirVoucherHtml(emp);
    document.body.appendChild(div);
    await new Promise<void>(resolve => {
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
    });
    return div;
  }

  // Nombre de archivo: boleta_<primer-nombre>_<DDMMYYYY> (fecha de emisión)
  private nombreArchivoBoleta(emp: ResumenEmpleadoDto): string {
    const primerNombre = (emp.nombreCompleto || 'trabajador').trim().split(/\s+/)[0]
      .toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
    const hoy = new Date();
    const dd = String(hoy.getDate()).padStart(2, '0');
    const mm = String(hoy.getMonth() + 1).padStart(2, '0');
    const yyyy = hoy.getFullYear();
    return `boleta_${primerNombre}_${dd}${mm}${yyyy}`;
  }

  async descargarPdf(emp: ResumenEmpleadoDto): Promise<void> {
    if (!this.esVistaMensual) {
      this.toast.mostrar('La boleta oficial se genera en la vista "Mes Completo"', 'error');
      return;
    }
    if (this.getSueldo(emp.id) <= 0) {
      this.toast.mostrar('Ingresa el sueldo base antes de generar la boleta', 'error');
      return;
    }
    this.generandoPdf = true;
    const div = await this.crearDivVoucher(emp);
    const filename = `${this.nombreArchivoBoleta(emp)}.pdf`;

    try {
      await html2pdf().set({
        margin: 0,
        filename,
        html2canvas: { scale: 2, useCORS: true, backgroundColor: '#ffffff' },
        jsPDF: { unit: 'pt', format: 'a4', orientation: 'portrait' },
      }).from(div).save();
      this.toast.mostrar('Boleta PDF generada', 'success');
    } catch {
      this.toast.mostrar('Error al generar el PDF', 'error');
    } finally {
      document.body.removeChild(div);
      this.generandoPdf = false;
    }
  }

  async enviarALegajo(emp: ResumenEmpleadoDto): Promise<void> {
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
    const div = await this.crearDivVoucher(emp);

    try {
      const blob: Blob = await html2pdf().set({
        margin: 0,
        html2canvas: { scale: 2, useCORS: true, backgroundColor: '#ffffff' },
        jsPDF: { unit: 'pt', format: 'a4', orientation: 'portrait' },
      }).from(div).outputPdf('blob');

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
    } catch {
      this.generandoPdf = false;
      this.toast.mostrar('Error al generar el PDF', 'error');
    } finally {
      document.body.removeChild(div);
    }
  }

  // ── Planilla Mensual de Remuneraciones (PDF consolidado, blanco y negro) ────
  // Registro formal de todos los trabajadores del mes en una sola hoja,
  // análogo al formato estándar de planilla MYPE: documento, datos, ingresos,
  // descuentos, neto y aporte patronal, con totales generales y firmas.

  private fechaCorta(iso: string | null): string {
    if (!iso) return '—';
    const d = new Date(iso + 'T00:00:00');
    return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
  }

  private fetchTodosEmpleadosMes(): Promise<ResumenEmpleadoDto[]> {
    return new Promise((resolve, reject) => {
      this.svc.getResumenAsistencia({
        fecha_inicio: `${this.selectedYear}-${String(this.selectedMonth).padStart(2, '0')}-01`,
        fecha_fin:    new Date(this.selectedYear, this.selectedMonth, 0).toISOString().split('T')[0],
        page:  1,
        limit: 500,
      }).subscribe({
        next: (res) => resolve(res.empleados ?? []),
        error: (err) => reject(err),
      });
    });
  }

  private construirPlanillaMensualHtml(lista: ResumenEmpleadoDto[]): string {
    const num = (n: number) => n.toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

    const razonSocial = this.empresaInfo?.razon_social || 'E-ZYRO TIC';
    const ruc = this.empresaInfo?.ruc || '—';
    const hoy = new Date();

    let totBasico = 0, totAsig = 0, totExtra = 0, totBruto = 0,
        totPension = 0, totRenta = 0, totDescto = 0, totNeto = 0, totEssalud = 0;

    const filas = lista.map((emp, i) => {
      const sueldoMostrado = this.sueldoPeriodoMostrar(emp);
      const asig    = this.asignacionFamiliar(emp);
      const extra   = this.pagoHorasExtra(emp);
      const bruto   = this.totalIngresos(emp);
      const pension = this.descuentoPension(emp);
      const renta   = this.impuestoQuintaCategoria(emp);
      const descto  = pension + renta;
      const neto    = this.netoAPagar(emp);
      const essalud = this.aporteEssalud(emp);

      totBasico += sueldoMostrado; totAsig += asig; totExtra += extra; totBruto += bruto;
      totPension += pension; totRenta += renta; totDescto += descto; totNeto += neto; totEssalud += essalud;

      return `
      <tr>
        <td class="c">${String(i + 1).padStart(2, '0')}</td>
        <td class="c">${emp.codigo || '—'}</td>
        <td class="izq">${emp.nombreCompleto}</td>
        <td class="izq">${emp.cargo}</td>
        <td class="c">${this.fechaCorta(emp.fecha_ingreso)}</td>
        <td class="m">${num(sueldoMostrado)}</td>
        <td class="m">${num(asig)}</td>
        <td class="m">${num(extra)}</td>
        <td class="m strong">${num(bruto)}</td>
        <td class="m">${num(pension)}</td>
        <td class="m">${num(renta)}</td>
        <td class="m strong">${num(descto)}</td>
        <td class="m strong">${num(neto)}</td>
        <td class="m">${num(essalud)}</td>
      </tr>`;
    }).join('');

    return `
    <div class="hoja">
      <div class="cab">
        <div>
          <div class="empresa">${razonSocial.toUpperCase()}</div>
          <div class="sub">Sistema de Gestión Empresarial</div>
          <div class="sub">RUC: ${ruc} | Régimen ${this.regimenLabel}</div>
        </div>
        <div class="cab-der">
          <div class="titulo">PLANILLA MENSUAL DE REMUNERACIONES</div>
          <div class="sub">Periodo Laboral: <strong>${this.titleCase(this.labelPeriodo)}</strong> &nbsp;|&nbsp; <strong>${this.esRegimenMype ? 'MYPE' : 'GENERAL'}</strong></div>
        </div>
      </div>

      <table class="reg">
        <thead>
          <tr>
            <th rowspan="2">N°</th>
            <th rowspan="2">Código</th>
            <th rowspan="2">Apellidos y Nombres</th>
            <th rowspan="2">Cargo u Ocupación</th>
            <th rowspan="2">Fecha<br>Ingreso</th>
            <th colspan="4">Ingresos (S/.)</th>
            <th colspan="3">Descuentos del Trabajador (S/.)</th>
            <th rowspan="2">Neto a<br>Pagar (S/.)</th>
            <th rowspan="2">Aporte (S/.)</th>
          </tr>
          <tr>
            <th>Sueldo<br>Básico</th>
            <th>Asig.<br>Fam.</th>
            <th>Horas<br>Extra</th>
            <th>Total<br>Bruto</th>
            <th>Pensiones<br>(AFP/ONP)</th>
            <th>Renta<br>5ta Cat.</th>
            <th>Total<br>Descto.</th>
            <th>EsSalud<br>(9%)</th>
          </tr>
        </thead>
        <tbody>
          ${filas || '<tr><td colspan="14" class="c">Sin empleados en este período</td></tr>'}
        </tbody>
        <tfoot>
          <tr>
            <td colspan="5" class="izq strong">TOTALES GENERALES</td>
            <td class="m strong">${num(totBasico)}</td>
            <td class="m strong">${num(totAsig)}</td>
            <td class="m strong">${num(totExtra)}</td>
            <td class="m strong">${num(totBruto)}</td>
            <td class="m strong">${num(totPension)}</td>
            <td class="m strong">${num(totRenta)}</td>
            <td class="m strong">${num(totDescto)}</td>
            <td class="m strong">${num(totNeto)}</td>
            <td class="m strong">${num(totEssalud)}</td>
          </tr>
        </tfoot>
      </table>

      <div class="nota">
        <strong>Nota informativa de Régimen ${this.regimenLabel}:</strong>
        ${this.esRegimenMype
          ? 'Conforme a la Ley N.° 28015 / D.L. N.° 1086, las micro y pequeñas empresas cuentan con tasas y beneficios laborales especiales.'
          : 'Trabajadores bajo Régimen Laboral General, con beneficios completos de CTS, gratificación y 30 días de vacaciones anuales.'}
        La asignación familiar (10% de la RMV vigente, S/ ${num(RMV_VIGENTE * ASIG_FAMILIAR_PCT)}) corresponde a los trabajadores con hijos menores o universitarios a cargo.
        El aporte a EsSalud equivale al 9% de la remuneración bruta. La Renta de 5ta Categoría y las tasas de AFP/ONP son referenciales — corresponde validarlas con el contador de la empresa antes de su uso oficial.
      </div>

      <div class="firmas">
        <div class="firma-bloque">
          <div class="firma-linea"></div>
          <div class="firma-cargo">Gerencia General</div>
          <div class="firma-sub">${razonSocial.toUpperCase()}</div>
        </div>
        <div class="firma-bloque">
          <div class="firma-linea"></div>
          <div class="firma-cargo">Contador General</div>
          <div class="firma-sub">Reg. CPC N.° ___________</div>
        </div>
      </div>

      <div class="pie">Generado el ${this.fechaCorta(hoy.toISOString().split('T')[0])} &nbsp;|&nbsp; Página 1 de 1</div>
    </div>`;
  }

  // El sueldo "informativo" de la planilla consolidada muestra el sueldo
  // base del período (sin descontar faltas aquí: las faltas restan dentro
  // del total bruto vía horas extra/pensión en el resto del sistema, pero en
  // este registro formal se expone el básico pactado tal cual se acordó).
  private sueldoPeriodoMostrar(emp: ResumenEmpleadoDto): number {
    return Math.max(0, this.sueldoPeriodo(emp.id) - this.descuentoFaltas(emp));
  }

  async descargarPlanillaMensual(): Promise<void> {
    if (!this.esVistaMensual) {
      this.toast.mostrar('La Planilla Mensual se genera en la vista "Mes Completo"', 'error');
      return;
    }
    this.generandoPlanillaPdf = true;
    try {
      const lista = await this.fetchTodosEmpleadosMes();
      const div = document.createElement('div');
      div.style.pointerEvents = 'none';
      div.innerHTML = `<style>${this.estilosPlanillaMensual()}</style>${this.construirPlanillaMensualHtml(lista)}`;
      document.body.appendChild(div);
      await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));

      const filename = `planilla_mensual_${this.selectedYear}${String(this.selectedMonth).padStart(2, '0')}.pdf`;
      await html2pdf().set({
        margin: 20,
        filename,
        html2canvas: { scale: 2, useCORS: true, backgroundColor: '#ffffff' },
        jsPDF: { unit: 'pt', format: 'a4', orientation: 'landscape' },
      }).from(div).save();

      document.body.removeChild(div);
      this.toast.mostrar('Planilla mensual generada', 'success');
    } catch {
      this.toast.mostrar('Error al generar la planilla mensual', 'error');
    } finally {
      this.generandoPlanillaPdf = false;
    }
  }

  private estilosPlanillaMensual(): string {
    return `
      .hoja { font-family: 'Times New Roman', Times, serif; width: 1000px; color: #000; padding: 10px; }
      .cab { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #000; padding-bottom: 10px; margin-bottom: 12px; }
      .empresa { font-size: 18px; font-weight: 700; letter-spacing: 0.5px; }
      .sub { font-size: 11px; color: #000; margin-top: 2px; }
      .cab-der { text-align: right; }
      .titulo { font-size: 14px; font-weight: 700; letter-spacing: 0.4px; }
      .reg { width: 100%; border-collapse: collapse; font-size: 10px; margin-bottom: 10px; }
      .reg th, .reg td { border: 1px solid #000; padding: 5px 6px; }
      .reg thead th { background: #e5e5e5; font-weight: 700; text-align: center; font-size: 9.5px; }
      .reg tfoot td { background: #e5e5e5; }
      .c { text-align: center; }
      .izq { text-align: left; }
      .m { text-align: right; }
      .strong { font-weight: 700; }
      .nota { font-size: 9.5px; line-height: 1.5; border-left: 3px solid #000; padding: 8px 12px; margin-bottom: 26px; background: #f5f5f5; }
      .firmas { display: flex; justify-content: space-between; margin-top: 10px; }
      .firma-bloque { width: 260px; text-align: center; }
      .firma-linea { border-top: 1px solid #000; margin-bottom: 4px; }
      .firma-cargo { font-size: 11px; font-weight: 700; }
      .firma-sub { font-size: 10px; }
      .pie { text-align: right; font-size: 9px; color: #444; margin-top: 18px; }
    `;
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

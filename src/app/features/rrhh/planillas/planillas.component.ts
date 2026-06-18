import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RrhhService, ResumenEmpleadoDto, PeriodoDto } from '../../../core/services/rrhh.service';
import { ToastService } from '../../../core/services/toast.service';
import { AuthService } from '../../../core/services/auth.service';
import { AppModalComponent } from '../../../shared/components/modal/app-modal.component';
import html2pdf from 'html2pdf.js';

const SUELDO_KEY       = 'ezp_sueldos_v1';
const REGIMEN_KEY      = 'ezp_regimen_v1';
const PENSION_KEY      = 'ezp_pensiones_v1';
const AFP_KEY          = 'ezp_afp_entidad_v1';
const AFP_COMISION_KEY = 'ezp_afp_comision_v1';
const ESQUEMA_KEY      = 'ezp_esquema_pago_v1';
const ASIGFAM_KEY      = 'ezp_asigfam_v1';
const CUSPP_KEY        = 'ezp_cuspp_v1';
const PER_PAGE         = 10;

// Divisores legales peruanos (D.L. 854, MTPE) — fijos por norma, no por calendario.
const DIVISOR_DIA  = 30;   // valor día = sueldo mensual / 30, siempre
const HORAS_JORNADA = 8;   // jornada ordinaria máxima diaria

const MESES_ES = [
  '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

// ── Parámetros legales vigentes 2026 (Perú) ───────────────────────────────
//    Fuentes: SUNAFIL, MTPE, SUNAT, SBS, Ley N.° 32353 (nueva clasificación
//    empresarial), D.L. 19990 (ONP), D.L. 25897 (AFP), D.L. 854 (jornada),
//    Ley 28518 (modalidades formativas), D.S. 035-90-TR (asignación familiar).
//    Verificar vigencia antes de procesar planilla real. ─────────────────────
const PENSION_ONP_PCT       = 0.13;    // ONP: aporte único fijo (D.L. 19990)
const AFP_APORTE_PCT        = 0.10;    // AFP: aporte obligatorio a cuenta individual (D.L. 25897)
const AFP_SEGURO_PCT        = 0.0137;  // AFP: prima de seguro 2026 — 1.37% (tope S/ 12,209.11)
const ESSALUD_PCT           = 0.09;    // EsSalud: aporte patronal 9% — NO se descuenta al trabajador (Ley 26790)
const RMV_VIGENTE           = 1130;    // RMV vigente desde enero 2025 (D.S. 001-2025-TR)
const CTS_PEQUENA_FACTOR    = 1 / 24;  // Pequeña Empresa: 15 rem. diarias/año mensualizado (tope 90 días)
const GRATIF_PEQUENA_FACTOR = 1 / 12;  // Pequeña Empresa: 2 medias remun./año mensualizado
const CTS_GENERAL_FACTOR    = 1 / 12;  // Régimen General: 1 remuneración/año mensualizado
const GRATIF_GENERAL_FACTOR = 1 / 6;   // Régimen General: 2 sueldos completos/año mensualizado
const VACACIONES_DIAS_MYPE  = 15;      // Micro y Pequeña Empresa: 15 días/año (Ley N.° 32353)
const VACACIONES_DIAS_GENERAL = 30;    // Régimen General: 30 días/año
const ASIG_FAMILIAR_PCT     = 0.10;    // 10% RMV = S/ 113.00 — SOLO Régimen General (D.S. 035-90-TR)
const UIT_VIGENTE           = 5500;    // UIT 2026 (R.M. de SUNAT)
const RENTA_5TA_DEDUCCION_UIT = 7;     // Deducción anual: 7 UIT = S/ 38,500 (2026)
// Tramos progresivos Renta de 5ta Categoría (base imponible anual en UIT — SUNAT 2026)
const RENTA_5TA_TRAMOS: { limiteUit: number; tasa: number }[] = [
  { limiteUit: 5,        tasa: 0.08 },
  { limiteUit: 20,       tasa: 0.14 },
  { limiteUit: 35,       tasa: 0.17 },
  { limiteUit: 45,       tasa: 0.20 },
  { limiteUit: Infinity, tasa: 0.30 },
];

// Comisión por flujo de cada AFP (2026, modalidad flujo — verificar SBS)
const AFP_COMISIONES: Record<AfpEntidad, number> = {
  integra:    0.0155,  // 1.55%
  prima:      0.0160,  // 1.60%
  profuturo:  0.0169,  // 1.69%
  habitat:    0.0147,  // 1.47%
};

type Regimen = 'micro' | 'pequena' | 'general';
type Pension = 'onp' | 'afp';
type AfpEntidad = 'integra' | 'prima' | 'profuturo' | 'habitat';
type PeriodoPago = 'q1' | 'q2' | 'mes';
type EsquemaPago = 'quincenal' | 'mensual';

@Component({
  selector: 'app-planillas',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
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

  // ── CUSPP: Código Único de Seguro Previsional Privado (D.S. N.° 001-98-TR) ─
  cusppMap: Record<string, string> = {};
  showCusppMap: Record<string, boolean> = {};

  // ── Comisión AFP personalizada (% flujo): permite sobrescribir la tabla estándar
  afpComisionCustomMap: Record<string, number> = {};

  // ── Modal confirmación cambio AFP entidad ─────────────────────────────────
  afpConfirmOpen    = false;
  afpConfirmEmpId   = '';
  afpConfirmNewVal: AfpEntidad = 'integra';
  afpConfirmLabel   = '';

  // ── Datos de la empresa (para el encabezado de la Planilla Mensual PDF) ────
  empresaInfo: { razon_social: string; ruc: string; regimen_tributario: string; direccion?: string; telefono?: string } | null = null;

  // ── Modal boleta individual ───────────────────────────────────────────────
  boletaEmp: ResumenEmpleadoDto | null = null;
  generandoPdf = false;

  // ── Envío masivo a Legajo Digital ─────────────────────────────────────────
  selectedLegajoMap: Record<string, boolean> = {};
  enviandoMasivo = false;
  masivoProgreso = '';

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
    this.sueldoMap           = JSON.parse(localStorage.getItem(SUELDO_KEY) ?? '{}');
    this.pensionMap          = JSON.parse(localStorage.getItem(PENSION_KEY) ?? '{}');
    this.afpEntidadMap       = JSON.parse(localStorage.getItem(AFP_KEY) ?? '{}');
    this.afpComisionCustomMap = JSON.parse(localStorage.getItem(AFP_COMISION_KEY) ?? '{}');
    this.asigFamiliarMap     = JSON.parse(localStorage.getItem(ASIGFAM_KEY) ?? '{}');
    this.cusppMap            = JSON.parse(localStorage.getItem(CUSPP_KEY) ?? '{}');
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
        // Pre-poblar CUSPP desde BD solo si el empleado aún no tiene valor local
        for (const emp of res.empleados) {
          if (emp.cuspp && !this.cusppMap[emp.id]) {
            this.cusppMap[emp.id] = emp.cuspp;
          }
        }
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
    const actual = this.getAfpEntidad(empId);
    if (actual === val) return;
    // Abrir modal de confirmación en lugar de confirm() nativo del navegador
    this.afpConfirmEmpId  = empId;
    this.afpConfirmNewVal = val;
    this.afpConfirmLabel  = this.afpEntidades.find(a => a.value === val)?.label ?? val;
    this.afpConfirmOpen   = true;
  }

  confirmarCambioAfp(): void {
    this.afpEntidadMap[this.afpConfirmEmpId] = this.afpConfirmNewVal;
    localStorage.setItem(AFP_KEY, JSON.stringify(this.afpEntidadMap));
    this.afpConfirmOpen = false;
    this.toast.mostrar(`AFP actualizada a ${this.afpConfirmLabel} — aplica desde ahora`, 'success');
  }

  cancelarCambioAfp(): void {
    // El select vuelve al valor previo al cerrarse el modal (Angular lo re-renderiza
    // con el valor de afpEntidadMap que no fue modificado).
    this.afpConfirmOpen = false;
  }

  // Retorna la comisión AFP efectiva: personalizada si el usuario la sobreescribió,
  // de lo contrario la tasa estándar de la entidad seleccionada.
  getAfpComisionPct(empId: string): number {
    if (this.afpComisionCustomMap[empId] !== undefined) return this.afpComisionCustomMap[empId];
    return AFP_COMISIONES[this.getAfpEntidad(empId)];
  }

  onAfpComisionChange(empId: string, raw: string): void {
    const pct = parseFloat(String(raw).replace(/[^0-9.]/g, '')) / 100;
    if (isNaN(pct) || pct < 0 || pct > 0.5) return;
    this.afpComisionCustomMap[empId] = pct;
    localStorage.setItem(AFP_COMISION_KEY, JSON.stringify(this.afpComisionCustomMap));
    this.toast.mostrar(`Comisión AFP actualizada a ${(pct * 100).toFixed(2)}% — aplica desde ahora`, 'success');
  }

  // ── CUSPP ─────────────────────────────────────────────────────────────────

  getCuspp(empId: string): string {
    return this.cusppMap[empId] ?? '';
  }

  setCuspp(empId: string, val: string): void {
    this.cusppMap[empId] = val.trim().toUpperCase();
    localStorage.setItem(CUSPP_KEY, JSON.stringify(this.cusppMap));
  }

  // Guarda el CUSPP al backend cuando el campo pierde el foco
  guardarCuspp(empId: string, val: string): void {
    const cuspp = val.trim().toUpperCase();
    this.cusppMap[empId] = cuspp;
    localStorage.setItem(CUSPP_KEY, JSON.stringify(this.cusppMap));
    this.svc.actualizarPerfilEmpleado(empId, { cuspp }).subscribe({
      next: () => this.toast.mostrar('CUSPP guardado', 'success'),
      error: () => this.toast.mostrar('Error al guardar el CUSPP — se mantiene localmente', 'error'),
    });
  }

  toggleShowCuspp(empId: string): void {
    this.showCusppMap = { ...this.showCusppMap, [empId]: !this.showCusppMap[empId] };
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

  // Asignación Familiar: 10% de la RMV (S/ 113.00 en 2026).
  // Según D.S. N.° 035-90-TR y la Ley N.° 32353, solo corresponde al
  // Régimen General. Micro y Pequeña Empresa están exoneradas.
  asignacionFamiliar(emp: ResumenEmpleadoDto): number {
    if (!this.esDependiente(emp)) return 0;
    if (this.regimenEmpresa !== 'general') return 0;
    if (!this.getAsigFamiliar(emp.id)) return 0;
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
  // Divisores legales fijos: valor día = sueldo / 30, valor hora = valor día / 8,
  // valor minuto = valor hora / 60. El divisor 30 es fijo por norma (no varía según
  // los días del mes) y aplica tanto en quincena como en mes completo.

  valorDia(emp: ResumenEmpleadoDto): number {
    return this.getSueldo(emp.id) / DIVISOR_DIA;
  }

  valorHora(emp: ResumenEmpleadoDto): number {
    return this.valorDia(emp) / HORAS_JORNADA;
  }

  valorMinuto(emp: ResumenEmpleadoDto): number {
    return this.valorHora(emp) / 60;
  }

  // Días de ausencia completa (jornada = 8h). Tardanzas son la fracción restante.
  diasFaltantes(emp: ResumenEmpleadoDto): number {
    return Math.floor(emp.horas_faltantes / HORAS_JORNADA);
  }

  minutosTardanza(emp: ResumenEmpleadoDto): number {
    return Math.round((emp.horas_faltantes % HORAS_JORNADA) * 60);
  }

  // Descuento dominical: por cada día de inasistencia injustificada se pierde
  // el descanso dominical de esa semana (D.S. 001-96-TR). Monto = valorDía / 30.
  descuentoDominical(emp: ResumenEmpleadoDto): number {
    return this.diasFaltantes(emp) * this.valorDia(emp) / DIVISOR_DIA;
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
    if (this.esPracticante(emp)) return extras * vh;
    const h1 = Math.min(extras, 2) * vh * 1.25;
    const h2 = Math.max(0, extras - 2) * vh * 1.35;
    return h1 + h2;
  }

  // Descuento total por faltas y tardanzas:
  //   · diasFaltantes × valorDía          (jornadas no laboradas)
  //   · diasFaltantes × valorDía / 30     (castigo dominical, D.S. 001-96-TR)
  //   · minutosTardanza × valorMinuto     (tardanzas parciales)
  descuentoFaltas(emp: ResumenEmpleadoDto): number {
    if (emp.horas_faltantes <= 0) return 0;
    const vd = this.valorDia(emp);
    const diasDesc    = this.diasFaltantes(emp) * vd;
    const dominical   = this.descuentoDominical(emp);
    const tardanzaDesc = this.minutosTardanza(emp) * this.valorMinuto(emp);
    return diasDesc + dominical + tardanzaDesc;
  }

  // Descuento por sistema de pensiones (ONP/AFP): obligatorio solo para
  // trabajadores dependientes (planilla/contrato). Los practicantes, bajo la
  // Ley de Modalidades Formativas (28518), no tienen relación laboral y no
  // están afiliados obligatoriamente.
  // Base imponible para el aporte a pensiones (remuneración computable del período).
  basePension(emp: ResumenEmpleadoDto): number {
    if (!this.esDependiente(emp)) return 0;
    const base = this.sueldoPeriodo(emp.id) - this.descuentoFaltas(emp) + this.pagoHorasExtra(emp) + this.asignacionFamiliar(emp);
    return Math.max(0, base);
  }

  descuentoPension(emp: ResumenEmpleadoDto): number {
    if (!this.esDependiente(emp)) return 0;
    return this.basePension(emp) * this.pensionPct(emp);
  }

  // ── Desglose del Sistema Privado de Pensiones (AFP) en sus 3 componentes ────
  // Estándar de boleta peruana: Aporte Obligatorio (10%), Prima de Seguro y
  // Comisión de la AFP por separado. Solo aplica a dependientes afiliados a AFP;
  // en ONP el aporte es único (13%). La suma de los tres = descuentoPension.
  esAfp(emp: ResumenEmpleadoDto): boolean {
    return this.esDependiente(emp) && this.getPension(emp.id) === 'afp';
  }

  afpAporteObligatorio(emp: ResumenEmpleadoDto): number {
    return this.esAfp(emp) ? this.basePension(emp) * AFP_APORTE_PCT : 0;
  }

  afpPrimaSeguro(emp: ResumenEmpleadoDto): number {
    return this.esAfp(emp) ? this.basePension(emp) * AFP_SEGURO_PCT : 0;
  }

  afpComision(emp: ResumenEmpleadoDto): number {
    return this.esAfp(emp) ? this.basePension(emp) * this.getAfpComisionPct(emp.id) : 0;
  }

  afpComisionPct(emp: ResumenEmpleadoDto): number {
    return this.getAfpComisionPct(emp.id);
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

  // ── Selección masiva para Legajo Digital ──────────────────────────────────

  get selectedLegajoCount(): number {
    return Object.values(this.selectedLegajoMap).filter(Boolean).length;
  }

  get allPageSelected(): boolean {
    return this.empleados.length > 0 && this.empleados.every(e => !!this.selectedLegajoMap[e.id]);
  }

  toggleLegajoSelect(empId: string): void {
    this.selectedLegajoMap = { ...this.selectedLegajoMap, [empId]: !this.selectedLegajoMap[empId] };
  }

  toggleSelectAllPage(): void {
    const all = this.allPageSelected;
    const next: Record<string, boolean> = { ...this.selectedLegajoMap };
    this.empleados.forEach(e => { next[e.id] = !all; });
    this.selectedLegajoMap = next;
  }

  async enviarLegajoMasivo(): Promise<void> {
    if (!this.isAdmin || !this.esVistaMensual) return;
    this.enviandoMasivo = true;

    if (this.selectedLegajoCount === 0) {
      this.masivoProgreso = 'Cargando lista de empleados…';
      this.svc.getResumenAsistencia({
        fecha_inicio: this.fechaInicio,
        fecha_fin:    this.fechaFin,
        page: 1,
        limit: 1000,
      }).subscribe({
        next: async (res) => {
          const validos = res.empleados.filter(e => this.getSueldo(e.id) > 0);
          if (validos.length === 0) {
            this.enviandoMasivo = false;
            this.masivoProgreso = '';
            this.toast.mostrar('Ningún empleado tiene sueldo registrado este período', 'error');
            return;
          }
          await this.procesarEnvioMasivo(validos);
        },
        error: () => {
          this.enviandoMasivo = false;
          this.masivoProgreso = '';
          this.toast.mostrar('Error al cargar la lista de empleados', 'error');
        }
      });
    } else {
      const selIds = new Set(
        Object.entries(this.selectedLegajoMap).filter(([, v]) => v).map(([k]) => k)
      );
      const validos = this.empleados.filter(e => selIds.has(e.id) && this.getSueldo(e.id) > 0);
      if (validos.length === 0) {
        this.enviandoMasivo = false;
        this.toast.mostrar('Los empleados seleccionados no tienen sueldo registrado', 'error');
        return;
      }
      await this.procesarEnvioMasivo(validos);
    }
  }

  private async procesarEnvioMasivo(emps: ResumenEmpleadoDto[]): Promise<void> {
    let enviados = 0;
    let errores = 0;
    const total = emps.length;

    for (let i = 0; i < emps.length; i++) {
      const emp = emps[i];
      this.masivoProgreso = `Procesando ${i + 1} / ${total}…`;
      let div: HTMLElement | null = null;
      try {
        div = await this.crearDivVoucher(emp);
        const blob: Blob = await html2pdf().set({
          margin: 20,
          html2canvas: { scale: 2, useCORS: true, backgroundColor: '#ffffff' },
          jsPDF: { unit: 'pt', format: 'a4', orientation: 'landscape' },
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

        await new Promise<void>((resolve) => {
          this.svc.subirDocumento(emp.id, form).subscribe({
            next: () => { enviados++; resolve(); },
            error: () => { errores++; resolve(); }
          });
        });
      } catch {
        errores++;
      } finally {
        if (div?.parentNode) div.parentNode.removeChild(div);
      }
    }

    this.enviandoMasivo = false;
    this.masivoProgreso = '';
    this.selectedLegajoMap = {};

    if (errores === 0) {
      this.toast.mostrar(`${enviados} boleta(s) enviadas al Legajo Digital`, 'success');
    } else {
      this.toast.mostrar(`${enviados} enviadas · ${errores} con error — revisar legajos`, 'error');
    }
  }

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
    const asig = this.asignacionFamiliar(emp);
    const renta = this.impuestoQuintaCategoria(emp);

    // Blanco y negro, sin color de relleno — solo bordes y negritas para
    // jerarquía visual (mismo lenguaje que la Planilla Mensual consolidada).
    const fila = (label: string, detalle: string, monto: string) => `
      <tr><td>${label}</td><td class="c-det">${detalle}</td><td class="c-mon">${monto}</td></tr>`;
    const filaSinMonto = (label: string, motivo: string) => `
      <tr><td>${label}</td><td class="c-det na" colspan="2">${motivo}</td></tr>`;

    let filasIngresos = fila('Remuneración Básica', `Jornada ordinaria pactada — ${this.formatH(emp.meta_horas)}`, `${this.formatMonto(sueldo)}`);
    if (extra > 0) {
      const detalleExtra = dependiente
        ? (this.horasExtra(emp) <= 2 ? `Recargo 25% — ${this.formatH(this.horasExtra(emp))}` : `2h al 25% + ${this.formatH(this.horasExtra(emp) - 2)} al 35%`)
        : `Tarifa simple — ${this.formatH(this.horasExtra(emp))} (sin recargo, Ley N.° 28518)`;
      filasIngresos += fila(`Trabajo en Sobretiempo (${this.formatH(this.horasExtra(emp))})`, detalleExtra, `+${this.formatMonto(extra)}`);
    }
    if (asig > 0) {
      filasIngresos += fila('Asignación Familiar', `10% de la R.M.V. (S/ ${RMV_VIGENTE}) — Régimen General · D.S. N.° 035-90-TR`, `+${this.formatMonto(asig)}`);
    }

    let filasDescuentos = '';
    if (descFaltas > 0) {
      const diasAus  = this.diasFaltantes(emp);
      const minsAus  = this.minutosTardanza(emp);
      const dominical = this.descuentoDominical(emp);
      const vd = this.valorDia(emp);
      const vm = this.valorMinuto(emp);
      let detalleAus = `Valor día S/ ${this.formatMonto(vd)} (sueldo / 30)`;
      if (diasAus > 0 && minsAus > 0) {
        detalleAus += ` · ${diasAus} día(s) + castigo dominical + ${minsAus} min. tardanza`;
      } else if (diasAus > 0) {
        detalleAus += ` · ${diasAus} día(s) ausente(s) + castigo dominical S/ ${this.formatMonto(dominical)}`;
      } else {
        detalleAus += ` · ${minsAus} min. tardanza × S/ ${this.formatMonto(vm)}/min`;
      }
      filasDescuentos += fila('Descuento por Inasistencias y Tardanzas', detalleAus, `−${this.formatMonto(descFaltas)}`);
    } else {
      filasDescuentos += filaSinMonto('Descuento por Inasistencias y Tardanzas', 'Sin faltas ni tardanzas registradas en el período');
    }
    if (descPension > 0) {
      if (this.esAfp(emp)) {
        // Desglose en 3 componentes (estándar de boleta peruana, D.L. N.° 25897).
        const afpNom = this.afpEntidadLabel(emp.id);
        filasDescuentos += fila('Aporte Obligatorio al Fondo de Pensiones', `Cuenta Individual de Capitalización — 10.00% · ${afpNom}`, `−${this.formatMonto(this.afpAporteObligatorio(emp))}`);
        filasDescuentos += fila('Prima de Seguro de Invalidez y Sobrevivencia', `Cobertura previsional SPP — ${(AFP_SEGURO_PCT * 100).toFixed(2)}% (tope S/ 12,209.11)`, `−${this.formatMonto(this.afpPrimaSeguro(emp))}`);
        filasDescuentos += fila('Comisión de Administración (AFP)', `${afpNom} — comisión sobre flujo ${(this.afpComisionPct(emp) * 100).toFixed(2)}%`, `−${this.formatMonto(this.afpComision(emp))}`);
      } else {
        filasDescuentos += fila('Aporte al Sistema Nacional de Pensiones (ONP)', 'Aporte obligatorio — D.L. N.° 19990 · 13.00%', `−${this.formatMonto(descPension)}`);
      }
    } else {
      filasDescuentos += filaSinMonto('Aporte al Sistema de Pensiones', this.motivoPension(emp));
    }
    if (renta > 0) {
      filasDescuentos += fila('Retención de Impuesto a la Renta de 5ta Categoría', 'Retención mensualizada — sujeta a regularización anual (SUNAT)', `−${this.formatMonto(renta)}`);
    } else {
      filasDescuentos += filaSinMonto('Retención de Impuesto a la Renta de 5ta Categoría', 'Proyección anual no supera el mínimo no imponible (7 UIT)');
    }

    let filasInformativas = fila('Aporte a EsSalud (Carga del Empleador)', 'Ley N.° 26790 — no se descuenta al trabajador', this.formatMonto(essalud));
    filasInformativas += cts > 0
      ? fila('Compensación por Tiempo de Servicios (CTS)', `${this.regimenLabel} · ${this.regimenEmpresa === 'general' ? '1 remuneración/año' : '15 rem. diarias/año'}`, this.formatMonto(cts))
      : filaSinMonto('Compensación por Tiempo de Servicios (CTS)', this.motivoCTS(emp));
    filasInformativas += grati > 0
      ? fila('Gratificación Legal (Ley N.° 27735)', `${this.regimenLabel} · ${this.regimenEmpresa === 'general' ? 'sueldo completo/semestre' : 'medio sueldo/semestre'}`, this.formatMonto(grati))
      : filaSinMonto('Gratificación Legal (Ley N.° 27735)', this.motivoGratificacion(emp));
    filasInformativas += vacaciones > 0
      ? fila('Provisión de Vacaciones', `${this.diasVacaciones} días/año`, this.formatMonto(vacaciones))
      : filaSinMonto('Provisión de Vacaciones', this.motivoVacaciones(emp));

    const razonSocial = this.empresaInfo?.razon_social || 'E-SYSTEM TIC';
    const ruc = this.empresaInfo?.ruc || '—';
    const direccionEmp = (this.empresaInfo?.direccion || '').trim();
    const telefonoEmp = (this.empresaInfo?.telefono || '').trim();
    const fechaEmision = new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' });

    // Documento de identidad del trabajador (DNI / Carné de Extranjería).
    const docTipo = (emp.tipo_documento || 'DNI').toUpperCase();
    const docNum  = (emp.numero_documento || '').trim() || '—';
    const cusppVal = (this.getCuspp(emp.id) || emp.cuspp || '').trim() || '—';
    // Fecha de ingreso (vital para el cálculo de beneficios sociales).
    const fechaIngreso = emp.fecha_ingreso
      ? new Date(emp.fecha_ingreso + 'T00:00:00').toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' })
      : '—';
    // Resumen de asistencia directo: días y horas efectivamente laborados.
    const diasLaborados  = (emp.dias_laborados ?? 0).toFixed(2);
    const horasLaboradas = this.formatH(emp.horas_reales);

    return `
    <style>
      .bol-hoja { font-family: 'Times New Roman', Times, serif; width: 1000px; margin: 0 auto; color: #000; padding: 16px; }
      .bol-cab { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #000; padding-bottom: 10px; margin-bottom: 12px; }
      .bol-empresa { font-size: 18px; font-weight: 700; letter-spacing: 0.4px; }
      .bol-sub { font-size: 11px; margin-top: 2px; }
      .bol-titulo { font-size: 14px; font-weight: 700; letter-spacing: 0.4px; }
      .bol-cab-der { text-align: right; }
      .bol-datos { width: 100%; border-collapse: collapse; margin-bottom: 14px; font-size: 11.5px; }
      .bol-datos td { padding: 3px 0; }
      .bol-cols { display: flex; gap: 16px; margin-bottom: 14px; }
      .bol-col { flex: 1; }
      .bol-sec-tit { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; margin-bottom: 4px; }
      .bol-tabla { width: 100%; border-collapse: collapse; font-size: 10.5px; }
      .bol-tabla th, .bol-tabla td { padding: 5px 7px; border-right: 1px solid #000; }
      .bol-tabla th:last-child, .bol-tabla td:last-child { border-right: none; }
      .bol-tabla thead th { border-top: 1px solid #000; border-bottom: 1.5px solid #000; font-weight: 700; text-align: left; font-size: 9.5px; text-transform: uppercase; }
      .bol-tabla thead th.c-mon, .bol-tabla thead th.c-det { text-align: right; }
      .bol-tabla .c-det { text-align: right; font-size: 10px; }
      .bol-tabla .c-mon { text-align: right; font-weight: 700; white-space: nowrap; }
      .bol-tabla .na { font-style: italic; text-align: left; opacity: 0.7; }
      .bol-tot td { border-top: 1.5px solid #000; font-weight: 800; }
      .bol-liq td { padding: 6px 8px; border-top: 1px solid #000; }
      .bol-liq tr:first-child td { border-top: 1.5px solid #000; }
      .bol-liq .c-mon { text-align: right; font-weight: 700; white-space: nowrap; }
      .bol-liq-final td { border-top: 1.5px solid #000; border-bottom: 1.5px solid #000; font-weight: 800; }
      .bol-nota { font-size: 9.5px; line-height: 1.5; border-left: 3px solid #000; padding: 8px 12px; margin-bottom: 18px; background: #f5f5f5; }
      .bol-pie { text-align: center; font-size: 9px; color: #333; border-top: 1px solid #000; padding-top: 8px; margin-top: 6px; line-height: 1.5; }
    </style>
    <div class="bol-hoja">
      <div class="bol-cab">
        <div>
          <div class="bol-empresa">${razonSocial.toUpperCase()}</div>
          <div class="bol-sub">RUC: ${ruc} | Régimen ${this.regimenLabel}</div>
          ${direccionEmp ? `<div class="bol-sub">Domicilio Fiscal: ${direccionEmp}</div>` : ''}
          ${telefonoEmp ? `<div class="bol-sub">Teléfono: ${telefonoEmp}</div>` : ''}
        </div>
        <div class="bol-cab-der">
          <div class="bol-titulo">BOLETA DE PAGO</div>
          <div class="bol-sub">Período Laboral: <strong>${this.titleCase(this.labelPeriodo)}</strong> | Fecha de Emisión: ${fechaEmision}</div>
        </div>
      </div>

      <table class="bol-datos">
        <tr>
          <td style="width:25%;"><strong>Apellidos y Nombres:</strong> ${emp.nombreCompleto}</td>
          <td style="width:25%;"><strong>${docTipo}:</strong> ${docNum}</td>
          <td style="width:25%;"><strong>Fecha de Ingreso:</strong> ${fechaIngreso}</td>
          <td style="width:25%;"><strong>Régimen Laboral:</strong> ${this.modalidadLabel(emp)}</td>
        </tr>
        <tr>
          <td style="width:25%;"><strong>Cargo u Ocupación:</strong> ${emp.cargo}</td>
          <td style="width:25%;"><strong>Área / Centro de Costo:</strong> ${emp.area || '—'}</td>
          <td style="width:25%;"><strong>CUSPP:</strong> ${cusppVal}</td>
          <td style="width:25%;"><strong>Días / Horas Laboradas:</strong> ${diasLaborados}d · ${horasLaboradas}</td>
        </tr>
      </table>

      <div class="bol-cols">
        <div class="bol-col">
          <div class="bol-sec-tit">Ingresos</div>
          <table class="bol-tabla">
            <thead><tr><th>Concepto</th><th class="c-det">Detalle</th><th class="c-mon">Importe S/.</th></tr></thead>
            <tbody>${filasIngresos}</tbody>
            <tfoot><tr class="bol-tot"><td colspan="2">TOTAL REMUNERACIÓN BRUTA</td><td class="c-mon">${this.formatMonto(this.totalIngresos(emp))}</td></tr></tfoot>
          </table>
        </div>
        <div class="bol-col">
          <div class="bol-sec-tit">Descuentos y Retenciones</div>
          <table class="bol-tabla">
            <thead><tr><th>Concepto</th><th class="c-det">Detalle</th><th class="c-mon">Importe S/.</th></tr></thead>
            <tbody>${filasDescuentos}</tbody>
            <tfoot><tr class="bol-tot"><td colspan="2">TOTAL DESCUENTOS</td><td class="c-mon">−${this.formatMonto(this.totalDescuentosLegales(emp))}</td></tr></tfoot>
          </table>
        </div>
      </div>

      <div class="bol-sec-tit">Resumen de Liquidación</div>
      <table class="bol-tabla bol-liq" style="margin-bottom:14px;">
        <tbody>
          <tr><td>Total Remuneración Bruta (ingresos afectos del período)</td><td class="c-mon">${this.formatMonto(this.totalIngresos(emp))}</td></tr>
          <tr><td>(−) Total Descuentos y Retenciones de cargo del trabajador</td><td class="c-mon">−${this.formatMonto(this.totalDescuentosLegales(emp))}</td></tr>
          <tr class="bol-liq-final"><td>Total Neto a Recibir</td><td class="c-mon">${this.formatMonto(neto)}</td></tr>
        </tbody>
      </table>

      <div class="bol-sec-tit">Provisiones y Aportes del Empleador</div>
      <table class="bol-tabla" style="margin-bottom:14px;">
        <thead><tr><th>Concepto</th><th class="c-det">Detalle</th><th class="c-mon">Importe S/.</th></tr></thead>
        <tbody>${filasInformativas}</tbody>
      </table>

      <div class="bol-pie">
        Documento emitido por <strong>${razonSocial.toUpperCase()}</strong> conforme al D.S. N.° 001-98-TR (Boleta de Pago) y entregado al trabajador como constancia de haberes del período indicado.<br>
        R.M.V. 2026: S/ ${RMV_VIGENTE} &middot; UIT 2026: S/ ${UIT_VIGENTE} &middot; EsSalud: ${(ESSALUD_PCT * 100).toFixed(0)}% (cargo empleador) &middot; Ley N.° 32353 — Régimen: ${this.regimenLabel}<br>
        Generado a través del Sistema de Gestión Empresarial E-ZYRO &middot; Emitido el ${fechaEmision}.
      </div>
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
        margin: 20,
        filename,
        html2canvas: { scale: 2, useCORS: true, backgroundColor: '#ffffff' },
        jsPDF: { unit: 'pt', format: 'a4', orientation: 'landscape' },
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
        margin: 20,
        html2canvas: { scale: 2, useCORS: true, backgroundColor: '#ffffff' },
        jsPDF: { unit: 'pt', format: 'a4', orientation: 'landscape' },
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

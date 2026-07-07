import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  RrhhService, PeriodoDto, PlanillaPreviewEmpleadoDto, PlanillaDto,
  RegimenLaboral, EsquemaPagoPlanilla, PeriodoPagoPlanilla, SistemaPension, EntidadAfp,
  TipoComisionAfp,
} from '../../../core/services/rrhh.service';
import { ToastService } from '../../../core/services/toast.service';
import { AuthService } from '../../../core/services/auth.service';
import { AppModalComponent } from '../../../shared/components/modal/app-modal.component';
import html2pdf from 'html2pdf.js';

const PER_PAGE = 10;

const MESES_ES = [
  '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

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

  // Esquema de pago y régimen laboral: configuración REAL de la empresa
  // (GET/PATCH /planilla/config) — ya no viven en localStorage.
  esquemaPago: EsquemaPagoPlanilla = 'quincenal';
  regimenEmpresa: RegimenLaboral = 'micro';
  // Gate de trámite para el pago de sobretiempo (GET/PATCH /planilla/config,
  // persistido — decisión de negocio CON RIESGO LEGAL, default false: solo
  // se paga sobretiempo respaldado por un trámite de Permanencia Extra
  // aprobado; si es true, se paga todo el sobretiempo registrado).
  pagarHorasExtraSinTramite = false;

  // Vista de período de pago: quincena (solo simulación, nunca genera una
  // Planilla real) o mes completo (la única que se puede calcular/aprobar/pagar).
  periodoPago: PeriodoPagoPlanilla = 'mes';

  // RMV vigente: viene del backend (parámetro legal) en cada preview.
  rmvVigente = 0;

  // ── Empleados (asistencia real + desglose legal ya calculado en backend) ───
  empleados:     PlanillaPreviewEmpleadoDto[] = [];
  totalRegistros = 0;
  totalPaginas   = 1;
  currentPage    = 1;
  cargando       = false;
  error          = '';

  // ── Sueldo base: buffer de ediciones NO guardadas (guardarSueldos() las
  // persiste una por una vía PUT /planilla/empleados/{id}/sueldo-base). El
  // valor mostrado en pantalla siempre es pendiente-o-servidor (getSueldo).
  sueldoPendienteMap: Record<string, number> = {};
  guardandoSueldos = false;

  // ── Modal confirmación cambio AFP entidad ─────────────────────────────────
  afpConfirmOpen    = false;
  afpConfirmEmpId   = '';
  afpConfirmNewVal: EntidadAfp = 'integra';
  afpConfirmLabel   = '';

  // ── Modal confirmación cambio comisión AFP ────────────────────────────────
  comisionConfirmOpen    = false;
  comisionConfirmEmpId   = '';
  comisionConfirmNewPct  = 0;   // nuevo valor en decimal (ej. 0.0160)
  comisionConfirmOldPct  = 0;   // valor oficial vigente en decimal

  // Valor que se muestra en el input de comisión (puede diferir del guardado
  // mientras el usuario edita) — se sincroniza al cargar desde emp.comision_afp_pct.
  comisionDisplayMap: Record<string, string> = {};

  // ── Datos de la empresa (para el encabezado de la Planilla Mensual PDF) ────
  empresaInfo: { razon_social: string; ruc: string; regimen_tributario: string; direccion?: string; telefono?: string } | null = null;

  // ── Estado real de la Planilla del mes (calcular/aprobar/pagar/anular) ─────
  planillaDelPeriodo: PlanillaDto | null = null;
  procesandoAccionPlanilla = false;

  // ── Modal boleta individual ───────────────────────────────────────────────
  boletaEmp: PlanillaPreviewEmpleadoDto | null = null;
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
    this.svc.getEmpresaInfo().subscribe({
      next: (res) => { this.empresaInfo = res; },
      error: () => { this.empresaInfo = null; },
    });
    this.svc.getConfigPlanilla().subscribe({
      next: (cfg) => {
        this.regimenEmpresa = cfg.regimen_laboral;
        this.esquemaPago    = cfg.esquema_pago_planilla;
        this.pagarHorasExtraSinTramite = cfg.pagar_horas_extra_sin_tramite;
        if (this.esquemaPago === 'mensual') this.periodoPago = 'mes';
        this.cargar();
      },
      error: () => { this.cargar(); },
    });
  }

  // ── Período ───────────────────────────────────────────────────────────────

  get labelPeriodo(): string {
    return new Date(this.selectedYear, this.selectedMonth - 1, 1)
      .toLocaleDateString('es-PE', { month: 'long', year: 'numeric' });
  }

  // YYYY-MM — identifica el período contable para calcular/listar la Planilla real.
  get periodoStr(): string {
    return `${this.selectedYear}-${String(this.selectedMonth).padStart(2, '0')}`;
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

  setPeriodoPago(val: PeriodoPagoPlanilla): void {
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

  // ── Esquema de pago de la empresa: Quincenal o Mensual (persistido) ────────

  setEsquemaPago(val: EsquemaPagoPlanilla): void {
    if (this.esquemaPago === val) return;
    const anterior = this.esquemaPago;
    this.esquemaPago = val;
    this.svc.actualizarConfigPlanilla({ esquema_pago_planilla: val }).subscribe({
      next: () => {
        this.toast.mostrar(`Esquema de pago actualizado a ${val === 'mensual' ? 'Mensual' : 'Quincenal'}`, 'success');
        if (val === 'mensual') this.setPeriodoPago('mes');
      },
      error: (err) => {
        this.esquemaPago = anterior;
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar el esquema de pago', 'error');
      },
    });
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

  // ── Carga de datos: desglose legal completo, ya calculado en backend ───────

  cargar(): void {
    this.cargando = true;
    this.error = '';
    this.svc.previewPlanilla({
      fecha_inicio: this.fechaInicio,
      fecha_fin:    this.fechaFin,
      periodo_pago: this.periodoPago,
      page:         this.currentPage,
      limit:        PER_PAGE,
    }).subscribe({
      next: (res) => {
        this.periodo        = res.periodo;
        this.empleados      = res.empleados;
        this.totalRegistros = res.total;
        this.totalPaginas   = res.total_paginas;
        this.rmvVigente     = res.rmv_vigente;
        this.cargando       = false;
        for (const emp of res.empleados) {
          this.comisionDisplayMap[emp.id] = (emp.comision_afp_pct * 100).toFixed(2);
        }
      },
      error: () => {
        this.error   = 'No se pudo cargar la nómina de este período.';
        this.cargando = false;
      }
    });
    if (this.esVistaMensual) this.cargarEstadoPlanilla();
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

  // ── Régimen de la empresa: Microempresa / Pequeña Empresa / Régimen General
  //    (persistido — cambia el cálculo real de CTS/gratificación/vacaciones/
  //    asignación familiar en el backend) ──────────────────────────────────

  setRegimen(val: RegimenLaboral): void {
    if (this.regimenEmpresa === val) return;
    const anterior = this.regimenEmpresa;
    this.regimenEmpresa = val;
    this.svc.actualizarConfigPlanilla({ regimen_laboral: val }).subscribe({
      next: () => {
        this.toast.mostrar(`Régimen actualizado a ${this.regimenLabel}`, 'success');
        this.cargar(); // los montos de toda la tabla cambian con el régimen
      },
      error: (err) => {
        this.regimenEmpresa = anterior;
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar el régimen', 'error');
      },
    });
  }

  get regimenLabel(): string {
    const map: Record<RegimenLaboral, string> = {
      micro:   'Microempresa',
      pequena: 'Pequeña Empresa',
      general: 'Régimen General',
    };
    return map[this.regimenEmpresa];
  }

  get esRegimenMype(): boolean {
    return this.regimenEmpresa !== 'general';
  }

  // ── Gate de trámite para el pago de sobretiempo (persistido, por empresa) ──
  // DECISIÓN CON RIESGO LEGAL: en false (default), solo se paga el
  // sobretiempo respaldado por un trámite de Permanencia Extra aprobado; en
  // true, se paga TODO el sobretiempo registrado (SUNAFIL presume
  // autorización tácita con el solo registro de asistencia).

  setPagarHorasExtraSinTramite(val: boolean): void {
    if (this.pagarHorasExtraSinTramite === val) return;
    const anterior = this.pagarHorasExtraSinTramite;
    this.pagarHorasExtraSinTramite = val;
    this.svc.actualizarConfigPlanilla({ pagar_horas_extra_sin_tramite: val }).subscribe({
      next: () => {
        this.toast.mostrar(
          val ? 'Ahora se paga todo el sobretiempo registrado, sin exigir trámite' : 'Ahora solo se paga el sobretiempo con trámite de Permanencia Extra aprobado',
          'success',
        );
        this.cargar(); // los montos de hora extra de toda la tabla cambian con el gate
      },
      error: (err) => {
        this.pagarHorasExtraSinTramite = anterior;
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar el gate de sobretiempo', 'error');
      },
    });
  }

  // ── Modalidad del trabajador (viene de la BD: empleado.tipo) ────────────────

  esDependiente(emp: PlanillaPreviewEmpleadoDto): boolean {
    return emp.tipo_contrato === 'planilla' || emp.tipo_contrato === 'contrato';
  }

  esPracticante(emp: PlanillaPreviewEmpleadoDto): boolean {
    return emp.tipo_contrato === 'practicante';
  }

  modalidadLabel(emp: PlanillaPreviewEmpleadoDto): string {
    const map: Record<string, string> = {
      planilla:    'Planilla',
      contrato:    'Contrato',
      practicante: 'Practicante',
    };
    return map[emp.tipo_contrato] ?? emp.tipo_contrato;
  }

  modalidadClass(emp: PlanillaPreviewEmpleadoDto): string {
    const map: Record<string, string> = {
      planilla:    'tipo-planilla',
      contrato:    'tipo-contrato',
      practicante: 'tipo-practicante',
    };
    return map[emp.tipo_contrato] ?? 'tipo-planilla';
  }

  // RRHH asigna la modalidad real de cada trabajador (afecta el cálculo legal:
  // pensión, recargo de horas extra, CTS/gratificación).
  onModalidadChange(emp: PlanillaPreviewEmpleadoDto, nuevoTipo: string): void {
    const anterior = emp.tipo_contrato;
    if (anterior === nuevoTipo) return;
    emp.tipo_contrato = nuevoTipo;
    this.svc.actualizarModalidad(emp.id, nuevoTipo as any).subscribe({
      next: () => {
        this.toast.mostrar(`Modalidad de ${emp.nombre_completo} actualizada a ${this.modalidadLabel(emp)}`, 'success');
        this.cargar(); // el cálculo legal completo depende de la modalidad
      },
      error: (err) => {
        emp.tipo_contrato = anterior;
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar la modalidad', 'error');
      }
    });
  }

  // ── Sueldo base: buffer local + guardado real por empleado ─────────────────

  getSueldo(emp: PlanillaPreviewEmpleadoDto): number {
    return this.sueldoPendienteMap[emp.id] ?? emp.sueldo_base;
  }

  tieneSueldoPendiente(emp: PlanillaPreviewEmpleadoDto): boolean {
    return this.sueldoPendienteMap[emp.id] !== undefined
      && this.sueldoPendienteMap[emp.id] !== emp.sueldo_base;
  }

  onSueldoChange(empId: string, raw: string): void {
    const val = parseFloat(raw.replace(/[^0-9.]/g, '')) || 0;
    this.sueldoPendienteMap[empId] = val;
  }

  guardarSueldos(): void {
    const pendientes = Object.entries(this.sueldoPendienteMap).filter(([empId, monto]) => {
      const emp = this.empleados.find(e => e.id === empId);
      return !emp || monto !== emp.sueldo_base;
    });
    if (pendientes.length === 0) {
      this.toast.mostrar('No hay cambios de sueldo por guardar', 'error');
      return;
    }
    this.guardandoSueldos = true;
    let ok = 0;
    let fallidos = 0;
    let restantes = pendientes.length;
    for (const [empId, monto] of pendientes) {
      this.svc.guardarSueldoBase(empId, monto).subscribe({
        next: () => { ok++; delete this.sueldoPendienteMap[empId]; finalizar(); },
        error: () => { fallidos++; finalizar(); },
      });
    }
    const finalizar = () => {
      restantes--;
      if (restantes > 0) return;
      this.guardandoSueldos = false;
      if (fallidos === 0) {
        this.toast.mostrar(`${ok} sueldo(s) guardado(s) correctamente`, 'success');
      } else {
        this.toast.mostrar(`${ok} guardado(s) · ${fallidos} con error — reintenta esos`, 'error');
      }
      this.cargar(); // refresca neto/descuentos con el sueldo ya persistido
    };
  }

  // ── Sistema de pensión (solo dependientes): ONP o AFP + entidad ─────────────

  readonly afpEntidades: { value: EntidadAfp; label: string }[] = [
    { value: 'integra',   label: 'AFP Integra' },
    { value: 'prima',     label: 'AFP Prima' },
    { value: 'profuturo', label: 'Profuturo AFP' },
    { value: 'habitat',   label: 'AFP Habitat' },
  ];

  onPensionChange(emp: PlanillaPreviewEmpleadoDto, val: SistemaPension): void {
    const anterior = emp.sistema_pension;
    if (anterior === val) return;
    emp.sistema_pension = val;
    this.svc.actualizarPensionEmpleado(emp.id, { sistema_pension: val }).subscribe({
      next: () => { this.toast.mostrar('Sistema de pensión actualizado', 'success'); this.cargar(); },
      error: (err) => {
        emp.sistema_pension = anterior;
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar el sistema de pensión', 'error');
      },
    });
  }

  // Esquema de comisión SPP: 'saldo' (default legal post-2013, NO se
  // descuenta en planilla) o 'flujo' (SÍ se descuenta cada mes sobre la
  // remuneración). Determina si la comisión editable de abajo tiene efecto.
  readonly tiposComisionAfp: { value: TipoComisionAfp; label: string }[] = [
    { value: 'saldo', label: 'Saldo (no se descuenta)' },
    { value: 'flujo', label: 'Flujo (se descuenta cada mes)' },
  ];

  onTipoComisionAfpChange(emp: PlanillaPreviewEmpleadoDto, val: TipoComisionAfp): void {
    const anterior = emp.tipo_comision_afp;
    if (anterior === val) return;
    emp.tipo_comision_afp = val;
    this.svc.actualizarPensionEmpleado(emp.id, { tipo_comision_afp: val }).subscribe({
      next: () => { this.toast.mostrar('Esquema de comisión AFP actualizado', 'success'); this.cargar(); },
      error: (err) => {
        emp.tipo_comision_afp = anterior;
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar el esquema de comisión', 'error');
      },
    });
  }

  onAfpEntidadChange(emp: PlanillaPreviewEmpleadoDto, val: EntidadAfp): void {
    const actual = emp.entidad_afp ?? 'integra';
    if (actual === val) return;
    // Abrir modal de confirmación en lugar de confirm() nativo del navegador
    this.afpConfirmEmpId  = emp.id;
    this.afpConfirmNewVal = val;
    this.afpConfirmLabel  = this.afpEntidades.find(a => a.value === val)?.label ?? val;
    this.afpConfirmOpen   = true;
  }

  confirmarCambioAfp(): void {
    const empId = this.afpConfirmEmpId;
    const emp = this.empleados.find(e => e.id === empId);
    const anteriorEntidad = emp?.entidad_afp ?? null;
    const anteriorComision = emp?.comision_afp_personalizada ?? null;
    if (emp) {
      emp.entidad_afp = this.afpConfirmNewVal;
      emp.comision_afp_personalizada = null; // la nueva AFP usa su propia tasa oficial
    }
    this.afpConfirmOpen = false;
    // entidad_afp=null en el body borraría el campo; aquí SÍ queremos setearlo,
    // así que se envían ambos explícitamente.
    this.svc.actualizarPensionEmpleado(empId, {
      entidad_afp: this.afpConfirmNewVal, comision_afp_personalizada: null,
    }).subscribe({
      next: () => { this.toast.mostrar(`AFP actualizada a ${this.afpConfirmLabel}`, 'success'); this.cargar(); },
      error: (err) => {
        if (emp) { emp.entidad_afp = anteriorEntidad; emp.comision_afp_personalizada = anteriorComision; }
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar la AFP', 'error');
      },
    });
  }

  cancelarCambioAfp(): void {
    this.afpConfirmOpen = false;
  }

  isComisionCustomizada(emp: PlanillaPreviewEmpleadoDto): boolean {
    return emp.comision_afp_personalizada !== null && emp.comision_afp_personalizada !== undefined;
  }

  onAfpComisionBlur(emp: PlanillaPreviewEmpleadoDto, displayVal: string): void {
    const newPct = parseFloat(String(displayVal).replace(/[^0-9.]/g, '')) / 100;
    const currentPct = emp.comision_afp_pct;
    // Entrada inválida o sin cambio: restablecer display al valor actual
    if (isNaN(newPct) || newPct < 0 || newPct > 0.5 || Math.abs(newPct - currentPct) < 0.00001) {
      this.comisionDisplayMap[emp.id] = (currentPct * 100).toFixed(2);
      return;
    }
    // Guardar pending y abrir modal de confirmación
    this.comisionConfirmEmpId  = emp.id;
    this.comisionConfirmNewPct = newPct;
    this.comisionConfirmOldPct = currentPct;
    this.comisionConfirmOpen   = true;
  }

  confirmarCambioComision(): void {
    const empId = this.comisionConfirmEmpId;
    const emp = this.empleados.find(e => e.id === empId);
    const anterior = emp?.comision_afp_personalizada ?? null;
    if (emp) emp.comision_afp_personalizada = this.comisionConfirmNewPct;
    this.comisionDisplayMap[empId] = (this.comisionConfirmNewPct * 100).toFixed(2);
    this.comisionConfirmOpen = false;
    this.svc.actualizarPensionEmpleado(empId, { comision_afp_personalizada: this.comisionConfirmNewPct }).subscribe({
      next: () => { this.toast.mostrar(`Comisión actualizada a ${(this.comisionConfirmNewPct * 100).toFixed(2)}%`, 'success'); this.cargar(); },
      error: (err) => {
        if (emp) emp.comision_afp_personalizada = anterior;
        if (emp) this.comisionDisplayMap[empId] = (emp.comision_afp_pct * 100).toFixed(2);
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar la comisión', 'error');
      },
    });
  }

  cancelarCambioComision(): void {
    const emp = this.empleados.find(e => e.id === this.comisionConfirmEmpId);
    if (emp) this.comisionDisplayMap[emp.id] = (emp.comision_afp_pct * 100).toFixed(2);
    this.comisionConfirmOpen = false;
  }

  resetComisionAfp(emp: PlanillaPreviewEmpleadoDto): void {
    const anterior = emp.comision_afp_personalizada;
    emp.comision_afp_personalizada = null;
    this.svc.actualizarPensionEmpleado(emp.id, { comision_afp_personalizada: null }).subscribe({
      next: () => {
        this.comisionDisplayMap[emp.id] = (emp.comision_afp_pct * 100).toFixed(2);
        this.toast.mostrar('Comisión restablecida a la tasa oficial', 'success');
        this.cargar();
      },
      error: (err) => {
        emp.comision_afp_personalizada = anterior;
        this.toast.mostrar(err?.error?.detail || 'Error al restablecer la comisión', 'error');
      },
    });
  }

  // ── CUSPP (ya persistido en el legajo del empleado, sin buffer local) ──────

  guardarCuspp(emp: PlanillaPreviewEmpleadoDto, val: string): void {
    const cuspp = val.trim().toUpperCase();
    const anterior = emp.cuspp;
    emp.cuspp = cuspp;
    this.svc.actualizarPerfilEmpleado(emp.id, { cuspp }).subscribe({
      next: () => this.toast.mostrar('CUSPP guardado', 'success'),
      error: () => {
        emp.cuspp = anterior;
        this.toast.mostrar('Error al guardar el CUSPP', 'error');
      },
    });
  }

  showCusppMap: Record<string, boolean> = {};
  toggleShowCuspp(empId: string): void {
    this.showCusppMap = { ...this.showCusppMap, [empId]: !this.showCusppMap[empId] };
  }

  afpEntidadLabel(emp: PlanillaPreviewEmpleadoDto): string {
    return this.afpEntidades.find(a => a.value === (emp.entidad_afp ?? 'integra'))?.label ?? 'AFP Integra';
  }

  // Porcentaje efectivo de pensión, derivado de los montos ya calculados por el
  // backend (no de constantes legales en el frontend). null si no hay base
  // imponible este período (ej. 0% de asistencia).
  pensionPct(emp: PlanillaPreviewEmpleadoDto): number | null {
    return emp.base_pension > 0 ? emp.descuento_pension / emp.base_pension : null;
  }

  pensionLabel(emp: PlanillaPreviewEmpleadoDto): string {
    const pct = this.pensionPct(emp);
    const pctTxt = pct !== null ? ` (${(pct * 100).toFixed(2)}%)` : '';
    if (emp.sistema_pension === 'onp') return `ONP${pctTxt}`;
    return `${this.afpEntidadLabel(emp)}${pctTxt}`;
  }

  // ── Asignación Familiar (10% RMV, solo dependientes con hijos a cargo) ──────

  onAsigFamiliarChange(emp: PlanillaPreviewEmpleadoDto, val: boolean): void {
    const anterior = emp.tiene_asignacion_familiar;
    emp.tiene_asignacion_familiar = val;
    this.svc.actualizarPensionEmpleado(emp.id, { tiene_asignacion_familiar: val }).subscribe({
      next: () => { this.toast.mostrar('Asignación familiar actualizada', 'success'); this.cargar(); },
      error: (err) => {
        emp.tiene_asignacion_familiar = anterior;
        this.toast.mostrar(err?.error?.detail || 'Error al actualizar la asignación familiar', 'error');
      },
    });
  }

  // ── Motivos (por qué un beneficio sí/no aplica) — texto reactivo a modalidad
  //    y régimen, usados en tabla, modal "Ver" y PDF. Sin cálculo de dinero:
  //    solo describe el resultado ya calculado por el backend (provision_*). ──

  motivoCTS(emp: PlanillaPreviewEmpleadoDto): string {
    if (this.esPracticante(emp)) return 'No aplica — Practicante (Ley 28518)';
    if (this.regimenEmpresa === 'micro') return 'No corresponde — Microempresa (exoneración MYPE)';
    if (this.regimenEmpresa === 'general') return 'Completo — 1 remuneración/año (mayo y noviembre)';
    return 'Medio — 15 remun. diarias/año (mayo y noviembre)';
  }

  motivoGratificacion(emp: PlanillaPreviewEmpleadoDto): string {
    if (this.esPracticante(emp)) return 'No aplica — Practicante (Ley 28518)';
    if (this.regimenEmpresa === 'micro') return 'No corresponde — Microempresa (exoneración MYPE)';
    if (this.regimenEmpresa === 'general') return 'Completa — 1 sueldo × semestre (julio y diciembre)';
    return 'Media — medio sueldo × semestre (julio y diciembre)';
  }

  motivoVacaciones(emp: PlanillaPreviewEmpleadoDto): string {
    if (this.esPracticante(emp)) return 'Descanso de 30 días/año (sin provisión monetaria)';
    return `${emp.dias_vacaciones} días/año, mensualizado`;
  }

  motivoPension(emp: PlanillaPreviewEmpleadoDto): string {
    if (this.esPracticante(emp)) return 'No aplica — sin afiliación obligatoria (Ley 28518)';
    return this.pensionLabel(emp);
  }

  // Resumen compacto para la columna "Beneficios" de la tabla.
  beneficiosResumen(emp: PlanillaPreviewEmpleadoDto): { cts: boolean; grati: boolean; vac: number; aplica: boolean } {
    return {
      cts:    emp.provision_cts > 0,
      grati:  emp.provision_gratificacion > 0,
      vac:    this.esDependiente(emp) ? emp.dias_vacaciones : 30,
      aplica: this.esDependiente(emp),
    };
  }

  // ── KPIs ──────────────────────────────────────────────────────────────────

  get kpis() {
    // Number(...): los campos Decimal del backend (neto_a_pagar,
    // total_descuentos_legales, pago_horas_extra, pago_domingo, pago_feriado,
    // horas_extra_sin_tramite) llegan como string en el JSON (Pydantic
    // serializa Decimal a str) — sumarlos con "+" sin coercionar concatena
    // strings en vez de sumar números.
    const sinSueldo = this.empleados.filter(e => this.getSueldo(e) === 0).length;
    const totalNeto = this.empleados.reduce((s, e) => s + Number(e.neto_a_pagar), 0);
    const totalDesc = this.empleados.reduce((s, e) => s + Number(e.total_descuentos_legales), 0);
    const totalExt  = this.empleados.reduce((s, e) => s + Number(e.pago_horas_extra), 0);
    const totalDomingo = this.empleados.reduce((s, e) => s + Number(e.pago_domingo) + Number(e.pago_feriado), 0);
    const horasSinTramite = this.empleados.reduce((s, e) => s + Number(e.horas_extra_sin_tramite), 0);
    const empleadosSinTramite = this.empleados.filter(e => e.horas_extra_sin_tramite > 0).length;
    const enPlanilla = this.empleados.filter(e => this.esDependiente(e)).length;
    const practicantes = this.empleados.filter(e => this.esPracticante(e)).length;
    const bajoRmvCount = this.empleados.filter(e => e.bajo_rmv).length;
    return { totalEmpleados: this.totalRegistros, totalNeto, totalDesc, totalExt, totalDomingo, horasSinTramite, empleadosSinTramite, sinSueldo, enPlanilla, practicantes, bajoRmvCount };
  }

  // ── Boleta individual ─────────────────────────────────────────────────────

  verBoleta(emp: PlanillaPreviewEmpleadoDto): void { this.boletaEmp = emp; }
  cerrarBoleta(): void { this.boletaEmp = null; }

  // ── Ciclo real de la Planilla del mes: calcular → aprobar → pagar / anular ─
  // Solo tiene sentido en Vista Mensual (la quincena es una simulación, nunca
  // genera una Planilla real — ver planilla_service.calcular_planilla).

  cargarEstadoPlanilla(): void {
    this.svc.getPlanillas(this.periodoStr).subscribe({
      next: (planillas) => {
        this.planillaDelPeriodo = planillas.find(p => p.estado !== 'anulada') ?? planillas[0] ?? null;
      },
      error: () => { this.planillaDelPeriodo = null; },
    });
  }

  calcularPlanillaDelMes(): void {
    this.procesandoAccionPlanilla = true;
    this.svc.calcularPlanilla(this.periodoStr).subscribe({
      next: (p) => {
        this.planillaDelPeriodo = p;
        this.procesandoAccionPlanilla = false;
        this.toast.mostrar(`Planilla de ${this.labelPeriodo} calculada`, 'success');
      },
      error: (err) => {
        this.procesandoAccionPlanilla = false;
        this.toast.mostrar(err?.error?.detail || 'Error al calcular la planilla', 'error');
      },
    });
  }

  aprobarPlanillaDelMes(): void {
    if (!this.planillaDelPeriodo) return;
    this.procesandoAccionPlanilla = true;
    this.svc.aprobarPlanilla(this.planillaDelPeriodo.id).subscribe({
      next: (p) => {
        this.planillaDelPeriodo = p;
        this.procesandoAccionPlanilla = false;
        this.toast.mostrar('Planilla aprobada — asiento de provisión contabilizado', 'success');
      },
      error: (err) => {
        this.procesandoAccionPlanilla = false;
        this.toast.mostrar(err?.error?.detail || 'Error al aprobar la planilla', 'error');
      },
    });
  }

  marcarPagadaPlanillaDelMes(): void {
    if (!this.planillaDelPeriodo) return;
    this.procesandoAccionPlanilla = true;
    this.svc.marcarPagadaPlanilla(this.planillaDelPeriodo.id).subscribe({
      next: (p) => {
        this.planillaDelPeriodo = p;
        this.procesandoAccionPlanilla = false;
        this.toast.mostrar('Planilla marcada como pagada — asiento de pago contabilizado', 'success');
      },
      error: (err) => {
        this.procesandoAccionPlanilla = false;
        this.toast.mostrar(err?.error?.detail || 'Error al marcar la planilla como pagada', 'error');
      },
    });
  }

  anularPlanillaDelMes(): void {
    if (!this.planillaDelPeriodo) return;
    this.procesandoAccionPlanilla = true;
    this.svc.anularPlanilla(this.planillaDelPeriodo.id).subscribe({
      next: () => {
        this.planillaDelPeriodo = null;
        this.procesandoAccionPlanilla = false;
        this.toast.mostrar('Planilla anulada — el período queda libre para recalcular', 'success');
      },
      error: (err) => {
        this.procesandoAccionPlanilla = false;
        this.toast.mostrar(err?.error?.detail || 'Error al anular la planilla', 'error');
      },
    });
  }

  estadoPlanillaLabel(estado: string): string {
    const map: Record<string, string> = {
      borrador: 'Borrador', calculada: 'Calculada', aprobada: 'Aprobada',
      pagada: 'Pagada', anulada: 'Anulada',
    };
    return map[estado] ?? estado;
  }

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
      this.svc.previewPlanilla({
        fecha_inicio: this.fechaInicio,
        fecha_fin:    this.fechaFin,
        periodo_pago: this.periodoPago,
        page: 1,
        limit: 1000,
      }).subscribe({
        next: async (res) => {
          const validos = res.empleados.filter(e => this.getSueldo(e) > 0);
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
      const validos = this.empleados.filter(e => selIds.has(e.id) && this.getSueldo(e) > 0);
      if (validos.length === 0) {
        this.enviandoMasivo = false;
        this.toast.mostrar('Los empleados seleccionados no tienen sueldo registrado', 'error');
        return;
      }
      await this.procesarEnvioMasivo(validos);
    }
  }

  private async procesarEnvioMasivo(emps: PlanillaPreviewEmpleadoDto[]): Promise<void> {
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

  private construirVoucherHtml(emp: PlanillaPreviewEmpleadoDto): string {
    const dependiente = this.esDependiente(emp);
    const sueldo       = emp.sueldo_periodo;
    const extra        = emp.pago_horas_extra;
    const descFaltas    = emp.descuento_faltas;
    const descPension   = emp.descuento_pension;
    const neto          = emp.neto_a_pagar;
    const essalud       = emp.aporte_essalud;
    const cts            = emp.provision_cts;
    const grati          = emp.provision_gratificacion;
    const vacaciones      = emp.provision_vacaciones;
    const asig = emp.asignacion_familiar;
    const renta = emp.renta_5ta;

    // Blanco y negro, sin color de relleno — solo bordes y negritas para
    // jerarquía visual (mismo lenguaje que la Planilla Mensual consolidada).
    const fila = (label: string, detalle: string, monto: string) => `
      <tr><td>${label}</td><td class="c-det">${detalle}</td><td class="c-mon">${monto}</td></tr>`;
    const filaSinMonto = (label: string, motivo: string) => `
      <tr><td>${label}</td><td class="c-det na" colspan="2">${motivo}</td></tr>`;

    let filasIngresos = fila('Remuneración Básica', `Jornada ordinaria pactada — ${this.formatH(emp.meta_horas)}`, `${this.formatMonto(sueldo)}`);
    if (extra > 0) {
      const horasPagadas = emp.horas_extra_pagables;
      const detalleExtra = dependiente
        ? (horasPagadas <= 2 ? `Recargo 25% — ${this.formatH(horasPagadas)}` : `2h al 25% + ${this.formatH(horasPagadas - 2)} al 35%`)
        : `Tarifa simple — ${this.formatH(horasPagadas)} (sin recargo, Ley N.° 28518)`;
      const nota = emp.horas_extra > horasPagadas ? ` · trabajó ${this.formatH(emp.horas_extra)}, se paga la hora completa` : '';
      filasIngresos += fila(`Trabajo en Sobretiempo (${this.formatH(horasPagadas)})`, detalleExtra + nota, `+${this.formatMonto(extra)}`);
      if (emp.horas_extra_sin_tramite > 0) {
        filasIngresos += filaSinMonto('⚠ Trámite de Permanencia Extra pendiente', `${this.formatH(emp.horas_extra_sin_tramite)} pagada(s) sin solicitud aprobada — regularizar en Trámites y Permisos`);
      }
    }
    if (emp.pago_domingo > 0) {
      const detalleDomingo = dependiente
        ? `Sobretasa 100% — D.Leg. N.° 713 Art. 3 (día de descanso semanal)`
        : `Tarifa simple — ${this.formatH(emp.horas_domingo)} (sin relación laboral, Ley N.° 28518)`;
      filasIngresos += fila(`Trabajo en Día de Descanso (Domingo, ${this.formatH(emp.horas_domingo)})`, detalleDomingo, `+${this.formatMonto(emp.pago_domingo)}`);
    }
    if (emp.pago_feriado > 0) {
      const detalleFeriado = dependiente
        ? `Sobretasa 100% — D.Leg. N.° 713 Art. 8/9 (feriado no laborable)`
        : `Tarifa simple — ${this.formatH(emp.horas_feriado)} (sin relación laboral, Ley N.° 28518)`;
      filasIngresos += fila(`Trabajo en Día Feriado (${this.formatH(emp.horas_feriado)})`, detalleFeriado, `+${this.formatMonto(emp.pago_feriado)}`);
    }
    if (asig > 0) {
      filasIngresos += fila('Asignación Familiar', `10% de la R.M.V. (S/ ${this.rmvVigente}) — Régimen General · D.S. N.° 035-90-TR`, `+${this.formatMonto(asig)}`);
    }

    let filasDescuentos = '';
    if (descFaltas > 0) {
      const diasAus  = emp.dias_faltantes;
      const minsAus  = emp.minutos_tardanza;
      const dominical = emp.descuento_dominical;
      const vd = emp.valor_dia;
      const vm = emp.valor_minuto;
      let detalleAus = `Valor día S/ ${this.formatMonto(vd)} (sueldo / 30)`;
      if (diasAus > 0 && minsAus > 0) {
        detalleAus += ` · ${diasAus} día(s) + castigo dominical + ${minsAus} min. tardanza`;
      } else if (diasAus > 0) {
        detalleAus += ` · ${diasAus} día(s) ausente(s) + castigo dominical S/ ${this.formatMonto(dominical)}`;
      } else {
        detalleAus += ` · ${minsAus} min. tardanza × S/ ${this.formatMonto(vm)}/min`;
      }
      filasDescuentos += fila('Inasistencias (parte no devengada del sueldo)', detalleAus, `−${this.formatMonto(descFaltas)}`);
    } else {
      filasDescuentos += filaSinMonto('Inasistencias (parte no devengada del sueldo)', 'Sin faltas ni tardanzas registradas en el período');
    }
    if (descPension > 0) {
      if (emp.es_afp) {
        // Desglose en 3 componentes (estándar de boleta peruana, D.L. N.° 25897).
        const afpNom = this.afpEntidadLabel(emp);
        filasDescuentos += fila('Aporte Obligatorio al Fondo de Pensiones', `Cuenta Individual de Capitalización · ${afpNom}`, `−${this.formatMonto(emp.afp_aporte_obligatorio)}`);
        filasDescuentos += fila('Prima de Seguro de Invalidez y Sobrevivencia', 'Cobertura previsional SPP', `−${this.formatMonto(emp.afp_prima_seguro)}`);
        filasDescuentos += fila('Comisión de Administración (AFP)', `${afpNom} — comisión sobre flujo ${(emp.comision_afp_pct * 100).toFixed(2)}%`, `−${this.formatMonto(emp.afp_comision)}`);
      } else {
        filasDescuentos += fila('Aporte al Sistema Nacional de Pensiones (ONP)', 'Aporte obligatorio — D.L. N.° 19990', `−${this.formatMonto(descPension)}`);
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
      ? fila('Provisión de Vacaciones', `${emp.dias_vacaciones} días/año`, this.formatMonto(vacaciones))
      : filaSinMonto('Provisión de Vacaciones', this.motivoVacaciones(emp));

    const razonSocial = this.empresaInfo?.razon_social || 'E-SYSTEM TIC';
    const ruc = this.empresaInfo?.ruc || '—';
    const direccionEmp = (this.empresaInfo?.direccion || '').trim();
    const telefonoEmp = (this.empresaInfo?.telefono || '').trim();
    const fechaEmision = new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' });

    // Documento de identidad del trabajador (DNI / Carné de Extranjería).
    const docTipo = (emp.tipo_documento || 'DNI').toUpperCase();
    const docNum  = (emp.numero_documento || '').trim() || '—';
    const cusppVal = (emp.cuspp || '').trim() || '—';
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
          <td style="width:25%;"><strong>Apellidos y Nombres:</strong> ${emp.nombre_completo}</td>
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
            <tfoot><tr class="bol-tot"><td colspan="2">TOTAL REMUNERACIÓN BRUTA</td><td class="c-mon">${this.formatMonto(emp.total_ingresos)}</td></tr></tfoot>
          </table>
        </div>
        <div class="bol-col">
          <div class="bol-sec-tit">Descuentos y Retenciones</div>
          <table class="bol-tabla">
            <thead><tr><th>Concepto</th><th class="c-det">Detalle</th><th class="c-mon">Importe S/.</th></tr></thead>
            <tbody>${filasDescuentos}</tbody>
            <tfoot><tr class="bol-tot"><td colspan="2">TOTAL DESCUENTOS</td><td class="c-mon">−${this.formatMonto(emp.total_descuentos_legales)}</td></tr></tfoot>
          </table>
        </div>
      </div>

      <div class="bol-sec-tit">Resumen de Liquidación</div>
      <table class="bol-tabla bol-liq" style="margin-bottom:14px;">
        <tbody>
          <tr><td>Total Remuneración Bruta (ingresos afectos del período)</td><td class="c-mon">${this.formatMonto(emp.total_ingresos)}</td></tr>
          <tr><td>(−) Total Descuentos y Retenciones de cargo del trabajador</td><td class="c-mon">−${this.formatMonto(emp.total_descuentos_legales)}</td></tr>
          <tr class="bol-liq-final"><td>Total Neto a Recibir</td><td class="c-mon">${this.formatMonto(neto)}</td></tr>
        </tbody>
      </table>

      <div class="bol-sec-tit">Provisiones y Aportes del Empleador</div>
      <table class="bol-tabla" style="margin-bottom:14px;">
        <thead><tr><th>Concepto</th><th class="c-det">Detalle</th><th class="c-mon">Importe S/.</th></tr></thead>
        <tbody>${filasInformativas}</tbody>
      </table>

      <div class="bol-pie">
        Documento emitido por <strong>${razonSocial.toUpperCase()}</strong><br>
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
  private async crearDivVoucher(emp: PlanillaPreviewEmpleadoDto): Promise<HTMLElement> {
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
  private nombreArchivoBoleta(emp: PlanillaPreviewEmpleadoDto): string {
    const primerNombre = (emp.nombre_completo || 'trabajador').trim().split(/\s+/)[0]
      .toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
    const hoy = new Date();
    const dd = String(hoy.getDate()).padStart(2, '0');
    const mm = String(hoy.getMonth() + 1).padStart(2, '0');
    const yyyy = hoy.getFullYear();
    return `boleta_${primerNombre}_${dd}${mm}${yyyy}`;
  }

  async descargarPdf(emp: PlanillaPreviewEmpleadoDto): Promise<void> {
    if (!this.esVistaMensual) {
      this.toast.mostrar('La boleta oficial se genera en la vista "Mes Completo"', 'error');
      return;
    }
    if (this.getSueldo(emp) <= 0) {
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

  async enviarALegajo(emp: PlanillaPreviewEmpleadoDto): Promise<void> {
    if (!this.esVistaMensual) {
      this.toast.mostrar('La boleta oficial se genera en la vista "Mes Completo"', 'error');
      return;
    }
    if (!this.isAdmin) {
      this.toast.mostrar('Solo un administrador puede enviar boletas al legajo digital', 'error');
      return;
    }
    if (this.getSueldo(emp) <= 0) {
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
          this.toast.mostrar(`Boleta enviada al legajo digital de ${emp.nombre_completo}`, 'success');
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

  iniciales(nombre: string | null): string {
    if (!nombre) return '?';
    return nombre.split(' ').slice(0, 2).map(w => w[0]).join('').toUpperCase();
  }

  estadoClass(emp: PlanillaPreviewEmpleadoDto): string {
    if (this.getSueldo(emp) === 0) return 'badge-sin-sueldo';
    if (emp.horas_faltantes === 0)  return 'badge-success';
    if (emp.porcentaje >= 75)       return 'badge-warning';
    return 'badge-danger';
  }

  estadoLabel(emp: PlanillaPreviewEmpleadoDto): string {
    if (this.getSueldo(emp) === 0) return 'Sin sueldo';
    if (emp.horas_faltantes === 0)  return 'Completo';
    return `−${emp.horas_faltantes.toFixed(1)}h`;
  }

  formatMonto(n: number): string {
    return new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN', minimumFractionDigits: 2 }).format(n ?? 0);
  }

  // Suma montos Decimal del backend (llegan como string en el JSON) sin caer
  // en concatenación de strings — ver nota en formatH().
  sumaMonto(...montos: number[]): number {
    return montos.reduce((s: number, m) => s + Number(m), 0);
  }

  formatH(n: number): string {
    // Los campos Decimal del backend (p. ej. horas_extra_pagables,
    // horas_domingo, horas_feriado) llegan como string en el JSON (Pydantic
    // serializa Decimal a str) — a diferencia de los campos float (meta_horas,
    // horas_reales, etc.), que sí llegan como number. Number() normaliza ambos.
    const v = Number(n);
    return v > 0 ? `${v.toFixed(1)}h` : '—';
  }

  private _uuidRx = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  safeArea(s: string | null): string {
    if (!s || this._uuidRx.test(s.trim())) return '';
    return ` · ${s}`;
  }
}

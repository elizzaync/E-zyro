import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';
import { RrhhService, SolicitudLaboralDto, SaldoVacacionesDto, DetalleSolicitudVac } from '../../../core/services/rrhh.service';
import { AuthService } from '../../../core/services/auth.service';
import { AppModalComponent } from '../../../shared/components/modal/app-modal.component';

const TIPO_LABELS: Record<string, string> = {
  vacaciones:           'Vacaciones',
  permiso:              'Permiso',
  licencia:             'Licencia',
  permiso_medico:       'Permiso médico',
  licencia_maternidad:  'Lic. maternidad',
  licencia_paternidad:  'Lic. paternidad',
  justificacion:        'Justificación',
  otro:                 'Otro',
};

// Tipos que corresponden al módulo de Asistencia, no a la bandeja
const TIPOS_ASISTENCIA = new Set(['justificacion_tardanza', 'permanencia_extra']);

@Component({
  selector: 'app-solicitudes-lista',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, AppModalComponent],
  templateUrl: './solicitudes-lista.component.html',
  styleUrls: ['./solicitudes-lista.component.css']
})
export class SolicitudesListaComponent implements OnInit, OnDestroy {

  // ── Estado de UI ─────────────────────────────────────────────────────────
  activeTab: 'permisos' | 'vacaciones' = 'permisos';
  filtroEstado: 'todos' | 'pendiente' | 'aprobada' | 'rechazada' = 'todos';
  searchTerm = '';
  cargando = true;
  error = '';

  // ── Paginación cliente ────────────────────────────────────────────────────
  readonly PER_PAGE_SOL = 10;
  solPage = 1;

  // ── Datos ─────────────────────────────────────────────────────────────────
  solicitudes: SolicitudLaboralDto[] = [];

  // ── Saldos de vacaciones ──────────────────────────────────────────────────
  saldosVac: SaldoVacacionesDto[] = [];
  cargandoSaldos = false;
  descargandoVac: 'xlsx' | 'pdf' | null = null;

  // Paginación tabla saldos
  readonly PER_PAGE_VAC = 8;
  vacPage = 1;
  // Filas expandidas (muestra períodos aprobados)
  vacExpandidas = new Set<string>();

  // ── Modal de evaluación ───────────────────────────────────────────────────
  showModal = false;
  solicitudActual: SolicitudLaboralDto | null = null;
  evalEstado: 'aprobada' | 'rechazada' | '' = '';
  evalObservacion = '';
  evalCargando = false;
  evalError = '';
  evalExito = '';

  constructor(private rrhhService: RrhhService, private authService: AuthService) {}

  ngOnInit(): void {
    this.cargar();
  }

  private cargar(): void {
    this.cargando = true;
    this.error = '';
    this.rrhhService.getSolicitudes().subscribe({
      next: (res) => {
        this.solicitudes = res.solicitudes;
        this.cargando = false;
      },
      error: () => {
        this.error = 'No se pudo cargar la bandeja de solicitudes.';
        this.cargando = false;
      }
    });
  }

  // ── Permisos ──────────────────────────────────────────────────────────────

  get isAdmin(): boolean {
    const rol = (this.authService.getUsuario()?.rol || '').trim();
    return rol === 'Administrador' || rol === 'administrador';
  }

  get puedeEvaluar(): boolean {
    const rol = (this.authService.getUsuario()?.rol || '').trim().toLowerCase()
      .replace(/\s+/g, '').replace(/\xa0/g, '');
    return !['técnicodecampo', 'clienteexterno'].includes(rol);
  }

  // ── Lógica de filtrado ────────────────────────────────────────────────────

  private esVacacion(s: SolicitudLaboralDto): boolean {
    return s.tipo.toLowerCase() === 'vacaciones';
  }

  private esDeAsistencia(s: SolicitudLaboralDto): boolean {
    return TIPOS_ASISTENCIA.has(s.tipo.toLowerCase());
  }

  get solicitudesPorTab(): SolicitudLaboralDto[] {
    return this.solicitudes.filter(s => {
      if (this.esDeAsistencia(s)) return false;  // nunca en bandeja
      return this.activeTab === 'vacaciones' ? this.esVacacion(s) : !this.esVacacion(s);
    });
  }

  onFiltroChange(): void { this.solPage = 1; }

  get filteredSolicitudes(): SolicitudLaboralDto[] {
    return this.solicitudesPorTab.filter(s => {
      const matchEstado = this.filtroEstado === 'todos' || s.estado === this.filtroEstado;
      const term = this.searchTerm.toLowerCase();
      const matchSearch = !term ||
        s.empleado.nombreCompleto.toLowerCase().includes(term) ||
        s.empleado.cargo.toLowerCase().includes(term) ||
        s.tipo.toLowerCase().includes(term);
      return matchEstado && matchSearch;
    });
  }

  get kpis() {
    const base = this.solicitudesPorTab;
    return {
      total:      base.length,
      pendientes: base.filter(s => s.estado === 'pendiente').length,
      aprobadas:  base.filter(s => s.estado === 'aprobada').length,
      rechazadas: base.filter(s => s.estado === 'rechazada').length,
    };
  }

  get totalPermisos(): number {
    return this.solicitudes.filter(s =>
      !this.esDeAsistencia(s) && s.tipo.toLowerCase() !== 'vacaciones'
    ).length;
  }

  get totalVacaciones(): number {
    return this.solicitudes.filter(s =>
      !this.esDeAsistencia(s) && s.tipo.toLowerCase() === 'vacaciones'
    ).length;
  }

  get paginatedSolicitudes(): SolicitudLaboralDto[] {
    const start = (this.solPage - 1) * this.PER_PAGE_SOL;
    return this.filteredSolicitudes.slice(start, start + this.PER_PAGE_SOL);
  }

  get solTotalPaginas(): number {
    return Math.max(1, Math.ceil(this.filteredSolicitudes.length / this.PER_PAGE_SOL));
  }

  get solRangoInfo() {
    const desde = (this.solPage - 1) * this.PER_PAGE_SOL + 1;
    const hasta = Math.min(this.solPage * this.PER_PAGE_SOL, this.filteredSolicitudes.length);
    return { desde, hasta, total: this.filteredSolicitudes.length };
  }

  get solPaginasBotones(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(1, this.solPage - 2); i <= Math.min(this.solTotalPaginas, this.solPage + 2); i++) {
      pages.push(i);
    }
    return pages;
  }

  irPaginaSol(p: number): void {
    if (p < 1 || p > this.solTotalPaginas) return;
    this.solPage = p;
  }

  setTab(tab: 'permisos' | 'vacaciones') {
    this.activeTab = tab;
    this.filtroEstado = 'todos';
    this.searchTerm = '';
    this.solPage = 1;
    if (tab === 'vacaciones' && this.saldosVac.length === 0) {
      this.cargarSaldosVac();
    }
  }

  private cargarSaldosVac(): void {
    this.cargandoSaldos = true;
    this.rrhhService.getSaldosVacaciones().subscribe({
      next: (data) => { this.saldosVac = data; this.cargandoSaldos = false; },
      error: ()     => { this.cargandoSaldos = false; },
    });
  }

  descargarReporteVac(fmt: 'xlsx' | 'pdf'): void {
    this.descargandoVac = fmt;
    this.rrhhService.descargarReporteVacaciones(fmt).subscribe({
      next: (blob) => {
        const url  = URL.createObjectURL(blob);
        const a    = document.createElement('a');
        a.href     = url;
        a.download = `vacaciones_${new Date().toISOString().slice(0, 10)}.${fmt}`;
        a.click();
        URL.revokeObjectURL(url);
        this.descargandoVac = null;
      },
      error: () => { this.descargandoVac = null; },
    });
  }

  estadoVacLabel(e: string): string {
    return { sin_derecho: 'Sin derecho', agotado: 'Saldo agotado', disponible: 'Disponible' }[e] ?? e;
  }

  // ── Paginación saldos ────────────────────────────────────────────────────
  get vacTotalPaginas(): number {
    return Math.max(1, Math.ceil(this.saldosVac.length / this.PER_PAGE_VAC));
  }

  get paginatedSaldos(): SaldoVacacionesDto[] {
    const start = (this.vacPage - 1) * this.PER_PAGE_VAC;
    return this.saldosVac.slice(start, start + this.PER_PAGE_VAC);
  }

  get vacRangoInfo() {
    const desde = (this.vacPage - 1) * this.PER_PAGE_VAC + 1;
    const hasta = Math.min(this.vacPage * this.PER_PAGE_VAC, this.saldosVac.length);
    return { desde, hasta, total: this.saldosVac.length };
  }

  get vacPaginasBotones(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(1, this.vacPage - 2); i <= Math.min(this.vacTotalPaginas, this.vacPage + 2); i++) {
      pages.push(i);
    }
    return pages;
  }

  irPaginaVac(p: number): void {
    if (p < 1 || p > this.vacTotalPaginas) return;
    this.vacPage = p;
  }

  // ── Detalle expandible ───────────────────────────────────────────────────
  toggleExpand(id: string): void {
    if (this.vacExpandidas.has(id)) this.vacExpandidas.delete(id);
    else this.vacExpandidas.add(id);
  }

  isExpanded(id: string): boolean {
    return this.vacExpandidas.has(id);
  }

  formatFechaCorta(iso: string | null): string {
    if (!iso) return '—';
    try {
      const d = new Date(iso + (iso.length === 10 ? 'T00:00:00' : ''));
      return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
    } catch { return iso; }
  }

  // ── Formateo ──────────────────────────────────────────────────────────────

  tipoLabel(tipo: string): string {
    return TIPO_LABELS[tipo.toLowerCase()] ?? tipo;
  }

  formatFecha(iso: string | null): string {
    if (!iso) return '—';
    try {
      return new Date(iso).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
    } catch { return iso; }
  }

  rangoFechas(s: SolicitudLaboralDto): string {
    if (!s.fecha_inicio) return '—';
    const fin = s.fecha_fin ? ` → ${this.formatFecha(s.fecha_fin)}` : '';
    return this.formatFecha(s.fecha_inicio) + fin;
  }

  diasLabel(dias: number | null): string {
    if (dias === null || dias === undefined) return '';
    return dias === 1 ? '1 día' : `${dias} días`;
  }

  ngOnDestroy(): void {
    document.body.style.overflow = '';
  }

  // ── Modal de evaluación ───────────────────────────────────────────────────

  abrirModal(s: SolicitudLaboralDto): void {
    this.solicitudActual = s;
    this.evalEstado = '';
    this.evalObservacion = '';
    this.evalError = '';
    this.evalExito = '';
    this.evalCargando = false;
    this.showModal = true;
  }

  cerrarModal(): void {
    this.showModal = false;
    this.solicitudActual = null;
  }

  seleccionarEstado(e: 'aprobada' | 'rechazada'): void {
    this.evalEstado = e;
    this.evalError = '';
  }

  confirmarEvaluacion(): void {
    if (!this.solicitudActual || !this.evalEstado) {
      this.evalError = 'Selecciona una acción (Aprobar o Rechazar).';
      return;
    }
    if (!this.evalObservacion.trim()) {
      this.evalError = 'La observación es obligatoria.';
      return;
    }
    this.evalCargando = true;
    this.evalError = '';

    this.rrhhService.evaluarSolicitud(
      this.solicitudActual.id,
      this.evalEstado,
      this.evalObservacion.trim()
    ).subscribe({
      next: (res) => {
        this.evalCargando = false;
        this.evalExito = res.mensaje ?? 'Solicitud evaluada correctamente.';
        const idx = this.solicitudes.findIndex(s => s.id === this.solicitudActual!.id);
        if (idx !== -1) {
          this.solicitudes[idx] = {
            ...this.solicitudes[idx],
            estado: this.evalEstado as 'aprobada' | 'rechazada',
            observacion: this.evalObservacion.trim(),
            fecha_aprobacion: new Date().toISOString(),
          };
        }
        setTimeout(() => this.cerrarModal(), 1400);
      },
      error: (err) => {
        this.evalCargando = false;
        this.evalError = err?.error?.detail ?? 'Error al evaluar la solicitud.';
      }
    });
  }
}

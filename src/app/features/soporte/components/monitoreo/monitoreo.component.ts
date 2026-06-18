import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SoporteService, AuditoriaDto, SesionDto } from '../../../../core/services/soporte.service';
import { ToastService } from '../../../../core/services/toast.service';

type TabMonitoreo = 'actividad' | 'sesiones';

@Component({
  selector: 'app-monitoreo',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './monitoreo.component.html',
  styleUrls: ['./monitoreo.component.css']
})
export class MonitoreoComponent implements OnInit {
  private svc   = inject(SoporteService);
  private toast = inject(ToastService);

  tab: TabMonitoreo = 'actividad';
  cargando = false;

  // Auditoría
  auditoria: AuditoriaDto[] = [];
  audBusqueda   = '';
  audModulo     = '';
  audFechaDesde = '';
  audFechaHasta = '';
  audPage       = 1;
  audTotalPages = 1;
  audTotal      = 0;
  audHayMas     = false;

  // Sesiones
  sesiones: SesionDto[] = [];
  sesBusqueda   = '';
  sesFechaDesde = '';
  sesFechaHasta = '';
  sesPage       = 1;
  sesTotalPages = 1;
  sesTotal      = 0;
  sesHayMas     = false;

  // KPIs
  kpiSesionesHoy  = 0;
  kpiAccionesHoy  = 0;

  readonly PAGE_SIZE = 50;

  readonly modulosDisponibles = [
    '', 'operaciones', 'logistica', 'rrhh', 'soporte', 'usuarios', 'auth', 'auditoria',
    'personal', 'configuracion', 'permisos', 'dashboard', 'planilla', 'asistencia'
  ];

  ngOnInit(): void {
    this.cargarKpis();
    this.cargarAuditoria(true);
  }

  setTab(t: TabMonitoreo): void {
    this.tab = t;
    if (t === 'sesiones' && this.sesiones.length === 0) this.cargarSesiones(true);
    if (t === 'actividad' && this.auditoria.length === 0) this.cargarAuditoria(true);
  }

  cargarKpis(): void {
    const hoy = new Date().toISOString().split('T')[0];
    this.svc.getAuditoria({ fecha_desde: hoy, page_size: 1 }).subscribe({
      next: data => { this.kpiAccionesHoy = data.length >= 50 ? 50 : data.length; }
    });
    this.svc.getSesiones({ fecha_desde: hoy, page_size: 100 }).subscribe({
      next: data => { this.kpiSesionesHoy = data.filter(s => s.activa).length; }
    });
  }

  cargarAuditoria(reset: boolean): void {
    if (reset) { this.audPage = 1; this.auditoria = []; }
    this.cargando = true;
    this.svc.getAuditoria({
      q: this.audBusqueda.trim() || undefined,
      modulo: this.audModulo || undefined,
      fecha_desde: this.audFechaDesde || undefined,
      fecha_hasta: this.audFechaHasta || undefined,
      page: this.audPage,
      page_size: this.PAGE_SIZE,
    }).subscribe({
      next: data => {
        this.auditoria = data;
        this.audHayMas = data.length === this.PAGE_SIZE;
        // Estimate total pages: if full page returned, there may be more
        if (reset) {
          this.audTotal = data.length;
          this.audTotalPages = this.audHayMas ? this.audPage + 1 : this.audPage;
        } else {
          this.audTotalPages = this.audHayMas ? this.audPage + 1 : this.audPage;
        }
        this.cargando = false;
      },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar auditoría.', 'error'); }
    });
  }

  cargarSesiones(reset: boolean): void {
    if (reset) { this.sesPage = 1; this.sesiones = []; }
    this.cargando = true;
    this.svc.getSesiones({
      fecha_desde: this.sesFechaDesde || undefined,
      fecha_hasta: this.sesFechaHasta || undefined,
      page: this.sesPage,
      page_size: this.PAGE_SIZE,
    }).subscribe({
      next: data => {
        this.sesiones = data;
        this.sesHayMas = data.length === this.PAGE_SIZE;
        if (reset) {
          this.sesTotalPages = this.sesHayMas ? this.sesPage + 1 : this.sesPage;
        } else {
          this.sesTotalPages = this.sesHayMas ? this.sesPage + 1 : this.sesPage;
        }
        this.cargando = false;
      },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar sesiones.', 'error'); }
    });
  }

  buscarAuditoria(): void { this.cargarAuditoria(true); }
  buscarSesiones(): void { this.cargarSesiones(true); }

  // ── Paginación auditoría ──────────────────────────────────────────────────
  irPaginaAud(page: number): void {
    if (page < 1 || page > this.audTotalPages) return;
    this.audPage = page;
    this.cargarAuditoria(false);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  get audPaginasVisibles(): (number | '...')[] {
    return this._paginasVisibles(this.audPage, this.audTotalPages);
  }

  // ── Paginación sesiones ───────────────────────────────────────────────────
  irPaginaSes(page: number): void {
    if (page < 1 || page > this.sesTotalPages) return;
    this.sesPage = page;
    this.cargarSesiones(false);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  get sesPaginasVisibles(): (number | '...')[] {
    return this._paginasVisibles(this.sesPage, this.sesTotalPages);
  }

  private _paginasVisibles(current: number, total: number): (number | '...')[] {
    if (total <= 7) {
      return Array.from({ length: total }, (_, i) => i + 1);
    }
    const pages: (number | '...')[] = [];
    const delta = 2;
    const left  = current - delta;
    const right = current + delta;

    pages.push(1);
    if (left > 2) pages.push('...');
    for (let i = Math.max(2, left); i <= Math.min(total - 1, right); i++) {
      pages.push(i);
    }
    if (right < total - 1) pages.push('...');
    pages.push(total);
    return pages;
  }

  get sesionesVista(): SesionDto[] {
    const q = this.sesBusqueda.toLowerCase().trim();
    if (!q) return this.sesiones;
    return this.sesiones.filter(s => s.usuario_nombre.toLowerCase().includes(q));
  }

  moduloLabel(m: string): string { return m ? m.charAt(0).toUpperCase() + m.slice(1) : '—'; }

  trackAuditoria(_: number, a: AuditoriaDto): string { return a.id; }
  trackSesion(_: number, s: SesionDto): string { return s.id; }
}

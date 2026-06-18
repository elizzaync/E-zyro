import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subject } from 'rxjs';
import { takeUntil } from 'rxjs/operators';
import { SoporteService, AuditoriaDto, SesionDto } from '../../../../core/services/soporte.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SoporteWsService } from '../../../../core/services/soporte-ws.service';
import { AuthService } from '../../../../core/services/auth.service';

type TabMonitoreo = 'actividad' | 'sesiones';

@Component({
  selector: 'app-monitoreo',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './monitoreo.component.html',
  styleUrls: ['./monitoreo.component.css']
})
export class MonitoreoComponent implements OnInit, OnDestroy {
  private svc      = inject(SoporteService);
  private toast    = inject(ToastService);
  private wsSvc    = inject(SoporteWsService);
  private auth     = inject(AuthService);
  private destroy$ = new Subject<void>();

  wsConectado = false;
  hayNuevasSesiones = false;
  hayNuevaAuditoria = false;

  tab: TabMonitoreo = 'actividad';
  cargando = false;

  // Auditoría
  auditoria: AuditoriaDto[] = [];
  audBusqueda   = '';
  audModulo     = '';
  audAccion     = '';
  audFechaDesde = '';
  audFechaHasta = '';
  audPage       = 1;
  audTotalPages = 1;
  audTotal      = 0;
  audHayMas     = false;
  audExpandedIds = new Set<string>();
  audDetalleModal: AuditoriaDto | null = null;
  audDetalleOpen = false;
  revirtiendo = false;

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
    // Conectar WebSocket y suscribirse a eventos de monitoreo.
    const token = this.auth.getToken();
    if (token) {
      this.wsSvc.connect(token);
      this.wsConectado = true;
      this.wsSvc.evento$
        .pipe(takeUntil(this.destroy$))
        .subscribe(e => {
          if (e.tipo === 'sesion_nueva') {
            this.hayNuevasSesiones = true;
            if (this.tab === 'sesiones') this.cargarSesiones(true);
          }
          if (e.tipo === 'auditoria_nueva') {
            this.hayNuevaAuditoria = true;
            if (this.tab === 'actividad') this.cargarAuditoria(true);
          }
        });
    }
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  setTab(t: TabMonitoreo): void {
    this.tab = t;
    if (t === 'sesiones') { this.hayNuevasSesiones = false; if (this.sesiones.length === 0) this.cargarSesiones(true); }
    if (t === 'actividad') { this.hayNuevaAuditoria = false; if (this.auditoria.length === 0) this.cargarAuditoria(true); }
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

  toggleExpand(id: string): void {
    if (this.audExpandedIds.has(id)) this.audExpandedIds.delete(id);
    else this.audExpandedIds.add(id);
  }

  tieneDetalle(a: AuditoriaDto): boolean {
    return !!(a.datos_anteriores || a.datos_nuevos || a.registro_id);
  }

  jsonStr(obj: any): string {
    if (!obj) return '—';
    try { return JSON.stringify(obj, null, 2); } catch { return String(obj); }
  }

  cargarAuditoria(reset: boolean): void {
    if (reset) { this.audPage = 1; this.auditoria = []; this.audExpandedIds.clear(); }
    this.cargando = true;
    this.svc.getAuditoria({
      q: this.audBusqueda.trim() || undefined,
      modulo: this.audModulo || undefined,
      accion: this.audAccion || undefined,
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

  abrirDetalle(a: AuditoriaDto): void {
    this.audDetalleModal = a;
    this.audDetalleOpen = true;
    const main = document.querySelector('main');
    if (main) { main.classList.add('modal-open'); document.body.style.overflow = 'hidden'; }
  }

  cerrarDetalle(): void {
    this.audDetalleOpen = false;
    this.audDetalleModal = null;
    const main = document.querySelector('main');
    if (main) { main.classList.remove('modal-open'); document.body.style.overflow = ''; }
  }

  revertir(a: AuditoriaDto): void {
    if (!a.datos_anteriores) return;
    this.revirtiendo = true;
    this.svc.revertirAuditoria(a.id).subscribe({
      next: (res) => {
        this.revirtiendo = false;
        this.toast.mostrar(res.detail, 'success');
        this.cerrarDetalle();
        this.cargarAuditoria(true);
      },
      error: (err) => {
        this.revirtiendo = false;
        this.toast.mostrar(err?.error?.detail || 'Error al revertir el cambio.', 'error');
      }
    });
  }

  puedeRevertir(a: AuditoriaDto): boolean {
    return !!(a.datos_anteriores && a.registro_id && !['ELIMINAR', 'DELETE'].includes(a.accion.toUpperCase()));
  }

  moduloLabel(m: string): string { return m ? m.charAt(0).toUpperCase() + m.slice(1) : '—'; }

  trackAuditoria(_: number, a: AuditoriaDto): string { return a.id; }
  trackSesion(_: number, s: SesionDto): string { return s.id; }
}

import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { forkJoin } from 'rxjs';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-portal-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink, FormsModule],
  templateUrl: './portal-dashboard.component.html',
  styleUrls: ['./portal-dashboard.component.css'],
})
export class PortalDashboardComponent implements OnInit {
  private svc  = inject(PortalClienteService);
  private auth = inject(AuthService);

  cargando  = true;
  error     = '';
  kpis: any = null;
  historial: any[] = [];

  // Filtros
  busqueda   = '';
  filtroEstado    = 'todos';
  filtroUbicacion = 'todas';

  // Paginación
  readonly PAGE_SIZE = 25;
  paginaActual = 1;

  get saludo() {
    const n = this.auth.getUsuario()?.nombre_completo ?? '';
    return n ? `Bienvenido(a), ${n}` : 'Bienvenido al Portal';
  }

  get hoy() {
    return new Date().toLocaleDateString('es-PE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
    });
  }

  // ── Listas únicas para los selects ──────────────────────────────────────
  get ubicacionesDisponibles(): string[] {
    const set = new Set<string>();
    this.historial.forEach(e => { if (e.ubicacion) set.add(e.ubicacion); });
    return ['todas', ...Array.from(set).sort()];
  }

  get proyectosDisponibles(): string[] {
    const set = new Set<string>();
    this.historial.forEach(e => { if (e.proyecto) set.add(e.proyecto); });
    return Array.from(set).sort();
  }

  // ── Historial aplicando todos los filtros ────────────────────────────────
  get historialFiltrado(): any[] {
    let result = this.historial;

    if (this.busqueda.trim()) {
      const q = this.busqueda.toLowerCase();
      result = result.filter(e =>
        (e.nombre    ?? '').toLowerCase().includes(q) ||
        (e.ubicacion ?? '').toLowerCase().includes(q) ||
        (e.proyecto  ?? '').toLowerCase().includes(q) ||
        (e.codigo    ?? '').toLowerCase().includes(q) ||
        (e.marca     ?? '').toLowerCase().includes(q)
      );
    }

    if (this.filtroEstado !== 'todos') {
      result = result.filter(e => e.estado_intervencion === this.filtroEstado);
    }

    if (this.filtroUbicacion !== 'todas') {
      result = result.filter(e => e.ubicacion === this.filtroUbicacion);
    }

    return result;
  }

  // ── Paginación ──────────────────────────────────────────────────────────
  get totalPaginas(): number {
    return Math.max(1, Math.ceil(this.historialFiltrado.length / this.PAGE_SIZE));
  }

  get historialPaginado(): any[] {
    const start = (this.paginaActual - 1) * this.PAGE_SIZE;
    return this.historialFiltrado.slice(start, start + this.PAGE_SIZE);
  }

  get paginasVisibles(): number[] {
    const total = this.totalPaginas;
    const cur   = this.paginaActual;
    const pages: number[] = [];
    const delta = 2;
    for (let i = Math.max(1, cur - delta); i <= Math.min(total, cur + delta); i++) {
      pages.push(i);
    }
    return pages;
  }

  irAPagina(p: number): void {
    if (p < 1 || p > this.totalPaginas) return;
    this.paginaActual = p;
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  resetFiltros(): void {
    this.busqueda        = '';
    this.filtroEstado    = 'todos';
    this.filtroUbicacion = 'todas';
    this.paginaActual    = 1;
  }

  onFiltroChange(): void { this.paginaActual = 1; }

  get hayFiltrosActivos(): boolean {
    return this.busqueda.trim() !== '' ||
           this.filtroEstado    !== 'todos' ||
           this.filtroUbicacion !== 'todas';
  }

  // ── Contadores por estado (para los chips) ────────────────────────────────
  countEstado(estado: string): number {
    return this.historial.filter(e => e.estado_intervencion === estado).length;
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────
  ngOnInit(): void {
    forkJoin({
      kpis:     this.svc.getKpis(),
      historial: this.svc.getHistorial(),
    }).subscribe({
      next: ({ kpis, historial }) => {
        this.kpis      = kpis;
        this.historial = historial;
        this.cargando  = false;
      },
      error: () => {
        this.error    = 'No se pudo cargar el panel. Intente nuevamente.';
        this.cargando = false;
      },
    });
  }

  badgeIntervencion(estado: string): string {
    const m: Record<string, string> = {
      pendiente:  'badge-pend',
      en_proceso: 'badge-prog',
      completado: 'badge-ok',
      cancelado:  'badge-err',
    };
    return m[estado] ?? 'badge-pend';
  }

  labelIntervencion(estado: string): string {
    const m: Record<string, string> = {
      pendiente:  'Pendiente',
      en_proceso: 'En proceso',
      completado: 'Completado',
      cancelado:  'Cancelado',
    };
    return m[estado] ?? estado;
  }

  proximoAlerta(fecha: string | null): boolean {
    if (!fecha) return false;
    const dias = (new Date(fecha).getTime() - Date.now()) / 86400000;
    return dias >= 0 && dias <= 30;
  }
}

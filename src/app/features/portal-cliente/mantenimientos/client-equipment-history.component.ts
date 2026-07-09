import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';

@Component({
  selector: 'app-client-equipment-history',
  standalone: true,
  imports: [CommonModule, RouterLink, FormsModule],
  templateUrl: './client-equipment-history.component.html',
  styleUrls: ['./client-equipment-history.component.css'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ClientEquipmentHistoryComponent implements OnInit {
  private svc = inject(PortalClienteService);
  private cdr = inject(ChangeDetectorRef);

  cargando  = true;
  error     = '';
  historial: any[] = [];

  busqueda        = '';
  filtroEstado    = 'todos';
  filtroUbicacion = 'todas';

  readonly PAGE_SIZE = 25;
  paginaActual = 1;

  // Precalculados en recalcular()/aplicarFiltros() — nunca en el template,
  // para no repetir pasadas sobre `historial` en cada change detection.
  historialFiltrado: any[] = [];
  historialPaginado: any[] = [];
  totalPaginas = 1;
  paginasVisibles: number[] = [];
  ubicacionesDisponibles: string[] = ['todas'];
  private countExito = 0;
  private countAdvertencia = 0;
  private countPeligro = 0;

  // ── FASE 1: lógica temporal unificada ────────────────────────────────────
  maintenanceStatus(eq: any): { label: string; badge: string } {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    if (eq.proximo_mantenimiento) {
      const prox  = new Date(eq.proximo_mantenimiento);
      const diffD = (prox.getTime() - today.getTime()) / 86_400_000;
      if (diffD < 0)   return { label: 'Vencido',          badge: 'badge-danger'  };
      if (diffD <= 30) return { label: 'Próximo a Vencer', badge: 'badge-warning' };
    }
    if (eq.ultimo_mantenimiento || eq.proximo_mantenimiento) {
      return { label: 'Vigente / Operativo', badge: 'badge-success' };
    }
    const fb: Record<string, { label: string; badge: string }> = {
      completado: { label: 'Vigente / Operativo', badge: 'badge-success' },
      en_proceso: { label: 'En Proceso',           badge: 'badge-prog'    },
    };
    return fb[eq.estado_intervencion] ?? { label: 'Vencido', badge: 'badge-danger' };
  }

  countPorBadge(badge: string): number {
    if (badge === 'badge-success') return this.countExito;
    if (badge === 'badge-warning') return this.countAdvertencia;
    if (badge === 'badge-danger')  return this.countPeligro;
    return 0;
  }

  proximoAlerta(fecha: string | null): boolean {
    if (!fecha) return false;
    const dias = (new Date(fecha).getTime() - Date.now()) / 86_400_000;
    return dias >= 0 && dias <= 30;
  }

  irAPagina(p: number): void {
    if (p < 1 || p > this.totalPaginas) return;
    this.paginaActual = p;
    this.actualizarPaginacion();
    this.cdr.markForCheck();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  resetFiltros(): void {
    this.busqueda        = '';
    this.filtroEstado    = 'todos';
    this.filtroUbicacion = 'todas';
    this.paginaActual    = 1;
    this.aplicarFiltros();
    this.cdr.markForCheck();
  }

  onFiltroChange(): void {
    this.paginaActual = 1;
    this.aplicarFiltros();
    this.cdr.markForCheck();
  }

  get hayFiltrosActivos(): boolean {
    return this.busqueda.trim() !== '' ||
           this.filtroEstado    !== 'todos' ||
           this.filtroUbicacion !== 'todas';
  }

  /** Recalcula lo que depende SOLO de `historial` (no cambia con los filtros). */
  private recalcularDerivadosDeHistorial(): void {
    const set = new Set<string>();
    let exito = 0, advertencia = 0, peligro = 0;
    for (const e of this.historial) {
      if (e.ubicacion) set.add(e.ubicacion);
      const badge = this.maintenanceStatus(e).badge;
      if (badge === 'badge-success') exito++;
      else if (badge === 'badge-warning') advertencia++;
      else if (badge === 'badge-danger') peligro++;
    }
    this.ubicacionesDisponibles = ['todas', ...Array.from(set).sort()];
    this.countExito = exito;
    this.countAdvertencia = advertencia;
    this.countPeligro = peligro;
  }

  /** Recalcula `historialFiltrado` según busqueda/filtroEstado/filtroUbicacion. */
  private aplicarFiltros(): void {
    let r = this.historial;

    if (this.busqueda.trim()) {
      const q = this.busqueda.toLowerCase();
      r = r.filter(e =>
        (e.nombre    ?? '').toLowerCase().includes(q) ||
        (e.ubicacion ?? '').toLowerCase().includes(q) ||
        (e.proyecto  ?? '').toLowerCase().includes(q) ||
        (e.codigo    ?? '').toLowerCase().includes(q) ||
        (e.marca     ?? '').toLowerCase().includes(q)
      );
    }

    if (this.filtroEstado !== 'todos') {
      r = r.filter(e => this.maintenanceStatus(e).badge === this.filtroEstado);
    }

    if (this.filtroUbicacion !== 'todas') {
      r = r.filter(e => e.ubicacion === this.filtroUbicacion);
    }

    this.historialFiltrado = r;
    this.actualizarPaginacion();
  }

  /** Recalcula totalPaginas/historialPaginado/paginasVisibles para paginaActual actual. */
  private actualizarPaginacion(): void {
    this.totalPaginas = Math.max(1, Math.ceil(this.historialFiltrado.length / this.PAGE_SIZE));
    const start = (this.paginaActual - 1) * this.PAGE_SIZE;
    this.historialPaginado = this.historialFiltrado.slice(start, start + this.PAGE_SIZE);

    const cur = this.paginaActual;
    const pages: number[] = [];
    for (let i = Math.max(1, cur - 2); i <= Math.min(this.totalPaginas, cur + 2); i++) {
      pages.push(i);
    }
    this.paginasVisibles = pages;
  }

  ngOnInit(): void {
    this.svc.getHistorial().subscribe({
      next: (data) => {
        this.historial = data;
        this.cargando = false;
        this.recalcularDerivadosDeHistorial();
        this.aplicarFiltros();
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'No se pudo cargar el historial.';
        this.cargando = false;
        this.cdr.markForCheck();
      },
    });
  }
}

import { Component, OnInit, inject } from '@angular/core';
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
})
export class ClientEquipmentHistoryComponent implements OnInit {
  private svc = inject(PortalClienteService);

  cargando  = true;
  error     = '';
  historial: any[] = [];

  busqueda        = '';
  filtroEstado    = 'todos';
  filtroUbicacion = 'todas';

  readonly PAGE_SIZE = 25;
  paginaActual = 1;

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
    return this.historial.filter(e => this.maintenanceStatus(e).badge === badge).length;
  }

  proximoAlerta(fecha: string | null): boolean {
    if (!fecha) return false;
    const dias = (new Date(fecha).getTime() - Date.now()) / 86_400_000;
    return dias >= 0 && dias <= 30;
  }

  get ubicacionesDisponibles(): string[] {
    const set = new Set<string>();
    this.historial.forEach(e => { if (e.ubicacion) set.add(e.ubicacion); });
    return ['todas', ...Array.from(set).sort()];
  }

  get historialFiltrado(): any[] {
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
      r = r.filter(e => {
        const s = this.maintenanceStatus(e);
        if (this.filtroEstado === 'badge-success')  return s.badge === 'badge-success';
        if (this.filtroEstado === 'badge-warning')  return s.badge === 'badge-warning';
        if (this.filtroEstado === 'badge-danger')   return s.badge === 'badge-danger';
        return false;
      });
    }

    if (this.filtroUbicacion !== 'todas') {
      r = r.filter(e => e.ubicacion === this.filtroUbicacion);
    }

    return r;
  }

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
    for (let i = Math.max(1, cur - 2); i <= Math.min(total, cur + 2); i++) {
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

  ngOnInit(): void {
    this.svc.getHistorial().subscribe({
      next:  (data) => { this.historial = data; this.cargando = false; },
      error: ()     => { this.error = 'No se pudo cargar el historial.'; this.cargando = false; },
    });
  }
}

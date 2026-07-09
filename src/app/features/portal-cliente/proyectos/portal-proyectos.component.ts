import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { StatusBadgeComponent } from '../shared/status-badge.component';
import { ProgressBarComponent } from '../shared/progress-bar.component';
import { EmptyStateComponent } from '../shared/empty-state.component';

type EstadoFiltro = 'todos' | 'activo' | 'completado' | 'planificado' | 'cancelado';

@Component({
  selector: 'app-portal-proyectos',
  standalone: true,
  imports: [CommonModule, RouterLink, FormsModule, StatusBadgeComponent, ProgressBarComponent, EmptyStateComponent],
  templateUrl: './portal-proyectos.component.html',
  styleUrls: ['./portal-proyectos.component.css'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PortalProyectosComponent implements OnInit {
  private svc = inject(PortalClienteService);
  private cdr = inject(ChangeDetectorRef);

  cargando    = true;
  error       = '';
  proyectos: any[] = [];

  busqueda = '';
  filtro: EstadoFiltro = 'todos';
  readonly filtros: Array<{ key: EstadoFiltro; label: string }> = [
    { key: 'todos',       label: 'Todos' },
    { key: 'activo',      label: 'En curso' },
    { key: 'completado',  label: 'Completados' },
    { key: 'planificado', label: 'Planificados' },
    { key: 'cancelado',   label: 'Cancelados' },
  ];

  // Precalculado en aplicarFiltros() — nunca en el template (OnPush).
  filtrados: any[] = [];

  ngOnInit(): void {
    this.svc.getProyectos().subscribe({
      next: (data) => {
        this.proyectos = data;
        this.cargando = false;
        this.aplicarFiltros();
        this.cdr.markForCheck();
      },
      error: () => { this.error = 'Error al cargar proyectos.'; this.cargando = false; this.cdr.markForCheck(); },
    });
  }

  onFiltroChange(): void { this.aplicarFiltros(); this.cdr.markForCheck(); }
  setFiltro(f: EstadoFiltro): void { this.filtro = f; this.aplicarFiltros(); this.cdr.markForCheck(); }

  private aplicarFiltros(): void {
    const q = this.busqueda.trim().toLowerCase();
    this.filtrados = this.proyectos.filter(p =>
      (this.filtro === 'todos' || p.estado === this.filtro) &&
      (!q || (p.nombre_proyecto ?? '').toLowerCase().includes(q))
    );
  }

  estadoSt(e: string): 'ok' | 'prog' | 'warn' | 'err' | 'neutral' {
    const m: Record<string, 'ok' | 'prog' | 'err' | 'neutral'> =
      { activo: 'prog', completado: 'ok', cancelado: 'err', planificado: 'neutral' };
    return m[e] ?? 'neutral';
  }

  estadoLabel(e: string): string {
    const m: Record<string, string> =
      { activo: 'En curso', completado: 'Completado', cancelado: 'Cancelado', planificado: 'Planificado' };
    return m[e] ?? e;
  }

  avancePct(p: any): number {
    return Math.max(0, Math.min(100, Math.round(p.avance_pct ?? 0)));
  }
}

import {
  Component, OnInit, AfterViewInit, OnDestroy,
  ElementRef, ViewChild, inject,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { forkJoin } from 'rxjs';
import {
  Chart, BarController, CategoryScale, LinearScale,
  BarElement, Tooltip, Legend,
} from 'chart.js';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { AuthService } from '../../../core/services/auth.service';

Chart.register(BarController, CategoryScale, LinearScale, BarElement, Tooltip, Legend);

@Component({
  selector: 'app-portal-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink, FormsModule],
  templateUrl: './portal-dashboard.component.html',
  styleUrls: ['./portal-dashboard.component.css'],
})
export class PortalDashboardComponent implements OnInit, AfterViewInit, OnDestroy {
  @ViewChild('tendenciaChart') chartCanvas!: ElementRef<HTMLCanvasElement>;

  private svc   = inject(PortalClienteService);
  private auth  = inject(AuthService);
  private chart: Chart | null = null;

  cargando  = true;
  error     = '';
  kpis: any = null;
  historial: any[] = [];

  // Filtros
  busqueda        = '';
  filtroEstado    = 'todos';
  filtroUbicacion = 'todas';

  // Paginación
  readonly PAGE_SIZE = 25;
  paginaActual = 1;

  // ── Saludo y fecha ────────────────────────────────────────────────────────
  get saludo() {
    const n = this.auth.getUsuario()?.nombre_completo ?? '';
    return n ? `Bienvenido(a), ${n}` : 'Bienvenido al Portal';
  }

  get hoy() {
    return new Date().toLocaleDateString('es-PE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
    });
  }

  // ── FASE 1: lógica de estado basada en fechas ─────────────────────────────
  maintenanceStatus(eq: any): { label: string; badge: string } {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    if (eq.ultimo_mantenimiento) {
      return { label: 'Se realizó mantenimiento', badge: 'badge-success' };
    }

    if (eq.proximo_mantenimiento) {
      const prox  = new Date(eq.proximo_mantenimiento);
      const diffD = (prox.getTime() - today.getTime()) / 86_400_000;

      if (diffD < 0) {
        return { label: 'No se realizó mantenimiento', badge: 'badge-danger' };
      }
      if (diffD <= 30) {
        return { label: 'Se aproxima próximo mantenimiento', badge: 'badge-warning' };
      }
    }

    // Fallback: usar estado_intervencion
    const fallback: Record<string, { label: string; badge: string }> = {
      completado: { label: 'Se realizó mantenimiento',     badge: 'badge-success' },
      en_proceso: { label: 'En proceso',                    badge: 'badge-prog'    },
      cancelado:  { label: 'Cancelado',                     badge: 'badge-err'     },
    };
    return fallback[eq.estado_intervencion] ?? { label: 'Pendiente', badge: 'badge-pend' };
  }

  // ── Listas únicas para selects ────────────────────────────────────────────
  get ubicacionesDisponibles(): string[] {
    const set = new Set<string>();
    this.historial.forEach(e => { if (e.ubicacion) set.add(e.ubicacion); });
    return ['todas', ...Array.from(set).sort()];
  }

  // ── Historial filtrado ────────────────────────────────────────────────────
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
        return e.estado_intervencion === this.filtroEstado;
      });
    }

    if (this.filtroUbicacion !== 'todas') {
      r = r.filter(e => e.ubicacion === this.filtroUbicacion);
    }

    return r;
  }

  // ── Paginación ────────────────────────────────────────────────────────────
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

  countPorBadge(badge: string): number {
    return this.historial.filter(e => this.maintenanceStatus(e).badge === badge).length;
  }

  // ── FASE 2: datos de tendencia para Chart.js ──────────────────────────────
  private buildChartData(): { labels: string[]; realizados: number[]; pendientes: number[]; } {
    const today  = new Date();
    const labels: string[] = [];
    const realizados: number[] = [];
    const pendientes: number[] = [];

    for (let i = 11; i >= 0; i--) {
      const d = new Date(today.getFullYear(), today.getMonth() - i, 1);
      labels.push(d.toLocaleString('es-PE', { month: 'short', year: '2-digit' }));

      const mesStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      let r = 0;
      let p = 0;

      this.historial.forEach(eq => {
        const dateRef = eq.ultimo_mantenimiento ?? eq.proximo_mantenimiento;
        if (!dateRef) return;
        const m = dateRef.substring(0, 7); // "YYYY-MM"
        if (m !== mesStr) return;
        if (eq.ultimo_mantenimiento) r++;
        else p++;
      });

      realizados.push(r);
      pendientes.push(p);
    }

    return { labels, realizados, pendientes };
  }

  private initChart(): void {
    if (!this.chartCanvas?.nativeElement || this.historial.length === 0) return;

    const isDark = document.documentElement.getAttribute('data-theme') === 'dark' ||
                   window.matchMedia('(prefers-color-scheme: dark)').matches;

    const gridColor  = isDark ? 'rgba(255,255,255,.07)' : 'rgba(0,0,0,.06)';
    const textColor  = isDark ? '#94a3b8' : '#6b7280';
    const { labels, realizados, pendientes } = this.buildChartData();

    this.chart = new Chart(this.chartCanvas.nativeElement, {
      type: 'bar',
      data: {
        labels,
        datasets: [
          {
            label: 'Realizados',
            data: realizados,
            backgroundColor: 'rgba(141,198,63,.85)',
            borderRadius: 6,
            borderSkipped: false,
          },
          {
            label: 'Próximos / Pendientes',
            data: pendientes,
            backgroundColor: 'rgba(245,158,11,.75)',
            borderRadius: 6,
            borderSkipped: false,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'top',
            labels: { color: textColor, font: { size: 12, weight: 600 }, boxWidth: 12, padding: 16 },
          },
          tooltip: {
            backgroundColor: isDark ? '#1e293b' : '#fff',
            titleColor:  isDark ? '#f8fafc' : '#111827',
            bodyColor:   isDark ? '#94a3b8' : '#6b7280',
            borderColor: isDark ? '#334155' : '#e5e7eb',
            borderWidth: 1,
            padding: 12,
            cornerRadius: 10,
          },
        },
        scales: {
          x: {
            grid:  { color: gridColor },
            ticks: { color: textColor, font: { size: 11 } },
          },
          y: {
            beginAtZero: true,
            grid:  { color: gridColor },
            ticks: { color: textColor, font: { size: 11 }, stepSize: 1 },
          },
        },
      },
    });
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  ngOnInit(): void {
    forkJoin({
      kpis:     this.svc.getKpis(),
      historial: this.svc.getHistorial(),
    }).subscribe({
      next: ({ kpis, historial }) => {
        this.kpis      = kpis;
        this.historial = historial;
        this.cargando  = false;
        // Chart init se dispara desde ngAfterViewInit después de que
        // cargando=false + Angular renderiza el canvas
        setTimeout(() => this.initChart(), 50);
      },
      error: () => {
        this.error    = 'No se pudo cargar el panel. Intente nuevamente.';
        this.cargando = false;
      },
    });
  }

  ngAfterViewInit(): void {
    // Por si los datos llegan antes del primer render
    if (!this.cargando && this.historial.length > 0) {
      setTimeout(() => this.initChart(), 50);
    }
  }

  ngOnDestroy(): void {
    this.chart?.destroy();
  }

  // ── Helpers de badge legacy (chips de filtro) ─────────────────────────────
  proximoAlerta(fecha: string | null): boolean {
    if (!fecha) return false;
    const dias = (new Date(fecha).getTime() - Date.now()) / 86_400_000;
    return dias >= 0 && dias <= 30;
  }
}

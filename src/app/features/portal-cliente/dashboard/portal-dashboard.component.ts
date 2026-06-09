import {
  Component, OnInit, AfterViewInit, OnDestroy,
  ElementRef, ViewChild, inject,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { forkJoin } from 'rxjs';
import {
  Chart, DoughnutController, ArcElement, Tooltip, Legend,
} from 'chart.js';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { AuthService } from '../../../core/services/auth.service';

Chart.register(DoughnutController, ArcElement, Tooltip, Legend);

@Component({
  selector: 'app-portal-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './portal-dashboard.component.html',
  styleUrls: ['./portal-dashboard.component.css'],
})
export class PortalDashboardComponent implements OnInit, AfterViewInit, OnDestroy {
  @ViewChild('donutChart') chartCanvas!: ElementRef<HTMLCanvasElement>;

  private svc   = inject(PortalClienteService);
  private auth  = inject(AuthService);
  private chart: Chart | null = null;

  cargando  = true;
  error     = '';
  kpis: any = null;
  historial: any[] = [];

  get saludo() {
    const n = this.auth.getUsuario()?.nombre_completo ?? '';
    return n ? `Bienvenido(a), ${n}` : 'Bienvenido al Portal';
  }

  get hoy() {
    return new Date().toLocaleDateString('es-PE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
    });
  }

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

  // ── FASE 3: conteos derivados ─────────────────────────────────────────────
  get countVencidos(): number {
    return this.historial.filter(e => this.maintenanceStatus(e).badge === 'badge-danger').length;
  }
  get countProximos(): number {
    return this.historial.filter(e => this.maintenanceStatus(e).badge === 'badge-warning').length;
  }
  get countVigentes(): number {
    return this.historial.length - this.countVencidos - this.countProximos;
  }

  get alertasEquipos(): any[] {
    return this.historial.filter(e => {
      const b = this.maintenanceStatus(e).badge;
      return b === 'badge-danger' || b === 'badge-warning';
    });
  }

  // ── FASE 3: Donut — Estado del Parque ────────────────────────────────────
  private initChart(): void {
    if (!this.chartCanvas?.nativeElement || this.historial.length === 0) return;

    const isDark = document.documentElement.getAttribute('data-theme') === 'dark' ||
                   window.matchMedia('(prefers-color-scheme: dark)').matches;
    const textColor = isDark ? '#94a3b8' : '#6b7280';

    this.chart = new Chart(this.chartCanvas.nativeElement, {
      type: 'doughnut',
      data: {
        labels: ['Vigente / Operativo', 'Próximo a Vencer', 'Vencido'],
        datasets: [{
          data: [this.countVigentes, this.countProximos, this.countVencidos],
          backgroundColor: ['#16a34a', '#f59e0b', '#dc2626'],
          hoverBackgroundColor: ['#15803d', '#d97706', '#b91c1c'],
          borderWidth: 3,
          borderColor: isDark ? '#1e293b' : '#fff',
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '65%',
        plugins: {
          legend: { display: false },
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
      },
    });
  }

  ngOnInit(): void {
    forkJoin({
      kpis:      this.svc.getKpis(),
      historial: this.svc.getHistorial(),
    }).subscribe({
      next: ({ kpis, historial }) => {
        this.kpis      = kpis;
        this.historial = historial;
        this.cargando  = false;
        setTimeout(() => this.initChart(), 50);
      },
      error: () => {
        this.error    = 'No se pudo cargar el panel. Intente nuevamente.';
        this.cargando = false;
      },
    });
  }

  ngAfterViewInit(): void {
    if (!this.cargando && this.historial.length > 0) {
      setTimeout(() => this.initChart(), 50);
    }
  }

  ngOnDestroy(): void {
    this.chart?.destroy();
  }
}

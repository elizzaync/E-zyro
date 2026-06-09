import {
  Component, OnInit, OnDestroy,
  ElementRef, ViewChild, inject,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { forkJoin } from 'rxjs';
import {
  Chart,
  DoughnutController, ArcElement,
  BarController, BarElement,
  LineController, LineElement, PointElement,
  CategoryScale, LinearScale,
  Tooltip, Legend, Filler,
} from 'chart.js';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { AuthService } from '../../../core/services/auth.service';

Chart.register(
  DoughnutController, ArcElement,
  BarController, BarElement,
  LineController, LineElement, PointElement,
  CategoryScale, LinearScale,
  Tooltip, Legend, Filler,
);

// ── Constantes de tema ────────────────────────────────────────────────────────
const DARK = {
  grid:    'rgba(255,255,255,0.05)',
  text:    '#7d8590',
  bg:      '#161b22',
  border:  '#30363d',
  tooltip: { bg: '#1c2128', title: '#e6edf3', body: '#7d8590' },
};

const P = {
  blue:   '#3b82f6',
  green:  '#10b981',
  amber:  '#f59e0b',
  red:    '#ef4444',
  brand:  '#8dc63f',
  purple: '#8b5cf6',
  cyan:   '#06b6d4',
};

@Component({
  selector: 'app-portal-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './portal-dashboard.component.html',
  styleUrls: ['./portal-dashboard.component.css'],
})
export class PortalDashboardComponent implements OnInit, OnDestroy {
  // Sparklines
  @ViewChild('spkTotal') spkTotal!: ElementRef<HTMLCanvasElement>;
  @ViewChild('spkVig')   spkVig!: ElementRef<HTMLCanvasElement>;
  @ViewChild('spkProx')  spkProx!: ElementRef<HTMLCanvasElement>;
  @ViewChild('spkVenc')  spkVenc!: ElementRef<HTMLCanvasElement>;
  // Main charts
  @ViewChild('mixedChart') mixedCanvas!: ElementRef<HTMLCanvasElement>;
  @ViewChild('donut1')     donut1Canvas!: ElementRef<HTMLCanvasElement>;
  @ViewChild('donut2')     donut2Canvas!: ElementRef<HTMLCanvasElement>;
  @ViewChild('horizBar')   horizBarCanvas!: ElementRef<HTMLCanvasElement>;

  private charts: (Chart | null)[] = new Array(8).fill(null);
  private svc  = inject(PortalClienteService);
  private auth = inject(AuthService);

  cargando  = true;
  error     = '';
  kpis: any = null;
  historial: any[] = [];

  get saludo() {
    return this.auth.getUsuario()?.nombre_completo ?? 'Portal Cliente';
  }
  get hoy() {
    return new Date().toLocaleDateString('es-PE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
    });
  }

  // ── FASE 1: lógica temporal unificada ────────────────────────────────────
  maintenanceStatus(eq: any): { label: string; badge: string } {
    const today = new Date(); today.setHours(0,0,0,0);
    if (eq.proximo_mantenimiento) {
      const d = (new Date(eq.proximo_mantenimiento).getTime() - today.getTime()) / 86_400_000;
      if (d < 0)   return { label: 'Vencido',          badge: 'badge-danger'  };
      if (d <= 30) return { label: 'Próximo a Vencer', badge: 'badge-warning' };
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

  get countVencidos(): number { return this.historial.filter(e => this.maintenanceStatus(e).badge === 'badge-danger').length;  }
  get countProximos(): number { return this.historial.filter(e => this.maintenanceStatus(e).badge === 'badge-warning').length; }
  get countVigentes(): number { return this.historial.length - this.countVencidos - this.countProximos; }

  // ── Tendencia mes actual vs mes anterior ──────────────────────────────────
  private countByMonthBadge(badge: string | null, offset: number): number {
    const t = new Date();
    const d = new Date(t.getFullYear(), t.getMonth() + offset, 1);
    const ms = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`;
    return this.historial.filter(eq => {
      const ref = eq.ultimo_mantenimiento ?? eq.proximo_mantenimiento;
      if (!ref?.startsWith(ms)) return false;
      return badge === null || this.maintenanceStatus(eq).badge === badge;
    }).length;
  }

  kpiTrend(badge: string | null): { pct: number; up: boolean } {
    const curr = this.countByMonthBadge(badge, 0);
    const prev = this.countByMonthBadge(badge, -1);
    if (prev === 0 && curr === 0) return { pct: 0, up: true };
    if (prev === 0) return { pct: 100, up: true };
    const pct = Math.round(((curr - prev) / prev) * 100);
    return { pct: Math.abs(pct), up: pct >= 0 };
  }

  // ── Próximos 7 días (calendario) ─────────────────────────────────────────
  get upcomingEvents(): any[] {
    const today = new Date(); today.setHours(0,0,0,0);
    const next7 = new Date(today); next7.setDate(today.getDate() + 7);
    return this.historial
      .filter(eq => {
        if (!eq.proximo_mantenimiento) return false;
        const d = new Date(eq.proximo_mantenimiento);
        return d >= today && d <= next7;
      })
      .sort((a, b) => new Date(a.proximo_mantenimiento).getTime() - new Date(b.proximo_mantenimiento).getTime())
      .slice(0, 12);
  }

  daysUntil(dateStr: string): number {
    const today = new Date(); today.setHours(0,0,0,0);
    return Math.ceil((new Date(dateStr).getTime() - today.getTime()) / 86_400_000);
  }

  eventClass(dateStr: string): string {
    const d = this.daysUntil(dateStr);
    if (d < 0)  return 'ev-danger';
    if (d <= 3) return 'ev-danger';
    if (d <= 7) return 'ev-warning';
    return 'ev-ok';
  }

  // ── Datos para gráficos ───────────────────────────────────────────────────

  private buildSparkData(badge: string | null): number[] {
    return Array.from({ length: 8 }, (_, i) => {
      const d = new Date(); const m = new Date(d.getFullYear(), d.getMonth() - (7 - i), 1);
      const ms = `${m.getFullYear()}-${String(m.getMonth()+1).padStart(2,'0')}`;
      return this.historial.filter(eq => {
        const ref = eq.ultimo_mantenimiento ?? eq.proximo_mantenimiento;
        if (!ref?.startsWith(ms)) return false;
        return badge === null || this.maintenanceStatus(eq).badge === badge;
      }).length;
    });
  }

  private buildMonthlyData(): { labels: string[]; ejecutados: number[]; programados: number[] } {
    const today = new Date();
    const labels: string[] = [], ejecutados: number[] = [], programados: number[] = [];
    for (let i = 11; i >= 0; i--) {
      const d = new Date(today.getFullYear(), today.getMonth() - i, 1);
      labels.push(d.toLocaleString('es-PE', { month: 'short', year: '2-digit' }));
      const ms = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`;
      ejecutados.push(this.historial.filter(e => e.ultimo_mantenimiento?.substring(0,7) === ms).length);
      programados.push(this.historial.filter(e => e.proximo_mantenimiento?.substring(0,7) === ms).length);
    }
    return { labels, ejecutados, programados };
  }

  private buildLocationData(): { labels: string[]; counts: number[] } {
    const map = new Map<string, number>();
    this.historial.forEach(eq => {
      const loc = (eq.ubicacion || 'Sin ubicación').trim().substring(0, 28);
      map.set(loc, (map.get(loc) ?? 0) + 1);
    });
    const sorted = Array.from(map.entries()).sort((a, b) => b[1] - a[1]).slice(0, 9);
    return { labels: sorted.map(([k]) => k), counts: sorted.map(([,v]) => v) };
  }

  private buildProyectoData(): { labels: string[]; counts: number[] } {
    const map = new Map<string, number>();
    this.historial.forEach(eq => {
      const p = (eq.proyecto || 'Sin Proyecto').trim();
      map.set(p, (map.get(p) ?? 0) + 1);
    });
    const sorted = Array.from(map.entries()).sort((a, b) => b[1] - a[1]);
    if (sorted.length <= 4) return { labels: sorted.map(([k]) => k), counts: sorted.map(([,v]) => v) };
    const top = sorted.slice(0, 3);
    const otros = sorted.slice(3).reduce((s, [,v]) => s + v, 0);
    return { labels: [...top.map(([k]) => k), 'Otros'], counts: [...top.map(([,v]) => v), otros] };
  }

  // ── Inicialización de gráficos ────────────────────────────────────────────

  private spark(canvas: HTMLCanvasElement | undefined, data: number[], color: string): Chart | null {
    if (!canvas) return null;
    return new Chart(canvas, {
      type: 'line',
      data: {
        labels: data.map(() => ''),
        datasets: [{
          data, borderColor: color, borderWidth: 2,
          fill: true, backgroundColor: color + '22',
          tension: 0.45, pointRadius: 0, pointHoverRadius: 0,
        }],
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        animation: { duration: 700 },
        plugins: { legend: { display: false }, tooltip: { enabled: false } },
        scales: { x: { display: false }, y: { display: false } },
      },
    });
  }

  private initAllCharts(): void {
    this.charts.forEach((c, i) => { c?.destroy(); this.charts[i] = null; });

    this.charts[0] = this.spark(this.spkTotal?.nativeElement, this.buildSparkData(null),             P.blue);
    this.charts[1] = this.spark(this.spkVig?.nativeElement,   this.buildSparkData('badge-success'),  P.green);
    this.charts[2] = this.spark(this.spkProx?.nativeElement,  this.buildSparkData('badge-warning'),  P.amber);
    this.charts[3] = this.spark(this.spkVenc?.nativeElement,  this.buildSparkData('badge-danger'),   P.red);

    // Mixed: barras (ejecutados) + línea (programados)
    if (this.mixedCanvas?.nativeElement) {
      const { labels, ejecutados, programados } = this.buildMonthlyData();
      this.charts[4] = new Chart(this.mixedCanvas.nativeElement, {
        type: 'bar',
        data: {
          labels,
          datasets: [
            {
              type: 'bar' as const,
              label: 'Ejecutados',
              data: ejecutados,
              backgroundColor: P.brand + 'CC',
              borderRadius: 5,
              borderSkipped: false,
              yAxisID: 'y',
            },
            {
              type: 'line' as const,
              label: 'Programados',
              data: programados,
              borderColor: P.blue,
              backgroundColor: P.blue + '1A',
              borderWidth: 2.5,
              fill: true,
              tension: 0.4,
              pointRadius: 4,
              pointBackgroundColor: P.blue,
              pointBorderColor: DARK.bg,
              pointBorderWidth: 2,
              yAxisID: 'y',
            },
          ],
        },
        options: {
          responsive: true, maintainAspectRatio: false,
          plugins: {
            legend: { position: 'top', labels: { color: DARK.text, font: { size: 12, weight: 600 }, boxWidth: 12, padding: 16 } },
            tooltip: { backgroundColor: DARK.tooltip.bg, titleColor: DARK.tooltip.title, bodyColor: DARK.tooltip.body, borderColor: DARK.border, borderWidth: 1, padding: 12, cornerRadius: 10 },
          },
          scales: {
            x: { grid: { color: DARK.grid }, ticks: { color: DARK.text, font: { size: 11 } } },
            y: { beginAtZero: true, grid: { color: DARK.grid }, ticks: { color: DARK.text, font: { size: 11 }, stepSize: 1 } },
          },
        },
      });
    }

    // Donut 1: Cumplimiento operativo
    if (this.donut1Canvas?.nativeElement) {
      const op = this.countVigentes + this.countProximos;
      this.charts[5] = new Chart(this.donut1Canvas.nativeElement, {
        type: 'doughnut',
        data: {
          labels: ['Operativos', 'Vencidos'],
          datasets: [{ data: [op, this.countVencidos], backgroundColor: [P.green, P.red], hoverBackgroundColor: ['#059669', '#dc2626'], borderWidth: 2, borderColor: DARK.bg }],
        },
        options: {
          responsive: true, maintainAspectRatio: false, cutout: '72%',
          plugins: {
            legend: { position: 'bottom', labels: { color: DARK.text, font: { size: 11 }, boxWidth: 10, padding: 10 } },
            tooltip: { backgroundColor: DARK.tooltip.bg, titleColor: DARK.tooltip.title, bodyColor: DARK.tooltip.body, borderColor: DARK.border, borderWidth: 1, padding: 10, cornerRadius: 8 },
          },
        },
      });
    }

    // Donut 2: Por Proyecto
    if (this.donut2Canvas?.nativeElement) {
      const { labels, counts } = this.buildProyectoData();
      const colors = [P.blue, P.amber, P.purple, P.cyan, P.green];
      this.charts[6] = new Chart(this.donut2Canvas.nativeElement, {
        type: 'doughnut',
        data: {
          labels,
          datasets: [{ data: counts, backgroundColor: colors.slice(0, labels.length), borderWidth: 2, borderColor: DARK.bg }],
        },
        options: {
          responsive: true, maintainAspectRatio: false, cutout: '72%',
          plugins: {
            legend: { position: 'bottom', labels: { color: DARK.text, font: { size: 11 }, boxWidth: 10, padding: 10 } },
            tooltip: { backgroundColor: DARK.tooltip.bg, titleColor: DARK.tooltip.title, bodyColor: DARK.tooltip.body, borderColor: DARK.border, borderWidth: 1, padding: 10, cornerRadius: 8 },
          },
        },
      });
    }

    // Barras horizontales: Por Ubicación
    if (this.horizBarCanvas?.nativeElement) {
      const { labels, counts } = this.buildLocationData();
      const maxC = Math.max(...counts, 1);
      this.charts[7] = new Chart(this.horizBarCanvas.nativeElement, {
        type: 'bar',
        data: {
          labels,
          datasets: [{
            label: 'Equipos',
            data: counts,
            backgroundColor: counts.map(c => `rgba(59,130,246,${(0.35 + (c/maxC)*0.65).toFixed(2)})`),
            borderRadius: 4,
            borderSkipped: false,
          }],
        },
        options: {
          indexAxis: 'y',
          responsive: true, maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: { backgroundColor: DARK.tooltip.bg, titleColor: DARK.tooltip.title, bodyColor: DARK.tooltip.body, borderColor: DARK.border, borderWidth: 1, padding: 10, cornerRadius: 8 },
          },
          scales: {
            x: { beginAtZero: true, grid: { color: DARK.grid }, ticks: { color: DARK.text, font: { size: 11 }, stepSize: 1 } },
            y: { grid: { display: false }, ticks: { color: DARK.text, font: { size: 11 } } },
          },
        },
      });
    }
  }

  ngOnInit(): void {
    forkJoin({ kpis: this.svc.getKpis(), historial: this.svc.getHistorial() }).subscribe({
      next: ({ kpis, historial }) => {
        this.kpis = kpis; this.historial = historial; this.cargando = false;
        setTimeout(() => this.initAllCharts(), 60);
      },
      error: () => { this.error = 'No se pudo cargar el panel ejecutivo.'; this.cargando = false; },
    });
  }

  ngOnDestroy(): void {
    this.charts.forEach(c => c?.destroy());
  }
}

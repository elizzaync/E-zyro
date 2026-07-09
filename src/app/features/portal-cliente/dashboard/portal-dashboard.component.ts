import {
  Component, OnInit, OnDestroy,
  ElementRef, ViewChild, inject,
  ChangeDetectionStrategy, ChangeDetectorRef, NgZone,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { forkJoin, Subscription } from 'rxjs';
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
import { ThemeService } from '../../../core/services/theme.service';

Chart.register(
  DoughnutController, ArcElement,
  BarController, BarElement,
  LineController, LineElement, PointElement,
  CategoryScale, LinearScale,
  Tooltip, Legend, Filler,
);

// Colores de acento invariantes (no cambian con el tema)
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
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PortalDashboardComponent implements OnInit, OnDestroy {
  @ViewChild('spkTotal') spkTotal!: ElementRef<HTMLCanvasElement>;
  @ViewChild('spkVig')   spkVig!: ElementRef<HTMLCanvasElement>;
  @ViewChild('spkProx')  spkProx!: ElementRef<HTMLCanvasElement>;
  @ViewChild('spkVenc')  spkVenc!: ElementRef<HTMLCanvasElement>;
  @ViewChild('mixedChart') mixedCanvas!: ElementRef<HTMLCanvasElement>;
  @ViewChild('donut1')     donut1Canvas!: ElementRef<HTMLCanvasElement>;
  @ViewChild('donut2')     donut2Canvas!: ElementRef<HTMLCanvasElement>;
  @ViewChild('horizBar')   horizBarCanvas!: ElementRef<HTMLCanvasElement>;

  private charts: (Chart | null)[] = new Array(8).fill(null);
  private svc   = inject(PortalClienteService);
  private auth  = inject(AuthService);
  private cdr   = inject(ChangeDetectorRef);
  private ngZone = inject(NgZone);
  readonly theme = inject(ThemeService);           // ← FASE 2: servicio reactivo
  private themeSub!: Subscription;

  cargando  = true;
  error     = '';
  kpis: any = null;
  historial: any[] = [];

  // Precalculados una sola vez al cargar `historial` (no cambia después) —
  // nunca en el template, para no recorrer el arreglo en cada change detection.
  countVencidos = 0;
  countProximos = 0;
  countVigentes = 0;
  upcomingEvents: any[] = [];
  private kpiTrends: Record<string, { pct: number; up: boolean }> = {};

  get saludo() { return this.auth.getUsuario()?.nombre_completo ?? 'Portal Cliente'; }
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

  private calcularKpiTrend(badge: string | null): { pct: number; up: boolean } {
    const curr = this.countByMonthBadge(badge, 0);
    const prev = this.countByMonthBadge(badge, -1);
    if (prev === 0 && curr === 0) return { pct: 0, up: true };
    if (prev === 0) return { pct: 100, up: true };
    const pct = Math.round(((curr - prev) / prev) * 100);
    return { pct: Math.abs(pct), up: pct >= 0 };
  }

  kpiTrend(badge: string | null): { pct: number; up: boolean } {
    return this.kpiTrends[badge ?? 'null'] ?? { pct: 0, up: true };
  }

  /** Deriva de `historial` todo lo que el template antes recalculaba en cada
   *  change detection (getters). Se llama una sola vez, al cargar los datos. */
  private precalcularDerivadosDeHistorial(): void {
    this.countVencidos = this.historial.filter(e => this.maintenanceStatus(e).badge === 'badge-danger').length;
    this.countProximos = this.historial.filter(e => this.maintenanceStatus(e).badge === 'badge-warning').length;
    this.countVigentes = this.historial.length - this.countVencidos - this.countProximos;

    this.kpiTrends = {
      'null':           this.calcularKpiTrend(null),
      'badge-success':  this.calcularKpiTrend('badge-success'),
      'badge-warning':  this.calcularKpiTrend('badge-warning'),
      'badge-danger':   this.calcularKpiTrend('badge-danger'),
    };

    const today = new Date(); today.setHours(0,0,0,0);
    const next7 = new Date(today); next7.setDate(today.getDate() + 7);
    this.upcomingEvents = this.historial
      .filter(eq => { if (!eq.proximo_mantenimiento) return false; const d = new Date(eq.proximo_mantenimiento); return d >= today && d <= next7; })
      .sort((a,b) => new Date(a.proximo_mantenimiento).getTime() - new Date(b.proximo_mantenimiento).getTime())
      .slice(0, 12);
  }

  daysUntil(dateStr: string): number {
    const today = new Date(); today.setHours(0,0,0,0);
    return Math.ceil((new Date(dateStr).getTime() - today.getTime()) / 86_400_000);
  }

  eventClass(dateStr: string): string {
    const d = this.daysUntil(dateStr);
    if (d <= 0) return 'ev-danger';
    if (d <= 3) return 'ev-danger';
    if (d <= 7) return 'ev-warning';
    return 'ev-ok';
  }

  // ── FASE 2: leer tokens del sistema de diseño ─────────────────────────────
  private cssToken(name: string): string {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }

  /** Devuelve los colores correctos para Chart.js según el tema activo */
  private chartTheme() {
    const dark = this.theme.isDark;
    return {
      text:    this.cssToken('--text-muted')   || (dark ? '#94a3b8' : '#6b7280'),
      title:   this.cssToken('--text-main')    || (dark ? '#f8fafc' : '#111827'),
      panelBg: this.cssToken('--card-bg')      || (dark ? '#1e293b' : '#ffffff'),
      border:  this.cssToken('--border-color') || (dark ? '#334155' : '#e5e7eb'),
      grid:    dark ? 'rgba(255,255,255,.05)' : 'rgba(0,0,0,.06)',
    };
  }

  /** Actualizar colores de todos los charts sin destruirlos (FASE 2) */
  private applyThemeToCharts(): void {
    const t = this.chartTheme();
    for (const chart of this.charts) {
      if (!chart) continue;
      const opts = chart.options as any;

      // Escalas: ticks + grid
      for (const scale of Object.values(opts.scales ?? {}) as any[]) {
        if (scale.ticks) scale.ticks.color = t.text;
        if (scale.grid)  scale.grid.color  = t.grid;
      }
      // Leyenda
      if (opts.plugins?.legend?.labels) {
        opts.plugins.legend.labels.color = t.text;
      }
      // Tooltip
      if (opts.plugins?.tooltip) {
        opts.plugins.tooltip.backgroundColor = t.panelBg;
        opts.plugins.tooltip.titleColor       = t.title;
        opts.plugins.tooltip.bodyColor        = t.text;
        opts.plugins.tooltip.borderColor      = t.border;
      }
      chart.update('none'); // sin animación al cambiar tema
    }
  }

  // ── Datos de gráficos ─────────────────────────────────────────────────────

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

  private buildMonthlyData() {
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

  private buildLocationData() {
    const map = new Map<string, number>();
    this.historial.forEach(eq => {
      const loc = (eq.ubicacion || 'Sin ubicación').trim().substring(0, 28);
      map.set(loc, (map.get(loc) ?? 0) + 1);
    });
    const sorted = Array.from(map.entries()).sort((a,b) => b[1]-a[1]).slice(0, 9);
    return { labels: sorted.map(([k]) => k), counts: sorted.map(([,v]) => v) };
  }

  private buildProyectoData() {
    const map = new Map<string, number>();
    this.historial.forEach(eq => { const p = (eq.proyecto || 'Sin Proyecto').trim(); map.set(p, (map.get(p) ?? 0) + 1); });
    const sorted = Array.from(map.entries()).sort((a,b) => b[1]-a[1]);
    if (sorted.length <= 4) return { labels: sorted.map(([k]) => k), counts: sorted.map(([,v]) => v) };
    const top = sorted.slice(0, 3);
    const otros = sorted.slice(3).reduce((s,[,v]) => s+v, 0);
    return { labels: [...top.map(([k]) => k), 'Otros'], counts: [...top.map(([,v]) => v), otros] };
  }

  // ── Inicializar gráficos (usa chartTheme() para colores dinámicos) ────────

  private spark(canvas: HTMLCanvasElement | undefined, data: number[], color: string): Chart | null {
    if (!canvas) return null;
    return new Chart(canvas, {
      type: 'line',
      data: { labels: data.map(() => ''), datasets: [{ data, borderColor: color, borderWidth: 2, fill: true, backgroundColor: color + '22', tension: 0.45, pointRadius: 0, pointHoverRadius: 0 }] },
      options: { responsive: true, maintainAspectRatio: false, animation: { duration: 700 }, plugins: { legend: { display: false }, tooltip: { enabled: false } }, scales: { x: { display: false }, y: { display: false } } },
    });
  }

  private initAllCharts(): void {
    this.charts.forEach((c, i) => { c?.destroy(); this.charts[i] = null; });
    const t = this.chartTheme(); // colores del tema actual

    // Sparklines (sin escalas visibles, no necesitan tema en runtime)
    this.charts[0] = this.spark(this.spkTotal?.nativeElement, this.buildSparkData(null),            P.blue);
    this.charts[1] = this.spark(this.spkVig?.nativeElement,   this.buildSparkData('badge-success'), P.green);
    this.charts[2] = this.spark(this.spkProx?.nativeElement,  this.buildSparkData('badge-warning'), P.amber);
    this.charts[3] = this.spark(this.spkVenc?.nativeElement,  this.buildSparkData('badge-danger'),  P.red);

    // Mixed Chart
    if (this.mixedCanvas?.nativeElement) {
      const { labels, ejecutados, programados } = this.buildMonthlyData();
      this.charts[4] = new Chart(this.mixedCanvas.nativeElement, {
        type: 'bar',
        data: { labels, datasets: [
          { type: 'bar' as const, label: 'Ejecutados', data: ejecutados, backgroundColor: P.brand + 'CC', borderRadius: 5, borderSkipped: false, yAxisID: 'y' },
          { type: 'line' as const, label: 'Programados', data: programados, borderColor: P.blue, backgroundColor: P.blue + '1A', borderWidth: 2.5, fill: true, tension: 0.4, pointRadius: 4, pointBackgroundColor: P.blue, pointBorderColor: t.panelBg, pointBorderWidth: 2, yAxisID: 'y' },
        ]},
        options: {
          responsive: true, maintainAspectRatio: false,
          plugins: {
            legend: { position: 'top', labels: { color: t.text, font: { size: 12, weight: 600 }, boxWidth: 12, padding: 16 } },
            tooltip: { backgroundColor: t.panelBg, titleColor: t.title, bodyColor: t.text, borderColor: t.border, borderWidth: 1, padding: 12, cornerRadius: 10 },
          },
          scales: {
            x: { grid: { color: t.grid }, ticks: { color: t.text, font: { size: 11 } } },
            y: { beginAtZero: true, grid: { color: t.grid }, ticks: { color: t.text, font: { size: 11 }, stepSize: 1 } },
          },
        },
      });
    }

    // Donut 1: Cumplimiento
    if (this.donut1Canvas?.nativeElement) {
      const op = this.countVigentes + this.countProximos;
      this.charts[5] = new Chart(this.donut1Canvas.nativeElement, {
        type: 'doughnut',
        data: { labels: ['Operativos', 'Vencidos'], datasets: [{ data: [op, this.countVencidos], backgroundColor: [P.green, P.red], hoverBackgroundColor: ['#059669','#dc2626'], borderWidth: 2, borderColor: t.panelBg }] },
        options: { responsive: true, maintainAspectRatio: false, cutout: '72%', plugins: { legend: { position: 'bottom', labels: { color: t.text, font: { size: 11 }, boxWidth: 10, padding: 10 } }, tooltip: { backgroundColor: t.panelBg, titleColor: t.title, bodyColor: t.text, borderColor: t.border, borderWidth: 1, padding: 10, cornerRadius: 8 } } },
      });
    }

    // Donut 2: Por Proyecto
    if (this.donut2Canvas?.nativeElement) {
      const { labels, counts } = this.buildProyectoData();
      const colors = [P.blue, P.amber, P.purple, P.cyan, P.green];
      this.charts[6] = new Chart(this.donut2Canvas.nativeElement, {
        type: 'doughnut',
        data: { labels, datasets: [{ data: counts, backgroundColor: colors.slice(0, labels.length), borderWidth: 2, borderColor: t.panelBg }] },
        options: { responsive: true, maintainAspectRatio: false, cutout: '72%', plugins: { legend: { position: 'bottom', labels: { color: t.text, font: { size: 11 }, boxWidth: 10, padding: 10 } }, tooltip: { backgroundColor: t.panelBg, titleColor: t.title, bodyColor: t.text, borderColor: t.border, borderWidth: 1, padding: 10, cornerRadius: 8 } } },
      });
    }

    // Barras Horizontales: Por Ubicación
    if (this.horizBarCanvas?.nativeElement) {
      const { labels, counts } = this.buildLocationData();
      const maxC = Math.max(...counts, 1);
      this.charts[7] = new Chart(this.horizBarCanvas.nativeElement, {
        type: 'bar',
        data: { labels, datasets: [{ label: 'Equipos', data: counts, backgroundColor: counts.map(c => `rgba(59,130,246,${(0.35 + (c/maxC)*0.65).toFixed(2)})`), borderRadius: 4, borderSkipped: false }] },
        options: {
          indexAxis: 'y', responsive: true, maintainAspectRatio: false,
          plugins: { legend: { display: false }, tooltip: { backgroundColor: t.panelBg, titleColor: t.title, bodyColor: t.text, borderColor: t.border, borderWidth: 1, padding: 10, cornerRadius: 8 } },
          scales: {
            x: { beginAtZero: true, grid: { color: t.grid }, ticks: { color: t.text, font: { size: 11 }, stepSize: 1 } },
            y: { grid: { display: false }, ticks: { color: t.text, font: { size: 11 } } },
          },
        },
      });
    }
  }

  ngOnInit(): void {
    // FASE 2: suscribirse al tema — actualizar charts sin destruirlos
    this.themeSub = this.theme.isDark$.subscribe(() => {
      if (this.charts.some(c => c !== null)) {
        this.applyThemeToCharts();
      }
    });

    forkJoin({ kpis: this.svc.getKpis(), historial: this.svc.getHistorial() }).subscribe({
      next: ({ kpis, historial }) => {
        this.kpis = kpis; this.historial = historial; this.cargando = false;
        this.precalcularDerivadosDeHistorial();
        this.cdr.markForCheck();
        // Chart.js registra sus propios listeners (mousemove/click) por cada
        // canvas para tooltips/hover. Creados fuera de la Angular zone, esos
        // listeners quedan fuera para siempre: mover el mouse sobre cualquiera
        // de los 8 gráficos ya no dispara change detection de toda la app
        // (mismo patrón que el fix de public/background.js).
        setTimeout(() => this.ngZone.runOutsideAngular(() => this.initAllCharts()), 60);
      },
      error: () => {
        this.error = 'No se pudo cargar el panel ejecutivo.';
        this.cargando = false;
        this.cdr.markForCheck();
      },
    });
  }

  ngOnDestroy(): void {
    this.themeSub?.unsubscribe();
    this.charts.forEach(c => c?.destroy());
  }
}

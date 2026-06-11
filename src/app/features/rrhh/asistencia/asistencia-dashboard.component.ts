import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RrhhService, PeriodoDto, ResumenEmpleadoDto } from '../../../core/services/rrhh.service';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-asistencia-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './asistencia-dashboard.component.html',
  styleUrls: ['./asistencia-dashboard.component.css']
})
export class AsistenciaDashboardComponent implements OnInit {

  // ── Estado de UI ──────────────────────────────────────────────────────────
  cargando  = true;
  error     = '';
  searchTerm = '';

  // ── Navegación de período ──────────────────────────────────────────────────
  semanaRef  = new Date();
  fechaInicio = '';
  fechaFin    = '';

  // ── Datos ──────────────────────────────────────────────────────────────────
  periodo:   PeriodoDto | null   = null;
  empleados: ResumenEmpleadoDto[] = [];

  // ── Modal advertencia ─────────────────────────────────────────────────────
  showModalAdv           = false;
  empleadoSeleccionado: ResumenEmpleadoDto | null = null;
  advCargando            = false;
  advError               = '';
  advExito               = '';

  constructor(
    private rrhhService: RrhhService,
    private authService: AuthService
  ) {}

  ngOnInit(): void {
    this.setSemana();
    this.cargar();
  }

  // ── Período ───────────────────────────────────────────────────────────────

  private setSemana(): void {
    this.fechaInicio = this.toISODate(this.lunesDe(this.semanaRef));
    this.fechaFin    = this.toISODate(this.sabadoDe(this.semanaRef));
  }

  private lunesDe(ref: Date): Date {
    const d   = new Date(ref);
    const day = d.getDay();
    d.setDate(d.getDate() - (day === 0 ? 6 : day - 1));
    return d;
  }

  private sabadoDe(ref: Date): Date {
    const lunes = this.lunesDe(ref);
    lunes.setDate(lunes.getDate() + 5);
    return lunes;
  }

  private toISODate(d: Date): string {
    return d.toISOString().split('T')[0];
  }

  get labelSemana(): string {
    if (!this.fechaInicio || !this.fechaFin) return '';
    const fi = new Date(this.fechaInicio + 'T00:00:00');
    const ff = new Date(this.fechaFin    + 'T00:00:00');
    const short: Intl.DateTimeFormatOptions = { day: '2-digit', month: 'short' };
    return `${fi.toLocaleDateString('es-PE', short)} — ${ff.toLocaleDateString('es-PE', { ...short, year: 'numeric' })}`;
  }

  get esSemanaActual(): boolean {
    const lunesHoy = this.toISODate(this.lunesDe(new Date()));
    return this.fechaInicio === lunesHoy;
  }

  irSemanaAnterior(): void {
    this.semanaRef = new Date(this.semanaRef.getTime() - 7 * 86400000);
    this.setSemana();
    this.cargar();
  }

  irSemanaSiguiente(): void {
    if (this.esSemanaActual) return;
    this.semanaRef = new Date(this.semanaRef.getTime() + 7 * 86400000);
    this.setSemana();
    this.cargar();
  }

  // ── Carga de datos ────────────────────────────────────────────────────────

  private cargar(): void {
    this.cargando = true;
    this.error    = '';
    this.rrhhService.getResumenAsistencia({
      fecha_inicio: this.fechaInicio,
      fecha_fin:    this.fechaFin,
    }).subscribe({
      next: (res) => {
        this.periodo   = res.periodo;
        this.empleados = res.empleados;
        this.cargando  = false;
      },
      error: () => {
        this.error    = 'No se pudo cargar el resumen de asistencia.';
        this.cargando = false;
      },
    });
  }

  // ── Permisos ──────────────────────────────────────────────────────────────

  get puedeEmitir(): boolean {
    const rol = (this.authService.getUsuario()?.rol || '').trim().toLowerCase()
      .replace(/\s+/g, '').replace(/\xa0/g, '');
    return !['técnicodecampo', 'clienteexterno'].includes(rol);
  }

  // ── KPIs ──────────────────────────────────────────────────────────────────

  get kpis() {
    return {
      total:           this.empleados.length,
      alDia:           this.empleados.filter(e => e.horas_faltantes === 0).length,
      conFaltas:       this.empleados.filter(e => e.horas_faltantes > 0).length,
      conAdvertencias: this.empleados.filter(e => e.advertencias > 0).length,
    };
  }

  // ── Filtrado ──────────────────────────────────────────────────────────────

  get filteredEmpleados(): ResumenEmpleadoDto[] {
    if (!this.searchTerm.trim()) return this.empleados;
    const t = this.searchTerm.toLowerCase();
    return this.empleados.filter(e =>
      e.nombreCompleto.toLowerCase().includes(t) ||
      e.cargo.toLowerCase().includes(t) ||
      e.area.toLowerCase().includes(t)
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  barraAncho(emp: ResumenEmpleadoDto): number {
    return Math.min(100, emp.porcentaje);
  }

  barraClase(emp: ResumenEmpleadoDto): string {
    if (emp.porcentaje >= 100) return 'fill-verde';
    if (emp.porcentaje >= 75)  return 'fill-amber';
    return 'fill-rojo';
  }

  estadoClase(emp: ResumenEmpleadoDto): string {
    if (emp.horas_faltantes === 0) return 'badge-success';
    if (emp.porcentaje >= 75)      return 'badge-warning';
    return 'badge-danger';
  }

  estadoLabel(emp: ResumenEmpleadoDto): string {
    if (emp.horas_faltantes === 0) return 'Al día';
    return `−${emp.horas_faltantes.toFixed(1)}h`;
  }

  advClase(n: number): string {
    if (n === 0) return '';
    if (n === 1) return 'adv-uno';
    if (n === 2) return 'adv-dos';
    return 'adv-tres';
  }

  // ── Modal advertencia ─────────────────────────────────────────────────────

  abrirModalAdv(emp: ResumenEmpleadoDto): void {
    this.empleadoSeleccionado = emp;
    this.advError    = '';
    this.advExito    = '';
    this.advCargando = false;
    this.showModalAdv = true;
  }

  cerrarModalAdv(): void {
    this.showModalAdv         = false;
    this.empleadoSeleccionado = null;
  }

  confirmarAdvertencia(): void {
    if (!this.empleadoSeleccionado) return;
    this.advCargando = true;
    this.advError    = '';

    this.rrhhService.emitirAdvertencia(this.empleadoSeleccionado.id).subscribe({
      next: (res) => {
        this.advCargando = false;
        this.advExito    = res.mensaje;
        const idx = this.empleados.findIndex(e => e.id === this.empleadoSeleccionado!.id);
        if (idx !== -1) {
          this.empleados[idx] = { ...this.empleados[idx], advertencias: res.numero_advertencia };
        }
        setTimeout(() => this.cerrarModalAdv(), 1500);
      },
      error: (err) => {
        this.advCargando = false;
        this.advError    = err?.error?.detail ?? 'Error al emitir la advertencia.';
      },
    });
  }
}

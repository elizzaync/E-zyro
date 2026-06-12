import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import * as L from 'leaflet';

import {
  RrhhService,
  PeriodoDto,
  ResumenEmpleadoDto,
  DetalleDiaDto,
  GeoDto,
} from '../../../core/services/rrhh.service';
import { AuthService } from '../../../core/services/auth.service';

// Corrige los íconos por defecto de Leaflet con Webpack/Angular
const iconDefault = L.icon({
  iconUrl:      'assets/leaflet/marker-icon.png',
  iconRetinaUrl:'assets/leaflet/marker-icon-2x.png',
  shadowUrl:    'assets/leaflet/marker-shadow.png',
  iconSize:    [25, 41],
  iconAnchor:  [12, 41],
  popupAnchor: [1, -34],
  shadowSize:  [41, 41],
});
L.Marker.prototype.options.icon = iconDefault;

type ReporteTipo = 'semanal' | 'mensual' | 'tardanzas' | 'individual' | 'horas-extra';

@Component({
  selector: 'app-asistencia-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './asistencia-dashboard.component.html',
  styleUrls: ['./asistencia-dashboard.component.css'],
})
export class AsistenciaDashboardComponent implements OnInit, OnDestroy{

  // ── Estado general ─────────────────────────────────────────────────────────
  cargando   = true;
  error      = '';
  searchTerm = '';

  // ── Período ────────────────────────────────────────────────────────────────
  semanaRef   = new Date();
  fechaInicio = '';
  fechaFin    = '';
  periodo:    PeriodoDto | null = null;

  // ── Datos + paginación ─────────────────────────────────────────────────────
  empleados:    ResumenEmpleadoDto[] = [];
  currentPage   = 1;
  readonly PER_PAGE = 10;
  totalRegistros = 0;
  totalPaginas   = 1;

  // ── Detalle diario ─────────────────────────────────────────────────────────
  empleadoDetalle:  ResumenEmpleadoDto | null = null;
  detalleLoading    = false;
  detalleError      = '';
  detalleDias:      DetalleDiaDto[] = [];
  detallePage       = 1;
  detalleTotalPag   = 1;
  detalleTotalDias  = 0;
  readonly DETALLE_PER_PAGE = 10;

  // ── Mapa ───────────────────────────────────────────────────────────────────
  showMapModal    = false;
  mapDia:         DetalleDiaDto | null = null;
  private leafletMap: L.Map | null = null;

  // ── Reportes ───────────────────────────────────────────────────────────────
  showReportes     = true;
  reporteEmpleadoId = '';
  reporteCargando:  Partial<Record<ReporteTipo, 'xlsx' | 'pdf' | null>> = {};

  // ── Modal advertencia ──────────────────────────────────────────────────────
  showModalAdv              = false;
  empleadoSeleccionado: ResumenEmpleadoDto | null = null;
  advCargando               = false;
  advError                  = '';
  advExito                  = '';

  constructor(
    private rrhhService: RrhhService,
    private authService: AuthService,
  ) {}

  ngOnInit(): void {
    this.setSemana();
    this.cargar();
  }

  ngOnDestroy(): void {
    this.destroyMap();
  }

  // ── Período ────────────────────────────────────────────────────────────────

  private setSemana(): void {
    this.fechaInicio = this.toISODate(this.lunesDe(this.semanaRef));
    this.fechaFin    = this.toISODate(this.sabadoDe(this.semanaRef));
  }

  private lunesDe(ref: Date): Date {
    const d = new Date(ref); const day = d.getDay();
    d.setDate(d.getDate() - (day === 0 ? 6 : day - 1));
    return d;
  }
  private sabadoDe(ref: Date): Date {
    const d = this.lunesDe(ref); d.setDate(d.getDate() + 5); return d;
  }
  private toISODate(d: Date): string { return d.toISOString().split('T')[0]; }

  get labelSemana(): string {
    if (!this.fechaInicio || !this.fechaFin) return '';
    const fi = new Date(this.fechaInicio + 'T00:00:00');
    const ff = new Date(this.fechaFin    + 'T00:00:00');
    const s: Intl.DateTimeFormatOptions = { day: '2-digit', month: 'short' };
    return `${fi.toLocaleDateString('es-PE', s)} — ${ff.toLocaleDateString('es-PE', { ...s, year: 'numeric' })}`;
  }

  get esSemanaActual(): boolean {
    return this.fechaInicio === this.toISODate(this.lunesDe(new Date()));
  }

  irSemanaAnterior(): void {
    this.semanaRef = new Date(this.semanaRef.getTime() - 7 * 86400000);
    this.setSemana(); this.currentPage = 1; this.cargar();
  }
  irSemanaSiguiente(): void {
    if (this.esSemanaActual) return;
    this.semanaRef = new Date(this.semanaRef.getTime() + 7 * 86400000);
    this.setSemana(); this.currentPage = 1; this.cargar();
  }

  // ── Carga de datos ─────────────────────────────────────────────────────────

  private cargar(): void {
    this.cargando = true; this.error = '';
    this.rrhhService.getResumenAsistencia({
      fecha_inicio: this.fechaInicio,
      fecha_fin:    this.fechaFin,
      page:  this.currentPage,
      limit: this.PER_PAGE,
    }).subscribe({
      next: (res) => {
        this.periodo        = res.periodo;
        this.empleados      = res.empleados;
        this.totalRegistros = res.total;
        this.totalPaginas   = res.total_paginas;
        this.cargando = false;
      },
      error: () => {
        this.error    = 'No se pudo cargar el resumen de asistencia.';
        this.cargando = false;
      },
    });
  }

  // ── Paginación tabla principal ─────────────────────────────────────────────

  get rangoMostrando() {
    const desde = (this.currentPage - 1) * this.PER_PAGE + 1;
    const hasta = Math.min(this.currentPage * this.PER_PAGE, this.totalRegistros);
    return { desde, hasta, total: this.totalRegistros };
  }

  get paginasBotones(): number[] {
    const total = this.totalPaginas; const cur = this.currentPage;
    const pages: number[] = [];
    for (let i = Math.max(1, cur - 2); i <= Math.min(total, cur + 2); i++) pages.push(i);
    return pages;
  }

  irPagina(p: number): void {
    if (p < 1 || p > this.totalPaginas) return;
    this.currentPage = p; this.cargar();
  }

  // ── Permisos ───────────────────────────────────────────────────────────────

  get puedeEmitir(): boolean {
    const rol = (this.authService.getUsuario()?.rol || '')
      .trim().toLowerCase().replace(/\s+/g,'').replace(/\xa0/g,'');
    return !['técnicodecampo','clienteexterno'].includes(rol);
  }

  // ── KPIs ───────────────────────────────────────────────────────────────────

  get kpis() {
    return {
      total:           this.totalRegistros,
      alDia:           this.empleados.filter(e => e.horas_faltantes === 0).length,
      conFaltas:       this.empleados.filter(e => e.horas_faltantes > 0).length,
      conAdvertencias: this.empleados.filter(e => e.advertencias > 0).length,
    };
  }

  // ── Filtrado ───────────────────────────────────────────────────────────────

  get filteredEmpleados(): ResumenEmpleadoDto[] {
    if (!this.searchTerm.trim()) return this.empleados;
    const t = this.searchTerm.toLowerCase();
    return this.empleados.filter(e =>
      e.nombreCompleto.toLowerCase().includes(t) ||
      e.cargo.toLowerCase().includes(t) ||
      e.area.toLowerCase().includes(t)
    );
  }

  // ── Helpers visuales ───────────────────────────────────────────────────────

  barraAncho(e: ResumenEmpleadoDto): number { return Math.min(100, e.porcentaje); }
  barraClase(e: ResumenEmpleadoDto): string {
    if (e.porcentaje >= 100) return 'fill-verde';
    if (e.porcentaje >= 75)  return 'fill-amber';
    return 'fill-rojo';
  }
  estadoClase(e: ResumenEmpleadoDto): string {
    if (e.horas_faltantes === 0) return 'badge-success';
    if (e.porcentaje >= 75)      return 'badge-warning';
    return 'badge-danger';
  }
  estadoLabel(e: ResumenEmpleadoDto): string {
    if (e.horas_faltantes === 0) return 'Al día';
    return `−${e.horas_faltantes.toFixed(1)}h`;
  }
  advClase(n: number): string {
    if (n === 1) return 'adv-uno'; if (n === 2) return 'adv-dos';
    return n >= 3 ? 'adv-tres' : '';
  }

  // ── Detalle diario ─────────────────────────────────────────────────────────

  abrirDetalle(emp: ResumenEmpleadoDto): void {
    if (this.empleadoDetalle?.id === emp.id) {
      this.empleadoDetalle = null; return;
    }
    this.empleadoDetalle = emp;
    this.detallePage     = 1;
    this.cargarDetalle();
  }

  private cargarDetalle(): void {
    if (!this.empleadoDetalle) return;
    this.detalleLoading = true; this.detalleError = '';
    this.rrhhService.getDetalleDiario(this.empleadoDetalle.id, {
      fecha_inicio: this.fechaInicio,
      fecha_fin:    this.fechaFin,
      page:  this.detallePage,
      limit: this.DETALLE_PER_PAGE,
    }).subscribe({
      next: (res) => {
        this.detalleDias     = res.dias;
        this.detalleTotalDias = res.total;
        this.detalleTotalPag  = res.total_paginas;
        this.detalleLoading  = false;
      },
      error: () => {
        this.detalleError   = 'No se pudo cargar el detalle.';
        this.detalleLoading = false;
      },
    });
  }

  irPaginaDetalle(p: number): void {
    if (p < 1 || p > this.detalleTotalPag) return;
    this.detallePage = p; this.cargarDetalle();
  }

  get paginasDetalleBtn(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(1, this.detallePage - 2); i <= Math.min(this.detalleTotalPag, this.detallePage + 2); i++)
      pages.push(i);
    return pages;
  }

  minVal(a: number, b: number): number { return Math.min(a, b); }

  estadoDiaClase(estado: string): string {
    switch (estado.toLowerCase()) {
      case 'al día':    return 'estado-aldia';
      case 'tardanza':  return 'estado-tardanza';
      case 'falta':     return 'estado-falta';
      case 'incompleto':return 'estado-incompleto';
      default:          return 'estado-aldia';
    }
  }

  formatHora(h: string | null): string { return h ?? '—'; }
  formatHoras(n: number): string { return n > 0 ? `${n.toFixed(1)}h` : '—'; }

  // ── Mapa ───────────────────────────────────────────────────────────────────

  abrirMapa(dia: DetalleDiaDto): void {
    this.mapDia      = dia;
    this.showMapModal = true;
    setTimeout(() => this.initMap(dia), 120);
  }

  cerrarMapa(): void {
    this.showMapModal = false;
    this.mapDia       = null;
    this.destroyMap();
  }

  private initMap(dia: DetalleDiaDto): void {
    this.destroyMap();
    const el = document.getElementById('leaflet-map-container');
    if (!el) return;

    const center: [number, number] = dia.geo_ingreso
      ? [dia.geo_ingreso.lat, dia.geo_ingreso.lng]
      : dia.geo_salida
        ? [dia.geo_salida.lat, dia.geo_salida.lng]
        : [-12.046374, -77.042793];

    this.leafletMap = L.map(el, { zoomControl: true }).setView(center, 15);

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© <a href="https://openstreetmap.org">OpenStreetMap</a>',
      maxZoom: 19,
    }).addTo(this.leafletMap);

    if (dia.geo_ingreso) {
      const icon = L.divIcon({
        html: `<div class="map-pin-green"><svg width="14" height="14" viewBox="0 0 24 24" fill="white"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z"/></svg></div>`,
        className: '', iconSize: [32, 32], iconAnchor: [16, 32],
      });
      L.marker([dia.geo_ingreso.lat, dia.geo_ingreso.lng], { icon })
        .addTo(this.leafletMap!).bindPopup('Ingreso').openPopup();
    }

    if (dia.geo_salida) {
      const icon = L.divIcon({
        html: `<div class="map-pin-red"><svg width="14" height="14" viewBox="0 0 24 24" fill="white"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z"/></svg></div>`,
        className: '', iconSize: [32, 32], iconAnchor: [16, 32],
      });
      L.marker([dia.geo_salida.lat, dia.geo_salida.lng], { icon })
        .addTo(this.leafletMap!).bindPopup('Salida');
    }

    if (dia.geo_ingreso && dia.geo_salida) {
      const bounds = L.latLngBounds(
        [dia.geo_ingreso.lat, dia.geo_ingreso.lng],
        [dia.geo_salida.lat, dia.geo_salida.lng],
      );
      this.leafletMap!.fitBounds(bounds, { padding: [40, 40] });
    }
  }

  private destroyMap(): void {
    if (this.leafletMap) { this.leafletMap.remove(); this.leafletMap = null; }
  }

  // ── Reportes ───────────────────────────────────────────────────────────────

  descargar(tipo: ReporteTipo, fmt: 'xlsx' | 'pdf'): void {
    this.reporteCargando = { ...this.reporteCargando, [tipo]: fmt };
    const params: Record<string, string> = { fmt };
    if (tipo === 'semanal')  { params['fecha_inicio'] = this.fechaInicio; params['fecha_fin'] = this.fechaFin; }
    if (tipo === 'individual' && this.reporteEmpleadoId) params['empleado_id'] = this.reporteEmpleadoId;

    this.rrhhService.descargarReporte(tipo, params).subscribe({
      next: (blob) => {
        const ext  = fmt === 'xlsx' ? 'xlsx' : 'pdf';
        const mime = fmt === 'xlsx'
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'application/pdf';
        const url  = URL.createObjectURL(new Blob([blob], { type: mime }));
        const a    = document.createElement('a');
        a.href     = url;
        a.download = `reporte_${tipo}_${new Date().toISOString().slice(0,10)}.${ext}`;
        a.click();
        URL.revokeObjectURL(url);
        this.reporteCargando = { ...this.reporteCargando, [tipo]: null };
      },
      error: () => {
        this.reporteCargando = { ...this.reporteCargando, [tipo]: null };
        alert('Error al generar el reporte. Intenta nuevamente.');
      },
    });
  }

  reporteEnCurso(tipo: ReporteTipo): boolean {
    return !!this.reporteCargando[tipo];
  }

  // ── Modal advertencia ──────────────────────────────────────────────────────

  abrirModalAdv(emp: ResumenEmpleadoDto): void {
    this.empleadoSeleccionado = emp;
    this.advError = ''; this.advExito = ''; this.advCargando = false;
    this.showModalAdv = true;
  }
  cerrarModalAdv(): void {
    this.showModalAdv         = false;
    this.empleadoSeleccionado = null;
  }
  confirmarAdvertencia(): void {
    if (!this.empleadoSeleccionado) return;
    this.advCargando = true; this.advError = '';
    this.rrhhService.emitirAdvertencia(this.empleadoSeleccionado.id).subscribe({
      next: (res) => {
        this.advCargando = false; this.advExito = res.mensaje;
        const idx = this.empleados.findIndex(e => e.id === this.empleadoSeleccionado!.id);
        if (idx !== -1) this.empleados[idx] = { ...this.empleados[idx], advertencias: res.numero_advertencia };
        setTimeout(() => this.cerrarModalAdv(), 1500);
      },
      error: (err) => {
        this.advCargando = false;
        this.advError    = err?.error?.detail ?? 'Error al emitir la advertencia.';
      },
    });
  }
}

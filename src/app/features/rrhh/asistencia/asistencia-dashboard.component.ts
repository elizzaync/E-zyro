import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AppModalComponent } from '../../../shared/components/modal/app-modal.component';
import * as L from 'leaflet';

import {
  RrhhService,
  PeriodoDto,
  ResumenEmpleadoDto,
  DetalleDiaDto,
  GeoDto,
  AsistenciaDiariaItemDto,
  EmpleadoLegajoDto,
} from '../../../core/services/rrhh.service';
import { AuthService } from '../../../core/services/auth.service';

// Corrige íconos Leaflet en Angular/Webpack
const iconDefault = L.icon({
  iconUrl:       'assets/leaflet/marker-icon.png',
  iconRetinaUrl: 'assets/leaflet/marker-icon-2x.png',
  shadowUrl:     'assets/leaflet/marker-shadow.png',
  iconSize:   [25, 41], iconAnchor: [12, 41],
  popupAnchor:[1, -34], shadowSize:  [41, 41],
});
L.Marker.prototype.options.icon = iconDefault;

@Component({
  selector: 'app-asistencia-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
  templateUrl: './asistencia-dashboard.component.html',
  styleUrls: ['./asistencia-dashboard.component.css'],
})
export class AsistenciaDashboardComponent implements OnInit, OnDestroy {

  // ── Tabs ───────────────────────────────────────────────────────────────────
  activeTab: 'semanal' | 'diaria' = 'semanal';

  // ── Reportes (colapsable) ──────────────────────────────────────────────────
  showReportes = true;

  rptGlobal = { fechaInicio: '', fechaFin: '', loading: false };
  rptIndividual = { fechaInicio: '', fechaFin: '', empleadoId: '', loading: false };
  rptHorasExtra = { fechaInicio: '', fechaFin: '', loading: false };

  listaEmpleados: EmpleadoLegajoDto[] = [];

  // ── Tab Semanal ────────────────────────────────────────────────────────────
  cargando   = true;
  error      = '';
  searchTerm = '';

  semanaRef   = new Date();
  fechaInicio = '';
  fechaFin    = '';
  periodo:    PeriodoDto | null = null;

  empleados:     ResumenEmpleadoDto[] = [];
  currentPage    = 1;
  readonly PER_PAGE = 10;
  totalRegistros = 0;
  totalPaginas   = 1;

  empleadoDetalle:   ResumenEmpleadoDto | null = null;
  detalleLoading     = false;
  detalleError       = '';
  detalleDias:       DetalleDiaDto[] = [];
  detallePage        = 1;
  detalleTotalPag    = 1;
  detalleTotalDias   = 0;
  readonly DETALLE_PER_PAGE = 10;

  showModalDetalle          = false;
  showModalAdv              = false;
  empleadoSeleccionado: ResumenEmpleadoDto | null = null;
  advCargando               = false;
  advError                  = '';
  advExito                  = '';

  // ── Tab Diaria ─────────────────────────────────────────────────────────────
  fechaDiaria = this.toISODate(new Date());
  diariaLoading = false;
  diariaError   = '';
  diariaEmpleados:  AsistenciaDiariaItemDto[] = [];
  diariaPage    = 1;
  diariaTotalPag= 1;
  diariaTotalReg= 0;
  readonly DIARIA_PER_PAGE = 10;

  // ── Mapa (compartido) ──────────────────────────────────────────────────────
  showMapModal   = false;
  mapLabel       = '';
  mapGeoIngreso: GeoDto | null = null;
  mapGeoSalida:  GeoDto | null = null;
  private leafletMap: L.Map | null = null;

  constructor(
    private rrhhService: RrhhService,
    private authService: AuthService,
  ) {}

  ngOnInit(): void {
    this.setSemana();
    this.cargar();
    this.cargarListaEmpleados();
    // Inicializar filtros de reportes con la semana actual
    this.rptGlobal.fechaInicio     = this.fechaInicio;
    this.rptGlobal.fechaFin        = this.fechaFin;
    this.rptHorasExtra.fechaInicio = this.fechaInicio;
    this.rptHorasExtra.fechaFin    = this.fechaFin;
    this.rptIndividual.fechaInicio = this.fechaInicio;
    this.rptIndividual.fechaFin    = this.fechaFin;
  }

  ngOnDestroy(): void {
    this.destroyMap();
  }

  setTab(tab: 'semanal' | 'diaria'): void {
    this.activeTab = tab;
    if (tab === 'diaria' && this.diariaEmpleados.length === 0) {
      this.cargarDiaria();
    }
  }

  // ── Lista empleados para selector ─────────────────────────────────────────

  private cargarListaEmpleados(): void {
    this.rrhhService.getTodosEmpleados().subscribe({
      next: (res) => { this.listaEmpleados = res.empleados; },
      error: () => {},
    });
  }

  // ── Período semanal ────────────────────────────────────────────────────────

  private setSemana(): void {
    this.fechaInicio = this.toISODate(this.lunesDe(this.semanaRef));
    this.fechaFin    = this.toISODate(this.sabadoDe(this.semanaRef));
  }
  private lunesDe(ref: Date): Date {
    const d = new Date(ref); const day = d.getDay();
    d.setDate(d.getDate() - (day === 0 ? 6 : day - 1)); return d;
  }
  private sabadoDe(ref: Date): Date {
    const d = this.lunesDe(ref); d.setDate(d.getDate() + 5); return d;
  }
  toISODate(d: Date): string { return d.toISOString().split('T')[0]; }

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

  // ── Carga semanal ──────────────────────────────────────────────────────────

  private cargar(): void {
    this.cargando = true; this.error = '';
    this.rrhhService.getResumenAsistencia({
      fecha_inicio: this.fechaInicio, fecha_fin: this.fechaFin,
      page: this.currentPage, limit: this.PER_PAGE,
    }).subscribe({
      next: (res) => {
        this.periodo        = res.periodo;
        this.empleados      = res.empleados;
        this.totalRegistros = res.total;
        this.totalPaginas   = res.total_paginas;
        this.cargando = false;
      },
      error: () => { this.error = 'No se pudo cargar el resumen de asistencia.'; this.cargando = false; },
    });
  }

  // ── Paginación semanal ─────────────────────────────────────────────────────

  get rangoMostrando() {
    const desde = (this.currentPage - 1) * this.PER_PAGE + 1;
    const hasta = Math.min(this.currentPage * this.PER_PAGE, this.totalRegistros);
    return { desde, hasta, total: this.totalRegistros };
  }
  get paginasBotones(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(1, this.currentPage - 2); i <= Math.min(this.totalPaginas, this.currentPage + 2); i++) pages.push(i);
    return pages;
  }
  irPagina(p: number): void {
    if (p < 1 || p > this.totalPaginas) return;
    this.currentPage = p; this.cargar();
  }

  // ── Permisos ───────────────────────────────────────────────────────────────

  get puedeEmitir(): boolean {
    const rol = (this.authService.getUsuario()?.rol || '').trim().toLowerCase()
      .replace(/\s+/g,'').replace(/\xa0/g,'');
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

  // ── Filtrado semanal ───────────────────────────────────────────────────────

  get filteredEmpleados(): ResumenEmpleadoDto[] {
    if (!this.searchTerm.trim()) return this.empleados;
    const t = this.searchTerm.toLowerCase();
    return this.empleados.filter(e =>
      e.nombreCompleto.toLowerCase().includes(t) ||
      e.cargo.toLowerCase().includes(t) || e.area.toLowerCase().includes(t));
  }

  // ── Helpers visuales semanal ───────────────────────────────────────────────

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
    return e.horas_faltantes === 0 ? 'Al día' : `−${e.horas_faltantes.toFixed(1)}h`;
  }
  advClase(n: number): string {
    if (n === 1) return 'adv-uno'; if (n === 2) return 'adv-dos';
    return n >= 3 ? 'adv-tres' : '';
  }

  // ── Detalle diario (panel expandible en tab semanal) ───────────────────────

  abrirDetalle(emp: ResumenEmpleadoDto): void {
    this.empleadoDetalle = emp; this.detallePage = 1;
    this.showModalDetalle = true; this.cargarDetalle();
  }
  cerrarModalDetalle(): void {
    this.showModalDetalle = false; this.empleadoDetalle = null;
  }
  private cargarDetalle(): void {
    if (!this.empleadoDetalle) return;
    this.detalleLoading = true; this.detalleError = '';
    this.rrhhService.getDetalleDiario(this.empleadoDetalle.id, {
      fecha_inicio: this.fechaInicio, fecha_fin: this.fechaFin,
      page: this.detallePage, limit: this.DETALLE_PER_PAGE,
    }).subscribe({
      next: (res) => {
        this.detalleDias     = res.dias;
        this.detalleTotalDias = res.total;
        this.detalleTotalPag  = res.total_paginas;
        this.detalleLoading  = false;
      },
      error: () => { this.detalleError = 'No se pudo cargar el detalle.'; this.detalleLoading = false; },
    });
  }
  irPaginaDetalle(p: number): void {
    if (p < 1 || p > this.detalleTotalPag) return;
    this.detallePage = p; this.cargarDetalle();
  }
  get paginasDetalleBtn(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(1, this.detallePage - 2); i <= Math.min(this.detalleTotalPag, this.detallePage + 2); i++) pages.push(i);
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
  formatCoord(v: number | null): string { return v !== null ? v.toFixed(5) : '—'; }

  private _uuidRx = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  safeArea(s: string): string {
    if (!s || this._uuidRx.test(s.trim())) return '';
    return ` · ${s}`;
  }

  // ── Modal advertencia ──────────────────────────────────────────────────────

  abrirModalAdv(emp: ResumenEmpleadoDto): void {
    this.empleadoSeleccionado = emp; this.advError = ''; this.advExito = '';
    this.advCargando = false; this.showModalAdv = true;
  }
  cerrarModalAdv(): void { this.showModalAdv = false; this.empleadoSeleccionado = null; }
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
      error: (err) => { this.advCargando = false; this.advError = err?.error?.detail ?? 'Error al emitir la advertencia.'; },
    });
  }

  // ── Tab Diaria ─────────────────────────────────────────────────────────────

  onFechaDiariaChange(): void { this.diariaPage = 1; this.cargarDiaria(); }

  cargarDiaria(): void {
    this.diariaLoading = true; this.diariaError = '';
    this.rrhhService.getAsistenciaDiaria(this.fechaDiaria, this.diariaPage, this.DIARIA_PER_PAGE).subscribe({
      next: (res) => {
        this.diariaEmpleados = res.empleados;
        this.diariaTotalReg  = res.total;
        this.diariaTotalPag  = res.total_paginas;
        this.diariaLoading   = false;
      },
      error: () => { this.diariaError = 'No se pudo cargar la asistencia diaria.'; this.diariaLoading = false; },
    });
  }

  irPaginaDiaria(p: number): void {
    if (p < 1 || p > this.diariaTotalPag) return;
    this.diariaPage = p; this.cargarDiaria();
  }
  get paginasDiariaBtn(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(1, this.diariaPage - 2); i <= Math.min(this.diariaTotalPag, this.diariaPage + 2); i++) pages.push(i);
    return pages;
  }
  get rangoDiaria() {
    const desde = (this.diariaPage - 1) * this.DIARIA_PER_PAGE + 1;
    const hasta = Math.min(this.diariaPage * this.DIARIA_PER_PAGE, this.diariaTotalReg);
    return { desde, hasta, total: this.diariaTotalReg };
  }

  labelFechaDiaria(): string {
    if (!this.fechaDiaria) return '';
    const d = new Date(this.fechaDiaria + 'T00:00:00');
    return d.toLocaleDateString('es-PE', { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric' });
  }

  // ── Mapa compartido ────────────────────────────────────────────────────────

  abrirMapa(label: string, geoIng: GeoDto | null, geoSal: GeoDto | null): void {
    this.mapLabel      = label;
    this.mapGeoIngreso = geoIng;
    this.mapGeoSalida  = geoSal;
    this.showMapModal  = true;
    setTimeout(() => this.initMap(geoIng, geoSal), 120);
  }
  cerrarMapa(): void { this.showMapModal = false; this.destroyMap(); }

  private initMap(geoIng: GeoDto | null, geoSal: GeoDto | null): void {
    this.destroyMap();
    const el = document.getElementById('leaflet-map-container');
    if (!el) return;

    const center: [number, number] = geoIng
      ? [geoIng.lat, geoIng.lng]
      : geoSal ? [geoSal.lat, geoSal.lng] : [-12.046374, -77.042793];

    this.leafletMap = L.map(el).setView(center, 15);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© <a href="https://openstreetmap.org">OpenStreetMap</a>', maxZoom: 19,
    }).addTo(this.leafletMap);

    const pinIcon = (color: string) => L.divIcon({
      html: `<div class="map-pin-${color}"><svg width="14" height="14" viewBox="0 0 24 24" fill="white"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z"/></svg></div>`,
      className: '', iconSize: [32, 32], iconAnchor: [16, 32],
    });
    if (geoIng) L.marker([geoIng.lat, geoIng.lng], { icon: pinIcon('green') }).addTo(this.leafletMap!).bindPopup('Ingreso').openPopup();
    if (geoSal) L.marker([geoSal.lat, geoSal.lng], { icon: pinIcon('red')   }).addTo(this.leafletMap!).bindPopup('Salida');

    if (geoIng && geoSal) {
      this.leafletMap!.fitBounds(
        L.latLngBounds([geoIng.lat, geoIng.lng], [geoSal.lat, geoSal.lng]),
        { padding: [40, 40] }
      );
    }
  }
  private destroyMap(): void {
    if (this.leafletMap) { this.leafletMap.remove(); this.leafletMap = null; }
  }

  // ── Reportes ───────────────────────────────────────────────────────────────

  descargarGlobal(fmt: 'xlsx' | 'pdf'): void {
    if (!this.rptGlobal.fechaInicio || !this.rptGlobal.fechaFin) {
      alert('Selecciona el rango de fechas para el reporte global.'); return;
    }
    this.rptGlobal.loading = true;
    this.rrhhService.descargarReporte('global', {
      fecha_inicio: this.rptGlobal.fechaInicio,
      fecha_fin:    this.rptGlobal.fechaFin,
      fmt,
    }).subscribe({
      next: (blob) => { this._triggerDownload(blob, fmt, `reporte_global`); this.rptGlobal.loading = false; },
      error: () => { alert('Error al generar reporte global.'); this.rptGlobal.loading = false; },
    });
  }

  descargarIndividual(fmt: 'xlsx' | 'pdf'): void {
    if (!this.rptIndividual.empleadoId) { alert('Selecciona un empleado.'); return; }
    if (!this.rptIndividual.fechaInicio || !this.rptIndividual.fechaFin) {
      alert('Selecciona el rango de fechas.'); return;
    }
    this.rptIndividual.loading = true;
    this.rrhhService.descargarReporte('individual', {
      empleado_id:  this.rptIndividual.empleadoId,
      fecha_inicio: this.rptIndividual.fechaInicio,
      fecha_fin:    this.rptIndividual.fechaFin,
      fmt,
    }).subscribe({
      next: (blob) => { this._triggerDownload(blob, fmt, `reporte_individual`); this.rptIndividual.loading = false; },
      error: () => { alert('Error al generar reporte individual.'); this.rptIndividual.loading = false; },
    });
  }

  descargarHorasExtra(fmt: 'xlsx' | 'pdf'): void {
    if (!this.rptHorasExtra.fechaInicio || !this.rptHorasExtra.fechaFin) {
      alert('Selecciona el rango de fechas.'); return;
    }
    this.rptHorasExtra.loading = true;
    this.rrhhService.descargarReporte('horas-extra', {
      fecha_inicio: this.rptHorasExtra.fechaInicio,
      fecha_fin:    this.rptHorasExtra.fechaFin,
      fmt,
    }).subscribe({
      next: (blob) => { this._triggerDownload(blob, fmt, `reporte_horas_extra`); this.rptHorasExtra.loading = false; },
      error: () => { alert('Error al generar reporte de horas extra.'); this.rptHorasExtra.loading = false; },
    });
  }

  private _triggerDownload(blob: Blob, fmt: 'xlsx' | 'pdf', nombre: string): void {
    const ext  = fmt === 'xlsx' ? 'xlsx' : 'pdf';
    const mime = fmt === 'xlsx'
      ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      : 'application/pdf';
    const url = URL.createObjectURL(new Blob([blob], { type: mime }));
    const a   = document.createElement('a');
    a.href = url; a.download = `${nombre}_${new Date().toISOString().slice(0,10)}.${ext}`;
    a.click(); URL.revokeObjectURL(url);
  }
}

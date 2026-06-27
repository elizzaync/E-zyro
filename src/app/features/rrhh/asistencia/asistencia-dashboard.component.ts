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
  FeriadoDto,
  FeriadoNacionalDto,
} from '../../../core/services/rrhh.service';
import { AuthService } from '../../../core/services/auth.service';
import {
  AsistenciaService,
  TurnoDto,
  CrearTurnoIn,
  AsignarTurnoIn,
  TurnoAsignacionDto,
} from '../../../core/services/asistencia.service';

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
  activeTab: 'semanal' | 'diaria' | 'turnos' | 'feriados' = 'semanal';

  listaEmpleados: EmpleadoLegajoDto[] = [];

  readonly MESES = [
    { v: '01', l: 'Enero' }, { v: '02', l: 'Febrero' }, { v: '03', l: 'Marzo' },
    { v: '04', l: 'Abril' }, { v: '05', l: 'Mayo' },    { v: '06', l: 'Junio' },
    { v: '07', l: 'Julio' }, { v: '08', l: 'Agosto' },  { v: '09', l: 'Septiembre' },
    { v: '10', l: 'Octubre' }, { v: '11', l: 'Noviembre' }, { v: '12', l: 'Diciembre' },
  ];

  // ── Modal Reporte Global (mensual) ─────────────────────────────────────────
  showRptGlobal = false;
  rptGlobal3 = {
    anio: new Date().getFullYear(),
    mes:  (new Date().getMonth() + 1).toString().padStart(2, '0'),
    fmt:  'pdf' as 'xlsx' | 'pdf',
    loading: false,
  };

  // ── Modal Reporte Detallado (individual por mes) ───────────────────────────
  showRptDetallado = false;
  rptDetallado3 = {
    empleadoId: '',
    search:     '',
    anio: new Date().getFullYear(),
    mes:  (new Date().getMonth() + 1).toString().padStart(2, '0'),
    fmt:  'pdf' as 'xlsx' | 'pdf',
    loading: false,
  };

  get anioActual(): number  { return new Date().getFullYear(); }
  get mesActual():  string  { return (new Date().getMonth() + 1).toString().padStart(2, '0'); }

  mesesDisponibles(anio: number): { v: string; l: string }[] {
    if (anio < this.anioActual) return this.MESES;
    return this.MESES.filter(m => m.v <= this.mesActual);
  }

  get listaEmpleadosFiltrada(): EmpleadoLegajoDto[] {
    const q = this.rptDetallado3.search.toLowerCase().trim();
    if (!q) return this.listaEmpleados;
    return this.listaEmpleados.filter(e =>
      e.nombreCompleto.toLowerCase().includes(q) || e.cargo.toLowerCase().includes(q)
    );
  }

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
  fechaDiaria       = this.toISODate(new Date());
  diariaFechaInicio = this.toISODate(new Date());
  diariaFechaFin    = this.toISODate(new Date());
  diariaSearch      = '';
  diariaLoading     = false;
  diariaError       = '';
  diariaEmpleados:  AsistenciaDiariaItemDto[] = [];
  diariaPage    = 1;
  diariaTotalPag= 1;
  diariaTotalReg= 0;
  readonly DIARIA_PER_PAGE = 10;

  // ── Tab Turnos ─────────────────────────────────────────────────────────────
  turnos:                TurnoDto[]           = [];
  turnosLoading          = false;
  turnosError            = '';
  turnoAsignaciones:     TurnoAsignacionDto[] = [];
  turnoAsignLoading      = false;

  showCrearTurno   = false;
  crearTurnoLoading = false;
  crearTurnoError  = '';
  crearTurnoExito  = '';
  formTurno: CrearTurnoIn = this.turnoVacio();

  showAsignarTurno  = false;
  asignarLoading    = false;
  asignarError      = '';
  asignarExito      = '';
  formAsignar: AsignarTurnoIn & { fecha_desde: string; fecha_hasta: string } = this.asignarVacio();

  // ── Mapa (compartido) ──────────────────────────────────────────────────────
  showMapModal   = false;
  mapLabel       = '';
  mapGeoIngreso: GeoDto | null = null;
  mapGeoSalida:  GeoDto | null = null;
  private leafletMap: L.Map | null = null;

  constructor(
    private rrhhService:      RrhhService,
    private authService:      AuthService,
    private asistenciaService: AsistenciaService,
  ) {}

  ngOnInit(): void {
    this.setSemana();
    this.cargar();
    this.cargarListaEmpleados();
  }

  ngOnDestroy(): void {
    this.destroyMap();
  }

  setTab(tab: 'semanal' | 'diaria' | 'turnos' | 'feriados'): void {
    this.activeTab = tab;
    if (tab === 'diaria' && this.diariaEmpleados.length === 0) {
      this.cargarDiaria();
    }
    if (tab === 'turnos' && this.turnos.length === 0) {
      this.cargarTurnos();
    }
    if (tab === 'feriados' && this.feriados.length === 0) {
      this.cargarFeriados();
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

  onFechaDiariaChange(): void {
    if (this.fechaDiaria < this.diariaFechaInicio) this.diariaFechaInicio = this.fechaDiaria;
    if (this.fechaDiaria > this.diariaFechaFin)    this.diariaFechaFin    = this.fechaDiaria;
    this.diariaPage = 1; this.cargarDiaria();
  }

  onRangoDiarioChange(): void {
    if (!this.diariaFechaInicio || !this.diariaFechaFin) return;
    if (this.diariaFechaFin < this.diariaFechaInicio) this.diariaFechaFin = this.diariaFechaInicio;
    if (this.fechaDiaria < this.diariaFechaInicio) this.fechaDiaria = this.diariaFechaInicio;
    if (this.fechaDiaria > this.diariaFechaFin)    this.fechaDiaria = this.diariaFechaInicio;
    this.diariaPage = 1; this.cargarDiaria();
  }

  setRangoPreset(preset: 'hoy' | 'semana' | 'mes'): void {
    const hoy = new Date();
    if (preset === 'hoy') {
      this.diariaFechaInicio = this.toISODate(hoy);
      this.diariaFechaFin    = this.toISODate(hoy);
      this.fechaDiaria       = this.toISODate(hoy);
    } else if (preset === 'semana') {
      this.diariaFechaInicio = this.toISODate(this.lunesDe(hoy));
      this.diariaFechaFin    = this.toISODate(this.sabadoDe(hoy));
      this.fechaDiaria       = this.toISODate(this.lunesDe(hoy));
    } else {
      const ini = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
      const fin = new Date(hoy.getFullYear(), hoy.getMonth() + 1, 0);
      this.diariaFechaInicio = this.toISODate(ini);
      this.diariaFechaFin    = this.toISODate(fin);
      this.fechaDiaria       = this.toISODate(ini);
    }
    this.diariaPage = 1; this.diariaSearch = ''; this.cargarDiaria();
  }

  irDiaAnterior(): void {
    if (!this.puedeIrDiaAnterior) return;
    const d = new Date(this.fechaDiaria + 'T00:00:00');
    d.setDate(d.getDate() - 1);
    this.fechaDiaria = this.toISODate(d);
    this.diariaPage = 1; this.cargarDiaria();
  }

  irDiaSiguiente(): void {
    if (!this.puedeIrDiaSiguiente) return;
    const d = new Date(this.fechaDiaria + 'T00:00:00');
    d.setDate(d.getDate() + 1);
    this.fechaDiaria = this.toISODate(d);
    this.diariaPage = 1; this.cargarDiaria();
  }

  get esRangoMultiDia(): boolean { return this.diariaFechaInicio !== this.diariaFechaFin; }
  get puedeIrDiaAnterior(): boolean { return !!this.diariaFechaInicio && this.fechaDiaria > this.diariaFechaInicio; }
  get puedeIrDiaSiguiente(): boolean { return !!this.diariaFechaFin && this.fechaDiaria < this.diariaFechaFin; }

  get diaEnRango(): string {
    if (!this.esRangoMultiDia) return '';
    const start = new Date(this.diariaFechaInicio + 'T00:00:00');
    const end   = new Date(this.diariaFechaFin    + 'T00:00:00');
    const curr  = new Date(this.fechaDiaria        + 'T00:00:00');
    const total  = Math.round((end.getTime()  - start.getTime()) / 86400000) + 1;
    const actual = Math.round((curr.getTime() - start.getTime()) / 86400000) + 1;
    return `Día ${actual} / ${total}`;
  }

  cargarDiaria(): void {
    this.diariaLoading = true; this.diariaError = '';
    const buscando = !!this.diariaSearch.trim();
    this.rrhhService.getAsistenciaDiaria(
      this.fechaDiaria,
      buscando ? 1 : this.diariaPage,
      buscando ? 500 : this.DIARIA_PER_PAGE,
    ).subscribe({
      next: (res) => {
        this.diariaEmpleados = res.empleados;
        this.diariaTotalReg  = res.total;
        this.diariaTotalPag  = buscando ? 1 : res.total_paginas;
        this.diariaLoading   = false;
      },
      error: () => { this.diariaError = 'No se pudo cargar la asistencia diaria.'; this.diariaLoading = false; },
    });
  }

  get diariaEmpleadosFiltrados(): AsistenciaDiariaItemDto[] {
    if (!this.diariaSearch.trim()) return this.diariaEmpleados;
    const t = this.diariaSearch.toLowerCase();
    return this.diariaEmpleados.filter(e =>
      e.nombreCompleto.toLowerCase().includes(t) ||
      e.cargo.toLowerCase().includes(t) ||
      (e.area || '').toLowerCase().includes(t),
    );
  }

  get kpisDiaria() {
    const emps = this.diariaEmpleados;
    return {
      total:     this.diariaTotalReg,
      presentes: emps.filter(e => !!e.hora_ingreso).length,
      ausentes:  emps.filter(e => !e.hora_ingreso).length,
      enOficina: emps.filter(e => !!e.hora_ingreso && !e.hora_salida).length,
    };
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

  // ── Modal Reporte Global ───────────────────────────────────────────────────

  abrirRptGlobal(): void {
    this.rptGlobal3.anio = this.anioActual;
    this.rptGlobal3.mes  = this.mesActual;
    this.rptGlobal3.fmt  = 'pdf';
    this.showRptGlobal   = true;
  }

  cerrarRptGlobal(): void { this.showRptGlobal = false; }

  onAnioGlobalChange(): void {
    if (this.rptGlobal3.anio > this.anioActual) this.rptGlobal3.anio = this.anioActual;
    const meses = this.mesesDisponibles(this.rptGlobal3.anio);
    if (!meses.find(m => m.v === this.rptGlobal3.mes)) {
      this.rptGlobal3.mes = meses[meses.length - 1]?.v ?? this.mesActual;
    }
  }

  generarRptGlobal(): void {
    this.rptGlobal3.loading = true;
    const mes = parseInt(this.rptGlobal3.mes, 10);
    this.rrhhService.descargarReporte('mensual', {
      anio: this.rptGlobal3.anio.toString(),
      mes:  mes.toString(),
      fmt:  this.rptGlobal3.fmt,
    }).subscribe({
      next: (blob) => {
        this._triggerDownload(blob, this.rptGlobal3.fmt,
          `reporte_global_${this.rptGlobal3.anio}_${this.rptGlobal3.mes}`);
        this.rptGlobal3.loading = false;
        this.cerrarRptGlobal();
      },
      error: (err) => { this._blobError(err, 'reporte global'); this.rptGlobal3.loading = false; },
    });
  }

  // ── Modal Reporte Detallado ────────────────────────────────────────────────

  abrirRptDetallado(): void {
    this.rptDetallado3.empleadoId = '';
    this.rptDetallado3.search     = '';
    this.rptDetallado3.anio = this.anioActual;
    this.rptDetallado3.mes  = this.mesActual;
    this.rptDetallado3.fmt  = 'pdf';
    this.showRptDetallado   = true;
    if (this.listaEmpleados.length === 0) this.cargarListaEmpleados();
  }

  cerrarRptDetallado(): void { this.showRptDetallado = false; }

  onAnioDetalladoChange(): void {
    if (this.rptDetallado3.anio > this.anioActual) this.rptDetallado3.anio = this.anioActual;
    const meses = this.mesesDisponibles(this.rptDetallado3.anio);
    if (!meses.find(m => m.v === this.rptDetallado3.mes)) {
      this.rptDetallado3.mes = meses[meses.length - 1]?.v ?? this.mesActual;
    }
  }

  generarRptDetallado(): void {
    if (!this.rptDetallado3.empleadoId) { alert('Selecciona un empleado.'); return; }
    this.rptDetallado3.loading = true;
    const anio = this.rptDetallado3.anio;
    const mes  = parseInt(this.rptDetallado3.mes, 10);
    const ultimoDia = new Date(anio, mes, 0).getDate();
    const fechaInicio = `${anio}-${this.rptDetallado3.mes}-01`;
    const fechaFin    = `${anio}-${this.rptDetallado3.mes}-${ultimoDia.toString().padStart(2, '0')}`;
    this.rrhhService.descargarReporte('individual', {
      empleado_id:  this.rptDetallado3.empleadoId,
      fecha_inicio: fechaInicio,
      fecha_fin:    fechaFin,
      fmt:          this.rptDetallado3.fmt,
    }).subscribe({
      next: (blob) => {
        this._triggerDownload(blob, this.rptDetallado3.fmt,
          `reporte_detallado_${this.rptDetallado3.anio}_${this.rptDetallado3.mes}`);
        this.rptDetallado3.loading = false;
        this.cerrarRptDetallado();
      },
      error: (err) => { this._blobError(err, 'reporte detallado'); this.rptDetallado3.loading = false; },
    });
  }

  private _blobError(err: any, label: string): void {
    if (err.error instanceof Blob) {
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const json = JSON.parse(reader.result as string);
          alert(json.detail ?? `Error al generar ${label}.`);
        } catch { alert(`Error al generar ${label}.`); }
      };
      reader.readAsText(err.error);
    } else {
      alert(err?.error?.detail ?? `Error al generar ${label}.`);
    }
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

  // ── Turnos ─────────────────────────────────────────────────────────────────

  turnoVacio(): CrearTurnoIn {
    return { nombre: '', hora_entrada: '08:00', hora_salida: '17:00', duracion_almuerzo_minutos: 60, tolerancia_minutos: 5 };
  }

  asignarVacio(): AsignarTurnoIn & { fecha_desde: string; fecha_hasta: string } {
    return { empleado_id: '', turno_id: '', fecha_desde: this.toISODate(new Date()), fecha_hasta: '' };
  }

  cargarTurnos(): void {
    this.turnosLoading = true; this.turnosError = '';
    this.asistenciaService.getTurnos().subscribe({
      next:  t  => { this.turnos = t; this.turnosLoading = false; },
      error: () => { this.turnosError = 'No se pudieron cargar los turnos.'; this.turnosLoading = false; },
    });
    this.cargarTurnoAsignaciones();
  }

  cargarTurnoAsignaciones(): void {
    this.turnoAsignLoading = true;
    this.asistenciaService.getTurnoAsignaciones().subscribe({
      next:  a  => { this.turnoAsignaciones = a; this.turnoAsignLoading = false; },
      error: () => { this.turnoAsignLoading = false; },
    });
  }

  abrirCrearTurno(): void {
    this.formTurno = this.turnoVacio();
    this.crearTurnoError = ''; this.crearTurnoExito = '';
    this.showCrearTurno = true;
  }
  cerrarCrearTurno(): void { this.showCrearTurno = false; }

  guardarTurno(): void {
    if (!this.formTurno.nombre.trim()) { this.crearTurnoError = 'El nombre es obligatorio.'; return; }
    this.crearTurnoLoading = true; this.crearTurnoError = '';
    this.asistenciaService.crearTurno(this.formTurno).subscribe({
      next: () => {
        this.crearTurnoLoading = false; this.crearTurnoExito = 'Turno creado correctamente.';
        this.cargarTurnos();
        setTimeout(() => { this.cerrarCrearTurno(); this.crearTurnoExito = ''; }, 1500);
      },
      error: (err) => { this.crearTurnoError = err?.error?.detail ?? 'Error al crear el turno.'; this.crearTurnoLoading = false; },
    });
  }

  abrirAsignarTurno(): void {
    this.formAsignar = this.asignarVacio();
    this.asignarError = ''; this.asignarExito = '';
    this.showAsignarTurno = true;
    if (this.listaEmpleados.length === 0) this.cargarListaEmpleados();
  }
  cerrarAsignarTurno(): void { this.showAsignarTurno = false; }

  confirmarAsignarTurno(): void {
    if (!this.formAsignar.empleado_id || !this.formAsignar.turno_id) {
      this.asignarError = 'Selecciona empleado y turno.'; return;
    }
    this.asignarLoading = true; this.asignarError = '';
    const body: AsignarTurnoIn = {
      empleado_id: this.formAsignar.empleado_id,
      turno_id:    this.formAsignar.turno_id,
      fecha_desde: this.formAsignar.fecha_desde || undefined,
      fecha_hasta: this.formAsignar.fecha_hasta || undefined,
    };
    this.asistenciaService.asignarTurno(body).subscribe({
      next: () => {
        this.asignarLoading = false; this.asignarExito = 'Turno asignado correctamente.';
        setTimeout(() => { this.cerrarAsignarTurno(); this.asignarExito = ''; }, 1500);
      },
      error: (err) => { this.asignarError = err?.error?.detail ?? 'Error al asignar el turno.'; this.asignarLoading = false; },
    });
  }

  turnoNombre(id: string): string {
    return this.turnos.find(t => t.id === id)?.nombre ?? id;
  }

  empleadoNombre(id: string): string {
    return this.listaEmpleados.find(e => e.id === id)?.nombreCompleto ?? '';
  }

  // ── Tab Feriados ───────────────────────────────────────────────────────────

  feriados:         FeriadoDto[]         = [];
  feriadosNac:      FeriadoNacionalDto[] = [];
  feriadosLoading   = false;
  feriadosError     = '';
  feriadoAnio       = new Date().getFullYear();

  // Formulario nuevo feriado
  showNuevoFeriado  = false;
  feriadoForm       = { fecha: '', nombre: '', tipo: 'empresa' as 'empresa' | 'nacional' };
  feriadoFormError  = '';
  feriadoFormLoading= false;
  feriadoFormExito  = '';
  feriadoToast      = false;

  cargarFeriados(): void {
    this.feriadosLoading = true; this.feriadosError = '';
    this.rrhhService.getFeriados(this.feriadoAnio).subscribe({
      next: (r) => { this.feriados = r.feriados; this.feriadosLoading = false; },
      error: () => { this.feriadosError = 'No se pudieron cargar los feriados.'; this.feriadosLoading = false; },
    });
  }

  cargarFeriadosNac(): void {
    this.rrhhService.getFeriadosNacionales(this.feriadoAnio).subscribe({
      next: (r) => { this.feriadosNac = r.feriados; },
    });
  }

  onAnioFeriadoChange(): void {
    this.cargarFeriados();
    this.cargarFeriadosNac();
  }

  abrirNuevoFeriado(): void {
    this.feriadoForm = { fecha: '', nombre: '', tipo: 'empresa' };
    this.feriadoFormError = ''; this.feriadoFormExito = '';
    this.showNuevoFeriado = true;
    if (this.feriadosNac.length === 0) this.cargarFeriadosNac();
  }
  cerrarNuevoFeriado(): void { this.showNuevoFeriado = false; }

  seleccionarFeriadoNac(fn: FeriadoNacionalDto): void {
    this.feriadoForm.fecha  = fn.fecha;
    this.feriadoForm.nombre = fn.nombre;
    this.feriadoForm.tipo   = 'nacional';
  }

  guardarFeriado(): void {
    if (!this.feriadoForm.fecha || !this.feriadoForm.nombre.trim()) {
      this.feriadoFormError = 'La fecha y el nombre son obligatorios.'; return;
    }
    this.feriadoFormLoading = true; this.feriadoFormError = '';
    this.rrhhService.crearFeriado(this.feriadoForm).subscribe({
      next: () => {
        this.feriadoFormLoading = false;
        this.feriadoFormExito = '¡Feriado agregado!';
        this.cargarFeriados();
        setTimeout(() => {
          this.cerrarNuevoFeriado();
          this.feriadoFormExito = '';
          this.feriadoToast = true;
          setTimeout(() => { this.feriadoToast = false; }, 3200);
        }, 900);
      },
      error: (err) => {
        this.feriadoFormError  = err?.error?.detail ?? 'Error al guardar.';
        this.feriadoFormLoading = false;
      },
    });
  }

  eliminarFeriado(id: string): void {
    if (!confirm('¿Eliminar este feriado?')) return;
    this.rrhhService.eliminarFeriado(id).subscribe({
      next: () => this.cargarFeriados(),
      error: () => alert('No se pudo eliminar el feriado.'),
    });
  }

  esFeriadoYaRegistrado(fecha: string): boolean {
    return this.feriados.some(f => f.fecha === fecha);
  }

  labelTipoFeriado(tipo: string): string {
    return tipo === 'nacional' ? 'Nacional' : 'Empresa';
  }
}

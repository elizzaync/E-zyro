import {
  Component, OnInit, OnDestroy,
  ChangeDetectionStrategy, ChangeDetectorRef, NgZone, inject,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import * as L from 'leaflet';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { ThemeService } from '../../../core/services/theme.service';
import { StatusBadgeComponent } from '../shared/status-badge.component';
import { EmptyStateComponent } from '../shared/empty-state.component';
import { PortalPaginationComponent } from '../shared/portal-pagination.component';

type St = 'ok' | 'prog' | 'warn' | 'err' | 'neutral';

interface ZonaMapa {
  region: string;      // nombre canónico mostrado
  lat: number;
  lng: number;
  equipos: any[];
  worst: 'ok' | 'warn' | 'err';
}

/** Centroides de referencia de las regiones del Perú (capital regional). */
const REGIONES_PERU: Record<string, { nombre: string; lat: number; lng: number }> = {
  'amazonas':      { nombre: 'Amazonas',      lat: -6.23,  lng: -77.87 },
  'ancash':        { nombre: 'Áncash',        lat: -9.53,  lng: -77.53 },
  'apurimac':      { nombre: 'Apurímac',      lat: -13.63, lng: -72.88 },
  'arequipa':      { nombre: 'Arequipa',      lat: -16.40, lng: -71.54 },
  'ayacucho':      { nombre: 'Ayacucho',      lat: -13.16, lng: -74.22 },
  'cajamarca':     { nombre: 'Cajamarca',     lat: -7.16,  lng: -78.51 },
  'callao':        { nombre: 'Callao',        lat: -12.05, lng: -77.13 },
  'cusco':         { nombre: 'Cusco',         lat: -13.53, lng: -71.97 },
  'cuzco':         { nombre: 'Cusco',         lat: -13.53, lng: -71.97 },
  'huancavelica':  { nombre: 'Huancavelica',  lat: -12.79, lng: -74.97 },
  'huanuco':       { nombre: 'Huánuco',       lat: -9.93,  lng: -76.24 },
  'ica':           { nombre: 'Ica',           lat: -14.07, lng: -75.73 },
  'junin':         { nombre: 'Junín',         lat: -12.07, lng: -75.21 },
  'la libertad':   { nombre: 'La Libertad',   lat: -8.11,  lng: -79.03 },
  'lambayeque':    { nombre: 'Lambayeque',    lat: -6.77,  lng: -79.84 },
  'lima':          { nombre: 'Lima',          lat: -12.05, lng: -77.04 },
  'loreto':        { nombre: 'Loreto',        lat: -3.75,  lng: -73.25 },
  'madre de dios': { nombre: 'Madre de Dios', lat: -12.59, lng: -69.19 },
  'moquegua':      { nombre: 'Moquegua',      lat: -17.19, lng: -70.93 },
  'pasco':         { nombre: 'Pasco',         lat: -10.68, lng: -76.26 },
  'piura':         { nombre: 'Piura',         lat: -5.19,  lng: -80.63 },
  'puno':          { nombre: 'Puno',          lat: -15.84, lng: -70.02 },
  'san martin':    { nombre: 'San Martín',    lat: -6.48,  lng: -76.37 },
  'tacna':         { nombre: 'Tacna',         lat: -18.01, lng: -70.25 },
  'tumbes':        { nombre: 'Tumbes',        lat: -3.57,  lng: -80.45 },
  'ucayali':       { nombre: 'Ucayali',       lat: -8.38,  lng: -74.55 },
};

const PERU_CENTER: [number, number] = [-9.19, -75.02];
const PERU_ZOOM = 5;
/** Recuadro de paneo: Perú + margen, evita arrastrar el mapa a océano vacío. */
const PERU_BOUNDS: L.LatLngBoundsExpression = [[-21, -84], [1.5, -65]];
/** A partir de este zoom la burbuja de un departamento se "abre" en pines
 *  individuales por equipo (claridad al acercarse a una zona). */
const EXPLODE_ZOOM = 8;
/** A partir de este zoom se muestra el nombre del departamento como etiqueta fija. */
const LABEL_ZOOM = 7;
/** Ángulo áureo (rad): reparte puntos en espiral tipo girasol sin superponerse. */
const GOLDEN_ANGLE = 2.399963229728653;

/** Basemaps CARTO — más limpios y "corporativos" que el OSM por defecto;
 *  además traen su propia paleta oscura (ya no hace falta el filter CSS). */
const TILES_LIGHT = 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
const TILES_DARK  = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
const TILES_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>';

@Component({
  selector: 'app-client-equipment-history',
  standalone: true,
  imports: [CommonModule, RouterLink, FormsModule, StatusBadgeComponent, EmptyStateComponent, PortalPaginationComponent],
  templateUrl: './client-equipment-history.component.html',
  styleUrls: ['./client-equipment-history.component.css'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ClientEquipmentHistoryComponent implements OnInit, OnDestroy {
  private svc    = inject(PortalClienteService);
  private cdr    = inject(ChangeDetectorRef);
  private ngZone = inject(NgZone);
  private router = inject(Router);
  private theme  = inject(ThemeService);

  cargando  = true;
  error     = '';
  historial: any[] = [];

  // ── Vista Lista / Mapa ─────────────────────────────────────────────────
  vista: 'lista' | 'mapa' = 'lista';

  busqueda        = '';
  filtroEstado    = 'todos';
  filtroUbicacion = 'todas';

  readonly PAGE_SIZE = 25;
  paginaActual = 1;

  // Precalculados (OnPush)
  historialFiltrado: any[] = [];
  historialPaginado: any[] = [];
  totalPaginas = 1;
  ubicacionesDisponibles: string[] = ['todas'];
  private countExito = 0;
  private countAdvertencia = 0;
  private countPeligro = 0;

  // ── Mapa del Perú ──────────────────────────────────────────────────────
  private map: L.Map | null = null;
  private tileLayer: L.TileLayer | null = null;
  private markers: L.Marker[] = [];
  private pinMarkers: L.Marker[] = [];
  private labelMarkers: L.Marker[] = [];
  private pinsVisible = false;
  private labelsVisible = false;
  private themeSub: Subscription | null = null;
  zonas: ZonaMapa[] = [];
  sinUbicacion: any[] = [];
  zonaSel: ZonaMapa | null = null;

  get totalEquiposMapa(): number {
    return this.zonas.reduce((acc, z) => acc + z.equipos.length, 0);
  }

  // ── Estado temporal unificado (misma lógica del resto del portal) ──────
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

  /** badge legacy → estado unificado del design system */
  stOf(eq: any): St {
    const b = this.maintenanceStatus(eq).badge;
    if (b === 'badge-success') return 'ok';
    if (b === 'badge-warning') return 'warn';
    if (b === 'badge-danger')  return 'err';
    if (b === 'badge-prog')    return 'prog';
    return 'neutral';
  }

  stLabel(eq: any): string { return this.maintenanceStatus(eq).label; }

  countPorBadge(badge: string): number {
    if (badge === 'badge-success') return this.countExito;
    if (badge === 'badge-warning') return this.countAdvertencia;
    if (badge === 'badge-danger')  return this.countPeligro;
    return 0;
  }

  proximoAlerta(fecha: string | null): boolean {
    if (!fecha) return false;
    const dias = (new Date(fecha).getTime() - Date.now()) / 86_400_000;
    return dias >= 0 && dias <= 30;
  }

  // ── Vista ──────────────────────────────────────────────────────────────

  setVista(v: 'lista' | 'mapa'): void {
    if (this.vista === v) return;
    this.vista = v;
    if (v === 'mapa') {
      // El contenedor del mapa recién existe tras el render de este tick.
      setTimeout(() => this.initMapa(), 0);
    } else {
      this.destroyMapa();
      this.zonaSel = null;
    }
    this.cdr.markForCheck();
  }

  // ── Lista: filtros y paginación ────────────────────────────────────────

  irAPagina(p: number): void {
    if (p < 1 || p > this.totalPaginas) return;
    this.paginaActual = p;
    this.actualizarPaginacion();
    this.cdr.markForCheck();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  resetFiltros(): void {
    this.busqueda        = '';
    this.filtroEstado    = 'todos';
    this.filtroUbicacion = 'todas';
    this.paginaActual    = 1;
    this.aplicarFiltros();
    this.cdr.markForCheck();
  }

  onFiltroChange(): void {
    this.paginaActual = 1;
    this.aplicarFiltros();
    this.cdr.markForCheck();
  }

  setFiltroEstado(f: string): void {
    this.filtroEstado = f;
    this.onFiltroChange();
  }

  get hayFiltrosActivos(): boolean {
    return this.busqueda.trim() !== '' ||
           this.filtroEstado    !== 'todos' ||
           this.filtroUbicacion !== 'todas';
  }

  private recalcularDerivadosDeHistorial(): void {
    const set = new Set<string>();
    let exito = 0, advertencia = 0, peligro = 0;
    for (const e of this.historial) {
      if (e.ubicacion) set.add(e.ubicacion);
      const badge = this.maintenanceStatus(e).badge;
      if (badge === 'badge-success') exito++;
      else if (badge === 'badge-warning') advertencia++;
      else if (badge === 'badge-danger') peligro++;
    }
    this.ubicacionesDisponibles = ['todas', ...Array.from(set).sort()];
    this.countExito = exito;
    this.countAdvertencia = advertencia;
    this.countPeligro = peligro;
  }

  private aplicarFiltros(): void {
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
      r = r.filter(e => this.maintenanceStatus(e).badge === this.filtroEstado);
    }

    if (this.filtroUbicacion !== 'todas') {
      r = r.filter(e => e.ubicacion === this.filtroUbicacion);
    }

    this.historialFiltrado = r;
    this.actualizarPaginacion();
  }

  private actualizarPaginacion(): void {
    this.totalPaginas = Math.max(1, Math.ceil(this.historialFiltrado.length / this.PAGE_SIZE));
    if (this.paginaActual > this.totalPaginas) this.paginaActual = this.totalPaginas;
    const start = (this.paginaActual - 1) * this.PAGE_SIZE;
    this.historialPaginado = this.historialFiltrado.slice(start, start + this.PAGE_SIZE);
  }

  // ── Mapa del Perú ──────────────────────────────────────────────────────

  private static norm(s: string | null | undefined): string {
    return (s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
  }

  /** Resuelve la región de un equipo: primero el campo region del backend,
   *  luego busca nombres de región dentro de sede/ubicación (texto libre). */
  private regionKeyDe(eq: any): string | null {
    const region = ClientEquipmentHistoryComponent.norm(eq.region);
    if (region && REGIONES_PERU[region]) return region;
    const texto = [eq.region, eq.sede, eq.ubicacion, eq.proyecto]
      .map(v => ClientEquipmentHistoryComponent.norm(v)).join(' | ');
    for (const key of Object.keys(REGIONES_PERU)) {
      if (texto.includes(key)) return key;
    }
    return null;
  }

  private agruparZonas(): void {
    const porRegion = new Map<string, any[]>();
    this.sinUbicacion = [];
    for (const eq of this.historial) {
      const key = this.regionKeyDe(eq);
      if (!key) { this.sinUbicacion.push(eq); continue; }
      const list = porRegion.get(key) ?? [];
      list.push(eq);
      porRegion.set(key, list);
    }
    this.zonas = Array.from(porRegion.entries()).map(([key, equipos]) => {
      const hayErr  = equipos.some(e => this.stOf(e) === 'err');
      const hayWarn = equipos.some(e => this.stOf(e) === 'warn');
      const meta = REGIONES_PERU[key];
      return {
        region: meta.nombre, lat: meta.lat, lng: meta.lng, equipos,
        worst: hayErr ? 'err' : (hayWarn ? 'warn' : 'ok'),
      } as ZonaMapa;
    });
  }

  private initMapa(): void {
    const el = document.getElementById('pc-peru-map');
    if (!el || this.map) return;

    // Leaflet registra sus propios listeners nativos: crearlo fuera de la
    // Angular zone evita change detection global en cada pan/zoom/mousemove
    // (mismo patrón que background.js y Chart.js del dashboard).
    this.ngZone.runOutsideAngular(() => {
      this.map = L.map(el, {
        center: PERU_CENTER, zoom: PERU_ZOOM,
        minZoom: 4, maxZoom: 14, zoomSnap: 0.5, zoomDelta: 0.5,
        zoomControl: true, attributionControl: true,
        maxBounds: PERU_BOUNDS, maxBoundsViscosity: 0.85,
      });
      this.tileLayer = L.tileLayer(this.theme.isDark ? TILES_DARK : TILES_LIGHT, {
        attribution: TILES_ATTRIBUTION, subdomains: 'abcd', maxZoom: 19,
      }).addTo(this.map);
      this.dibujarMarcadores();
      // Al acercarse/alejarse se decide si se ven burbujas por zona o
      // pines individuales por equipo (nivel de detalle progresivo).
      this.map.on('zoomend', () => this.actualizarNivelDetalle());
    });

    // El basemap CARTO ya trae su propia paleta oscura: solo hay que
    // cambiar la URL de tiles cuando el usuario alterna el tema.
    this.themeSub = this.theme.isDark$.subscribe(dark => {
      if (!this.tileLayer) return;
      this.ngZone.runOutsideAngular(() => this.tileLayer!.setUrl(dark ? TILES_DARK : TILES_LIGHT));
    });
  }

  /** Posición de un equipo dentro de su zona a un zoom de referencia: reparto
   *  en espiral (ángulo áureo) en espacio de píxeles, luego convertido a
   *  LatLng. Al ser una posición fija, mientras más zoom más se separan en
   *  pantalla (efecto natural de "abrir" el grupo). */
  private pinLatLng(centro: L.LatLng, i: number, atZoom: number): L.LatLng {
    const angle = i * GOLDEN_ANGLE;
    const radiusPx = 14 + 9 * Math.sqrt(i);
    const offset = L.point(radiusPx * Math.cos(angle), radiusPx * Math.sin(angle));
    const punto = this.map!.project(centro, atZoom).add(offset);
    return this.map!.unproject(punto, atZoom);
  }

  private dibujarMarcadores(): void {
    if (!this.map) return;
    this.markers.forEach(m => m.remove());
    this.pinMarkers.forEach(m => m.remove());
    this.labelMarkers.forEach(m => m.remove());
    this.markers = [];
    this.pinMarkers = [];
    this.labelMarkers = [];
    this.pinsVisible = false;
    this.labelsVisible = false;

    for (const z of this.zonas) {
      const n = z.equipos.length;
      const size = Math.max(34, Math.min(58, 30 + n * 4));
      const pulse = z.worst === 'err' ? ' eh-marker-outer--pulse' : '';
      const centro = L.latLng(z.lat, z.lng);

      const icon = L.divIcon({
        className: 'eh-marker-wrap',
        html: `<div class="eh-marker-outer${pulse}">` +
              `<span class="eh-marker-pulse eh-marker-pulse--${z.worst}"></span>` +
              `<div class="eh-marker eh-marker--${z.worst}">${n}</div>` +
              `</div>`,
        iconSize: [size, size],
        iconAnchor: [size / 2, size / 2],
      });
      const marker = L.marker(centro, { icon, zIndexOffset: 1000 })
        .addTo(this.map!)
        .bindTooltip(`${z.region} · ${n} equipo${n === 1 ? '' : 's'}`, { direction: 'top', offset: L.point(0, -size / 2) });
      marker.on('click', () => {
        // El click nace fuera de la zone (Leaflet) → reentrar para que
        // Angular pinte el panel de la zona seleccionada.
        this.ngZone.run(() => this.seleccionarZona(z));
      });
      this.markers.push(marker);

      // Etiqueta fija con el nombre del departamento (aparece con el zoom).
      const labelIcon = L.divIcon({
        className: 'eh-zone-label-wrap',
        html: `<div class="eh-zone-label">${z.region}</div>`,
        iconSize: [1, 1],
        iconAnchor: [-(size / 2 + 6), 5],
      });
      this.labelMarkers.push(L.marker(centro, { icon: labelIcon, interactive: false, zIndexOffset: 900 }));

      // Pines individuales por equipo (aparecen con más zoom todavía).
      const equipos = [...z.equipos].sort((a, b) => (a.id ?? 0) - (b.id ?? 0));
      equipos.forEach((eq, i) => {
        const st = this.stOf(eq);
        const pinIcon = L.divIcon({
          className: 'eh-pin-wrap',
          html: `<div class="eh-pin eh-pin--${st}"></div>`,
          iconSize: [14, 14],
          iconAnchor: [7, 7],
        });
        const pin = L.marker(this.pinLatLng(centro, i, EXPLODE_ZOOM), { icon: pinIcon, zIndexOffset: 800 })
          .bindTooltip(`${eq.nombre} · ${this.stLabel(eq)}`, { direction: 'top', offset: L.point(0, -9) });
        pin.on('click', () => this.ngZone.run(() => this.abrirEquipo(eq)));
        this.pinMarkers.push(pin);
      });
    }

    this.actualizarNivelDetalle();
  }

  /** Alterna burbujas ⇄ pines individuales ⇄ etiquetas según el zoom actual. */
  private actualizarNivelDetalle(): void {
    if (!this.map) return;
    const zoom = this.map.getZoom();

    const showPins = zoom >= EXPLODE_ZOOM;
    if (showPins !== this.pinsVisible) {
      this.pinsVisible = showPins;
      this.pinMarkers.forEach(p => (showPins ? p.addTo(this.map!) : p.remove()));
    }

    const showLabels = zoom >= LABEL_ZOOM;
    if (showLabels !== this.labelsVisible) {
      this.labelsVisible = showLabels;
      this.labelMarkers.forEach(l => (showLabels ? l.addTo(this.map!) : l.remove()));
    }
  }

  seleccionarZona(z: ZonaMapa): void {
    this.zonaSel = z;
    this.ngZone.runOutsideAngular(() => this.map?.flyTo([z.lat, z.lng], 9, { duration: .9 }));
    this.cdr.markForCheck();
  }

  verTodoElPeru(): void {
    this.zonaSel = null;
    this.ngZone.runOutsideAngular(() => this.map?.flyTo(PERU_CENTER, PERU_ZOOM, { duration: .9 }));
    this.cdr.markForCheck();
  }

  abrirEquipo(eq: any): void {
    this.router.navigate(['/portal-cliente/mantenimiento', eq.id]);
  }

  private destroyMapa(): void {
    this.themeSub?.unsubscribe();
    this.themeSub = null;
    if (this.map) {
      this.map.remove();
      this.map = null;
      this.tileLayer = null;
      this.markers = [];
      this.pinMarkers = [];
      this.labelMarkers = [];
      this.pinsVisible = false;
      this.labelsVisible = false;
    }
  }

  // ── Ciclo de vida ──────────────────────────────────────────────────────

  ngOnInit(): void {
    this.svc.getHistorial().subscribe({
      next: (data) => {
        this.historial = data;
        this.cargando = false;
        this.recalcularDerivadosDeHistorial();
        this.aplicarFiltros();
        this.agruparZonas();
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'No se pudo cargar el historial.';
        this.cargando = false;
        this.cdr.markForCheck();
      },
    });
  }

  ngOnDestroy(): void {
    this.destroyMapa();
  }
}

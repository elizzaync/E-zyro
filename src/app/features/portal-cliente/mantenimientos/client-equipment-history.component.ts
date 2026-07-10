import {
  Component, OnInit, HostListener,
  ChangeDetectionStrategy, ChangeDetectorRef, inject,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { StatusBadgeComponent } from '../shared/status-badge.component';
import { EmptyStateComponent } from '../shared/empty-state.component';
import { PortalPaginationComponent } from '../shared/portal-pagination.component';
import { AppModalComponent } from '../../../shared/components/modal/app-modal.component';
import { PERU_DEPARTAMENTOS, PERU_GEO_ANCHO, PERU_GEO_ALTO, DepartamentoGeo } from '../../../shared/data/peru-departamentos';

type St = 'ok' | 'prog' | 'warn' | 'err' | 'neutral';
type EstadoDep = 'vencido' | 'proximo' | 'ok' | 'sin_equipos';

const KGREEN = '#8FD11B';
const KAMBER = '#F59E0B';
const KRED = '#E53935';
const KSIN_EQUIPOS = '#243044';

const COLOR_POR_ESTADO: Record<EstadoDep, string> = {
  vencido: KRED, proximo: KAMBER, ok: KGREEN, sin_equipos: KSIN_EQUIPOS,
};

// Ciudades/provincias conocidas → departamento — el mismo mapeo que usa el
// mapa interno de Operaciones (mapa-parque), para que el cliente vea
// exactamente la misma zonificación que los técnicos.
const CIUDAD_A_DEP: Record<string, string> = {
  CHACHAPOYAS: 'AMAZONAS', BAGUA: 'AMAZONAS',
  HUARAZ: 'ANCASH', CHIMBOTE: 'ANCASH',
  ABANCAY: 'APURIMAC',
  HUAMANGA: 'AYACUCHO',
  CUZCO: 'CUSCO',
  CHINCHA: 'ICA', PISCO: 'ICA', NAZCA: 'ICA',
  HUANCAYO: 'JUNIN', TARMA: 'JUNIN', SATIPO: 'JUNIN', 'LA OROYA': 'JUNIN',
  TRUJILLO: 'LA LIBERTAD', CHEPEN: 'LA LIBERTAD',
  CHICLAYO: 'LAMBAYEQUE',
  HUACHO: 'LIMA', CANETE: 'LIMA', BARRANCA: 'LIMA',
  IQUITOS: 'LORETO', YURIMAGUAS: 'LORETO',
  'PUERTO MALDONADO': 'MADRE DE DIOS',
  ILO: 'MOQUEGUA',
  'CERRO DE PASCO': 'PASCO',
  SULLANA: 'PIURA', TALARA: 'PIURA', PAITA: 'PIURA',
  JULIACA: 'PUNO',
  MOYOBAMBA: 'SAN MARTIN', TARAPOTO: 'SAN MARTIN',
  PUCALLPA: 'UCAYALI',
};

interface DepEstado {
  equipos: any[];
  vencidos: number;
  proximos: number;
  sinPlan: number;
}

interface DepVista {
  nombre: string;
  anillosPoints: string[];
  color: string;
  estado: EstadoDep;
  total: number;
  vencidos: number;
  proximos: number;
  alDia: number;
  sinPlan: number;
  cx: number;
  cy: number;
  pulso: boolean; // vencidos > 0
}

interface TooltipPos { x: number; y: number; }

@Component({
  selector: 'app-client-equipment-history',
  standalone: true,
  imports: [
    CommonModule, RouterLink, FormsModule,
    StatusBadgeComponent, EmptyStateComponent, PortalPaginationComponent, AppModalComponent,
  ],
  templateUrl: './client-equipment-history.component.html',
  styleUrls: ['./client-equipment-history.component.css'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ClientEquipmentHistoryComponent implements OnInit {
  private svc    = inject(PortalClienteService);
  private cdr    = inject(ChangeDetectorRef);
  private router = inject(Router);

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

  // ── Mapa del Perú (SVG — el mismo que usan los técnicos en Operaciones) ──
  readonly ancho = PERU_GEO_ANCHO;
  readonly alto  = PERU_GEO_ALTO;

  departamentosVista: DepVista[] = [];
  sinUbicar: any[] = [];
  seleccionado: string | null = null; // nombre de departamento, o 'SIN_UBICAR'

  hoverDep: DepVista | null = null;
  hoverPos: TooltipPos | null = null;

  filtroLeyenda: EstadoDep | null = null;
  filtroPanel = '';

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
    if (v === 'mapa' && this.departamentosVista.length === 0) this.agrupar();
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

  // ── Mapa del Perú (SVG) ──────────────────────────────────────────────────

  private static normalizar(s: string | null | undefined): string {
    return (s ?? '')
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '') // quita marcas de acento combinantes (tildes) tras NFD
      .toUpperCase()
      .trim();
  }

  /** Resuelve el departamento de un equipo: primero busca el nombre de un
   *  departamento dentro de sus campos de ubicación (región/sede/ubicación/
   *  proyecto), luego el mapeo de ciudad conocida → departamento. */
  private depDe(eq: any): string | null {
    const texto = [eq.region, eq.sede, eq.ubicacion, eq.proyecto]
      .map(v => ClientEquipmentHistoryComponent.normalizar(v)).join(' | ');
    if (!texto.trim()) return null;
    for (const d of PERU_DEPARTAMENTOS) {
      if (texto.includes(d.nombre)) return d.nombre;
    }
    for (const [ciudad, dep] of Object.entries(CIUDAD_A_DEP)) {
      if (texto.includes(ciudad)) return dep;
    }
    return null;
  }

  private agrupar(): void {
    const porDep = new Map<string, DepEstado>();
    for (const d of PERU_DEPARTAMENTOS) porDep.set(d.nombre, { equipos: [], vencidos: 0, proximos: 0, sinPlan: 0 });
    this.sinUbicar = [];

    for (const e of this.historial) {
      const dep = this.depDe(e);
      if (!dep) { this.sinUbicar.push(e); continue; }
      const est = porDep.get(dep)!;
      est.equipos.push(e);
      const st = this.stOf(e);
      if (st === 'err') est.vencidos++;
      else if (st === 'warn') est.proximos++;
      else if (st !== 'ok') est.sinPlan++;
    }

    this.departamentosVista = PERU_DEPARTAMENTOS.map(d => {
      const est = porDep.get(d.nombre)!;
      const total = est.equipos.length;
      const estado: EstadoDep = total === 0 ? 'sin_equipos'
        : est.vencidos > 0 ? 'vencido'
        : est.proximos > 0 ? 'proximo'
        : 'ok';
      const { cx, cy } = ClientEquipmentHistoryComponent.centroide(d);
      return {
        nombre: d.nombre,
        anillosPoints: d.anillos.map(anillo => ClientEquipmentHistoryComponent.aPoints(anillo)),
        color: COLOR_POR_ESTADO[estado],
        estado, total,
        vencidos: est.vencidos, proximos: est.proximos, sinPlan: est.sinPlan,
        alDia: total - est.vencidos - est.proximos - est.sinPlan,
        cx, cy,
        pulso: est.vencidos > 0,
      };
    });
  }

  private static aPoints(anillo: number[]): string {
    const pts: string[] = [];
    for (let i = 0; i < anillo.length; i += 2) pts.push(`${anillo[i]},${anillo[i + 1]}`);
    return pts.join(' ');
  }

  /** Centro del bounding box del anillo más grande (aprox. al centroide real). */
  private static centroide(d: DepartamentoGeo): { cx: number; cy: number } {
    const anillo = d.anillos.reduce((a, b) => (a.length >= b.length ? a : b));
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (let i = 0; i < anillo.length; i += 2) {
      const x = anillo[i], y = anillo[i + 1];
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
    return { cx: (minX + maxX) / 2, cy: (minY + maxY) / 2 };
  }

  // ── Hover / foco (mouse + teclado) ───────────────────────────────────
  onHoverDep(d: DepVista, ev: MouseEvent): void {
    this.hoverDep = d;
    this.hoverPos = { x: ev.clientX, y: ev.clientY };
  }

  onHoverMove(ev: MouseEvent): void {
    if (this.hoverDep) this.hoverPos = { x: ev.clientX, y: ev.clientY };
  }

  onHoverLeave(): void {
    this.hoverDep = null;
    this.hoverPos = null;
  }

  onFocusDep(d: DepVista, ev: FocusEvent): void {
    const rect = (ev.target as SVGGraphicsElement).getBoundingClientRect();
    this.hoverDep = d;
    this.hoverPos = { x: rect.left + rect.width / 2, y: rect.top };
  }

  get tooltipStyle(): { [k: string]: string } {
    if (!this.hoverPos) return {};
    const cercaBordeDerecho = this.hoverPos.x > window.innerWidth - 220;
    const left = cercaBordeDerecho ? this.hoverPos.x - 220 : this.hoverPos.x + 16;
    const top = Math.max(8, this.hoverPos.y - 12);
    return { left: `${left}px`, top: `${top}px` };
  }

  // ── Leyenda interactiva ───────────────────────────────────────────────
  toggleFiltroLeyenda(estado: EstadoDep): void {
    this.filtroLeyenda = this.filtroLeyenda === estado ? null : estado;
  }

  depAtenuado(d: DepVista): boolean {
    return this.filtroLeyenda !== null && d.estado !== this.filtroLeyenda;
  }

  // ── Selección / panel de detalle ─────────────────────────────────────
  get equiposDelSeleccionado(): any[] {
    if (!this.seleccionado) return [];
    if (this.seleccionado === 'SIN_UBICAR') return this.sinUbicar;
    return this.historial.filter(e => this.depDe(e) === this.seleccionado);
  }

  get equiposFiltradosPanel(): any[] {
    const term = this.filtroPanel.trim().toLowerCase();
    const lista = this.equiposDelSeleccionado;
    if (!term) return lista;
    return lista.filter(e =>
      (e.nombre    || '').toLowerCase().includes(term) ||
      (e.ubicacion || '').toLowerCase().includes(term) ||
      (e.proyecto  || '').toLowerCase().includes(term));
  }

  get depSeleccionado(): DepVista | null {
    if (!this.seleccionado || this.seleccionado === 'SIN_UBICAR') return null;
    return this.departamentosVista.find(x => x.nombre === this.seleccionado) ?? null;
  }

  get tituloPanel(): string {
    if (this.seleccionado === 'SIN_UBICAR') return 'Equipos sin ubicar';
    return this.tituloCase(this.seleccionado || '');
  }

  get subtituloPanel(): string {
    const n = this.equiposDelSeleccionado.length;
    return `${n} equipo${n !== 1 ? 's' : ''} registrado${n !== 1 ? 's' : ''}`;
  }

  get iconBgPanel(): string {
    const color = this.seleccionado === 'SIN_UBICAR' ? '#64748b' : (this.depSeleccionado?.color ?? '#64748b');
    return this.hexARgba(color, 0.14);
  }

  get iconColorPanel(): string {
    return this.seleccionado === 'SIN_UBICAR' ? '#64748b' : (this.depSeleccionado?.color ?? '#64748b');
  }

  private hexARgba(hex: string, alpha: number): string {
    const h = hex.replace('#', '');
    const r = parseInt(h.substring(0, 2), 16);
    const g = parseInt(h.substring(2, 4), 16);
    const b = parseInt(h.substring(4, 6), 16);
    return `rgba(${r},${g},${b},${alpha})`;
  }

  private tituloCase(nombre: string): string {
    return nombre.toLowerCase().replace(/\b\p{L}/gu, (c) => c.toUpperCase());
  }

  @HostListener('document:keydown.escape')
  onEsc(): void {
    if (this.seleccionado) this.cerrarPanel();
  }

  seleccionar(d: DepVista): void {
    this.seleccionado = d.nombre;
    this.filtroPanel = '';
  }

  verSinUbicar(): void {
    this.seleccionado = 'SIN_UBICAR';
    this.filtroPanel = '';
  }

  cerrarPanel(): void {
    this.seleccionado = null;
    this.filtroPanel = '';
  }

  abrirEquipo(eq: any): void {
    this.cerrarPanel();
    this.router.navigate(['/portal-cliente/mantenimiento', eq.id]);
  }

  // ── Ciclo de vida ──────────────────────────────────────────────────────

  ngOnInit(): void {
    this.svc.getHistorial().subscribe({
      next: (data) => {
        this.historial = data;
        this.cargando = false;
        this.recalcularDerivadosDeHistorial();
        this.aplicarFiltros();
        this.agrupar();
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'No se pudo cargar el historial.';
        this.cargando = false;
        this.cdr.markForCheck();
      },
    });
  }
}

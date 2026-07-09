import { Component, OnInit, HostListener, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { EquipoIntervenidoService } from '../../../../../core/services/equipo-intervenido.service';
import { SpinnerComponent } from '../../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../../shared/components/modal/app-modal.component';
import { PERU_DEPARTAMENTOS, PERU_GEO_ANCHO, PERU_GEO_ALTO, DepartamentoGeo } from '../../../../../shared/data/peru-departamentos';

type EstadoSemaforo = 'vencido' | 'proximo' | 'ok' | 'sin_plan';
type EstadoDep = 'vencido' | 'proximo' | 'ok' | 'sin_equipos';

const KGREEN = '#8FD11B';
const KAMBER = '#F59E0B';
const KRED = '#E53935';
const KSIN_EQUIPOS = '#243044';

const COLOR_POR_ESTADO: Record<EstadoDep, string> = {
  vencido: KRED, proximo: KAMBER, ok: KGREEN, sin_equipos: KSIN_EQUIPOS,
};

// Ciudades/provincias conocidas → departamento (nombres ya normalizados),
// portado literal de pantalla_mapa_parque.dart (_ciudadADep).
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
  selector: 'app-mapa-parque',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './mapa-parque.component.html',
  styleUrls: ['./mapa-parque.component.css'],
})
export class MapaParqueComponent implements OnInit {
  private svc = inject(EquipoIntervenidoService);
  private router = inject(Router);

  isLoading = true;
  errorMessage: string | null = null;
  equipos: any[] = [];

  readonly ancho = PERU_GEO_ANCHO;
  readonly alto = PERU_GEO_ALTO;

  departamentosVista: DepVista[] = [];
  sinUbicar: any[] = [];
  seleccionado: string | null = null; // nombre de departamento, o 'SIN_UBICAR'

  // ── Hover / tooltip ───────────────────────────────────────────────────
  hoverDep: DepVista | null = null;
  hoverPos: TooltipPos | null = null;

  // ── Leyenda interactiva (filtra/resalta por estado) ──────────────────
  filtroLeyenda: EstadoDep | null = null;

  // ── Buscador dentro del panel ─────────────────────────────────────────
  filtroPanel = '';

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.listar().subscribe({
      next: (data) => {
        this.equipos = data || [];
        this.agrupar();
        this.isLoading = false;
      },
      error: () => {
        this.errorMessage = 'Error de conexión con el servidor.';
        this.isLoading = false;
      },
    });
  }

  @HostListener('document:keydown.escape')
  onEsc(): void {
    if (this.seleccionado) this.cerrarPanel();
  }

  private static normalizar(s: string): string {
    return s
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '') // quita marcas de acento combinantes (tildes) tras NFD
      .toUpperCase()
      .trim();
  }

  private depDe(ubicacion: string | null | undefined): string | null {
    if (!ubicacion) return null;
    const u = MapaParqueComponent.normalizar(ubicacion);
    for (const d of PERU_DEPARTAMENTOS) {
      if (u === d.nombre || u.includes(d.nombre)) return d.nombre;
    }
    for (const [ciudad, dep] of Object.entries(CIUDAD_A_DEP)) {
      if (u.includes(ciudad)) return dep;
    }
    return null;
  }

  private diasParaMantenimiento(e: any): number | null {
    if (!e.proximo_mantenimiento) return null;
    const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
    const prox = new Date(e.proximo_mantenimiento + 'T00:00:00');
    return Math.round((prox.getTime() - hoy.getTime()) / 86400000);
  }

  /** Estado individual de un equipo (para el badge en el panel). */
  estadoDe(e: any): EstadoSemaforo {
    const d = this.diasParaMantenimiento(e);
    if (d === null) return 'sin_plan';
    if (d < 0) return 'vencido';
    if (d <= 30) return 'proximo';
    return 'ok';
  }

  private agrupar(): void {
    const porDep = new Map<string, DepEstado>();
    for (const d of PERU_DEPARTAMENTOS) porDep.set(d.nombre, { equipos: [], vencidos: 0, proximos: 0, sinPlan: 0 });
    this.sinUbicar = [];

    for (const e of this.equipos) {
      const dep = this.depDe(e.ubicacion_nombre);
      if (!dep) { this.sinUbicar.push(e); continue; }
      const est = porDep.get(dep)!;
      est.equipos.push(e);
      const estado = this.estadoDe(e);
      if (estado === 'vencido') est.vencidos++;
      else if (estado === 'proximo') est.proximos++;
      else if (estado === 'sin_plan') est.sinPlan++;
    }
    for (const est of porDep.values()) {
      est.equipos.sort((a, b) => (this.diasParaMantenimiento(a) ?? 99999) - (this.diasParaMantenimiento(b) ?? 99999));
    }
    this.sinUbicar.sort((a, b) => (this.diasParaMantenimiento(a) ?? 99999) - (this.diasParaMantenimiento(b) ?? 99999));

    this.departamentosVista = PERU_DEPARTAMENTOS.map(d => {
      const est = porDep.get(d.nombre)!;
      const total = est.equipos.length;
      const estado: EstadoDep = total === 0 ? 'sin_equipos'
        : est.vencidos > 0 ? 'vencido'
        : est.proximos > 0 ? 'proximo'
        : 'ok';
      const { cx, cy } = MapaParqueComponent.centroide(d);
      return {
        nombre: d.nombre,
        anillosPoints: d.anillos.map(anillo => MapaParqueComponent.aPoints(anillo)),
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
    const cerca_borde_derecho = this.hoverPos.x > window.innerWidth - 220;
    const left = cerca_borde_derecho ? this.hoverPos.x - 220 : this.hoverPos.x + 16;
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
    const dep = PERU_DEPARTAMENTOS.find(x => x.nombre === this.seleccionado);
    return this.equipos.filter(e => this.depDe(e.ubicacion_nombre) === dep?.nombre);
  }

  get equiposFiltradosPanel(): any[] {
    const term = this.filtroPanel.trim().toLowerCase();
    const lista = this.equiposDelSeleccionado;
    if (!term) return lista;
    return lista.filter(e =>
      (e.nombre || '').toLowerCase().includes(term) ||
      (e.ubicacion_nombre || '').toLowerCase().includes(term) ||
      (e.zona_nombre || '').toLowerCase().includes(term));
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

  irADetalle(id: string): void {
    this.cerrarPanel();
    this.router.navigate(['/operaciones/mantenimiento', id]);
  }

  volver(): void { this.router.navigate(['/operaciones/mantenimiento']); }

  // ── Presentación de estado por equipo (badge del panel) ──────────────
  estadoLabel(e: any): string {
    const d = this.diasParaMantenimiento(e);
    const estado = this.estadoDe(e);
    if (estado === 'sin_plan') return 'Sin plan';
    if (estado === 'vencido') return `Vencido hace ${Math.abs(d!)} d`;
    if (d === 0) return 'Hoy';
    return `En ${d} d`;
  }

  estadoBadgeClass(e: any): string {
    return `badge-${this.estadoDe(e)}`;
  }

  ubicacionCorta(e: any): string {
    return [e.ubicacion_nombre, e.zona_nombre].filter(Boolean).join(' · ') || '—';
  }
}

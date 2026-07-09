import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { EquipoIntervenidoService } from '../../../../../core/services/equipo-intervenido.service';
import { SpinnerComponent } from '../../../../../shared/components/spinner/spinner.component';
import { PERU_DEPARTAMENTOS, PERU_GEO_ANCHO, PERU_GEO_ALTO, DepartamentoGeo } from '../../../../../shared/data/peru-departamentos';

const KGREEN = '#8FD11B';
const KAMBER = '#F59E0B';
const KRED = '#E53935';
const KSIN_EQUIPOS = '#243044';

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
}

interface DepVista {
  nombre: string;
  anillosPoints: string[];
  color: string;
  total: number;
  cx: number;
  cy: number;
  pulso: boolean; // vencidos > 0
}

@Component({
  selector: 'app-mapa-parque',
  standalone: true,
  imports: [CommonModule, SpinnerComponent],
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

  private agrupar(): void {
    const porDep = new Map<string, DepEstado>();
    for (const d of PERU_DEPARTAMENTOS) porDep.set(d.nombre, { equipos: [], vencidos: 0, proximos: 0 });
    this.sinUbicar = [];

    for (const e of this.equipos) {
      const dep = this.depDe(e.ubicacion_nombre);
      if (!dep) { this.sinUbicar.push(e); continue; }
      const est = porDep.get(dep)!;
      est.equipos.push(e);
      const dias = this.diasParaMantenimiento(e);
      if (dias !== null) {
        if (dias < 0) est.vencidos++;
        else if (dias <= 30) est.proximos++;
      }
    }
    for (const est of porDep.values()) {
      est.equipos.sort((a, b) => (this.diasParaMantenimiento(a) ?? 99999) - (this.diasParaMantenimiento(b) ?? 99999));
    }
    this.sinUbicar.sort((a, b) => (this.diasParaMantenimiento(a) ?? 99999) - (this.diasParaMantenimiento(b) ?? 99999));

    this.departamentosVista = PERU_DEPARTAMENTOS.map(d => {
      const est = porDep.get(d.nombre)!;
      const color = est.equipos.length === 0 ? KSIN_EQUIPOS
        : est.vencidos > 0 ? KRED
        : est.proximos > 0 ? KAMBER
        : KGREEN;
      const { cx, cy } = MapaParqueComponent.centroide(d);
      return {
        nombre: d.nombre,
        anillosPoints: d.anillos.map(anillo => MapaParqueComponent.aPoints(anillo)),
        color, total: est.equipos.length, cx, cy,
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

  get equiposDelSeleccionado(): any[] {
    if (!this.seleccionado) return [];
    if (this.seleccionado === 'SIN_UBICAR') return this.sinUbicar;
    const d = this.departamentosVista.find(x => x.nombre === this.seleccionado);
    if (!d) return [];
    const dep = PERU_DEPARTAMENTOS.find(x => x.nombre === this.seleccionado);
    // Recuperar la lista real (no solo el conteo) desde el agrupamiento.
    return this.equipos.filter(e => this.depDe(e.ubicacion_nombre) === dep?.nombre);
  }

  seleccionar(nombre: string): void { this.seleccionado = nombre; }
  verSinUbicar(): void { this.seleccionado = 'SIN_UBICAR'; }
  cerrarPanel(): void { this.seleccionado = null; }

  irADetalle(id: string): void { this.router.navigate(['/operaciones/mantenimiento', id]); }
  volver(): void { this.router.navigate(['/operaciones/mantenimiento']); }

  textoSemaforo(e: any): string {
    const d = this.diasParaMantenimiento(e);
    if (d === null) return 'Sin plan';
    if (d < 0) return `Vencido hace ${Math.abs(d)} d`;
    if (d === 0) return 'Hoy';
    return `En ${d} d`;
  }
}

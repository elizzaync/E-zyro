import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';

// ─── Re-exports para compatibilidad con componentes hijos ──────────────────
export interface ProcedimientoEI {
  id: string;
  orden: number;
  nombre: string;
  descripcion?: string;
  estado: 'pendiente' | 'en_proceso' | 'completado';
  fotoUrl?: string;
}

export interface EquipoEI {
  id: string;
  nombre: string;
  tag?: string;
  ubicacion?: string;
  estado: 'pendiente' | 'en_proceso' | 'completado';
  procedimientos: ProcedimientoEI[];
}

export interface TipoEquipoGrupoEI {
  id: string;
  nombre: string;
  equipos: EquipoEI[];
}

// ─── Types nuevos (vista de zonas) ─────────────────────────────────────────
export type EstadoZona = 'completado' | 'en_proceso' | 'sin_inicio';

export interface ResumenEquiposZona {
  operativos: number;
  enMantenimiento: number;
  fueraDeServicio: number;
  pendientes: number;
}

export interface ZonaServicio {
  id: string;
  nombre: string;
  ciudad: string;
  region: string;
  direccion?: string;
  equipoTotal: number;
  completados: number;
  estado: EstadoZona;
  resumen: ResumenEquiposZona;
  tecnicosAsignados: string[];
  fechaIntervencion?: string;
}

// ─── Mock data ─────────────────────────────────────────────────────────────
const MOCK_ZONAS: ZonaServicio[] = [
  {
    id: 'trujillo',
    nombre: 'Sede Norte',
    ciudad: 'Trujillo', region: 'La Libertad',
    direccion: 'Av. Larco 1240',
    equipoTotal: 7, completados: 5,
    estado: 'en_proceso',
    resumen: { operativos: 3, enMantenimiento: 2, fueraDeServicio: 1, pendientes: 1 },
    tecnicosAsignados: ['Carlos V.', 'Andrea L.'],
    fechaIntervencion: '24 May 2026',
  },
  {
    id: 'iquitos',
    nombre: 'Base Amazónica',
    ciudad: 'Iquitos', region: 'Loreto',
    direccion: 'Jr. Próspero 312',
    equipoTotal: 4, completados: 2,
    estado: 'en_proceso',
    resumen: { operativos: 1, enMantenimiento: 1, fueraDeServicio: 2, pendientes: 0 },
    tecnicosAsignados: ['Miguel R.'],
    fechaIntervencion: '24 May 2026',
  },
  {
    id: 'loreto',
    nombre: 'Sede Loretana',
    ciudad: 'Yurimaguas', region: 'Loreto',
    direccion: 'Calle Libertad 88',
    equipoTotal: 0, completados: 0,
    estado: 'sin_inicio',
    resumen: { operativos: 0, enMantenimiento: 0, fueraDeServicio: 0, pendientes: 0 },
    tecnicosAsignados: [],
    fechaIntervencion: '25 May 2026',
  },
  {
    id: 'lima-norte',
    nombre: 'Planta Lima Norte',
    ciudad: 'Los Olivos', region: 'Lima',
    direccion: 'Av. Tomás Valle 2100',
    equipoTotal: 3, completados: 1,
    estado: 'en_proceso',
    resumen: { operativos: 2, enMantenimiento: 0, fueraDeServicio: 0, pendientes: 1 },
    tecnicosAsignados: ['Sandra M.', 'Jhon C.', 'Pedro A.'],
    fechaIntervencion: '23 May 2026',
  },
  {
    id: 'callao',
    nombre: 'Puerto Industrial',
    ciudad: 'Callao', region: 'Callao',
    direccion: 'Av. N. Gambetta 8000',
    equipoTotal: 6, completados: 6,
    estado: 'completado',
    resumen: { operativos: 6, enMantenimiento: 0, fueraDeServicio: 0, pendientes: 0 },
    tecnicosAsignados: ['Karla F.', 'Luis B.'],
    fechaIntervencion: '22 May 2026',
  },
];

// ─── Component ─────────────────────────────────────────────────────────────
@Component({
  selector: 'app-equipos-intervenidos',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './equipos-intervenidos.component.html',
  styleUrls: ['./equipos-intervenidos.component.css'],
})
export class EquiposIntervenidosComponent implements OnInit {
  private route    = inject(ActivatedRoute);
  private router   = inject(Router);
  private location = inject(Location);

  servicioId: string | null = null;
  cargando = true;
  zonas: ZonaServicio[] = [];
  filtroEstado: EstadoZona | 'todos' = 'todos';

  // ─── Lifecycle ───────────────────────────────────────────────────────────
  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id');
    setTimeout(() => {
      this.zonas = MOCK_ZONAS.map(z => ({ ...z }));
      this.cargando = false;
    }, 800);
  }

  // ─── Navigation ──────────────────────────────────────────────────────────
  volver(): void { this.location.back(); }

  verEquipos(zona: ZonaServicio): void {
    this.router.navigate(['/operaciones/servicio', this.servicioId, 'equipos', zona.id]);
  }

  // ─── Getters ─────────────────────────────────────────────────────────────
  get zonasFiltradas(): ZonaServicio[] {
    if (this.filtroEstado === 'todos') return this.zonas;
    return this.zonas.filter(z => z.estado === this.filtroEstado);
  }

  get totalEquipos(): number {
    return this.zonas.reduce((a, z) => a + z.equipoTotal, 0);
  }

  get totalCompletados(): number {
    return this.zonas.reduce((a, z) => a + z.completados, 0);
  }

  get progresoGlobal(): number {
    return this.totalEquipos ? Math.round((this.totalCompletados / this.totalEquipos) * 100) : 0;
  }

  get contarCompletadas(): number {
    return this.zonas.filter(z => z.estado === 'completado').length;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────
  progreso(zona: ZonaServicio): number {
    return zona.equipoTotal ? Math.round((zona.completados / zona.equipoTotal) * 100) : 0;
  }

  estadoLabel(e: EstadoZona): string {
    return { completado: 'Completado', en_proceso: 'En proceso', sin_inicio: 'Sin inicio' }[e];
  }

  avatarColor(idx: number): string {
    const palette = ['#91d337', '#3b82f6', '#8b5cf6', '#f59e0b', '#06b6d4', '#ec4899'];
    return palette[idx % palette.length];
  }
}

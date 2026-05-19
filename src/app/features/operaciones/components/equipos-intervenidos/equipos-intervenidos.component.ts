import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { ActivatedRoute } from '@angular/router';

import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { TipoEquipoGrupoComponent } from './components/tipo-equipo-grupo/tipo-equipo-grupo.component';

/* ── Modelos de dominio ──────────────────────────────────────────────────── */

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

/* ── Componente ──────────────────────────────────────────────────────────── */

@Component({
  selector: 'app-equipos-intervenidos',
  standalone: true,
  imports: [CommonModule, SpinnerComponent, TipoEquipoGrupoComponent],
  templateUrl: './equipos-intervenidos.component.html',
  styleUrls: ['./equipos-intervenidos.component.css'],
})
export class EquiposIntervenidosComponent implements OnInit {
  private route    = inject(ActivatedRoute);
  private location = inject(Location);

  servicioId: string | null = null;
  cargando = true;
  grupos: TipoEquipoGrupoEI[] = [];

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id');
    // TODO: reemplazar con llamada real a OperacionesService
    setTimeout(() => {
      this.grupos = this._mockData();
      this.cargando = false;
    }, 600);
  }

  volver(): void {
    this.location.back();
  }

  /** Calcula el progreso (%) de un grupo en base a sus procedimientos. */
  progresoGrupo(grupo: TipoEquipoGrupoEI): number {
    const total = grupo.equipos.reduce((s, e) => s + e.procedimientos.length, 0);
    if (total === 0) return 0;
    const done = grupo.equipos.reduce(
      (s, e) => s + e.procedimientos.filter(p => p.estado === 'completado').length,
      0,
    );
    return Math.round((done / total) * 100);
  }

  /* ── Datos de demostración (reemplazar con API) ──────────────────────── */
  private _mockData(): TipoEquipoGrupoEI[] {
    return [
      {
        id: 'g1',
        nombre: 'Pozos a Tierra — Sede Jauja',
        equipos: [
          {
            id: 'eq1', nombre: 'Pozo a Tierra #1', tag: 'PT-001',
            ubicacion: 'Sala de servidores', estado: 'completado',
            procedimientos: [
              { id: 'p1', orden: 1, nombre: 'Inspección visual del electrodo',   estado: 'completado', fotoUrl: 'https://picsum.photos/seed/p1/400/300' },
              { id: 'p2', orden: 2, nombre: 'Medición de resistencia inicial',   estado: 'completado', fotoUrl: 'https://picsum.photos/seed/p2/400/300' },
              { id: 'p3', orden: 3, nombre: 'Aplicación de gel conductor',       estado: 'completado' },
            ],
          },
          {
            id: 'eq2', nombre: 'Pozo a Tierra #2', tag: 'PT-002',
            ubicacion: 'Tablero principal', estado: 'en_proceso',
            procedimientos: [
              { id: 'p4', orden: 1, nombre: 'Inspección visual del electrodo',   estado: 'completado', fotoUrl: 'https://picsum.photos/seed/p4/400/300' },
              { id: 'p5', orden: 2, nombre: 'Medición de resistencia inicial',   estado: 'en_proceso' },
              { id: 'p6', orden: 3, nombre: 'Aplicación de gel conductor',       estado: 'pendiente' },
            ],
          },
        ],
      },
      {
        id: 'g2',
        nombre: 'Tableros Eléctricos — Sede Principal',
        equipos: [
          {
            id: 'eq3', nombre: 'Tablero General TG-01', tag: 'TG-001',
            ubicacion: 'Ingreso principal', estado: 'pendiente',
            procedimientos: [
              { id: 'p7', orden: 1, nombre: 'Verificar tensión de alimentación', estado: 'pendiente' },
              { id: 'p8', orden: 2, nombre: 'Revisión de bornes y conexiones',   estado: 'pendiente' },
            ],
          },
        ],
      },
    ];
  }
}

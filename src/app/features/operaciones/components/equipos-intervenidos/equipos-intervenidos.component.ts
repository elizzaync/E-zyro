import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';

export interface ProcedimientoEI {
  id: string;
  orden: number;
  nombre: string;
  descripcion?: string | null;
  estado: 'pendiente' | 'en_proceso' | 'completado';
  fotoUrl?: string | null;
}

export interface EquipoEI {
  id: string;
  nombre: string;
  tag?: string | null;
  estado: 'pendiente' | 'en_proceso' | 'completado';
  ubicacion?: string | null;
  procedimientos: ProcedimientoEI[];
}

export interface TipoEquipoGrupoEI {
  nombre: string;
  equipos: EquipoEI[];
}

export interface EquipoIntervenido {
  id: string;
  nombre: string;
  codigo?: string | null;
  tipoNombre?: string | null;
  tipoEquipoId?: string | null;
  marca?: string | null;
  modelo?: string | null;
  numeroSerie?: string | null;
  estadoIntervencion: 'pendiente' | 'en_proceso' | 'completado' | 'cancelado';
  estado: string;
  observaciones?: string | null;
}

export interface EquipoDisponible {
  id: string;
  nombre: string;
  codigo?: string | null;
  tipoNombre?: string | null;
  marca?: string | null;
  modelo?: string | null;
  ubicacion?: string | null;
  estado: string;
}

@Component({
  selector: 'app-equipos-intervenidos',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './equipos-intervenidos.component.html',
  styleUrls: ['./equipos-intervenidos.component.css'],
})
export class EquiposIntervenidosComponent implements OnInit {
  private route    = inject(ActivatedRoute);
  private router   = inject(Router);
  private location = inject(Location);
  private svc      = inject(OperacionesService);

  servicioId: string = '';
  cargando    = true;
  error       = false;
  equipos: EquipoIntervenido[] = [];

  // Modal agregar
  showModal      = false;
  cargandoModal  = false;
  equiposDisp: EquipoDisponible[] = [];
  filtroModal    = '';
  agregando      = false;

  // Confirmación quitar
  confirmandoQuitarId: string | null = null;

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id') ?? '';
    this.cargar();
  }

  cargar(): void {
    this.cargando = true;
    this.error    = false;
    this.svc.getEquiposIntervenidos(this.servicioId).subscribe({
      next: (data) => {
        this.equipos = data.map(this._mapEquipo);
        this.cargando = false;
      },
      error: () => { this.cargando = false; this.error = true; }
    });
  }

  // ── Modal ────────────────────────────────────────────────────────────────
  abrirModal(): void {
    this.showModal    = true;
    this.filtroModal  = '';
    this.cargandoModal = true;
    this.svc.getEquiposDisponibles(this.servicioId).subscribe({
      next: (data) => {
        this.equiposDisp  = data.map(this._mapDisp);
        this.cargandoModal = false;
      },
      error: () => { this.cargandoModal = false; }
    });
  }

  cerrarModal(): void { this.showModal = false; }

  get equiposFiltrados(): EquipoDisponible[] {
    const q = this.filtroModal.toLowerCase().trim();
    if (!q) return this.equiposDisp;
    return this.equiposDisp.filter(e =>
      e.nombre.toLowerCase().includes(q) ||
      (e.codigo ?? '').toLowerCase().includes(q) ||
      (e.tipoNombre ?? '').toLowerCase().includes(q)
    );
  }

  agregar(equipo: EquipoDisponible): void {
    if (this.agregando) return;
    this.agregando = true;
    this.svc.agregarEquipoIntervenido(this.servicioId, equipo.id).subscribe({ // id = activo_cliente_id
      next: (nuevo) => {
        this.equipos.push(this._mapEquipo(nuevo));
        this.equiposDisp = this.equiposDisp.filter(e => e.id !== equipo.id);
        this.agregando = false;
      },
      error: () => { this.agregando = false; }
    });
  }

  // ── Quitar ───────────────────────────────────────────────────────────────
  confirmarQuitar(id: string): void { this.confirmandoQuitarId = id; }
  cancelarQuitar(): void            { this.confirmandoQuitarId = null; }

  quitar(id: string): void {
    this.svc.quitarEquipoIntervenido(this.servicioId, id).subscribe({
      next: () => {
        this.equipos = this.equipos.filter(e => e.id !== id);
        this.confirmandoQuitarId = null;
      }
    });
  }

  // ── Intervenir ───────────────────────────────────────────────────────────
  intervenir(ei: EquipoIntervenido): void {
    if (ei.estadoIntervencion === 'pendiente') {
      this.svc.actualizarEstadoIntervencion(this.servicioId, ei.id, 'en_proceso').subscribe({
        next: () => { ei.estadoIntervencion = 'en_proceso'; }
      });
    }
    this.router.navigate([
      '/operaciones/servicio', this.servicioId,
      'equipos-intervenidos', ei.id
    ]);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  volver(): void { this.location.back(); }

  estadoLabel(e: string): string {
    return ({
      pendiente:   'Pendiente',
      en_proceso:  'En Proceso',
      completado:  'Completado',
      cancelado:   'Cancelado',
    } as Record<string, string>)[e] ?? e;
  }

  estadoClass(e: string): string {
    return ({
      pendiente:  'badge--warn',
      en_proceso: 'badge--info',
      completado: 'badge--ok',
      cancelado:  'badge--muted',
    } as Record<string, string>)[e] ?? '';
  }

  private _mapEquipo = (r: any): EquipoIntervenido => ({
    id:                 r.id,
    nombre:             r.nombre,
    codigo:             r.codigo       ?? null,
    tipoNombre:         r.tipo_nombre  ?? null,
    tipoEquipoId:       r.tipo_equipo_id ?? null,
    marca:              r.marca        ?? null,
    modelo:             r.modelo       ?? null,
    numeroSerie:        r.numero_serie ?? null,
    estadoIntervencion: r.estado_intervencion ?? 'pendiente',
    estado:             r.estado ?? 'operativo',
    observaciones:      r.observaciones ?? null,
  });

  private _mapDisp = (r: any): EquipoDisponible => ({
    id:        r.id,
    nombre:    r.nombre,
    codigo:    r.codigo      ?? null,
    tipoNombre:r.tipo_nombre ?? null,
    marca:     r.marca       ?? null,
    modelo:    r.modelo      ?? null,
    ubicacion: r.ubicacion   ?? null,
    estado:    r.estado,
  });
}

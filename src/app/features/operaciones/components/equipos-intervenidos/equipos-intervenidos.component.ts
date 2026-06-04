import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { ToastService } from '../../../../core/services/toast.service';

// Interfaces legacy requeridas por sub-componentes heredados
export interface ProcedimientoEI {
  id: string; orden: number; nombre: string;
  descripcion?: string | null; estado: 'pendiente' | 'en_proceso' | 'completado';
  fotoUrl?: string | null;
}
export interface EquipoEI {
  id: string; nombre: string; tag?: string | null;
  estado: 'pendiente' | 'en_proceso' | 'completado';
  ubicacion?: string | null; procedimientos: ProcedimientoEI[];
}
export interface TipoEquipoGrupoEI { nombre: string; equipos: EquipoEI[]; }

export interface EquipoIntervenido {
  id: string;
  nombre: string;
  codigo: string | null;
  ubicacionReferencia: string | null;
  tipoNombre: string | null;
  tipoEquipoId: string | null;
  marca: string | null;
  modelo: string | null;
  numeroSerie: string | null;
  ubicacion: string | null;
  zona: string | null;
  ultimoMantenimiento: string | null;
  proximoMantenimiento: string | null;
  estadoIntervencion: string;
  estado: string;
}

@Component({
  selector: 'app-equipos-intervenidos',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './equipos-intervenidos.component.html',
  styleUrls: ['./equipos-intervenidos.component.css'],
})
export class EquiposIntervenidosComponent implements OnInit {
  private route    = inject(ActivatedRoute);
  private router   = inject(Router);
  private location = inject(Location);
  private svc      = inject(OperacionesService);
  private toast    = inject(ToastService);

  servicioId = '';
  cargando   = true;
  error      = false;

  equipos: EquipoIntervenido[] = [];
  filtro = '';

  // Modal nuevo equipo
  showFormNuevo  = false;
  guardandoNuevo = false;
  nuevoNombre    = '';
  nuevoTipo      = '';
  nuevoDesc      = '';

  // Tipos de equipo disponibles para el form
  tiposDisp: { id: string; nombre: string }[] = [];

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id') ?? '';
    this.cargar();
  }

  cargar(): void {
    this.cargando = true;
    this.error    = false;
    this.svc.getEquiposIntervenidos(this.servicioId).subscribe({
      next: (data: any[]) => {
        this.equipos = data.map(r => ({
          id:                  r.id,
          nombre:              r.nombre,
          codigo:              r.codigo       ?? null,
          ubicacionReferencia: r.ubicacion_referencia ?? null,
          tipoNombre:          r.tipo_nombre  ?? null,
          tipoEquipoId:        r.tipo_equipo_id ?? null,
          marca:               r.marca        ?? null,
          modelo:              r.modelo       ?? null,
          numeroSerie:         r.numero_serie ?? null,
          ubicacion:           r.ubicacion    ?? null,
          zona:                r.zona         ?? null,
          ultimoMantenimiento: r.ultimo_mantenimiento ?? null,
          proximoMantenimiento: r.proximo_mantenimiento ?? null,
          estadoIntervencion:  r.estado_intervencion ?? 'sin_inspeccion',
          estado:              r.estado ?? 'operativo',
        }));
        this.cargando = false;

        // Extraer tipos únicos para el formulario
        const vistos = new Set<string>();
        this.tiposDisp = [];
        data.forEach((r: any) => {
          if (r.tipo_equipo_id && r.tipo_nombre && !vistos.has(r.tipo_equipo_id)) {
            vistos.add(r.tipo_equipo_id);
            this.tiposDisp.push({ id: r.tipo_equipo_id, nombre: r.tipo_nombre });
          }
        });
        this.tiposDisp.sort((a, b) => a.nombre.localeCompare(b.nombre));
      },
      error: () => { this.cargando = false; this.error = true; }
    });
  }

  // ── Filtro ────────────────────────────────────────────────────────────────
  get equiposFiltrados(): EquipoIntervenido[] {
    const q = this.filtro.toLowerCase().trim();
    if (!q) return this.equipos;
    return this.equipos.filter(e =>
      e.nombre.toLowerCase().includes(q) ||
      (e.tipoNombre ?? '').toLowerCase().includes(q) ||
      (e.ubicacion  ?? '').toLowerCase().includes(q) ||
      (e.zona       ?? '').toLowerCase().includes(q) ||
      (e.codigo     ?? '').toLowerCase().includes(q)
    );
  }

  // ── Inspeccionar ──────────────────────────────────────────────────────────
  inspeccionar(ei: EquipoIntervenido): void {
    this.router.navigate([
      '/operaciones/servicio', this.servicioId,
      'equipos-intervenidos', ei.id
    ]);
  }

  // ── Crear nuevo equipo en catálogo ────────────────────────────────────────
  abrirFormNuevo(): void {
    this.showFormNuevo = true;
    this.nuevoNombre   = '';
    this.nuevoTipo     = '';
    this.nuevoDesc     = '';
  }
  cerrarFormNuevo(): void { this.showFormNuevo = false; }

  guardarNuevo(): void {
    if (!this.nuevoNombre.trim()) {
      this.toast.mostrar('Ingresa el nombre del equipo.', 'error');
      return;
    }
    this.guardandoNuevo = true;
    this.svc.crearEquipoCatalogo(this.servicioId, {
      nombre:        this.nuevoNombre.trim(),
      tipo_equipo_id: this.nuevoTipo || null,
      descripcion:   this.nuevoDesc.trim() || null,
    }).subscribe({
      next: (nuevo: any) => {
        this.guardandoNuevo = false;
        this.showFormNuevo  = false;
        this.toast.mostrar('Equipo agregado al catálogo.', 'success');
        this.cargar();
      },
      error: (err: any) => {
        this.guardandoNuevo = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al crear el equipo.', 'error');
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  volver(): void { this.location.back(); }

  estadoLabel(e: string): string {
    return ({
      sin_inspeccion: 'Sin inspección',
      en_proceso:     'En Proceso',
      completado:     'Completado',
    } as Record<string, string>)[e] ?? e;
  }

  estadoClass(e: string): string {
    return ({
      sin_inspeccion: 'badge--muted',
      en_proceso:     'badge--info',
      completado:     'badge--ok',
    } as Record<string, string>)[e] ?? 'badge--muted';
  }
}

import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

interface PasoLocal {
  id: string;
  orden: number;
  nombre: string;
  descripcion: string | null;
  completado: boolean;
  fotoUrl: string | null;
  fotoPublicId: string | null;
  subiendoFoto: boolean;
}

interface EquipoDetalle {
  id: string;
  nombre: string;
  codigo: string | null;
  tipoNombre: string | null;
  marca: string | null;
  modelo: string | null;
  numeroSerie: string | null;
  estado: string;
  estadoIntervencion: string;
  observaciones: string | null;
}

@Component({
  selector: 'app-intervencion-equipo',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './intervencion-equipo.component.html',
  styleUrls: ['./intervencion-equipo.component.css'],
})
export class IntervencionEquipoComponent implements OnInit {
  private route    = inject(ActivatedRoute);
  private location = inject(Location);
  private svc      = inject(OperacionesService);
  private toast    = inject(ToastService);

  servicioId = '';
  eiId       = '';

  cargando  = true;
  error     = false;
  guardando = false;

  equipo: EquipoDetalle | null = null;
  pasos:  PasoLocal[]          = [];

  observaciones = '';

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id')    ?? '';
    this.eiId       = this.route.snapshot.paramMap.get('eiId')  ?? '';
    this.cargar();
  }

  cargar(): void {
    this.cargando = true;
    this.error    = false;

    this.svc.getDetalleEI(this.servicioId, this.eiId).subscribe({
      next: (data: any) => {
        this.equipo = {
          id:                 data.id,
          nombre:             data.nombre,
          codigo:             data.codigo        ?? null,
          tipoNombre:         data.tipo_nombre   ?? null,
          marca:              data.marca         ?? null,
          modelo:             data.modelo        ?? null,
          numeroSerie:        data.numero_serie  ?? null,
          estado:             data.estado,
          estadoIntervencion: data.estado_intervencion,
          observaciones:      data.observaciones ?? null,
        };
        this.observaciones = data.observaciones ?? '';
        this._cargarOIniciarPasos();
      },
      error: () => { this.cargando = false; this.error = true; },
    });
  }

  private _cargarOIniciarPasos(): void {
    this.svc.getProcedimientosEI(this.servicioId, this.eiId).subscribe({
      next: (lista: any[]) => {
        if (lista.length > 0) {
          this.pasos    = lista.map(this._mapPaso);
          this.cargando = false;
        } else {
          this.svc.iniciarProcedimientosEI(this.servicioId, this.eiId).subscribe({
            next: (creados: any[]) => {
              this.pasos    = creados.map(this._mapPaso);
              this.cargando = false;
              if (this.equipo) this.equipo.estadoIntervencion = 'en_proceso';
            },
            error: (err: any) => {
              this.cargando = false;
              this.error    = true;
              this.toast.mostrar(err?.error?.detail ?? 'Error al iniciar la inspección.', 'error');
            },
          });
        }
      },
      error: () => { this.cargando = false; this.error = true; },
    });
  }

  private _mapPaso = (r: any): PasoLocal => ({
    id:           r.id,
    orden:        r.orden,
    nombre:       r.nombre,
    descripcion:  r.descripcion ?? null,
    completado:   r.estado === 'completado',
    fotoUrl:      r.foto_url ?? null,
    fotoPublicId: null,
    subiendoFoto: false,
  });

  // ── Toggle completado (local, sin API) ───────────────────────────────────
  toggleCompletado(paso: PasoLocal): void {
    if (this.estaFinalizado) return;
    paso.completado = !paso.completado;
  }

  // ── Subir foto al seleccionarla ──────────────────────────────────────────
  onFotoSeleccionada(event: Event, paso: PasoLocal): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    (event.target as HTMLInputElement).value = '';
    if (!file || this.estaFinalizado) return;

    const reader = new FileReader();
    reader.onload = e => { paso.fotoUrl = e.target?.result as string; };
    reader.readAsDataURL(file);

    paso.subiendoFoto = true;
    const fd = new FormData();
    fd.append('archivo', file);

    this.svc.subirFotoEI(this.servicioId, this.eiId, paso.id, fd).subscribe({
      next: (res: any) => {
        paso.fotoUrl      = res.url ?? paso.fotoUrl;
        paso.fotoPublicId = res.public_id ?? null;
        paso.subiendoFoto = false;
      },
      error: (err: any) => {
        paso.subiendoFoto = false;
        paso.fotoUrl      = null;
        this.toast.mostrar(err?.error?.detail ?? 'Error al subir la foto.', 'error');
      },
    });
  }

  // ── Guardado global ──────────────────────────────────────────────────────
  guardar(): void {
    if (this.guardando || this.estaFinalizado) return;

    const alguno_subiendo = this.pasos.some(p => p.subiendoFoto);
    if (alguno_subiendo) {
      this.toast.mostrar('Espera a que terminen de subirse las fotos.', 'error');
      return;
    }

    this.guardando = true;

    const payload = {
      pasos: this.pasos.map(p => ({
        id:            p.id,
        completado:    p.completado,
        foto_url:      p.fotoUrl      ?? null,
        foto_public_id: p.fotoPublicId ?? null,
      })),
      observaciones: this.observaciones.trim() || null,
    };

    this.svc.guardarInspeccion(this.servicioId, this.eiId, payload).subscribe({
      next: (res: any) => {
        this.guardando = false;
        if (this.equipo) {
          this.equipo.estadoIntervencion = res.estado_intervencion ?? this.equipo.estadoIntervencion;
        }
        const msg = res.estado_intervencion === 'completado'
          ? '¡Inspección completada y guardada exitosamente!'
          : 'Inspección guardada correctamente.';
        this.toast.mostrar(msg, 'success');
      },
      error: (err: any) => {
        this.guardando = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al guardar la inspección.', 'error');
      },
    });
  }

  // ── Computed ─────────────────────────────────────────────────────────────
  get completados(): number  { return this.pasos.filter(p => p.completado).length; }
  get total(): number        { return this.pasos.length; }
  get progreso(): number     { return this.total ? Math.round((this.completados / this.total) * 100) : 0; }
  get todosCompletados(): boolean { return this.total > 0 && this.completados === this.total; }
  get estaFinalizado(): boolean   { return this.equipo?.estadoIntervencion === 'completado'; }

  estadoLabel(e: string): string {
    return ({ pendiente: 'Pendiente', en_proceso: 'En Proceso', completado: 'Completado' } as Record<string, string>)[e] ?? e;
  }

  volver(): void { this.location.back(); }
}

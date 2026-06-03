import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { ActivatedRoute } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

interface ProcEI {
  id: string;
  orden: number;
  nombre: string;
  descripcion?: string | null;
  estado: 'pendiente' | 'en_proceso' | 'completado';
  fotoUrl?: string | null;
  subiendoFoto?: boolean;
  completando?: boolean;
}

interface EquipoDetalle {
  id: string;
  nombre: string;
  codigo?: string | null;
  tipoNombre?: string | null;
  marca?: string | null;
  modelo?: string | null;
  numeroSerie?: string | null;
  estado: string;
  estadoIntervencion: string;
}

@Component({
  selector: 'app-intervencion-equipo',
  standalone: true,
  imports: [CommonModule, SpinnerComponent],
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
  equipo: EquipoDetalle | null = null;
  procs: ProcEI[] = [];

  finalizando = false;

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
        };
        this._cargarOIniciarProcedimientos();
      },
      error: () => { this.cargando = false; this.error = true; }
    });
  }

  private _cargarOIniciarProcedimientos(): void {
    this.svc.getProcedimientosEI(this.servicioId, this.eiId).subscribe({
      next: (lista) => {
        if (lista.length > 0) {
          this.procs   = lista.map(this._mapProc);
          this.cargando = false;
        } else {
          // Primera vez: instanciar desde template
          this.svc.iniciarProcedimientosEI(this.servicioId, this.eiId).subscribe({
            next: (creados) => {
              this.procs   = creados.map(this._mapProc);
              this.cargando = false;
              if (this.equipo) this.equipo.estadoIntervencion = 'en_proceso';
            },
            error: (err: any) => {
              this.cargando = false;
              this.error    = true;
              this.toast.mostrar(err?.error?.detail ?? 'Error al iniciar procedimientos.', 'error');
            }
          });
        }
      },
      error: () => { this.cargando = false; this.error = true; }
    });
  }

  private _mapProc = (r: any): ProcEI => ({
    id:          r.id,
    orden:       r.orden,
    nombre:      r.nombre,
    descripcion: r.descripcion ?? null,
    estado:      r.estado ?? 'pendiente',
    fotoUrl:     r.foto_url ?? null,
    subiendoFoto: false,
    completando:  false,
  });

  // ── Subir foto y completar procedimiento ──────────────────────────────────
  onFotoSeleccionada(event: Event, proc: ProcEI): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    (event.target as HTMLInputElement).value = '';
    if (!file) return;

    // Preview local inmediata
    const reader = new FileReader();
    reader.onload = e => { proc.fotoUrl = e.target?.result as string; };
    reader.readAsDataURL(file);

    proc.subiendoFoto = true;
    const fd = new FormData();
    fd.append('archivo', file);
    fd.append('etapa', 'durante');

    this.svc.subirEvidencia(proc.id, fd).subscribe({
      next: (res: any) => {
        proc.fotoUrl     = res.url ?? proc.fotoUrl;
        proc.estado      = 'completado';
        proc.subiendoFoto = false;
        this._verificarAutoFinalizar();
      },
      error: (err: any) => {
        proc.subiendoFoto = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al subir la foto.', 'error');
      }
    });
  }

  // ── Completar sin foto ────────────────────────────────────────────────────
  completarSinFoto(proc: ProcEI): void {
    if (proc.completando) return;
    proc.completando = true;
    this.svc.toggleProcedimiento(proc.id, 'completado').subscribe({
      next: () => {
        proc.estado      = 'completado';
        proc.completando = false;
        this._verificarAutoFinalizar();
      },
      error: (err: any) => {
        proc.completando = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al completar el paso.', 'error');
      }
    });
  }

  // ── Desmarcar procedimiento ───────────────────────────────────────────────
  desmarcar(proc: ProcEI): void {
    if (proc.completando) return;
    proc.completando = true;
    this.svc.toggleProcedimiento(proc.id, 'pendiente').subscribe({
      next: () => {
        proc.estado      = 'pendiente';
        proc.completando = false;
      },
      error: () => { proc.completando = false; }
    });
  }

  private _verificarAutoFinalizar(): void {
    if (this.todosCompletados && this.equipo?.estadoIntervencion !== 'completado') {
      this.toast.mostrar('¡Todos los pasos completados! Puedes finalizar la intervención.', 'success');
    }
  }

  // ── Finalizar intervención ────────────────────────────────────────────────
  finalizar(): void {
    if (!this.todosCompletados || this.finalizando) return;
    this.finalizando = true;
    this.svc.completarIntervencion(this.servicioId, this.eiId).subscribe({
      next: () => {
        if (this.equipo) this.equipo.estadoIntervencion = 'completado';
        this.finalizando = false;
        this.toast.mostrar('Intervención finalizada correctamente.', 'success');
      },
      error: (err: any) => {
        this.finalizando = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al finalizar la intervención.', 'error');
      }
    });
  }

  // ── Computed ──────────────────────────────────────────────────────────────
  get completados(): number  { return this.procs.filter(p => p.estado === 'completado').length; }
  get total(): number        { return this.procs.length; }
  get progreso(): number     { return this.total ? Math.round((this.completados / this.total) * 100) : 0; }
  get todosCompletados(): boolean { return this.total > 0 && this.completados === this.total; }

  estadoLabel(e: string): string {
    return ({ pendiente: 'Pendiente', en_proceso: 'En Proceso', completado: 'Completado' } as Record<string, string>)[e] ?? e;
  }

  volver(): void { this.location.back(); }
}

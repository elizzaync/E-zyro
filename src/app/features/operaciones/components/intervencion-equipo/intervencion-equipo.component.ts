import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

interface ProcLocal {
  orden: number;
  nombre: string;
  descripcion: string;
  completado: boolean;
  fotoUrl: string | null;
  fotoPublicId: string | null;
  subiendoFoto: boolean;
  quitandoFoto: boolean;
}

interface EquipoInfo {
  nombre: string;
  codigo: string | null;
  tipoNombre: string | null;
  marca: string | null;
  modelo: string | null;
  numeroSerie: string | null;
  estadoIntervencion: string;
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

  servicioId    = '';
  eiId          = '';
  inspeccionId  = '';

  cargando   = true;
  error      = false;
  guardando   = false;
  finalizando = false;

  // Alerta confirmación finalizar con incompletos
  showAlertaFinalizar = false;

  equipo: EquipoInfo | null = null;
  procs: ProcLocal[]        = [];

  observaciones  = '';
  proximaFecha   = '';
  mostrarFinalizar = false;

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id')    ?? '';
    this.eiId       = this.route.snapshot.paramMap.get('eiId')  ?? '';
    this.cargar();
  }

  cargar(): void {
    this.cargando = true;
    this.error    = false;
    this.svc.getInspeccionActiva(this.servicioId, this.eiId).subscribe({
      next: (data: any) => {
        this.inspeccionId = data.inspeccion_id;
        this.observaciones = data.observaciones ?? '';
        this.proximaFecha  = data.proxima_fecha ?? '';
        this.equipo = {
          nombre:             data.equipo.nombre,
          codigo:             data.equipo.codigo ?? null,
          tipoNombre:         data.equipo.tipo_nombre ?? null,
          marca:              data.equipo.marca ?? null,
          modelo:             data.equipo.modelo ?? null,
          numeroSerie:        data.equipo.numero_serie ?? null,
          estadoIntervencion: data.equipo.estado_intervencion,
        };
        this.procs = (data.resultado as any[]).map(r => ({
          orden:        r.orden,
          nombre:       r.nombre,
          descripcion:  r.descripcion ?? '',
          completado:   r.completado ?? false,
          fotoUrl:      r.foto_url ?? null,
          fotoPublicId: r.foto_public_id ?? null,
          subiendoFoto: false,
          quitandoFoto: false,
        }));
        this.cargando = false;
      },
      error: () => { this.cargando = false; this.error = true; },
    });
  }

  // ── Toggle completado (local) ────────────────────────────────────────────
  toggleCompletado(proc: ProcLocal): void {
    proc.completado = !proc.completado;
  }

  // ── Subir / reemplazar foto ───────────────────────────────────────────────
  onFotoSeleccionada(event: Event, proc: ProcLocal): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    (event.target as HTMLInputElement).value = '';
    if (!file) return;

    // Preview inmediato
    const reader = new FileReader();
    reader.onload = e => { proc.fotoUrl = e.target?.result as string; };
    reader.readAsDataURL(file);

    proc.subiendoFoto = true;
    const fd = new FormData();
    fd.append('archivo', file);

    this.svc.subirFotoInspeccion(this.inspeccionId, proc.orden, fd).subscribe({
      next: (res: any) => {
        proc.fotoUrl      = res.url;
        proc.fotoPublicId = res.public_id;
        proc.subiendoFoto = false;
      },
      error: (err: any) => {
        proc.subiendoFoto = false;
        proc.fotoUrl      = null;
        this.toast.mostrar(err?.error?.detail ?? 'Error al subir la foto.', 'error');
      },
    });
  }

  // ── Quitar foto ──────────────────────────────────────────────────────────
  quitarFoto(proc: ProcLocal): void {
    if (proc.quitandoFoto) return;
    const urlAnterior = proc.fotoUrl;
    proc.fotoUrl      = null;
    proc.fotoPublicId = null;

    if (urlAnterior?.startsWith('http')) {
      proc.quitandoFoto = true;
      this.svc.quitarFotoInspeccion(this.inspeccionId, proc.orden).subscribe({
        next: () => { proc.quitandoFoto = false; },
        error: () => {
          proc.fotoUrl      = urlAnterior;
          proc.quitandoFoto = false;
          this.toast.mostrar('No se pudo quitar la foto.', 'error');
        },
      });
    }
  }

  // ── Guardar progreso (sin finalizar) ─────────────────────────────────────
  guardar(): void {
    if (this.guardando) return;
    this.guardando = true;
    this.svc.guardarInspeccion(this.inspeccionId, {
      resultado:    this.procs.map(p => ({ orden: p.orden, completado: p.completado })),
      observaciones: this.observaciones.trim() || null,
    }).subscribe({
      next: (res: any) => {
        this.guardando = false;
        this.toast.mostrar('Progreso guardado correctamente.', 'success');
        if (res.todos_completados) this.mostrarFinalizar = true;
      },
      error: (err: any) => {
        this.guardando = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al guardar.', 'error');
      },
    });
  }

  // ── Finalizar inspección ─────────────────────────────────────────────────
  intentarFinalizar(): void {
    if (this.finalizando) return;
    if (!this.todosCompletados) {
      this.showAlertaFinalizar = true;
      return;
    }
    this.finalizar();
  }

  cancelarFinalizar(): void { this.showAlertaFinalizar = false; }

  finalizar(): void {
    this.showAlertaFinalizar = false;
    if (this.finalizando) return;
    this.finalizando = true;
    this.svc.finalizarInspeccion(this.inspeccionId, {
      resultado:    this.procs.map(p => ({ orden: p.orden, completado: p.completado })),
      observaciones: this.observaciones.trim() || null,
      proxima_fecha_mantenimiento: this.proximaFecha || null,
    }).subscribe({
      next: (res: any) => {
        this.finalizando = false;
        if (this.equipo) this.equipo.estadoIntervencion = 'completado';
        this.toast.mostrar('¡Inspección finalizada y guardada en historial!', 'success');
      },
      error: (err: any) => {
        this.finalizando = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al finalizar.', 'error');
      },
    });
  }

  // ── Computed ─────────────────────────────────────────────────────────────
  get completados(): number      { return this.procs.filter(p => p.completado).length; }
  get total(): number            { return this.procs.length; }
  get progreso(): number         { return this.total ? Math.round((this.completados / this.total) * 100) : 0; }
  get todosCompletados(): boolean { return this.total > 0 && this.completados === this.total; }
  get estaFinalizado(): boolean  { return this.equipo?.estadoIntervencion === 'completado'; }
  get hayAlgoSubiendo(): boolean { return this.procs.some(p => p.subiendoFoto); }

  volver(): void { this.location.back(); }
}

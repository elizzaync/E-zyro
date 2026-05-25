import {
  Component, Input, Output, EventEmitter,
  OnInit, OnDestroy, inject, HostListener
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

export interface ClienteBasico {
  id: string;
  razon_social: string;
  ruc: string | null;
}

@Component({
  selector: 'app-crear-proyecto-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, SpinnerComponent],
  templateUrl: './crear-proyecto-modal.component.html',
  styleUrls: ['./crear-proyecto-modal.component.css']
})
export class CrearProyectoModalComponent implements OnInit, OnDestroy {
  @Input() mode: 'crear' | 'editar' = 'crear';
  @Input() proyectoId: string | null = null; // para editar
  @Output() closed = new EventEmitter<{ guardado: boolean; proyectoId?: string }>();

  private fb      = inject(FormBuilder);
  private svc     = inject(OperacionesService);
  private destroy$ = new Subject<void>();

  // Data
  clientes: ClienteBasico[] = [];
  cargandoClientes = false;

  // UI
  guardando  = false;
  errorMsg   = '';
  seccion: 1 | 2 = 1;

  form!: FormGroup;

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this._initForm();
    this._cargarClientes();
    if (this.mode === 'editar' && this.proyectoId) {
      this._precargarProyecto();
    }
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
    document.body.style.overflow = '';
  }

  @HostListener('document:keydown.escape') onEsc() { this.cerrar(); }

  private _initForm(): void {
    this.form = this.fb.group({
      nombre_proyecto:    ['', [Validators.required, Validators.maxLength(200)]],
      cliente_id:         ['', Validators.required],
      orden_trabajo:      ['', [Validators.required, Validators.maxLength(50)]],
      estado:             ['Pendiente', Validators.required],
      fecha_inicio:       [''],
      fecha_fin_estimada: [''],
      zona_ejecucion:     ['', Validators.maxLength(255)],
      alcance:            ['', Validators.maxLength(2000)],
    });
  }

  private _cargarClientes(): void {
    this.cargandoClientes = true;
    this.svc.getClientes().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this.clientes = (Array.isArray(res) ? res : res.clientes ?? []).map((c: any) => ({
          id: c.id,
          razon_social: c.razon_social,
          ruc: c.ruc ?? null
        }));
        this.cargandoClientes = false;
      },
      error: () => { this.cargandoClientes = false; }
    });
  }

  private _precargarProyecto(): void {
    this.svc.getDetalleProyecto(this.proyectoId!).pipe(takeUntil(this.destroy$)).subscribe({
      next: (raw: any) => {
        this.form.patchValue({
          nombre_proyecto:    raw.nombre_proyecto ?? '',
          cliente_id:         raw.cliente_id ?? '',
          orden_trabajo:      raw.orden_trabajo ?? '',
          estado:             raw.estado ?? 'Pendiente',
          fecha_inicio:       raw.fecha_inicio?.split('T')[0] ?? '',
          fecha_fin_estimada: raw.fecha_fin_estimada?.split('T')[0] ?? '',
          zona_ejecucion:     raw.detalle?.zona_ejecucion ?? '',
          alcance:            raw.detalle?.alcance ?? '',
        });
      }
    });
  }

  irSeccion(n: 1 | 2): void { this.seccion = n; this.errorMsg = ''; }
  siguiente(): void { this.seccion = 2; this.errorMsg = ''; }
  anterior():  void { this.seccion = 1; }

  guardar(): void {
    this.errorMsg = '';
    this.form.markAllAsTouched();
    if (this.form.invalid) {
      this.errorMsg = 'Completa todos los campos requeridos.';
      this.seccion = 1;
      return;
    }

    const v = this.form.value;
    const payload = {
      nombre_proyecto:    v.nombre_proyecto,
      cliente_id:         v.cliente_id,
      orden_trabajo:      v.orden_trabajo,
      estado:             v.estado,
      fecha_inicio:       v.fecha_inicio || null,
      fecha_fin_estimada: v.fecha_fin_estimada || null,
      zona_ejecucion:     v.zona_ejecucion || null,
      alcance:            v.alcance || null,
    };

    this.guardando = true;
    const obs = this.mode === 'editar' && this.proyectoId
      ? this.svc.actualizarProyecto(this.proyectoId, payload)
      : this.svc.crearProyecto(payload);

    obs.pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this.guardando = false;
        this.closed.emit({ guardado: true, proyectoId: res?.id ?? this.proyectoId ?? undefined });
      },
      error: (err: any) => {
        this.guardando = false;
        this.errorMsg = err?.error?.detail ?? 'Error al guardar. Verifica los datos.';
      }
    });
  }

  cerrar(): void { this.closed.emit({ guardado: false }); }

  ctrl(name: string) { return this.form.get(name); }

  estados = ['Pendiente', 'En_Proceso', 'En_Pausa', 'Completado', 'Cancelado'];
  estadoLabel(e: string): string {
    const m: Record<string, string> = { 'En_Proceso': 'En Proceso', 'En_Pausa': 'En Pausa' };
    return m[e] ?? e;
  }

  get seccion1Completa(): boolean {
    const c = this.form;
    return !!(c.get('nombre_proyecto')?.valid && c.get('cliente_id')?.valid && c.get('orden_trabajo')?.valid);
  }
}

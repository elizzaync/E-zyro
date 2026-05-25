import {
  Component, Input, Output, EventEmitter,
  OnInit, OnDestroy, inject, HostListener
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

export interface CatalogoServicio {
  id: string;
  nombre: string;
  tipo_trabajo: string;
  descripcion: string | null;
}

@Component({
  selector: 'app-crear-servicio-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, SpinnerComponent],
  templateUrl: './crear-servicio-modal.component.html',
  styleUrls: ['./crear-servicio-modal.component.css']
})
export class CrearServicioModalComponent implements OnInit, OnDestroy {
  @Input() proyectoId!: string;
  @Input() mode: 'crear' | 'editar' = 'crear';
  @Input() servicioId: string | null = null; // para editar
  @Output() closed = new EventEmitter<{ guardado: boolean }>();

  private fb      = inject(FormBuilder);
  private svc     = inject(OperacionesService);
  private destroy$ = new Subject<void>();

  catalogo: CatalogoServicio[] = [];
  cargandoCatalogo = false;

  guardando = false;
  errorMsg  = '';

  form!: FormGroup;

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this._initForm();
    this._cargarCatalogo();
    if (this.mode === 'editar' && this.servicioId) {
      this._precargarServicio();
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
      nombre:               ['', [Validators.required, Validators.maxLength(200)]],
      catalogo_servicio_id: ['', Validators.required],
      descripcion:          ['', Validators.maxLength(1000)],
      estado:               ['Pendiente'],
      fecha_programada:     [''],
      fecha_inicio:         [''],
      fecha_fin:            [''],
    });
  }

  private _cargarCatalogo(): void {
    this.cargandoCatalogo = true;
    this.svc.getCatalogoServicios().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this.catalogo = (Array.isArray(res) ? res : res.catalogo ?? []).map((c: any) => ({
          id:           c.id,
          nombre:       c.nombre,
          tipo_trabajo: c.tipo_trabajo,
          descripcion:  c.descripcion ?? null
        }));
        this.cargandoCatalogo = false;
      },
      error: () => { this.cargandoCatalogo = false; }
    });
  }

  private _precargarServicio(): void {
    this.svc.getDetalleServicio(this.servicioId!).pipe(takeUntil(this.destroy$)).subscribe({
      next: (raw: any) => {
        this.form.patchValue({
          nombre:               raw.tipo_servicio ?? raw.nombre ?? '',
          catalogo_servicio_id: raw.catalogo_servicio_id ?? '',
          descripcion:          raw.descripcion ?? '',
          estado:               raw.estado ?? 'Pendiente',
          fecha_programada:     raw.fecha_programada?.split('T')[0] ?? '',
          fecha_inicio:         raw.fecha_inicio?.split('T')[0] ?? '',
          fecha_fin:            raw.fecha_fin?.split('T')[0] ?? '',
        });
      }
    });
  }

  guardar(): void {
    this.errorMsg = '';
    this.form.markAllAsTouched();
    if (this.form.invalid) {
      this.errorMsg = 'Completa los campos requeridos (Nombre y Tipo de Servicio).';
      return;
    }

    // Validar rango de fechas
    const v = this.form.value;
    if (v.fecha_inicio && v.fecha_fin && v.fecha_fin < v.fecha_inicio) {
      this.errorMsg = 'La fecha de fin no puede ser anterior a la de inicio.';
      return;
    }

    this.guardando = true;
    const payload = {
      nombre:               v.nombre,
      catalogo_servicio_id: v.catalogo_servicio_id,
      descripcion:          v.descripcion || null,
      estado:               v.estado,
      fecha_programada:     v.fecha_programada || null,
      fecha_inicio:         v.fecha_inicio     || null,
      fecha_fin:            v.fecha_fin        || null,
    };

    const obs = this.mode === 'editar' && this.servicioId
      ? this.svc.actualizarServicio(this.servicioId, payload)
      : this.svc.crearServicio(this.proyectoId, payload);

    obs.pipe(takeUntil(this.destroy$)).subscribe({
      next: () => {
        this.guardando = false;
        this.closed.emit({ guardado: true });
      },
      error: (err: any) => {
        this.guardando = false;
        this.errorMsg = err?.error?.detail ?? 'Error al guardar el servicio.';
      }
    });
  }

  cerrar(): void { this.closed.emit({ guardado: false }); }

  ctrl(name: string) { return this.form.get(name); }

  getCatalogoSeleccionado(): CatalogoServicio | null {
    const id = this.form.get('catalogo_servicio_id')?.value;
    return id ? (this.catalogo.find(c => c.id === id) ?? null) : null;
  }

  getCatalogoLabel(id: string): string {
    return this.catalogo.find(c => c.id === id)?.nombre ?? id;
  }

  estados = ['Pendiente', 'En_Proceso', 'Completado', 'Cancelado'];
  estadoLabel(e: string): string {
    const m: Record<string, string> = { 'En_Proceso': 'En Proceso' };
    return m[e] ?? e;
  }
}

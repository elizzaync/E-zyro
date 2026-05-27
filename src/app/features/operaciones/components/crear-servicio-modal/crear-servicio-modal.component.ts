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

export interface PersonaServicio {
  id: string;          // empleado.id
  nombre: string;
  apellido: string;
  cargo: string | null;
  foto_url: string | null;
}

export type TipoDocumentoCliente = 'OC' | 'PROF' | 'SIN_OC';

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
  @Input() servicioId: string | null = null;
  @Output() closed = new EventEmitter<{ guardado: boolean }>();

  private fb       = inject(FormBuilder);
  private svc      = inject(OperacionesService);
  private destroy$ = new Subject<void>();

  catalogo: CatalogoServicio[]      = [];
  lideres: PersonaServicio[]        = [];
  responsables: PersonaServicio[]   = [];
  cargandoCatalogo     = false;
  cargandoLideres      = false;
  cargandoResponsables = false;

  guardando = false;
  errorMsg  = '';

  form!: FormGroup;

  // ── Catálogos UI ───────────────────────────────────────────────────
  tiposDocumento: { value: TipoDocumentoCliente; label: string }[] = [
    { value: 'OC',     label: 'Orden de Compra (OC)' },
    { value: 'PROF',   label: 'Proforma' },
    { value: 'SIN_OC', label: 'Sin OC' },
  ];

  estados = ['Pendiente', 'En_Proceso', 'Completado', 'Cancelado'];

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this._initForm();
    this._cargarCatalogo();
    this._cargarLideres();
    this._cargarResponsables();
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

  // ─────────────────────────────────────────────────────────────────────
  private _initForm(): void {
    this.form = this.fb.group({
      nombre:                 ['', [Validators.required, Validators.maxLength(200)]],
      catalogo_servicio_id:   ['', Validators.required],
      descripcion:            ['', Validators.maxLength(1000)],

      // Liderazgo
      lider_id:               [''],   // Líder del Servicio (opcional: si se omite, el jefe que configura queda como líder)
      responsable_id:         [''],   // Técnico Líder (opcional)
      zona_ejecucion:         ['', Validators.maxLength(255)],
      alcance:                ['', Validators.maxLength(4000)],
      tipo_documento_cliente: ['SIN_OC' as TipoDocumentoCliente],
      nro_documento:          ['', Validators.maxLength(100)],

      estado:                 ['Pendiente'],
      fecha_programada:       [''],
      fecha_inicio:           [''],
      fecha_fin:              [''],
    });

    // Si el tipo de documento es "SIN_OC" limpiamos el nro
    this.form.get('tipo_documento_cliente')!.valueChanges
      .pipe(takeUntil(this.destroy$))
      .subscribe((tipo: TipoDocumentoCliente) => {
        const nroCtrl = this.form.get('nro_documento')!;
        if (tipo === 'SIN_OC') {
          nroCtrl.setValue('');
          nroCtrl.disable({ emitEvent: false });
        } else {
          nroCtrl.enable({ emitEvent: false });
        }
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

  private _mapPersona = (u: any): PersonaServicio => ({
    id:       u.id ?? u.usuario_id,
    nombre:   u.nombre   ?? '',
    apellido: u.apellido ?? '',
    cargo:    u.cargo    ?? null,
    foto_url: u.foto_url ?? null,
  });

  private _cargarLideres(): void {
    this.cargandoLideres = true;
    this.svc.getLideresServicio().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        const list = Array.isArray(res) ? res : (res?.lideres ?? []);
        this.lideres = list.map(this._mapPersona);
        this.cargandoLideres = false;
      },
      error: () => { this.cargandoLideres = false; }
    });
  }

  private _cargarResponsables(): void {
    this.cargandoResponsables = true;
    this.svc.getResponsablesServicio().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        const list = Array.isArray(res) ? res : (res?.responsables ?? []);
        this.responsables = list.map(this._mapPersona);
        this.cargandoResponsables = false;
      },
      error: () => { this.cargandoResponsables = false; }
    });
  }

  private _precargarServicio(): void {
    this.svc.getDetalleServicio(this.servicioId!).pipe(takeUntil(this.destroy$)).subscribe({
      next: (raw: any) => {
        const tipo = (raw.tipo_documento_cliente ?? 'SIN_OC') as TipoDocumentoCliente;
        this.form.patchValue({
          nombre:                 raw.tipo_servicio ?? raw.nombre ?? '',
          catalogo_servicio_id:   raw.catalogo_servicio_id ?? '',
          descripcion:            raw.descripcion ?? '',

          lider_id:               raw.lider_id ?? '',
          responsable_id:         raw.responsable_id ?? '',
          zona_ejecucion:         raw.zona_ejecucion ?? '',
          alcance:                raw.alcance ?? '',
          tipo_documento_cliente: tipo,
          nro_documento:          raw.nro_documento ?? '',

          estado:                 raw.estado ?? 'Pendiente',
          fecha_programada:       raw.fecha_programada?.split('T')[0] ?? '',
          fecha_inicio:           raw.fecha_inicio?.split('T')[0]     ?? '',
          fecha_fin:              raw.fecha_fin?.split('T')[0]        ?? '',
        });
        if (tipo === 'SIN_OC') this.form.get('nro_documento')?.disable({ emitEvent: false });
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  guardar(): void {
    this.errorMsg = '';
    this.form.markAllAsTouched();
    if (this.form.invalid) {
      this.errorMsg = 'Completa los campos requeridos (Nombre y Tipo de Servicio).';
      return;
    }

    const v = this.form.getRawValue();
    if (v.fecha_inicio && v.fecha_fin && v.fecha_fin < v.fecha_inicio) {
      this.errorMsg = 'La fecha de fin no puede ser anterior a la de inicio.';
      return;
    }
    if (v.tipo_documento_cliente !== 'SIN_OC' && !String(v.nro_documento ?? '').trim()) {
      this.errorMsg = 'Indica el N° de documento para la OC/Proforma seleccionada.';
      return;
    }

    this.guardando = true;
    const payload = {
      nombre:                 v.nombre,
      catalogo_servicio_id:   v.catalogo_servicio_id,
      descripcion:            v.descripcion || null,

      lider_id:               v.lider_id || null,
      responsable_id:         v.responsable_id || null,
      zona_ejecucion:         v.zona_ejecucion || null,
      alcance:                v.alcance || null,
      tipo_documento_cliente: v.tipo_documento_cliente,
      nro_documento:          v.tipo_documento_cliente === 'SIN_OC' ? null : (v.nro_documento || null),

      estado:                 v.estado,
      fecha_programada:       v.fecha_programada || null,
      fecha_inicio:           v.fecha_inicio     || null,
      fecha_fin:              v.fecha_fin        || null,
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

  // ─────────────────────────────────────────────────────────────────────
  getCatalogoSeleccionado(): CatalogoServicio | null {
    const id = this.form.get('catalogo_servicio_id')?.value;
    return id ? (this.catalogo.find(c => c.id === id) ?? null) : null;
  }

  getCatalogoLabel(id: string): string {
    return this.catalogo.find(c => c.id === id)?.nombre ?? id;
  }

  estadoLabel(e: string): string {
    const m: Record<string, string> = { 'En_Proceso': 'En Proceso' };
    return m[e] ?? e;
  }

  get nroDocumentoRequerido(): boolean {
    return this.form.get('tipo_documento_cliente')?.value !== 'SIN_OC';
  }
}

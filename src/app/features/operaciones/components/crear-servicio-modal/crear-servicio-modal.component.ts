import {
  Component, Input, Output, EventEmitter,
  OnInit, OnDestroy, inject, HostListener, ElementRef
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { FormsModule } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { AuthService } from '../../../../core/services/auth.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { JustificacionModalComponent } from '../../../../shared/components/justificacion-modal/justificacion-modal.component';

export interface CatalogoServicio {
  id: string;
  nombre: string;
  tipo_trabajo: string;
  descripcion: string | null;
}

export interface PersonaServicio {
  id: string;
  nombre: string;
  apellido: string;
  cargo: string | null;
  foto_url: string | null;
}

export type TipoDocumentoCliente = 'OC' | 'PROF' | 'SIN_OC';

interface GeoItem { id: string; nombre: string; }

@Component({
  selector: 'app-crear-servicio-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule, SpinnerComponent, JustificacionModalComponent],
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
  private auth     = inject(AuthService);
  private elRef    = inject(ElementRef);
  private destroy$ = new Subject<void>();

  get isJefeOperaciones(): boolean {
    return (this.auth.getUsuario()?.rol || '').trim() === 'Jefe de Operaciones';
  }

  showJustModal    = false;
  _pendingPayload: object | null = null;

  catalogo: CatalogoServicio[]    = [];
  lideres: PersonaServicio[]      = [];
  responsables: PersonaServicio[] = [];
  cargandoCatalogo     = false;
  cargandoLideres      = false;
  cargandoResponsables = false;

  // ── Catálogos geográficos ──────────────────────────────────────────
  ubicaciones: GeoItem[] = [];
  zonas: GeoItem[]       = [];
  cargandoUbicaciones    = false;
  cargandoZonas          = false;

  // Dropdown state
  showUbicDrop  = false;
  showZonaDrop  = false;
  ubicSearch    = '';
  zonaSearch    = '';

  // Inline "agregar nueva"
  addingUbic    = false;
  nuevaUbicNom  = '';
  guardandoUbic = false;
  addingZona    = false;
  nuevaZonaNom  = '';
  guardandoZona = false;

  // Seleccionados (label a mostrar)
  ubicSelLabel = '';
  zonaSelLabel = '';

  guardando = false;
  errorMsg  = '';

  form!: FormGroup;

  tiposDocumento: { value: TipoDocumentoCliente; label: string }[] = [
    { value: 'OC',     label: 'Orden de Compra (OC)' },
    { value: 'PROF',   label: 'Proforma' },
    { value: 'SIN_OC', label: 'Sin OC' },
  ];
  estados = ['Pendiente', 'En_Proceso', 'Completado', 'Cancelado'];

  // ── Init ──────────────────────────────────────────────────────────
  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this._initForm();
    this._cargarCatalogo();
    this._cargarLideres();
    this._cargarResponsables();
    this._cargarUbicaciones();
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

  @HostListener('document:click', ['$event'])
  onDocClick(e: MouseEvent): void {
    if (!this.elRef.nativeElement.contains(e.target)) return;
    const t = e.target as HTMLElement;
    if (!t.closest('.geo-dropdown')) {
      this.showUbicDrop = false;
      this.showZonaDrop = false;
    }
  }

  // ── Form ──────────────────────────────────────────────────────────
  private _initForm(): void {
    this.form = this.fb.group({
      nombre:                 ['', [Validators.required, Validators.maxLength(200)]],
      catalogo_servicio_id:   ['', Validators.required],
      descripcion:            ['', Validators.maxLength(1000)],
      lider_id:               [''],
      responsable_id:         [''],
      ubicacion_id:           [''],
      zona_id:                [''],
      alcance:                ['', Validators.maxLength(4000)],
      tipo_documento_cliente: ['SIN_OC' as TipoDocumentoCliente],
      nro_documento:          ['', Validators.maxLength(100)],
      estado:                 ['Pendiente'],
      fecha_programada:           [''],
      fecha_inicio:               [''],
      fecha_fin:                  [''],
      tiene_equipos_intervenidos: [false],
    });

    this.form.get('tipo_documento_cliente')!.valueChanges
      .pipe(takeUntil(this.destroy$))
      .subscribe((tipo: TipoDocumentoCliente) => {
        const ctrl = this.form.get('nro_documento')!;
        if (tipo === 'SIN_OC') { ctrl.setValue(''); ctrl.disable({ emitEvent: false }); }
        else { ctrl.enable({ emitEvent: false }); }
      });
  }

  // ── Loaders ───────────────────────────────────────────────────────
  private _cargarCatalogo(): void {
    this.cargandoCatalogo = true;
    this.svc.getCatalogoServicios().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this.catalogo = (Array.isArray(res) ? res : res.catalogo ?? []).map((c: any) => ({
          id: c.id, nombre: c.nombre, tipo_trabajo: c.tipo_trabajo, descripcion: c.descripcion ?? null
        }));
        this.cargandoCatalogo = false;
      },
      error: () => { this.cargandoCatalogo = false; }
    });
  }

  private _mapPersona = (u: any): PersonaServicio => ({
    id: u.id ?? u.usuario_id, nombre: u.nombre ?? '', apellido: u.apellido ?? '',
    cargo: u.cargo ?? null, foto_url: u.foto_url ?? null,
  });

  private _cargarLideres(): void {
    this.cargandoLideres = true;
    this.svc.getLideresServicio().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this.lideres = (Array.isArray(res) ? res : (res?.lideres ?? [])).map(this._mapPersona);
        this.cargandoLideres = false;
      },
      error: () => { this.cargandoLideres = false; }
    });
  }

  private _cargarResponsables(): void {
    this.cargandoResponsables = true;
    this.svc.getResponsablesServicio().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this.responsables = (Array.isArray(res) ? res : (res?.responsables ?? [])).map(this._mapPersona);
        this.cargandoResponsables = false;
      },
      error: () => { this.cargandoResponsables = false; }
    });
  }

  private _cargarUbicaciones(): void {
    this.cargandoUbicaciones = true;
    this.svc.getUbicaciones().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res) => { this.ubicaciones = res; this.cargandoUbicaciones = false; },
      error: () => { this.cargandoUbicaciones = false; }
    });
  }

  private _cargarZonas(ubicacionId: string): void {
    this.cargandoZonas = true;
    this.svc.getZonas(ubicacionId).pipe(takeUntil(this.destroy$)).subscribe({
      next: (res) => { this.zonas = res; this.cargandoZonas = false; },
      error: () => { this.cargandoZonas = false; }
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
          ubicacion_id:           raw.ubicacion_id ?? '',
          zona_id:                raw.zona_id ?? '',
          alcance:                raw.alcance ?? '',
          tipo_documento_cliente: tipo,
          nro_documento:          raw.nro_documento ?? '',
          estado:                 raw.estado ?? 'Pendiente',
          fecha_programada:           raw.fecha_programada?.split('T')[0] ?? '',
          fecha_inicio:               raw.fecha_inicio?.split('T')[0]     ?? '',
          fecha_fin:                  raw.fecha_fin?.split('T')[0]        ?? '',
          tiene_equipos_intervenidos: raw.es_mantenimiento ?? false,
        });
        if (tipo === 'SIN_OC') this.form.get('nro_documento')?.disable({ emitEvent: false });

        if (raw.ubicacion_id) {
          // Usa el nombre que viene del backend (no depende de que la lista async ya cargó).
          // Fallback: buscar en la lista si el backend no lo envió.
          this.ubicSelLabel = raw.ubicacion_nombre
            ?? this.ubicaciones.find(u => u.id === raw.ubicacion_id)?.nombre
            ?? '';
          this.zonaSelLabel = raw.zona_nombre ?? '';
          this._cargarZonas(raw.ubicacion_id);
          if (raw.zona_id && !this.zonaSelLabel) {
            this.svc.getZonas(raw.ubicacion_id).pipe(takeUntil(this.destroy$)).subscribe(zs => {
              this.zonaSelLabel = zs.find(x => x.id === raw.zona_id)?.nombre ?? '';
            });
          }
        }
      }
    });
  }

  // ── Geo Dropdown logic ────────────────────────────────────────────

  get ubicFiltradas(): GeoItem[] {
    const q = this.ubicSearch.toLowerCase().trim();
    return q ? this.ubicaciones.filter(u => u.nombre.toLowerCase().includes(q)) : this.ubicaciones;
  }

  get zonasFiltradas(): GeoItem[] {
    const q = this.zonaSearch.toLowerCase().trim();
    return q ? this.zonas.filter(z => z.nombre.toLowerCase().includes(q)) : this.zonas;
  }

  toggleUbicDrop(): void {
    this.showUbicDrop = !this.showUbicDrop;
    if (this.showUbicDrop) { this.showZonaDrop = false; this.ubicSearch = ''; this.addingUbic = false; }
  }

  toggleZonaDrop(): void {
    if (!this.form.get('ubicacion_id')?.value) return;
    this.showZonaDrop = !this.showZonaDrop;
    if (this.showZonaDrop) { this.showUbicDrop = false; this.zonaSearch = ''; this.addingZona = false; }
  }

  seleccionarUbicacion(u: GeoItem): void {
    this.form.patchValue({ ubicacion_id: u.id, zona_id: '' });
    this.ubicSelLabel = u.nombre;
    this.zonaSelLabel = '';
    this.zonas = [];
    this.showUbicDrop = false;
    this.addingUbic = false;
    this._cargarZonas(u.id);
  }

  limpiarUbicacion(): void {
    this.form.patchValue({ ubicacion_id: '', zona_id: '' });
    this.ubicSelLabel = '';
    this.zonaSelLabel = '';
    this.zonas = [];
  }

  seleccionarZona(z: GeoItem): void {
    this.form.patchValue({ zona_id: z.id });
    this.zonaSelLabel = z.nombre;
    this.showZonaDrop = false;
    this.addingZona = false;
  }

  limpiarZona(): void {
    this.form.patchValue({ zona_id: '' });
    this.zonaSelLabel = '';
  }

  // ── Crear nueva ubicacion ─────────────────────────────────────────

  iniciarNuevaUbic(): void { this.addingUbic = true; this.nuevaUbicNom = ''; }
  cancelarNuevaUbic(): void { this.addingUbic = false; this.nuevaUbicNom = ''; }

  guardarNuevaUbic(): void {
    const nom = this.nuevaUbicNom.trim();
    if (!nom) return;
    this.guardandoUbic = true;
    this.svc.crearUbicacion(nom).pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        const nuevo: GeoItem = { id: res.id, nombre: res.nombre };
        this.ubicaciones = [...this.ubicaciones, nuevo].sort((a, b) => a.nombre.localeCompare(b.nombre));
        this.guardandoUbic = false;
        this.addingUbic = false;
        this.seleccionarUbicacion(nuevo);
      },
      error: () => { this.guardandoUbic = false; }
    });
  }

  // ── Crear nueva zona ──────────────────────────────────────────────

  iniciarNuevaZona(): void { this.addingZona = true; this.nuevaZonaNom = ''; }
  cancelarNuevaZona(): void { this.addingZona = false; this.nuevaZonaNom = ''; }

  guardarNuevaZona(): void {
    const nom = this.nuevaZonaNom.trim();
    const ubicId = this.form.get('ubicacion_id')?.value;
    if (!nom || !ubicId) return;
    this.guardandoZona = true;
    this.svc.crearZona(nom, ubicId).pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        const nuevo: GeoItem = { id: res.id, nombre: res.nombre };
        this.zonas = [...this.zonas, nuevo].sort((a, b) => a.nombre.localeCompare(b.nombre));
        this.guardandoZona = false;
        this.addingZona = false;
        this.seleccionarZona(nuevo);
      },
      error: () => { this.guardandoZona = false; }
    });
  }

  // ── Computed ──────────────────────────────────────────────────────

  get esMantenimiento(): boolean {
    const cat = this.getCatalogoSeleccionado();
    return (cat?.tipo_trabajo ?? '').toLowerCase() === 'mantenimiento';
  }

  getCatalogoSeleccionado(): CatalogoServicio | null {
    const id = this.form.get('catalogo_servicio_id')?.value;
    return id ? (this.catalogo.find(c => c.id === id) ?? null) : null;
  }

  // ── Guardar ───────────────────────────────────────────────────────
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

    const payload = {
      nombre:                 v.nombre,
      catalogo_servicio_id:   v.catalogo_servicio_id,
      descripcion:            v.descripcion || null,
      lider_id:               v.lider_id ?? '',
      responsable_id:         v.responsable_id ?? '',
      ubicacion_id:           v.ubicacion_id || null,
      zona_id:                v.zona_id || null,
      alcance:                v.alcance || null,
      tipo_documento_cliente:     v.tipo_documento_cliente,
      nro_documento:              v.tipo_documento_cliente === 'SIN_OC' ? null : (v.nro_documento || null),
      estado:                     v.estado,
      fecha_programada:           v.fecha_programada || null,
      fecha_inicio:               v.fecha_inicio     || null,
      fecha_fin:                  v.fecha_fin        || null,
      tiene_equipos_intervenidos: !!v.tiene_equipos_intervenidos,
    };

    if (this.mode === 'editar' && this.isJefeOperaciones) {
      this._pendingPayload = payload;
      this.showJustModal = true;
      return;
    }

    this.guardando = true;
    this._ejecutarGuardar(payload);
  }

  private _ejecutarGuardar(payload: object, justificacion?: string): void {
    const obs = this.mode === 'editar' && this.servicioId
      ? this.svc.actualizarServicio(this.servicioId, payload, justificacion)
      : this.svc.crearServicio(this.proyectoId, payload);

    obs.pipe(takeUntil(this.destroy$)).subscribe({
      next: () => { this.guardando = false; this.closed.emit({ guardado: true }); },
      error: (err: any) => {
        this.guardando = false;
        this.errorMsg = err?.error?.detail ?? 'Error al guardar el servicio.';
      }
    });
  }

  onJustConfirmado(justificacion: string): void {
    this.showJustModal = false;
    if (this._pendingPayload) {
      this.guardando = true;
      this._ejecutarGuardar(this._pendingPayload, justificacion);
      this._pendingPayload = null;
    }
  }

  onJustCancelado(): void {
    this.showJustModal = false;
    this._pendingPayload = null;
  }

  cerrar(): void { this.closed.emit({ guardado: false }); }
  ctrl(name: string) { return this.form.get(name); }

  estadoLabel(e: string): string {
    const m: Record<string, string> = { 'En_Proceso': 'En Proceso' };
    return m[e] ?? e;
  }

  get nroDocumentoRequerido(): boolean {
    return this.form.get('tipo_documento_cliente')?.value !== 'SIN_OC';
  }
}

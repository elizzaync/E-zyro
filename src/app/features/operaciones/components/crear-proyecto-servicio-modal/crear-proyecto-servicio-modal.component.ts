import {
  Component, Output, EventEmitter,
  OnInit, OnDestroy, inject, HostListener
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Subject, switchMap, takeUntil } from 'rxjs';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

interface ClienteBasico { id: string; razon_social: string; ruc: string | null; }
interface CatalogoSvc   { id: string; nombre: string; tipo_trabajo: string; }
interface PersonaSvc    { id: string; nombre: string; apellido: string; cargo: string | null; }
interface GeoItem       { id: string; nombre: string; }

@Component({
  selector: 'app-crear-proyecto-servicio-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule, SpinnerComponent],
  templateUrl: './crear-proyecto-servicio-modal.component.html',
  styleUrls: ['./crear-proyecto-servicio-modal.component.css'],
})
export class CrearProyectoServicioModalComponent implements OnInit, OnDestroy {
  @Output() closed = new EventEmitter<{ guardado: boolean; proyectoId?: string; servicioId?: string }>();

  private fb       = inject(FormBuilder);
  private svc      = inject(OperacionesService);
  private destroy$ = new Subject<void>();

  paso: 1 | 2 = 1;
  guardando   = false;
  errorMsg    = '';

  // ── Datos cargados ────────────────────────────────────────────────
  clientes:     ClienteBasico[] = [];
  catalogo:     CatalogoSvc[]   = [];
  lideres:      PersonaSvc[]    = [];
  ubicaciones:  GeoItem[]       = [];
  zonas:        GeoItem[]       = [];
  cargandoClientes    = false;
  cargandoCatalogo    = false;
  cargandoLideres     = false;
  cargandoUbicaciones = false;
  cargandoZonas       = false;

  // ── Geo pickers ──────────────────────────────────────────────────
  ubicSelLabel = '';
  zonaSelLabel = '';
  showUbicDrop = false;
  showZonaDrop = false;
  ubicSearch   = '';
  zonaSearch   = '';

  estadosProyecto = ['Pendiente', 'En_Proceso', 'En_Pausa', 'Completado', 'Cancelado'];
  tiposDoc = [
    { value: 'OC',     label: 'Orden de Compra' },
    { value: 'PROF',   label: 'Proforma' },
    { value: 'SIN_OC', label: 'Sin OC' },
  ];

  fProyecto!: FormGroup;
  fServicio!:  FormGroup;

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this._initForms();
    this._cargar();
    this.svc.getSiguienteOrdenTrabajo().pipe(takeUntil(this.destroy$)).subscribe({
      next: (r) => this.fProyecto.get('orden_trabajo')?.setValue(r?.orden_trabajo ?? ''),
    });
  }

  ngOnDestroy(): void {
    this.destroy$.next(); this.destroy$.complete();
    document.body.style.overflow = '';
  }

  @HostListener('document:keydown.escape') onEsc() { this.cerrar(); }

  private _initForms(): void {
    this.fProyecto = this.fb.group({
      nombre_proyecto:    ['', [Validators.required, Validators.maxLength(200)]],
      cliente_id:         ['', Validators.required],
      orden_trabajo:      [{ value: '', disabled: true }],
      estado:             ['Pendiente', Validators.required],
      fecha_inicio:       [''],
      fecha_fin_estimada: [''],
    });

    this.fServicio = this.fb.group({
      nombre:               ['', [Validators.required, Validators.maxLength(200)]],
      catalogo_servicio_id: ['', Validators.required],
      lider_id:             [''],
      ubicacion_id:         [''],
      zona_id:              [''],
      tipo_documento_cliente: ['SIN_OC'],
      nro_documento:        [{ value: '', disabled: true }],
      fecha_programada:     [''],
    });

    this.fServicio.get('tipo_documento_cliente')!.valueChanges
      .pipe(takeUntil(this.destroy$))
      .subscribe(tipo => {
        const ctrl = this.fServicio.get('nro_documento')!;
        tipo === 'SIN_OC' ? ctrl.disable({ emitEvent: false }) : ctrl.enable({ emitEvent: false });
      });
  }

  private _cargar(): void {
    this.cargandoClientes = true;
    this.svc.getClientes().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this.clientes = (Array.isArray(res) ? res : res.clientes ?? []).map((c: any) => ({
          id: c.id, razon_social: c.razon_social, ruc: c.ruc ?? null,
        }));
        this.cargandoClientes = false;
      },
      error: () => { this.cargandoClientes = false; }
    });

    this.cargandoCatalogo = true;
    this.svc.getCatalogoServicios().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this.catalogo = (Array.isArray(res) ? res : res.catalogo ?? []).map((c: any) => ({
          id: c.id, nombre: c.nombre, tipo_trabajo: c.tipo_trabajo,
        }));
        this.cargandoCatalogo = false;
      },
      error: () => { this.cargandoCatalogo = false; }
    });

    this.cargandoLideres = true;
    this.svc.getLideresServicio().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this.lideres = (Array.isArray(res) ? res : res.lideres ?? []).map((u: any) => ({
          id: u.id ?? u.usuario_id, nombre: u.nombre ?? '', apellido: u.apellido ?? '', cargo: u.cargo ?? null,
        }));
        this.cargandoLideres = false;
      },
      error: () => { this.cargandoLideres = false; }
    });

    this.cargandoUbicaciones = true;
    this.svc.getUbicaciones().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res) => { this.ubicaciones = res; this.cargandoUbicaciones = false; },
      error: () => { this.cargandoUbicaciones = false; }
    });

  }

  // ── Geo helpers ──────────────────────────────────────────────────
  get ubicFiltradas(): GeoItem[] {
    const q = this.ubicSearch.toLowerCase();
    return q ? this.ubicaciones.filter(u => u.nombre.toLowerCase().includes(q)) : this.ubicaciones;
  }
  get zonasFiltradas(): GeoItem[] {
    const q = this.zonaSearch.toLowerCase();
    return q ? this.zonas.filter(z => z.nombre.toLowerCase().includes(q)) : this.zonas;
  }

  toggleUbicDrop(): void { this.showUbicDrop = !this.showUbicDrop; this.showZonaDrop = false; this.ubicSearch = ''; }
  toggleZonaDrop(): void {
    if (!this.fServicio.get('ubicacion_id')?.value) return;
    this.showZonaDrop = !this.showZonaDrop; this.showUbicDrop = false; this.zonaSearch = '';
  }

  selUbic(u: GeoItem): void {
    this.fServicio.patchValue({ ubicacion_id: u.id, zona_id: '' });
    this.ubicSelLabel = u.nombre; this.zonaSelLabel = '';
    this.zonas = []; this.showUbicDrop = false;
    this.cargandoZonas = true;
    this.svc.getZonas(u.id).pipe(takeUntil(this.destroy$)).subscribe({
      next: (z) => { this.zonas = z; this.cargandoZonas = false; },
      error: () => { this.cargandoZonas = false; }
    });
  }
  limpiarUbic(): void { this.fServicio.patchValue({ ubicacion_id: '', zona_id: '' }); this.ubicSelLabel = ''; this.zonaSelLabel = ''; this.zonas = []; }

  selZona(z: GeoItem): void { this.fServicio.patchValue({ zona_id: z.id }); this.zonaSelLabel = z.nombre; this.showZonaDrop = false; }
  limpiarZona(): void { this.fServicio.patchValue({ zona_id: '' }); this.zonaSelLabel = ''; }

  // ── Wizard navigation (modo 'nuevo') ─────────────────────────────
  get paso1Valido(): boolean {
    return !!(this.fProyecto.get('nombre_proyecto')?.valid && this.fProyecto.get('cliente_id')?.valid);
  }

  siguiente(): void {
    this.fProyecto.markAllAsTouched();
    if (!this.paso1Valido) { this.errorMsg = 'Completa los campos requeridos.'; return; }
    this.errorMsg = '';
    this.paso = 2;
  }
  anterior(): void { this.paso = 1; this.errorMsg = ''; }

  // ── Guardar ──────────────────────────────────────────────────────
  guardar(): void {
    this.fServicio.markAllAsTouched();
    if (this.fServicio.invalid) { this.errorMsg = 'Completa los campos del servicio.'; return; }

    const vs = this.fServicio.getRawValue();
    const payloadServicio = {
      nombre:               vs.nombre,
      catalogo_servicio_id: vs.catalogo_servicio_id,
      lider_id:             vs.lider_id || null,
      ubicacion_id:         vs.ubicacion_id || null,
      zona_id:              vs.zona_id || null,
      tipo_documento_cliente: vs.tipo_documento_cliente,
      nro_documento:        vs.nro_documento || null,
      fecha_programada:     vs.fecha_programada || null,
      estado:               'Pendiente',
    };

    this.errorMsg = '';
    this.guardando = true;

    const vp = this.fProyecto.value;
    const payloadProyecto = {
      nombre_proyecto:    vp.nombre_proyecto,
      cliente_id:         vp.cliente_id,
      estado:             vp.estado,
      fecha_inicio:       vp.fecha_inicio || null,
      fecha_fin_estimada: vp.fecha_fin_estimada || null,
    };

    let _proyectoId = '';
    this.svc.crearProyecto(payloadProyecto).pipe(
      takeUntil(this.destroy$),
      switchMap((proyecto: any) => {
        _proyectoId = proyecto.id;
        return this.svc.crearServicio(proyecto.id, payloadServicio).pipe(takeUntil(this.destroy$));
      })
    ).subscribe({
      next: (servicio: any) => {
        this.guardando = false;
        this.closed.emit({ guardado: true, proyectoId: _proyectoId, servicioId: servicio?.id });
      },
      error: (err: any) => {
        this.guardando = false;
        this.errorMsg = err?.error?.detail ?? 'Error al guardar. Verifica los datos.';
      }
    });
  }

  estadoLabel(e: string): string {
    const m: Record<string, string> = { 'En_Proceso': 'En Proceso', 'En_Pausa': 'En Pausa' };
    return m[e] ?? e;
  }

  ctrl1(n: string) { return this.fProyecto.get(n); }
  ctrl2(n: string) { return this.fServicio.get(n); }

  cerrar(): void { this.closed.emit({ guardado: false }); }
}

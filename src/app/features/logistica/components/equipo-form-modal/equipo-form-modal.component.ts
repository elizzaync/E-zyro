import {
  Component, Input, Output, EventEmitter,
  OnInit, OnDestroy, inject, HostListener
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators, FormsModule } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import {
  EquipoHerramienta, ClaseArticulo,
  CLASES_ARTICULO, ESTADOS_EQUIPO, FRECUENCIAS_MANTENIMIENTO,
  CatalogoItem, AlmacenItem, ModeloItem,
} from '../../logistica.models';

@Component({
  selector: 'app-equipo-form-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule, SpinnerComponent],
  templateUrl: './equipo-form-modal.component.html',
  styleUrls: ['./equipo-form-modal.component.css']
})
export class EquipoFormModalComponent implements OnInit, OnDestroy {
  @Input() equipo: EquipoHerramienta | null = null;
  @Input() guardando = false;
  @Output() guardar = new EventEmitter<any>();
  @Output() cerrar  = new EventEmitter<void>();

  private fb  = inject(FormBuilder);
  private svc = inject(LogisticaService);
  private destroy$ = new Subject<void>();
  form!: FormGroup;

  // equipo_tecnologico no se crea desde esta sección; tiene su propio flujo
  clases  = CLASES_ARTICULO.filter(c => c.value !== 'equipo_tecnologico');
  estados = ESTADOS_EQUIPO;
  frecuencias  = FRECUENCIAS_MANTENIMIENTO.filter(f => f.value !== 'ninguno');

  // Catálogos
  categorias: CatalogoItem[] = [];
  marcas:     CatalogoItem[] = [];
  modelos:    ModeloItem[]   = [];   // filtrado por marca seleccionada
  almacenes:  AlmacenItem[]  = [];

  // Inputs "+ Nuevo"
  showAddCategoria = false; nuevaCategoria = ''; creandoCategoria = false;
  showAddMarca  = false; nuevaMarca  = ''; creandoMarca  = false;
  showAddModelo = false; nuevoModelo = ''; creandoModelo = false;
  showAddAlmacen = false; nuevoAlmacen = ''; creandoAlmacen = false;

  // Marca: combobox buscador
  marcaSearch   = '';
  showMarcaDrop = false;

  get marcasFiltradas(): CatalogoItem[] {
    const q = this.marcaSearch.toLowerCase().trim();
    return q ? this.marcas.filter(m => m.nombre.toLowerCase().includes(q)) : this.marcas;
  }
  get marcaNombre(): string {
    const id = this.form?.get('marcaId')?.value;
    return id ? (this.marcas.find(m => m.id === id)?.nombre ?? '') : '';
  }

  codigoPreview = '';

  get esEdicion(): boolean { return !!this.equipo; }
  get marcaSeleccionada(): string { return this.form?.get('marcaId')?.value || ''; }

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    const e = this.equipo;
    this.form = this.fb.group({
      nombre:      [e?.nombre ?? '', [Validators.required, Validators.maxLength(200)]],
      clase:       [e?.clase ?? 'equipo' as ClaseArticulo, Validators.required],
      categoriaId: [e?.categoriaId ?? ''],
      marcaId:     [e?.marcaId ?? ''],
      modeloId:    [e?.modeloId ?? ''],
      numeroSerie: [e?.numeroSerie ?? ''],
      almacenId:   [e?.almacenId ?? ''],
      cantidad:    [e?.cantidad ?? 1, [Validators.required, Validators.min(0)]],
      stockMinimo: [e?.stockMinimo ?? 0, [Validators.min(0)]],
      precioCompra:[e?.precioCompra ?? null],
      estado:      [e?.estado ?? 'operativo', Validators.required],
      observaciones:[e?.observaciones ?? ''],
      requiereMantenimiento:    [e?.requiereMantenimiento ?? false],
      frecuenciaMantenimiento:  [e?.frecuenciaMantenimiento && e.frecuenciaMantenimiento !== 'ninguno' ? e.frecuenciaMantenimiento : 'mensual'],
      proximaFechaMantenimiento:[e?.proximaFechaMantenimiento ?? null],
      fechaAdquisicion:         [e?.fechaAdquisicion ?? null],
      fichaTecnica:             [e?.fichaTecnica ?? ''],
    });

    // Reset mantenimiento al desactivar
    this.form.get('requiereMantenimiento')!.valueChanges
      .pipe(takeUntil(this.destroy$))
      .subscribe((req: boolean) => {
        if (!req) this.form.patchValue({ proximaFechaMantenimiento: null }, { emitEvent: false });
      });

    // Cuando cambia clase, regenerar preview de código
    this.form.get('clase')!.valueChanges.pipe(takeUntil(this.destroy$))
      .subscribe((c: ClaseArticulo) => {
        if (!this.esEdicion) {
          this.svc.getSiguienteCodigo(c).subscribe({ next: r => (this.codigoPreview = r.codigo) });
        }
      });

    // Cuando cambia marca, recargar modelos y limpiar selección
    this.form.get('marcaId')!.valueChanges.pipe(takeUntil(this.destroy$))
      .subscribe((marcaId: string) => {
        this._cargarModelos(marcaId);
        const modeloActual = this.form.get('modeloId')?.value;
        if (modeloActual && !this.modelos.find(m => m.id === modeloActual)) {
          this.form.patchValue({ modeloId: '' }, { emitEvent: false });
        }
      });

    this._cargarCatalogos();
    if (!this.esEdicion) {
      this.svc.getSiguienteCodigo(this.form.get('clase')!.value).subscribe({
        next: r => (this.codigoPreview = r.codigo),
      });
    }
  }

  ngOnDestroy(): void {
    this.destroy$.next(); this.destroy$.complete();
    document.body.style.overflow = '';
  }

  @HostListener('document:keydown.escape') onEsc() { this.cerrar.emit(); }
  @HostListener('document:click') onDocClick() { this.showMarcaDrop = false; }

  abrirMarcaDrop(e: MouseEvent): void {
    e.stopPropagation();
    this.showMarcaDrop = !this.showMarcaDrop;
    if (this.showMarcaDrop) this.marcaSearch = '';
  }
  seleccionarMarca(m: CatalogoItem, e: MouseEvent): void {
    e.stopPropagation();
    this.form.patchValue({ marcaId: m.id || '' });
    this.showMarcaDrop = false;
    this.marcaSearch = '';
  }
  limpiarMarca(e: MouseEvent): void {
    e.stopPropagation();
    this.form.patchValue({ marcaId: '', modeloId: '' });
    this.modelos = [];
    this.showMarcaDrop = false;
    this.marcaSearch = '';
  }

  ctrl(n: string) { return this.form.get(n); }
  get requiereMant(): boolean { return !!this.form?.get('requiereMantenimiento')?.value; }

  private _cargarCatalogos(): void {
    this.svc.getCategoriasEquipo().subscribe({ next: r => (this.categorias = r) });
    this.svc.getMarcas().subscribe({ next: r => (this.marcas = r) });
    this.svc.getAlmacenes().subscribe({ next: r => (this.almacenes = r) });
    this._cargarModelos(this.form.get('marcaId')?.value);
  }

  private _cargarModelos(marcaId: string | null): void {
    if (!marcaId) { this.modelos = []; return; }
    this.svc.getModelos(marcaId).subscribe({ next: r => (this.modelos = r) });
  }

  // ── Crear catálogos inline ──
  toggleAddCategoria(): void {
    this.showAddCategoria = !this.showAddCategoria;
    this.nuevaCategoria = '';
  }
  confirmarNuevaCategoria(): void {
    const n = this.nuevaCategoria.trim();
    if (!n || this.creandoCategoria) return;
    this.creandoCategoria = true;
    this.svc.crearCategoriaEquipo(n).subscribe({
      next: (c) => {
        this.categorias = [...this.categorias.filter(x => x.id !== c.id), c].sort((a, b) => a.nombre.localeCompare(b.nombre));
        this.form.patchValue({ categoriaId: c.id });
        this.showAddCategoria = false;
        this.nuevaCategoria = '';
        this.creandoCategoria = false;
      },
      error: () => (this.creandoCategoria = false),
    });
  }

  toggleAddMarca(): void { this.showAddMarca = !this.showAddMarca; this.nuevaMarca = ''; }
  confirmarNuevaMarca(): void {
    const n = this.nuevaMarca.trim(); if (!n) return;
    this.creandoMarca = true;
    this.svc.crearMarca(n).subscribe({
      next: (m) => {
        this.marcas = [...this.marcas.filter(x => x.id !== m.id), m].sort((a, b) => a.nombre.localeCompare(b.nombre));
        this.form.patchValue({ marcaId: m.id });
        this.showAddMarca = false; this.nuevaMarca = ''; this.creandoMarca = false;
      },
      error: () => (this.creandoMarca = false),
    });
  }

  toggleAddModelo(): void { this.showAddModelo = !this.showAddModelo; this.nuevoModelo = ''; }
  confirmarNuevoModelo(): void {
    const n = this.nuevoModelo.trim();
    const marcaId = this.form.get('marcaId')?.value as string;
    if (!n || !marcaId) return;
    this.creandoModelo = true;
    this.svc.crearModelo(n, marcaId).subscribe({
      next: (m) => {
        this.modelos = [...this.modelos.filter(x => x.id !== m.id), m].sort((a, b) => a.nombre.localeCompare(b.nombre));
        this.form.patchValue({ modeloId: m.id });
        this.showAddModelo = false; this.nuevoModelo = ''; this.creandoModelo = false;
      },
      error: () => (this.creandoModelo = false),
    });
  }

  toggleAddAlmacen(): void { this.showAddAlmacen = !this.showAddAlmacen; this.nuevoAlmacen = ''; }
  confirmarNuevoAlmacen(): void {
    const n = this.nuevoAlmacen.trim(); if (!n) return;
    this.creandoAlmacen = true;
    this.svc.crearAlmacen(n).subscribe({
      next: (a) => {
        this.almacenes = [...this.almacenes.filter(x => x.id !== a.id), a].sort((x, y) => x.nombre.localeCompare(y.nombre));
        this.form.patchValue({ almacenId: a.id });
        this.showAddAlmacen = false; this.nuevoAlmacen = ''; this.creandoAlmacen = false;
      },
      error: () => (this.creandoAlmacen = false),
    });
  }

  onGuardar(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid) return;
    const v = this.form.getRawValue();
    const requiere = !!v.requiereMantenimiento;
    const stockMin = Number(v.stockMinimo ?? 0);
    this.guardar.emit({
      nombre:       v.nombre.trim(),
      clase:        v.clase,
      categoriaId:  v.categoriaId || null,
      marcaId:      v.marcaId || null,
      modeloId:     v.modeloId || null,
      numeroSerie:  v.numeroSerie?.trim() || null,
      almacenId:    v.almacenId || null,
      cantidad:     Number(v.cantidad),
      stockMinimo:  stockMin,
      precioCompra: v.precioCompra ? Number(v.precioCompra) : null,
      observaciones:v.observaciones?.trim() || null,
      estado:       v.estado,
      atributos:    stockMin > 0 ? { stock_minimo: stockMin } : null,
      requiereMantenimiento:     requiere,
      frecuenciaMantenimiento:   requiere ? v.frecuenciaMantenimiento : 'ninguno',
      proximaFechaMantenimiento: requiere ? (v.proximaFechaMantenimiento || null) : null,
      fechaAdquisicion:          v.fechaAdquisicion || null,
      fichaTecnica:              v.fichaTecnica?.trim() || null,
    });
  }
}

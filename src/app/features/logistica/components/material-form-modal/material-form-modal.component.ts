import {
  Component, Input, Output, EventEmitter,
  OnInit, OnDestroy, inject, HostListener
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators, FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { MaterialLog, CatalogoItem, AlmacenItem, UnidadItem } from '../../logistica.models';

@Component({
  selector: 'app-material-form-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './material-form-modal.component.html',
  styleUrls: ['./material-form-modal.component.css']
})
export class MaterialFormModalComponent implements OnInit, OnDestroy {
  @Input() material: MaterialLog | null = null;
  @Input() guardando = false;
  @Output() guardar = new EventEmitter<any>();
  @Output() cerrar  = new EventEmitter<void>();

  private fb  = inject(FormBuilder);
  private svc = inject(LogisticaService);
  form!: FormGroup;

  // Catálogos cargados desde BD
  categorias: CatalogoItem[] = [];
  unidades:   UnidadItem[]   = [];
  almacenes:  AlmacenItem[]  = [];
  marcas:     CatalogoItem[] = [];
  cargandoCatalogos = false;

  // Inputs "+ Nueva …"
  showAddCategoria = false; nuevaCategoria = ''; creandoCategoria = false;
  showAddUnidad    = false; nuevaUnidad    = ''; creandoUnidad    = false;
  showAddAlmacen   = false; nuevoAlmacen   = ''; creandoAlmacen   = false;

  // Preview de código autogenerado (modo crear)
  codigoPreview = '';

  get esEdicion(): boolean { return !!this.material; }

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this.form = this.fb.group({
      nombre:       [this.material?.nombre ?? '', [Validators.required, Validators.maxLength(200)]],
      categoriaId:  [this.material?.categoriaId ?? '', Validators.required],
      unidadId:     [this.material?.unidadId ?? '', Validators.required],
      almacenMaterialId: [this.material?.almacenMaterialId ?? '', Validators.required],
      descripcion:  [this.material?.descripcion ?? ''],
      cantidad:     [this.material?.cantidad ?? 0, [Validators.required, Validators.min(0)]],
      stockMinimo:  [this.material?.stockMinimo ?? 0, [Validators.required, Validators.min(0)]],
      precio:       [this.material?.precio ?? null, [Validators.min(0)]],
      precioCompra: [this.material?.precioCompra ?? null as number | null, [Validators.min(0)]],
      serie:        [this.material?.serie ?? ''],
      marcaId:      [this.material?.marcaId ?? ''],
      activo:       [this.material?.activo ?? true],
    });
    this._cargarCatalogos();
    if (!this.esEdicion) {
      this.svc.getSiguienteCodigo('material').subscribe({
        next: r => (this.codigoPreview = r.codigo),
      });
    }
  }

  ngOnDestroy(): void { document.body.style.overflow = ''; }

  @HostListener('document:keydown.escape') onEsc() { this.cerrar.emit(); }

  ctrl(n: string) { return this.form.get(n); }

  private _cargarCatalogos(): void {
    this.cargandoCatalogos = true;
    this.svc.getCategorias().subscribe({ next: r => (this.categorias = r) });
    this.svc.getUnidades().subscribe({   next: r => (this.unidades   = r) });
    this.svc.getMarcas().subscribe({     next: r => (this.marcas     = r) });
    this.svc.getAlmacenes().subscribe({
      next: r => { this.almacenes = r; this.cargandoCatalogos = false; },
      error: () => (this.cargandoCatalogos = false),
    });
  }

  // ── Crear catálogo inline ──
  toggleAddCategoria(): void { this.showAddCategoria = !this.showAddCategoria; this.nuevaCategoria = ''; }
  confirmarNuevaCategoria(): void {
    const n = this.nuevaCategoria.trim();
    if (!n) return;
    this.creandoCategoria = true;
    this.svc.crearCategoria(n).subscribe({
      next: (cat) => {
        this.categorias = [...this.categorias.filter(c => c.id !== cat.id), cat]
          .sort((a, b) => a.nombre.localeCompare(b.nombre));
        this.form.patchValue({ categoriaId: cat.id });
        this.showAddCategoria = false; this.nuevaCategoria = ''; this.creandoCategoria = false;
      },
      error: () => { this.creandoCategoria = false; },
    });
  }

  toggleAddUnidad(): void { this.showAddUnidad = !this.showAddUnidad; this.nuevaUnidad = ''; }
  confirmarNuevaUnidad(): void {
    const n = this.nuevaUnidad.trim();
    if (!n) return;
    this.creandoUnidad = true;
    this.svc.crearUnidad(n).subscribe({
      next: (u) => {
        this.unidades = [...this.unidades.filter(x => x.id !== u.id), u]
          .sort((a, b) => a.nombre.localeCompare(b.nombre));
        this.form.patchValue({ unidadId: u.id });
        this.showAddUnidad = false; this.nuevaUnidad = ''; this.creandoUnidad = false;
      },
      error: () => { this.creandoUnidad = false; },
    });
  }

  toggleAddAlmacen(): void { this.showAddAlmacen = !this.showAddAlmacen; this.nuevoAlmacen = ''; }
  confirmarNuevoAlmacen(): void {
    const n = this.nuevoAlmacen.trim();
    if (!n) return;
    this.creandoAlmacen = true;
    this.svc.crearAlmacen(n).subscribe({
      next: (a) => {
        this.almacenes = [...this.almacenes.filter(x => x.id !== a.id), a]
          .sort((x, y) => x.nombre.localeCompare(y.nombre));
        this.form.patchValue({ almacenMaterialId: a.id });
        this.showAddAlmacen = false; this.nuevoAlmacen = ''; this.creandoAlmacen = false;
      },
      error: () => { this.creandoAlmacen = false; },
    });
  }

  onGuardar(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid) return;
    const v = this.form.getRawValue();
    const stockMin = Number(v.stockMinimo ?? 0);
    this.guardar.emit({
      nombre:       v.nombre.trim(),
      categoriaId:       v.categoriaId,
      unidadId:          v.unidadId,
      almacenMaterialId: v.almacenMaterialId || null,
      descripcion:  v.descripcion?.trim() || null,
      cantidad:     Number(v.cantidad),
      stockMinimo:  stockMin,
      precio:       v.precio === null || v.precio === '' ? null : Number(v.precio),
      precioCompra: v.precioCompra ? Number(v.precioCompra) : null,
      serie:        v.serie?.trim() || null,
      marcaId:      v.marcaId || null,
      atributos:    stockMin > 0 ? { stock_minimo: stockMin } : null,
      activo:       !!v.activo,
    });
  }
}

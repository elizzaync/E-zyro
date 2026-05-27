import {
  Component, Input, Output, EventEmitter,
  OnInit, OnDestroy, inject, HostListener
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { MaterialLog } from '../../logistica.models';

@Component({
  selector: 'app-material-form-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, SpinnerComponent],
  templateUrl: './material-form-modal.component.html',
  styleUrls: ['./material-form-modal.component.css']
})
export class MaterialFormModalComponent implements OnInit, OnDestroy {
  @Input() material: MaterialLog | null = null;     // null → crear
  @Input() guardando = false;
  @Output() guardar = new EventEmitter<Omit<MaterialLog, 'id'>>();
  @Output() cerrar  = new EventEmitter<void>();

  private fb = inject(FormBuilder);
  form!: FormGroup;

  get esEdicion(): boolean { return !!this.material; }

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this.form = this.fb.group({
      codigo:      [this.material?.codigo ?? '', [Validators.required, Validators.maxLength(50)]],
      nombre:      [this.material?.nombre ?? '', [Validators.required, Validators.maxLength(200)]],
      categoria:   [this.material?.categoria ?? '', Validators.required],
      unidad:      [this.material?.unidad ?? 'Unidad', Validators.required],
      descripcion: [this.material?.descripcion ?? ''],
      cantidad:    [this.material?.cantidad ?? 0, [Validators.required, Validators.min(0)]],
      stockMinimo: [this.material?.stockMinimo ?? 0, [Validators.required, Validators.min(0)]],
      almacen:     [this.material?.almacen ?? 'Almacén Central', Validators.required],
      precio:      [this.material?.precio ?? null, [Validators.min(0)]],
      activo:      [this.material?.activo ?? true],
    });
  }

  ngOnDestroy(): void { document.body.style.overflow = ''; }

  @HostListener('document:keydown.escape') onEsc() { this.cerrar.emit(); }

  ctrl(n: string) { return this.form.get(n); }

  unidades = ['Unidad', 'Par', 'Metros', 'Litros', 'Kilogramos', 'Cajas', 'Rollos', 'Juego'];
  almacenes = ['Almacén Central', 'Almacén Norte', 'Almacén Sur'];

  onGuardar(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid) return;
    const v = this.form.getRawValue();
    this.guardar.emit({
      codigo:      v.codigo.trim(),
      nombre:      v.nombre.trim(),
      categoriaId: this.material?.categoriaId ?? null,
      categoria:   v.categoria,
      unidad:      v.unidad,
      descripcion: v.descripcion?.trim() || null,
      cantidad:    Number(v.cantidad),
      stockMinimo: Number(v.stockMinimo),
      almacenId:   this.material?.almacenId ?? null,
      almacen:     v.almacen,
      precio:      v.precio === null || v.precio === '' ? null : Number(v.precio),
      activo:      !!v.activo,
    });
  }
}

import { Component, Input, Output, EventEmitter, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { Epp, EppIn, CatalogoItem, UnidadItem } from '../../logistica.models';

@Component({
  selector: 'app-epp-form-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './epp-form-modal.component.html',
  styleUrls: ['./epp-form-modal.component.css'],
})
export class EppFormModalComponent implements OnInit {
  @Input() epp: Epp | null = null;
  @Input() guardando = false;
  @Output() guardar = new EventEmitter<EppIn>();
  @Output() cerrar  = new EventEmitter<void>();

  private fb  = inject(FormBuilder);
  private svc = inject(LogisticaService);
  form!: FormGroup;

  marcas: CatalogoItem[] = [];
  unidades: UnidadItem[] = [];

  get esEdicion(): boolean { return !!this.epp; }

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    const e = this.epp;
    this.form = this.fb.group({
      nombre:      [e?.nombre ?? '', [Validators.required, Validators.maxLength(200)]],
      descripcion: [e?.descripcion ?? ''],
      marcaId:     [e?.marca_id ?? ''],
      unidadId:    [e?.unidad_id ?? ''],
      stockMin:    [e?.stock_min ?? 0, [Validators.min(0)]],
      precio:      [e?.precio ?? null],
    });
    this.svc.getMarcas().subscribe({ next: r => (this.marcas = r) });
    this.svc.getUnidades().subscribe({ next: r => (this.unidades = r) });
  }

  ctrl(n: string) { return this.form.get(n); }

  onGuardar(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid) return;
    const v = this.form.getRawValue();
    this.guardar.emit({
      nombre:      v.nombre.trim(),
      descripcion: v.descripcion?.trim() || null,
      marca_id:    v.marcaId || null,
      unidad_id:   v.unidadId || null,
      stock_min:   Number(v.stockMin ?? 0),
      precio:      v.precio != null && v.precio !== '' ? Number(v.precio) : null,
    });
  }
}

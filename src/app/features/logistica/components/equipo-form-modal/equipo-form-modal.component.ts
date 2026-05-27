import {
  Component, Input, Output, EventEmitter,
  OnInit, OnDestroy, inject, HostListener
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import {
  EquipoHerramienta, ClaseArticulo,
  CLASES_ARTICULO, ESTADOS_EQUIPO, FRECUENCIAS_MANTENIMIENTO,
} from '../../logistica.models';

@Component({
  selector: 'app-equipo-form-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, SpinnerComponent],
  templateUrl: './equipo-form-modal.component.html',
  styleUrls: ['./equipo-form-modal.component.css']
})
export class EquipoFormModalComponent implements OnInit, OnDestroy {
  @Input() equipo: EquipoHerramienta | null = null;     // null → crear
  @Input() guardando = false;
  @Output() guardar = new EventEmitter<Omit<EquipoHerramienta, 'id'>>();
  @Output() cerrar  = new EventEmitter<void>();

  private fb = inject(FormBuilder);
  private destroy$ = new Subject<void>();
  form!: FormGroup;

  clases       = CLASES_ARTICULO;
  estados      = ESTADOS_EQUIPO;
  frecuencias  = FRECUENCIAS_MANTENIMIENTO.filter(f => f.value !== 'ninguno');

  get esEdicion(): boolean { return !!this.equipo; }

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    const e = this.equipo;
    this.form = this.fb.group({
      codigo:      [e?.codigo ?? '', [Validators.required, Validators.maxLength(50)]],
      nombre:      [e?.nombre ?? '', [Validators.required, Validators.maxLength(200)]],
      clase:       [e?.clase ?? 'equipo' as ClaseArticulo, Validators.required],
      tipo:        [e?.tipo ?? '', Validators.required],
      marca:       [e?.marca ?? ''],
      modelo:      [e?.modelo ?? ''],
      numeroSerie: [e?.numeroSerie ?? ''],
      ubicacion:   [e?.ubicacion ?? 'Almacén Central'],
      cantidad:    [e?.cantidad ?? 1, [Validators.required, Validators.min(0)]],
      estado:      [e?.estado ?? 'operativo', Validators.required],
      requiereMantenimiento:    [e?.requiereMantenimiento ?? false],
      frecuenciaMantenimiento:  [e?.frecuenciaMantenimiento && e.frecuenciaMantenimiento !== 'ninguno' ? e.frecuenciaMantenimiento : 'mensual'],
      proximaFechaMantenimiento:[e?.proximaFechaMantenimiento ?? null],
      fechaAdquisicion:         [e?.fechaAdquisicion ?? null],
      fichaTecnica:             [e?.fichaTecnica ?? ''],
    });

    // Al desactivar mantenimiento, limpiamos los campos dependientes
    this.form.get('requiereMantenimiento')!.valueChanges
      .pipe(takeUntil(this.destroy$))
      .subscribe((req: boolean) => {
        if (!req) this.form.patchValue({ proximaFechaMantenimiento: null }, { emitEvent: false });
      });
  }

  ngOnDestroy(): void {
    this.destroy$.next(); this.destroy$.complete();
    document.body.style.overflow = '';
  }

  @HostListener('document:keydown.escape') onEsc() { this.cerrar.emit(); }

  ctrl(n: string) { return this.form.get(n); }
  get requiereMant(): boolean { return !!this.form?.get('requiereMantenimiento')?.value; }

  onGuardar(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid) return;
    const v = this.form.getRawValue();
    const requiere = !!v.requiereMantenimiento;
    this.guardar.emit({
      codigo:      v.codigo.trim(),
      nombre:      v.nombre.trim(),
      clase:       v.clase,
      tipo:        v.tipo.trim(),
      marca:       v.marca?.trim() || null,
      modelo:      v.modelo?.trim() || null,
      numeroSerie: v.numeroSerie?.trim() || null,
      ubicacion:   v.ubicacion?.trim() || null,
      cantidad:    Number(v.cantidad),
      estado:      v.estado,
      requiereMantenimiento:     requiere,
      frecuenciaMantenimiento:   requiere ? v.frecuenciaMantenimiento : 'ninguno',
      proximaFechaMantenimiento: requiere ? (v.proximaFechaMantenimiento || null) : null,
      fechaAdquisicion:          v.fechaAdquisicion || null,
      fichaTecnica:              v.fichaTecnica?.trim() || null,
    });
  }
}

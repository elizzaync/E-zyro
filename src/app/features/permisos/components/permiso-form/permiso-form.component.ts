import {
  Component, OnInit, OnDestroy,
  Input, Output, EventEmitter,
  ViewChild, ElementRef,
  inject
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Subject } from 'rxjs';
import { takeUntil } from 'rxjs/operators';
import { ToastService } from '../../../../core/services/toast.service';
import { AlertComponent } from '../../../../shared/components/login/alert.component';

// 👇 INTERFAZ CORREGIDA: Se agregaron los campos faltantes para evitar errores de tipado
export interface PreviewData {
  tipo: string;
  tipoLabel?: string;
  fechaInicio?: string;
  fechaFin?: string;
  horaInicio?: string;
  horaFin?: string;
  motivo?: string;
  firmaBase64?: string;
  adjuntoNombre?: string;
  lugarDestino?: string;
  periodo?: string | null;
  totalDias?: number | string | null;
  horasCalculadas?: number | null;
}

export const TIPOS_PERMISO = [
  { id: 'permiso_personal',         label: 'Permiso personal',            num: 1 },
  { id: 'comision_trabajo',         label: 'Comisión de Trabajo',         num: 2 },
  { id: 'cita_essalud',             label: 'Cita Essalud / Clínica',      num: 3 },
  { id: 'permanencia_capacitacion', label: 'Permanencia Capacitación',    num: 4 },
  { id: 'permanencia_extra',        label: 'Permanencia Extra (H)',       num: 5 },
  { id: 'recuperacion',             label: 'Recuperación (H)',            num: 6 },
  { id: 'vacaciones',               label: 'Vacaciones',                  num: 7 },
  { id: 'dias_libres',              label: 'Día(s) Libre(s)',             num: 8 },
  { id: 'transferencia',            label: 'Transferencia',               num: 9 },
  { id: 'otros',                    label: 'Otros',                       num: 10 },
];

@Component({
  selector: 'app-permiso-form',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, AlertComponent],
  templateUrl: './permiso-form.component.html',
  styleUrls: ['./permiso-form.component.css']
})
export class PermisoFormComponent implements OnInit, OnDestroy {
  @Input()  firmaGuardadaUrl: string | null = null;
  @Output() previewDataChange = new EventEmitter<PreviewData>();
  @Output() onEnviar          = new EventEmitter<void>();

  private fb           = inject(FormBuilder);
  private toastService = inject(ToastService);
  private destroy$     = new Subject<void>();

  readonly tipos = TIPOS_PERMISO;
  form!: FormGroup;

  adjuntoNombre    = '';
  firmaBase64      = '';
  firmaMode: 'draw' | 'upload' = 'draw';
  horasCalculadas: number | null = null;
  bloqueVacaciones = false;
  isDrawing        = false;

  // Para simular validación de vacaciones (6 meses de antigüedad)
  private readonly fechaIngreso = new Date(Date.now() - 6 * 30 * 24 * 60 * 60 * 1000);
  private prevTipo = '';
  private ctx?: CanvasRenderingContext2D;
  private _canvasRef?: ElementRef<HTMLCanvasElement>;

  // Listeners táctiles guardados para poder removerlos (Evita fugas de memoria)
  private readonly touchStartFn = (e: TouchEvent) => this.onTouchStart(e);
  private readonly touchMoveFn  = (e: TouchEvent) => this.onTouchMove(e);
  private readonly touchEndFn   = ()               => this.onTouchEnd();

  @ViewChild('firmaCanvas') set canvasRefSetter(ref: ElementRef<HTMLCanvasElement> | undefined) {
    this.cleanupTouchListeners();
    this._canvasRef = ref;
    if (ref) {
      setTimeout(() => this.initCanvas(), 0);
    }
  }
  get canvasRef(): ElementRef<HTMLCanvasElement> | undefined { return this._canvasRef; }

  // ── Getters de visibilidad ──────────────────────────────────────
  get tipo(): string { return this.form.get('tipo')?.value ?? ''; }

  get esMismoDia(): boolean {
    return ['permiso_personal', 'dias_libres'].includes(this.tipo);
  }
  get soloHoras(): boolean {
    return ['permanencia_extra', 'permanencia_capacitacion'].includes(this.tipo);
  }
  get mostrarFechas(): boolean {
    return !this.soloHoras && ['vacaciones', 'permiso_personal', 'dias_libres',
      'comision_trabajo', 'transferencia', 'otros', 'cita_essalud'].includes(this.tipo);
  }
  get mostrarHoras(): boolean {
    return ['permiso_personal', 'dias_libres', 'cita_essalud',
      'permanencia_extra', 'permanencia_capacitacion', 'recuperacion'].includes(this.tipo);
  }
  get mostrarLugar(): boolean {
    return ['comision_trabajo', 'transferencia'].includes(this.tipo);
  }
  get mostrarArchivo(): boolean {
    return ['cita_essalud', 'recuperacion'].includes(this.tipo);
  }
  get mostrarMotivo(): boolean {
    return !this.soloHoras;
  }

  // ── Lifecycle ───────────────────────────────────────────────────
  ngOnInit(): void {
    this.form = this.fb.group({
      tipo:         ['permiso_personal', Validators.required],
      fechaInicio:  [''],
      fechaFin:     [''],
      horaInicio:   [''],
      horaFin:      [''],
      motivo:       [''],
      lugarDestino: [''],
    });

    this.prevTipo = this.tipo;

    this.form.valueChanges.pipe(takeUntil(this.destroy$)).subscribe(() => {
      const currentTipo = this.tipo;
      if (currentTipo !== this.prevTipo) {
        this.limpiarCamposIrrelevantes(currentTipo);
        this.prevTipo = currentTipo;
      }
      this.aplicarReglas();
      this.emitirPreview();
    });

    this.emitirPreview();
  }

  ngOnDestroy(): void {
    this.cleanupTouchListeners();
    this.destroy$.next();
    this.destroy$.complete();
  }

  // ── Canvas: inicialización ──────────────────────────────────────
  private initCanvas(): void {
    const canvas = this._canvasRef?.nativeElement;
    if (!canvas) return;

    canvas.width  = canvas.offsetWidth  || 380;
    canvas.height = canvas.offsetHeight || 110;

    this.ctx = canvas.getContext('2d')!;
    this.ctx.strokeStyle = '#1e293b';
    this.ctx.lineWidth   = 2.5;
    this.ctx.lineCap     = 'round';
    this.ctx.lineJoin    = 'round';

    canvas.addEventListener('touchstart', this.touchStartFn, { passive: false });
    canvas.addEventListener('touchmove',  this.touchMoveFn,  { passive: false });
    canvas.addEventListener('touchend',   this.touchEndFn);
  }

  private cleanupTouchListeners(): void {
    const canvas = this._canvasRef?.nativeElement;
    if (!canvas) return;
    canvas.removeEventListener('touchstart', this.touchStartFn);
    canvas.removeEventListener('touchmove',  this.touchMoveFn);
    canvas.removeEventListener('touchend',   this.touchEndFn);
  }

  private getCanvasPos(clientX: number, clientY: number): { x: number; y: number } {
    const canvas = this._canvasRef!.nativeElement;
    const rect   = canvas.getBoundingClientRect();
    return {
      x: (clientX - rect.left) * (canvas.width  / rect.width),
      y: (clientY - rect.top)  * (canvas.height / rect.height),
    };
  }

  // ── Canvas: eventos de ratón ────────────────────────────────────
  onMouseDown(event: MouseEvent): void {
    if (!this.ctx) return;
    this.isDrawing = true;
    const { x, y } = this.getCanvasPos(event.clientX, event.clientY);
    this.ctx.beginPath();
    this.ctx.moveTo(x, y);
  }

  onMouseMove(event: MouseEvent): void {
    if (!this.isDrawing || !this.ctx) return;
    const { x, y } = this.getCanvasPos(event.clientX, event.clientY);
    this.ctx.lineTo(x, y);
    this.ctx.stroke();
  }

  onMouseUp(): void {
    if (!this.isDrawing) return;
    this.isDrawing = false;
    this.captureCanvasSignature();
  }

  // ── Canvas: eventos táctiles ────────────────────────────────────
  private onTouchStart(event: TouchEvent): void {
    event.preventDefault(); // Evita que la pantalla haga scroll mientras firmas en móvil
    if (!this.ctx) return;
    const touch = event.touches[0];
    this.isDrawing = true;
    const { x, y } = this.getCanvasPos(touch.clientX, touch.clientY);
    this.ctx.beginPath();
    this.ctx.moveTo(x, y);
  }

  private onTouchMove(event: TouchEvent): void {
    event.preventDefault();
    if (!this.isDrawing || !this.ctx) return;
    const touch = event.touches[0];
    const { x, y } = this.getCanvasPos(touch.clientX, touch.clientY);
    this.ctx.lineTo(x, y);
    this.ctx.stroke();
  }

  private onTouchEnd(): void {
    if (!this.isDrawing) return;
    this.isDrawing = false;
    this.captureCanvasSignature();
  }

  private captureCanvasSignature(): void {
    const canvas = this._canvasRef?.nativeElement;
    if (!canvas) return;
    this.firmaBase64 = canvas.toDataURL('image/png');
    this.emitirPreview();
  }

  limpiarFirma(): void {
    const canvas = this._canvasRef?.nativeElement;
    if (canvas && this.ctx) {
      this.ctx.clearRect(0, 0, canvas.width, canvas.height);
    }
    this.firmaBase64 = '';
    this.emitirPreview();
  }

  // ── Subir imagen de firma ───────────────────────────────────────
  onFirmaImageSeleccionada(event: Event): void {
    const input = event.target as HTMLInputElement;
    if (!input.files?.length) return;
    const reader = new FileReader();
    reader.onload = (e) => {
      this.firmaBase64 = e.target?.result as string;
      this.emitirPreview();
      this.toastService.mostrar('Imagen de firma cargada correctamente.', 'success');
    };
    reader.readAsDataURL(input.files[0]);
  }

  // ── Lógica de negocio ───────────────────────────────────────────
  private limpiarCamposIrrelevantes(nuevoTipo: string): void {
    const patch: any = {};

    if (!['permiso_personal', 'dias_libres', 'cita_essalud',
          'permanencia_extra', 'permanencia_capacitacion', 'recuperacion'].includes(nuevoTipo)) {
      patch.horaInicio = '';
      patch.horaFin    = '';
    }
    if (!['comision_trabajo', 'transferencia'].includes(nuevoTipo)) {
      patch.lugarDestino = '';
    }
    if (!['cita_essalud', 'recuperacion'].includes(nuevoTipo)) {
      this.adjuntoNombre = '';
    }

    this.horasCalculadas = null;
    if (Object.keys(patch).length) {
      this.form.patchValue(patch, { emitEvent: false });
    }
  }

  private aplicarReglas(): void {
    const tipo = this.tipo;

    if (tipo === 'vacaciones') {
      const msAnio = 365 * 24 * 60 * 60 * 1000;
      this.bloqueVacaciones = (Date.now() - this.fechaIngreso.getTime()) < msAnio;
    } else {
      this.bloqueVacaciones = false;
    }

    if (this.esMismoDia) {
      const inicio = this.form.get('fechaInicio')?.value;
      const fin    = this.form.get('fechaFin')?.value;
      if (inicio && !fin) {
        this.form.patchValue({ fechaFin: inicio }, { emitEvent: false });
      } else if (inicio && fin && fin !== inicio) {
        this.form.patchValue({ fechaFin: inicio }, { emitEvent: false });
        this.toastService.mostrar('Este tipo de permiso permite máximo 1 día exacto.', 'info');
      }
    }

    if (this.soloHoras) {
      this.horasCalculadas = this.calcularHoras();
    } else {
      this.horasCalculadas = null;
    }
  }

  private calcularHoras(): number | null {
    const inicio = this.form.get('horaInicio')?.value;
    const fin    = this.form.get('horaFin')?.value;
    if (!inicio || !fin) return null;
    const [h1, m1] = inicio.split(':').map(Number);
    const [h2, m2] = fin.split(':').map(Number);
    const diff = (h2 * 60 + m2) - (h1 * 60 + m1);
    return diff > 0 ? parseFloat((diff / 60).toFixed(2)) : null;
  }

  private calcularTotalDias(): number | null {
    const inicio = this.form.get('fechaInicio')?.value;
    const fin    = this.form.get('fechaFin')?.value || inicio;
    if (!inicio) return null;
    const d1   = new Date(inicio + 'T00:00:00');
    const d2   = new Date((fin || inicio) + 'T00:00:00');
    const diff = Math.round((d2.getTime() - d1.getTime()) / (1000 * 60 * 60 * 24)) + 1;
    return diff > 0 ? diff : null;
  }

  private emitirPreview(): void {
    const v       = this.form.value;
    const tipoObj = this.tipos.find(t => t.id === v.tipo);
    this.previewDataChange.emit({
      tipo:            v.tipo,
      tipoLabel:       tipoObj?.label ?? '',
      fechaInicio:     v.fechaInicio,
      fechaFin:        v.fechaFin || v.fechaInicio,
      horaInicio:      v.horaInicio,
      horaFin:         v.horaFin,
      motivo:          v.motivo,
      lugarDestino:    v.lugarDestino,
      adjuntoNombre:   this.adjuntoNombre,
      horasCalculadas: this.horasCalculadas,
      totalDias:       this.calcularTotalDias(),
      firmaBase64:     this.firmaBase64,
      periodo:         null // Opcional, lo dejamos listo para el PDF
    });
  }

  // ── Handlers de UI ──────────────────────────────────────────────
  onArchivoSeleccionado(event: Event): void {
    const input = event.target as HTMLInputElement;
    if (input.files?.length) {
      this.adjuntoNombre = input.files[0].name;
      this.toastService.mostrar(`Archivo adjunto: ${this.adjuntoNombre}`, 'success');
      this.emitirPreview();
    }
  }

  usarFirmaGuardada(): void {
    if (this.firmaGuardadaUrl) {
      this.firmaBase64 = this.firmaGuardadaUrl;
      this.emitirPreview();
      this.toastService.mostrar('Firma guardada aplicada al documento.', 'success');
    }
  }

  enviarSolicitud(): void {
    if (this.bloqueVacaciones) return;

    if (!this.firmaBase64) {
      this.toastService.mostrar('Debes registrar tu firma antes de enviar.', 'error');
      return;
    }
    if (this.mostrarArchivo && !this.adjuntoNombre) {
      this.toastService.mostrar('Debes adjuntar el documento de sustento.', 'error');
      return;
    }
    if (!this.form.get('fechaInicio')?.value && !this.soloHoras) {
      this.toastService.mostrar('Selecciona la fecha de inicio del permiso.', 'error');
      return;
    }
    if (this.mostrarMotivo && !this.form.get('motivo')?.value?.trim()) {
      this.toastService.mostrar('El sustento/motivo es obligatorio.', 'error');
      return;
    }

    this.onEnviar.emit();
  }
}
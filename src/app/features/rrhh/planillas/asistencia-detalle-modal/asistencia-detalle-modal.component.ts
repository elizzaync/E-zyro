import { Component, EventEmitter, HostListener, Input, OnChanges, Output, SimpleChanges, inject } from '@angular/core';
import { CommonModule } from '@angular/common';

import { RrhhService, AsistenciaDetallePlanillaDto, AsistDiaDetalleDto } from '../../../../core/services/rrhh.service';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { AsistenciaDiaModalComponent } from './asistencia-dia-modal.component';

const DIA_LABEL: Record<string, string> = {
  laborable: 'Laborable',
  domingo: 'Domingo',
  feriado: 'Feriado',
  no_laborable_turno: 'Fuera de turno',
};

const BADGE_STYLE: Record<string, { bg: string; color: string }> = {
  laborable:          { bg: '#f1f5f9', color: '#475569' },
  domingo:            { bg: '#f3ecff', color: '#7c3aed' },
  feriado:            { bg: '#fff1e6', color: '#c2410c' },
  no_laborable_turno: { bg: '#f8fafc', color: '#94a3b8' },
};

/**
 * Modal de verificación de asistencia (botón "Ver asistencia" de Planilla):
 * lista de días del período con los totales que ya usa la boleta. Solo
 * lectura — consume GET /planilla/empleados/{id}/asistencia-detalle, nunca
 * recalcula nada en el cliente. Diseño importado de Claude Design (proyecto
 * "Diseño modal interactivo" → Verificar Asistencia.dc.html, 2026-07-08).
 *
 * El detalle de CADA día (línea de tiempo, marcaciones, mapa) vive en un
 * modal HIJO aparte (`AsistenciaDiaModalComponent`) con navegación
 * anterior/siguiente entre días sin cerrar.
 */
@Component({
  selector: 'app-asistencia-detalle-modal',
  standalone: true,
  imports: [CommonModule, AppModalComponent, AsistenciaDiaModalComponent],
  templateUrl: './asistencia-detalle-modal.component.html',
  styleUrls: ['./asistencia-detalle-modal.component.css'],
})
export class AsistenciaDetalleModalComponent implements OnChanges {
  private svc = inject(RrhhService);

  @Input() open = false;
  @Input() empleadoId: string | null = null;
  @Input() nombreEmpleado: string | null = null;
  @Input() inicio = '';   // YYYY-MM-DD
  @Input() fin = '';      // YYYY-MM-DD
  @Output() cerrarModal = new EventEmitter<void>();

  cargando = false;
  error = '';
  datos: AsistenciaDetallePlanillaDto | null = null;

  diaModalOpen = false;
  indiceSeleccionado = -1;

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['open'] && this.open && this.empleadoId && this.inicio && this.fin) {
      this.cargar();
    }
    if (changes['open'] && !this.open) {
      this.cerrarDiaModal();
    }
  }

  @HostListener('document:keydown.escape')
  onEsc(): void {
    if (this.open && !this.diaModalOpen) this.cerrar();
  }

  cargar(): void {
    if (!this.empleadoId) return;
    this.cargando = true;
    this.error = '';
    this.datos = null;
    this.cerrarDiaModal();
    this.svc.obtenerAsistenciaDetalle(this.empleadoId, this.inicio, this.fin).subscribe({
      next: (res) => { this.datos = res; this.cargando = false; },
      error: (err) => {
        this.error = err?.error?.detail || 'No se pudo cargar el detalle de asistencia.';
        this.cargando = false;
      },
    });
  }

  cerrar(): void {
    this.cerrarDiaModal();
    this.cerrarModal.emit();
  }

  abrirDia(d: AsistDiaDetalleDto): void {
    if (!this.datos) return;
    this.indiceSeleccionado = this.datos.detalle_dias.findIndex(x => x.fecha === d.fecha);
    this.diaModalOpen = true;
  }
  cerrarDiaModal(): void {
    this.diaModalOpen = false;
  }
  onNavegar(nuevoIndice: number): void {
    this.indiceSeleccionado = nuevoIndice;
  }

  get diaSeleccionado(): AsistDiaDetalleDto | null {
    if (!this.datos || this.indiceSeleccionado < 0) return null;
    return this.datos.detalle_dias[this.indiceSeleccionado] ?? null;
  }

  // ── Helpers numéricos (Decimal llega como string — SIEMPRE Number() antes
  //    de sumar/formatear, mismo patrón que planillas.component.ts) ─────────
  num(v: string | number | null | undefined): number {
    return v === null || v === undefined ? 0 : Number(v);
  }

  h(v: string | number | null | undefined): string {
    return `${this.num(v).toFixed(1)}h`;
  }

  // ── Reconciliación legible: horas_reales = meta - faltas + extra (por
  // construcción, ver planilla_asistencia_service.py — un día corto resta,
  // uno largo suma, nunca se compensan entre sí en el MISMO acumulador). ──
  get reconciliacionTexto(): string {
    if (!this.datos) return '';
    const t = this.datos.totales;
    const meta = this.num(t.meta_horas), faltas = this.num(t.horas_faltantes), extra = this.num(t.horas_extra_bruto);
    const trabajado = this.num(t.horas_reales);
    return `Meta ${meta.toFixed(1)}h − Faltas ${faltas.toFixed(1)}h + Extra ${extra.toFixed(1)}h (solo lo trabajado después de la salida) = Trabajado ${trabajado.toFixed(1)}h`;
  }

  tipoDiaLabel(tipo: string): string {
    return DIA_LABEL[tipo] ?? tipo;
  }
  badgeStyle(tipo: string): Record<string, string> {
    const c = BADGE_STYLE[tipo] ?? BADGE_STYLE['laborable'];
    return { background: c.bg, color: c.color };
  }

  filaClass(d: AsistDiaDetalleDto): string {
    return d.alerta ? 'asist-fila con-alerta' : 'asist-fila';
  }
}

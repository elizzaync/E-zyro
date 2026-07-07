import { Component, EventEmitter, HostListener, Input, OnChanges, OnDestroy, Output, SimpleChanges, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import * as L from 'leaflet';

import { RrhhService, AsistenciaDetallePlanillaDto, AsistDiaDetalleDto, AsistMarcacionDto } from '../../../../core/services/rrhh.service';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

const DIA_LABEL: Record<string, string> = {
  laborable: 'Laborable',
  domingo: 'Domingo',
  feriado: 'Feriado',
  no_laborable_turno: 'Fuera de turno',
};

/**
 * Modal de verificación de asistencia (botón "Ver asistencia" de Planilla):
 * detalle día-por-día de cómo el backend llegó a horas_reales/extra/falta de
 * la fila. Solo lectura — consume GET /planilla/empleados/{id}/asistencia-detalle,
 * nunca recalcula nada en el cliente (los totales YA vienen sumados del backend).
 *
 * Leaflet se importa de forma ESTÁTICA (no dinámica): esta app no usa SSR, y
 * el `import('leaflet')` dinámico rompía en producción (el bundler devolvía
 * el namespace bajo `.default` en vez de plano, así que `L.map` quedaba
 * `undefined` y el error salía recién dentro del constructor minificado de
 * Leaflet — mensaje confuso, "o.map is not a function"). Mismo patrón que
 * `asistencia-dashboard.component.ts`, que ya funciona en producción.
 */
@Component({
  selector: 'app-asistencia-detalle-modal',
  standalone: true,
  imports: [CommonModule, AppModalComponent],
  templateUrl: './asistencia-detalle-modal.component.html',
  styleUrls: ['./asistencia-detalle-modal.component.css'],
})
export class AsistenciaDetalleModalComponent implements OnChanges, OnDestroy {
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
  diaExpandido: string | null = null;

  private leafletMap: L.Map | null = null;

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['open'] && this.open && this.empleadoId && this.inicio && this.fin) {
      this.cargar();
    }
    if (changes['open'] && !this.open) {
      this.diaExpandido = null;
      this.destruirMapa();
    }
  }

  ngOnDestroy(): void {
    this.destruirMapa();
  }

  @HostListener('document:keydown.escape')
  onEsc(): void {
    if (this.open) this.cerrar();
  }

  cargar(): void {
    if (!this.empleadoId) return;
    this.cargando = true;
    this.error = '';
    this.datos = null;
    this.diaExpandido = null;
    this.svc.obtenerAsistenciaDetalle(this.empleadoId, this.inicio, this.fin).subscribe({
      next: (res) => { this.datos = res; this.cargando = false; },
      error: (err) => {
        this.error = err?.error?.detail || 'No se pudo cargar el detalle de asistencia.';
        this.cargando = false;
      },
    });
  }

  cerrar(): void {
    this.diaExpandido = null;
    this.destruirMapa();
    this.cerrarModal.emit();
  }

  // ── Helpers numéricos (Decimal llega como string — SIEMPRE Number() antes
  //    de sumar/formatear, mismo patrón que planillas.component.ts) ─────────
  num(v: string | number | null | undefined): number {
    return v === null || v === undefined ? 0 : Number(v);
  }

  h(v: string | number | null | undefined): string {
    return `${this.num(v).toFixed(1)}h`;
  }

  hora(v: string | null): string {
    if (!v) return '—';
    const d = new Date(v);
    return isNaN(d.getTime()) ? '—' : d.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' });
  }

  /** "08:00:00" o un ISO datetime -> "08:00" (solo lectura, sin timezone). */
  horaCorta(v: string | null): string {
    if (!v) return '—';
    const m = v.match(/T?(\d{2}):(\d{2})/);
    return m ? `${m[1]}:${m[2]}` : '—';
  }

  private minutosDelDia(v: string | null): number | null {
    if (!v) return null;
    const m = v.match(/T?(\d{2}):(\d{2})/);
    if (!m) return null;
    return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
  }

  /** Compara la hora REAL de una marcación contra la hora PACTADA del turno
   * y arma un texto legible: "15 min tarde", "puntual", "1h 30min antes". */
  compararConTurno(horaReal: string | null, horaTurno: string | null, tipo: 'entrada' | 'salida'): string | null {
    if (!horaReal || !horaTurno) return null;
    const real = this.minutosDelDia(horaReal);
    const turno = this.minutosDelDia(horaTurno);
    if (real === null || turno === null) return null;

    const diff = real - turno;
    if (diff === 0) return 'puntual';

    const abs = Math.abs(diff);
    const horas = Math.floor(abs / 60), mins = abs % 60;
    const dur = horas > 0 ? `${horas}h ${mins}min` : `${mins} min`;

    if (tipo === 'entrada') {
      return diff > 0 ? `${dur} tarde` : `${dur} antes de su hora`;
    }
    return diff > 0 ? `${dur} después de su hora` : `${dur} antes de su hora`;
  }

  // ── Reconciliación legible: horas_reales = meta - faltas + extra (por
  // construcción, ver planilla_asistencia_service.py — un día corto resta,
  // uno largo suma, nunca se compensan entre sí en el MISMO acumulador). ──
  get reconciliacionTexto(): string {
    if (!this.datos) return '';
    const t = this.datos.totales;
    const meta = this.num(t.meta_horas), faltas = this.num(t.horas_faltantes), extra = this.num(t.horas_extra_bruto);
    const trabajado = this.num(t.horas_reales);
    return `Meta ${meta.toFixed(1)}h − Faltas ${faltas.toFixed(1)}h + Extra ${extra.toFixed(1)}h (separado, por día) = Trabajado ${trabajado.toFixed(1)}h`;
  }

  tipoDiaLabel(tipo: string): string {
    return DIA_LABEL[tipo] ?? tipo;
  }

  filaClass(d: AsistDiaDetalleDto): string {
    const clases = ['asist-fila', `tipo-${d.tipo_dia}`];
    if (d.es_justificado) clases.push('justificado');
    if (this.num(d.falta) > 0) clases.push('con-falta');
    if (this.num(d.extra_25) + this.num(d.extra_35) > 0) clases.push('con-extra');
    if (this.diaExpandido === d.fecha) clases.push('expandida');
    return clases.join(' ');
  }

  toggleDia(d: AsistDiaDetalleDto): void {
    if (this.diaExpandido === d.fecha) {
      this.diaExpandido = null;
      this.destruirMapa();
      return;
    }
    this.diaExpandido = d.fecha;
    this.destruirMapa();
    setTimeout(() => this.initMapaDia(d), 80);
  }

  marcacionesDelDia(d: AsistDiaDetalleDto): { label: string; m: AsistMarcacionDto | null; color: string; turnoHora: string | null; tipo: 'entrada' | 'salida' | null }[] {
    return [
      { label: 'Entrada',          m: d.marcaciones.entrada,         color: 'green', turnoHora: d.turno_hora_entrada, tipo: 'entrada' },
      { label: 'Almuerzo inicio',  m: d.marcaciones.almuerzo_inicio, color: 'amber', turnoHora: null,                 tipo: null       },
      { label: 'Almuerzo fin',     m: d.marcaciones.almuerzo_fin,    color: 'amber', turnoHora: null,                 tipo: null       },
      { label: 'Salida',           m: d.marcaciones.salida,          color: 'red',   turnoHora: d.turno_hora_salida,  tipo: 'salida'   },
    ];
  }

  // ── Mapa (Leaflet + OpenStreetMap, sin API key) ─────────────────────────
  private initMapaDia(d: AsistDiaDetalleDto): void {
    const puntos = this.marcacionesDelDia(d).filter(p => p.m && p.m.lat !== null && p.m.lng !== null);
    if (puntos.length === 0) return;

    const el = document.getElementById(`asist-mapa-${d.fecha}`);
    if (!el) return;

    const pinIcon = (color: string) => L.divIcon({
      html: `<div class="map-pin-${color}"><svg width="14" height="14" viewBox="0 0 24 24" fill="white"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z"/></svg></div>`,
      className: '', iconSize: [28, 28], iconAnchor: [14, 28],
    });

    const centro: [number, number] = [puntos[0].m!.lat as number, puntos[0].m!.lng as number];
    this.leafletMap = L.map(el).setView(centro, 16);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© <a href="https://openstreetmap.org">OpenStreetMap</a>', maxZoom: 19,
    }).addTo(this.leafletMap);

    const latlngs: [number, number][] = [];
    for (const p of puntos) {
      const lat = p.m!.lat as number, lng = p.m!.lng as number;
      latlngs.push([lat, lng]);
      L.marker([lat, lng], { icon: pinIcon(p.color) })
        .addTo(this.leafletMap)
        .bindPopup(`${p.label} · ${this.hora(p.m!.hora)}`);
    }
    if (latlngs.length > 1) {
      this.leafletMap.fitBounds(L.latLngBounds(latlngs), { padding: [30, 30] });
    }
  }

  private destruirMapa(): void {
    if (this.leafletMap) { this.leafletMap.remove(); this.leafletMap = null; }
  }

  tieneGeolocalizacion(d: AsistDiaDetalleDto): boolean {
    return this.marcacionesDelDia(d).some(p => p.m && p.m.lat !== null && p.m.lng !== null);
  }
}

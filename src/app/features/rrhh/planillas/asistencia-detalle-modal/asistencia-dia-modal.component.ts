import { Component, EventEmitter, HostListener, Input, OnChanges, OnDestroy, Output, SimpleChanges } from '@angular/core';
import { CommonModule } from '@angular/common';
import * as L from 'leaflet';

import { AsistDiaDetalleDto, AsistMarcacionDto } from '../../../../core/services/rrhh.service';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

const DIA_LABEL: Record<string, string> = {
  laborable: 'Laborable',
  domingo: 'Domingo',
  feriado: 'Feriado',
  no_laborable_turno: 'Fuera de turno',
};

interface MarcacionRow {
  label: string;
  m: AsistMarcacionDto | null;
  color: string;
  turnoHora: string | null;
  tipo: 'entrada' | 'salida' | null;
}

interface ZonaBarra {
  leftPct: number;
  widthPct: number;
}

/**
 * Modal HIJO: detalle de UN día (se abre al hacer click en una fila del
 * modal de lista `AsistenciaDetalleModalComponent`). Separado en su propio
 * modal (2026-07-08, pedido explícito del usuario) para tener espacio de
 * sobra para explicar bien: línea de tiempo proporcional, comparación
 * marcación-vs-turno y mapa, sin competir con la tabla de días.
 */
@Component({
  selector: 'app-asistencia-dia-modal',
  standalone: true,
  imports: [CommonModule, AppModalComponent],
  templateUrl: './asistencia-dia-modal.component.html',
  styleUrls: ['./asistencia-dia-modal.component.css'],
})
export class AsistenciaDiaModalComponent implements OnChanges, OnDestroy {
  @Input() open = false;
  @Input() dia: AsistDiaDetalleDto | null = null;
  @Output() cerrarModal = new EventEmitter<void>();

  private leafletMap: L.Map | null = null;

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['open'] && this.open && this.dia) {
      this.destruirMapa();
      setTimeout(() => this.initMapa(), 80);
    }
    if (changes['open'] && !this.open) {
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

  cerrar(): void {
    this.destruirMapa();
    this.cerrarModal.emit();
  }

  // ── Helpers numéricos / de hora (Decimal llega como string) ────────────
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
  horaCorta(v: string | null): string {
    if (!v) return '—';
    const m = v.match(/T?(\d{2}):(\d{2})/);
    return m ? `${m[1]}:${m[2]}` : '—';
  }
  private minutosDelDia(v: string | null): number | null {
    if (!v) return null;
    const m = v.match(/T?(\d{2}):(\d{2})/);
    return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : null;
  }

  tipoDiaLabel(tipo: string): string {
    return DIA_LABEL[tipo] ?? tipo;
  }

  /** Compara la hora REAL de una marcación contra la hora PACTADA del turno:
   * "15 min tarde", "puntual", "1h antes (no cuenta)". Para 'entrada', llegar
   * antes SIEMPRE se marca "no cuenta" (2026-07-08: el sobretiempo es
   * exclusivamente tiempo trabajado DESPUÉS de la salida pactada). */
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
      return diff > 0 ? `${dur} tarde` : `${dur} antes (no cuenta)`;
    }
    return diff > 0 ? `${dur} después (SÍ es extra)` : `${dur} antes de su hora`;
  }

  esNegativoParaElTrabajador(horaReal: string | null, horaTurno: string | null, tipo: 'entrada' | 'salida'): boolean {
    const texto = this.compararConTurno(horaReal, horaTurno, tipo);
    if (!texto) return false;
    if (tipo === 'entrada') return texto.includes('tarde');
    return texto.includes('antes de su hora');
  }

  marcacionesDelDia(d: AsistDiaDetalleDto): MarcacionRow[] {
    return [
      { label: 'Entrada',          m: d.marcaciones.entrada,         color: 'green', turnoHora: d.turno_hora_entrada, tipo: 'entrada' },
      { label: 'Almuerzo inicio',  m: d.marcaciones.almuerzo_inicio, color: 'amber', turnoHora: null,                 tipo: null       },
      { label: 'Almuerzo fin',     m: d.marcaciones.almuerzo_fin,    color: 'amber', turnoHora: null,                 tipo: null       },
      { label: 'Salida',           m: d.marcaciones.salida,          color: 'red',   turnoHora: d.turno_hora_salida,  tipo: 'salida'   },
    ];
  }

  tieneGeolocalizacion(d: AsistDiaDetalleDto): boolean {
    return this.marcacionesDelDia(d).some(p => p.m && p.m.lat !== null && p.m.lng !== null);
  }

  // ── Línea de tiempo proporcional: turno (núcleo) + zona "no cuenta"
  // (llegada temprana) + zona "extra" (después de la salida) ─────────────
  private escalaMinutos(d: AsistDiaDetalleDto): { min: number; max: number } | null {
    const turnoIn = this.minutosDelDia(d.turno_hora_entrada);
    const turnoOut = this.minutosDelDia(d.turno_hora_salida);
    if (turnoIn === null || turnoOut === null) return null;
    let min = turnoIn, max = turnoOut;
    const marcIn = this.minutosDelDia(d.marcaciones.entrada?.hora ?? null);
    const marcOut = this.minutosDelDia(d.marcaciones.salida?.hora ?? null);
    if (marcIn !== null) min = Math.min(min, marcIn);
    if (marcOut !== null) max = Math.max(max, marcOut);
    const pad = 20;
    return { min: min - pad, max: max + pad };
  }

  private pct(minutos: number | null, escala: { min: number; max: number }): number {
    if (minutos === null) return 0;
    const span = escala.max - escala.min;
    if (span <= 0) return 0;
    return Math.max(0, Math.min(100, ((minutos - escala.min) / span) * 100));
  }

  tieneLineaDeTiempo(d: AsistDiaDetalleDto): boolean {
    return this.escalaMinutos(d) !== null && !!d.marcaciones.entrada && !!d.marcaciones.salida;
  }

  turnoZona(d: AsistDiaDetalleDto): ZonaBarra | null {
    const escala = this.escalaMinutos(d);
    if (!escala) return null;
    const turnoIn = this.minutosDelDia(d.turno_hora_entrada)!;
    const turnoOut = this.minutosDelDia(d.turno_hora_salida)!;
    const left = this.pct(turnoIn, escala);
    return { leftPct: left, widthPct: this.pct(turnoOut, escala) - left };
  }

  /** Zona "no cuenta": desde la marcación de entrada hasta el inicio del
   * turno, SOLO si llegó antes. */
  tempranoZona(d: AsistDiaDetalleDto): ZonaBarra | null {
    const escala = this.escalaMinutos(d);
    const marcIn = this.minutosDelDia(d.marcaciones.entrada?.hora ?? null);
    const turnoIn = this.minutosDelDia(d.turno_hora_entrada);
    if (!escala || marcIn === null || turnoIn === null || marcIn >= turnoIn) return null;
    const left = this.pct(marcIn, escala);
    return { leftPct: left, widthPct: this.pct(turnoIn, escala) - left };
  }

  /** Zona "extra": desde el fin del turno hasta la marcación de salida,
   * SOLO si se quedó después. */
  extraZona(d: AsistDiaDetalleDto): ZonaBarra | null {
    const escala = this.escalaMinutos(d);
    const marcOut = this.minutosDelDia(d.marcaciones.salida?.hora ?? null);
    const turnoOut = this.minutosDelDia(d.turno_hora_salida);
    if (!escala || marcOut === null || turnoOut === null || marcOut <= turnoOut) return null;
    const left = this.pct(turnoOut, escala);
    return { leftPct: left, widthPct: this.pct(marcOut, escala) - left };
  }

  marcadorPct(hora: string | null | undefined, d: AsistDiaDetalleDto): number | null {
    const escala = this.escalaMinutos(d);
    const min = this.minutosDelDia(hora ?? null);
    if (!escala || min === null) return null;
    return this.pct(min, escala);
  }

  // ── Mapa (Leaflet, import estático — ver nota en asistencia-detalle-modal) ──
  private initMapa(): void {
    const d = this.dia;
    if (!d) return;
    const puntos = this.marcacionesDelDia(d).filter(p => p.m && p.m.lat !== null && p.m.lng !== null);
    if (puntos.length === 0) return;

    const el = document.getElementById('asist-dia-mapa');
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
}

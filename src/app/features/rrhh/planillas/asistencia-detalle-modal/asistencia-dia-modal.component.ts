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

const BADGE_STYLE: Record<string, { bg: string; color: string }> = {
  laborable:           { bg: '#f1f5f9', color: '#475569' },
  domingo:              { bg: '#f3ecff', color: '#7c3aed' },
  feriado:              { bg: '#fff1e6', color: '#c2410c' },
  no_laborable_turno:   { bg: '#f8fafc', color: '#94a3b8' },
  justificado:          { bg: '#eaf1ff', color: '#2563eb' },
};

interface MarcacionRow {
  label: string;
  m: AsistMarcacionDto | null;
  color: string;
  turnoHora: string | null;
  tipo: 'entrada' | 'salida' | null;
}
interface ZonaBarra { leftPct: number; widthPct: number; }
interface HoverTip { text: string; leftPct: number; }

/**
 * Modal HIJO: detalle de UN día, con navegación anterior/siguiente entre
 * días sin cerrar (flechas + ← →), línea de tiempo proporcional con
 * tooltips al pasar el mouse, y mapa. Diseño importado de Claude Design
 * (proyecto "Diseño modal interactivo" → Verificar Asistencia.dc.html,
 * 2026-07-08).
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
  @Input() dias: AsistDiaDetalleDto[] = [];
  @Input() indice = -1;
  @Output() cerrarModal = new EventEmitter<void>();
  @Output() navegar = new EventEmitter<number>();

  hoverTip: HoverTip | null = null;
  private leafletMap: L.Map | null = null;

  ngOnChanges(changes: SimpleChanges): void {
    if ((changes['open'] || changes['dia']) && this.open && this.dia) {
      this.hoverTip = null;
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
  @HostListener('document:keydown.arrowleft')
  onArrowLeft(): void {
    if (this.open && !this.prevDisabled) this.irAnterior();
  }
  @HostListener('document:keydown.arrowright')
  onArrowRight(): void {
    if (this.open && !this.nextDisabled) this.irSiguiente();
  }

  cerrar(): void {
    this.destruirMapa();
    this.cerrarModal.emit();
  }

  get prevDisabled(): boolean { return this.indice <= 0; }
  get nextDisabled(): boolean { return this.indice < 0 || this.indice >= this.dias.length - 1; }

  irAnterior(): void { if (!this.prevDisabled) this.navegar.emit(this.indice - 1); }
  irSiguiente(): void { if (!this.nextDisabled) this.navegar.emit(this.indice + 1); }

  // ── Helpers numéricos / de hora (Decimal llega como string) ────────────
  num(v: string | number | null | undefined): number {
    return v === null || v === undefined ? 0 : Number(v);
  }
  h(v: string | number | null | undefined): string {
    return `${this.num(v).toFixed(1)}h`;
  }
  hora(v: string | null | undefined): string {
    if (!v) return '—';
    const d = new Date(v);
    return isNaN(d.getTime()) ? '—' : d.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' });
  }
  horaCorta(v: string | null): string {
    if (!v) return '—';
    const m = v.match(/T?(\d{2}):(\d{2})/);
    return m ? `${m[1]}:${m[2]}` : '—';
  }
  private minutosDelDia(v: string | null | undefined): number | null {
    if (!v) return null;
    const m = v.match(/T?(\d{2}):(\d{2})/);
    return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : null;
  }
  private fmtMin(min: number): string {
    const h = Math.floor(min / 60), m = min % 60;
    return h > 0 ? `${h}h ${m}min` : `${m} min`;
  }

  tipoDiaLabel(tipo: string): string {
    return DIA_LABEL[tipo] ?? tipo;
  }
  badgeStyle(tipo: string): Record<string, string> {
    const c = BADGE_STYLE[tipo] ?? BADGE_STYLE['laborable'];
    return { background: c.bg, color: c.color };
  }

  /** true si la entrada fue DESPUÉS de la hora pactada (tardanza real). */
  entradaTarde(d: AsistDiaDetalleDto): boolean {
    const real = this.minutosDelDia(d.marcaciones.entrada?.hora);
    const turno = this.minutosDelDia(d.turno_hora_entrada);
    return real !== null && turno !== null && real > turno;
  }

  compararConTurno(horaReal: string | null | undefined, horaTurno: string | null, tipo: 'entrada' | 'salida'): string | null {
    const real = this.minutosDelDia(horaReal);
    const turno = this.minutosDelDia(horaTurno);
    if (real === null || turno === null) return null;
    const diff = real - turno;
    if (diff === 0) return 'puntual';
    const dur = this.fmtMin(Math.abs(diff));
    if (tipo === 'entrada') return diff > 0 ? `${dur} tarde` : `${dur} antes (no cuenta)`;
    return diff > 0 ? `${dur} después (SÍ es extra)` : `${dur} antes de su hora`;
  }

  marcacionesDelDia(d: AsistDiaDetalleDto): MarcacionRow[] {
    const entradaTarde = this.entradaTarde(d);
    return [
      { label: 'Entrada',          m: d.marcaciones.entrada,         color: entradaTarde ? 'amber' : 'green', turnoHora: d.turno_hora_entrada, tipo: 'entrada' },
      { label: 'Almuerzo inicio',  m: d.marcaciones.almuerzo_inicio, color: d.marcaciones.almuerzo_inicio ? 'green' : 'gris', turnoHora: null, tipo: null },
      { label: 'Almuerzo fin',     m: d.marcaciones.almuerzo_fin,    color: d.marcaciones.almuerzo_fin ? 'green' : 'gris',    turnoHora: null, tipo: null },
      { label: 'Salida',           m: d.marcaciones.salida,          color: 'red', turnoHora: d.turno_hora_salida, tipo: 'salida' },
    ];
  }

  tieneGeolocalizacion(d: AsistDiaDetalleDto): boolean {
    return this.marcacionesDelDia(d).some(p => p.m && p.m.lat !== null && p.m.lng !== null);
  }

  /** Turno asignado pero SIN NINGUNA marcación ese día (ausencia total, a
   * diferencia de "marcó entrada pero no salida"). */
  sinMarcacionesEnAbsoluto(d: AsistDiaDetalleDto): boolean {
    return !!d.turno_hora_entrada && !d.marcaciones.entrada;
  }

  turnoLineText(d: AsistDiaDetalleDto): string {
    if (!d.turno_hora_entrada || !d.turno_hora_salida) {
      return d.tipo_dia === 'domingo'
        ? 'Día de descanso semanal — no tiene turno asignado.'
        : 'Sin turno con horario definido asignado este día.';
    }
    return `Turno ${d.turno_nombre || 'asignado'}: entra a las ${this.horaCorta(d.turno_hora_entrada)}, sale a las ${this.horaCorta(d.turno_hora_salida)} (${this.h(d.req_horas)} netas de jornada).`;
  }

  /** Líneas de explicación del cálculo del día, en el orden del mockup:
   * trabajado-vs-jornada, luego extra (si hay), luego temprano/tarde. */
  calcLines(d: AsistDiaDetalleDto): string[] {
    const lineas: string[] = [];
    if (!d.turno_hora_entrada) {
      lineas.push(`Día sin turno asignado — no se calculan horas.`);
      return lineas;
    }
    if (this.sinMarcacionesEnAbsoluto(d)) {
      lineas.push(`No se registraron marcaciones este día — se contabiliza como falta de <strong>${this.h(d.req_horas)}</strong>.`);
      return lineas;
    }
    lineas.push(`Trabajó (dentro de su turno) <strong>${this.h(d.horas_reales)}</strong> vs. jornada de <strong>${this.h(d.req_horas)}</strong>`);
    if (this.num(d.horas_extra_bruto) > 0) {
      const bruto = this.num(d.horas_extra_bruto), pagable = this.num(d.horas_extra_pagable);
      let txt = `<strong>${this.h(bruto)}</strong> después de su hora de salida`;
      if (pagable < bruto) {
        txt += ` (se paga solo la hora completa: <strong>${this.h(pagable)}</strong>, la fracción de ${this.h(bruto - pagable)} no se paga)`;
      }
      lineas.push(txt);
    }
    const entradaMin = this.minutosDelDia(d.marcaciones.entrada?.hora);
    const turnoMin = this.minutosDelDia(d.turno_hora_entrada);
    if (entradaMin !== null && turnoMin !== null && entradaMin < turnoMin) {
      lineas.push(`Llegó ${this.fmtMin(turnoMin - entradaMin)} antes de su turno — no cuenta ni suma ni resta.`);
    } else if (entradaMin !== null && turnoMin !== null && entradaMin > turnoMin) {
      lineas.push(`Llegó ${this.fmtMin(entradaMin - turnoMin)} tarde respecto al turno.`);
    }
    return lineas;
  }

  // ── Línea de tiempo proporcional con tooltips ───────────────────────────
  private escalaMinutos(d: AsistDiaDetalleDto): { min: number; max: number } | null {
    const turnoIn = this.minutosDelDia(d.turno_hora_entrada);
    const turnoOut = this.minutosDelDia(d.turno_hora_salida);
    if (turnoIn === null || turnoOut === null) return null;
    let min = turnoIn, max = turnoOut;
    const marcIn = this.minutosDelDia(d.marcaciones.entrada?.hora);
    const marcOut = this.minutosDelDia(d.marcaciones.salida?.hora);
    if (marcIn !== null) min = Math.min(min, marcIn);
    if (marcOut !== null) max = Math.max(max, marcOut);
    return { min: min - 20, max: max + 20 };
  }
  private pct(minutos: number | null, escala: { min: number; max: number }): number {
    if (minutos === null) return 0;
    const span = escala.max - escala.min;
    return span <= 0 ? 0 : Math.max(0, Math.min(100, ((minutos - escala.min) / span) * 100));
  }

  /** true si el día tiene un turno con horario — la barra siempre se
   * muestra (rayada si no hay turno), igual que el mockup. */
  tieneTurno(d: AsistDiaDetalleDto): boolean {
    return !!d.turno_hora_entrada && !!d.turno_hora_salida;
  }
  tieneMarcas(d: AsistDiaDetalleDto): boolean {
    return !!d.marcaciones.entrada && !!d.marcaciones.salida;
  }

  barLabels(d: AsistDiaDetalleDto): { left: string; right: string } {
    if (!this.tieneTurno(d)) return { left: '', right: '' };
    const escala = this.escalaMinutos(d)!;
    return { left: this.horaCorta(d.turno_hora_entrada), right: this.horaCorta(d.turno_hora_salida) };
  }

  turnoZona(d: AsistDiaDetalleDto): ZonaBarra | null {
    const escala = this.escalaMinutos(d);
    if (!escala) return null;
    const turnoIn = this.minutosDelDia(d.turno_hora_entrada)!;
    const turnoOut = this.minutosDelDia(d.turno_hora_salida)!;
    const left = this.pct(turnoIn, escala);
    return { leftPct: left, widthPct: this.pct(turnoOut, escala) - left };
  }
  tempranoZona(d: AsistDiaDetalleDto): ZonaBarra | null {
    const escala = this.escalaMinutos(d);
    const marcIn = this.minutosDelDia(d.marcaciones.entrada?.hora);
    const turnoIn = this.minutosDelDia(d.turno_hora_entrada);
    if (!escala || marcIn === null || turnoIn === null || marcIn >= turnoIn) return null;
    const left = this.pct(marcIn, escala);
    return { leftPct: left, widthPct: this.pct(turnoIn, escala) - left };
  }
  extraZona(d: AsistDiaDetalleDto): ZonaBarra | null {
    const escala = this.escalaMinutos(d);
    const marcOut = this.minutosDelDia(d.marcaciones.salida?.hora);
    const turnoOut = this.minutosDelDia(d.turno_hora_salida);
    if (!escala || marcOut === null || turnoOut === null || marcOut <= turnoOut) return null;
    const left = this.pct(turnoOut, escala);
    return { leftPct: left, widthPct: this.pct(marcOut, escala) - left };
  }
  marcadorPct(hora: string | null | undefined, d: AsistDiaDetalleDto): number | null {
    const escala = this.escalaMinutos(d);
    const min = this.minutosDelDia(hora);
    if (!escala || min === null) return null;
    return this.pct(min, escala);
  }

  mostrarTip(text: string, leftPct: number): void { this.hoverTip = { text, leftPct }; }
  ocultarTip(): void { this.hoverTip = null; }

  legend(d: AsistDiaDetalleDto): { color: string; label: string }[] {
    if (!this.tieneTurno(d)) return [{ color: '#e2e8f0', label: 'Sin turno asignado este día' }];
    if (!this.tieneMarcas(d)) {
      return [{ color: '#dbeafe', label: `Turno asignado: ${this.horaCorta(d.turno_hora_entrada)} – ${this.horaCorta(d.turno_hora_salida)} (sin marcaciones)` }];
    }
    const items = [{ color: '#2563eb', label: 'Jornada del turno' }];
    if (this.tempranoZona(d)) items.push({ color: '#e2e8f0', label: 'Llegó antes (no cuenta)' });
    if (this.entradaTarde(d)) items.push({ color: '#f59e0b', label: 'Llegó tarde' });
    if (this.extraZona(d)) items.push({ color: '#16a34a', label: 'Hora extra (después de salida)' });
    return items;
  }

  // ── Mapa (Leaflet, import estático) ─────────────────────────────────────
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

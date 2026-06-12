import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { AsistenciaService, EstadoHoyDto } from '../../core/services/asistencia.service';

type PasoMarca = 'cargando' | 'listo' | 'marcando' | 'exito' | 'error_empleado' | 'error';
type GpsEstado = 'solicitando' | 'refinando' | 'ok' | 'denegado' | 'sin_soporte';

interface GpsInfo {
  lat:       number;
  lon:       number;
  precision: number;
  direccion: string;
}

// Objetivo de precisión y tiempo máximo de watch
const PRECISION_OBJETIVO_M = 30;
const WATCH_TIMEOUT_MS      = 20_000;

@Component({
  selector: 'app-asistencia',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './asistencia.component.html',
  styleUrls: ['./asistencia.component.css']
})
export class AsistenciaComponent implements OnInit, OnDestroy {

  paso: PasoMarca = 'cargando';
  estado: EstadoHoyDto | null = null;
  ultimaMarca: string | null = null;
  ultimoTipo:  string | null = null;
  errorMsg = '';

  gpsEstado: GpsEstado = 'solicitando';
  gpsInfo:   GpsInfo | null = null;

  horaActual  = '';
  fechaActual = '';

  private relojInterval: ReturnType<typeof setInterval> | null = null;
  private gpsWatchId:    number | null = null;
  private gpsTimeout:    ReturnType<typeof setTimeout> | null = null;
  // Última posición para la que se hizo geocodificación
  private geocodePos:    { lat: number; lon: number } | null = null;

  constructor(
    private svc:    AsistenciaService,
    private router: Router,
  ) {}

  ngOnInit(): void {
    this.actualizarReloj();
    this.relojInterval = setInterval(() => this.actualizarReloj(), 1000);
    this.cargarEstado();
    this.iniciarGps();
  }

  ngOnDestroy(): void {
    if (this.relojInterval) clearInterval(this.relojInterval);
    this.detenerWatch();
  }

  // ── Reloj ─────────────────────────────────────────────────────────────────

  private actualizarReloj(): void {
    const now = new Date();
    this.horaActual = now.toLocaleTimeString('es-PE', {
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
    });
    const opts: Intl.DateTimeFormatOptions = {
      weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
    };
    const raw = now.toLocaleDateString('es-PE', opts);
    this.fechaActual = raw.charAt(0).toUpperCase() + raw.slice(1);
  }

  // ── Asistencia ────────────────────────────────────────────────────────────

  private cargarEstado(): void {
    this.paso = 'cargando';
    this.svc.getEstadoHoy().subscribe({
      next: (est) => { this.estado = est; this.paso = 'listo'; },
      error: (err) => {
        const detail = err?.error?.detail ?? '';
        this.paso = (err.status === 404 || detail.includes('Empleado'))
          ? 'error_empleado'
          : 'error';
        if (this.paso === 'error') this.errorMsg = 'No se pudo conectar al servidor.';
      },
    });
  }

  get accionPendiente(): 'entrada' | 'salida' | null {
    if (!this.estado) return null;
    if (!this.estado.tiene_entrada) return 'entrada';
    if (!this.estado.tiene_salida)  return 'salida';
    return null;
  }

  marcar(): void {
    const tipo = this.accionPendiente;
    if (!tipo) return;

    this.detenerWatch();   // ya no necesitamos seguir actualizando
    this.paso = 'marcando';

    const coords = this.gpsInfo
      ? { lat: this.gpsInfo.lat, lon: this.gpsInfo.lon, precision: this.gpsInfo.precision }
      : undefined;

    this.svc.marcar(tipo, coords).subscribe({
      next: (res) => {
        const hora = new Date(res.timestamp).toLocaleTimeString('es-PE', {
          hour: '2-digit', minute: '2-digit', hour12: false,
        });
        this.ultimaMarca = hora;
        this.ultimoTipo  = tipo;
        this.paso = 'exito';
        setTimeout(() => this.cargarEstado(), 2500);
      },
      error: (err) => {
        this.errorMsg = err?.error?.detail ?? 'Ocurrió un error al marcar. Intenta de nuevo.';
        this.paso = 'error';
      },
    });
  }

  reintentar(): void { this.cargarEstado(); }

  volver(): void { this.router.navigate(['/home']); }

  // ── GPS ───────────────────────────────────────────────────────────────────

  private iniciarGps(): void {
    if (!navigator.geolocation) {
      this.gpsEstado = 'sin_soporte';
      return;
    }

    this.gpsEstado  = 'solicitando';
    this.gpsInfo    = null;
    this.geocodePos = null;

    // watchPosition refina la señal con cada nueva lectura del SO
    this.gpsWatchId = navigator.geolocation.watchPosition(
      (pos) => this.onPosicion(pos),
      ()    => { if (!this.gpsInfo) this.gpsEstado = 'denegado'; },
      { enableHighAccuracy: true, timeout: 15_000, maximumAge: 0 }
    );

    // Tope de 20 s: si ya tenemos algo, lo dejamos; si no, marcamos denegado
    this.gpsTimeout = setTimeout(() => {
      this.detenerWatch();
      if (!this.gpsInfo) this.gpsEstado = 'denegado';
    }, WATCH_TIMEOUT_MS);
  }

  private onPosicion(pos: GeolocationPosition): void {
    const { latitude: lat, longitude: lon, accuracy: precision } = pos.coords;

    // Solo actualizar si la lectura actual mejora la anterior
    const esLaMejor = !this.gpsInfo || precision < this.gpsInfo.precision;
    if (!esLaMejor) return;

    const prevDireccion = this.gpsInfo?.direccion ?? '';
    this.gpsInfo = {
      lat, lon, precision,
      direccion: prevDireccion || `${lat.toFixed(5)}, ${lon.toFixed(5)}`,
    };
    this.gpsEstado = precision <= PRECISION_OBJETIVO_M ? 'ok' : 'refinando';

    // Geocodificación: solo si no hicimos una o el punto se movió >80 m
    const dist = this.geocodePos ? this.haversineM(lat, lon, this.geocodePos.lat, this.geocodePos.lon) : Infinity;
    if (!this.geocodePos || dist > 80) {
      this.geocodePos = { lat, lon };
      this.svc.reverseGeocode(lat, lon).subscribe((dir) => {
        if (this.gpsInfo) this.gpsInfo = { ...this.gpsInfo, direccion: dir };
      });
    }

    // Alcanzamos el objetivo → detenemos el watch
    if (precision <= PRECISION_OBJETIVO_M) {
      this.detenerWatch();
    }
  }

  private detenerWatch(): void {
    if (this.gpsWatchId !== null) {
      navigator.geolocation.clearWatch(this.gpsWatchId);
      this.gpsWatchId = null;
    }
    if (this.gpsTimeout !== null) {
      clearTimeout(this.gpsTimeout);
      this.gpsTimeout = null;
    }
    // Si quedó en refinando y ya tenemos posición, lo damos como ok
    if (this.gpsEstado === 'refinando' && this.gpsInfo) {
      this.gpsEstado = 'ok';
    }
  }

  reintentarGps(): void {
    this.detenerWatch();
    this.gpsInfo   = null;
    this.iniciarGps();
  }

  get gpsPrecisionClase(): string {
    if (!this.gpsInfo) return '';
    if (this.gpsInfo.precision <= 30)  return 'prec-alta';
    if (this.gpsInfo.precision <= 100) return 'prec-media';
    return 'prec-baja';
  }

  // Distancia en metros entre dos coords (Haversine simplificado)
  private haversineM(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6_371_000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) ** 2
      + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }
}

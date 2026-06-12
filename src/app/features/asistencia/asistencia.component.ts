import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { AsistenciaService, EstadoHoyDto } from '../../core/services/asistencia.service';

type PasoMarca = 'cargando' | 'listo' | 'marcando' | 'exito' | 'error_empleado' | 'error';
type GpsEstado = 'solicitando' | 'ok' | 'denegado' | 'sin_soporte';

interface GpsInfo {
  lat:       number;
  lon:       number;
  precision: number;
  direccion: string;
}

@Component({
  selector: 'app-asistencia',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './asistencia.component.html',
  styleUrls: ['./asistencia.component.css']
})
export class AsistenciaComponent implements OnInit, OnDestroy {

  paso: PasoMarca  = 'cargando';
  estado: EstadoHoyDto | null = null;
  ultimaMarca: string | null = null;
  ultimoTipo:  string | null = null;
  errorMsg = '';

  // GPS independiente del flujo de marca
  gpsEstado: GpsEstado = 'solicitando';
  gpsInfo:   GpsInfo | null = null;

  horaActual  = '';
  fechaActual = '';

  private relojInterval: ReturnType<typeof setInterval> | null = null;

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
  }

  // ── Reloj ──────────────────────────────────────────────────────────────────

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

  // ── Asistencia ─────────────────────────────────────────────────────────────

  private cargarEstado(): void {
    this.paso = 'cargando';
    this.svc.getEstadoHoy().subscribe({
      next: (est) => {
        this.estado = est;
        this.paso   = 'listo';
      },
      error: (err) => {
        const detail = err?.error?.detail ?? '';
        if (err.status === 404 || detail.includes('Empleado')) {
          this.paso = 'error_empleado';
        } else {
          this.errorMsg = 'No se pudo conectar al servidor.';
          this.paso = 'error';
        }
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

  reintentar(): void {
    this.cargarEstado();
  }

  volver(): void {
    this.router.navigate(['/home']);
  }

  // ── GPS ────────────────────────────────────────────────────────────────────

  private iniciarGps(): void {
    if (!navigator.geolocation) {
      this.gpsEstado = 'sin_soporte';
      return;
    }

    this.gpsEstado = 'solicitando';

    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const lat       = pos.coords.latitude;
        const lon       = pos.coords.longitude;
        const precision = pos.coords.accuracy;

        // Muestra coordenadas inmediatamente, luego enriquece con dirección
        this.gpsInfo   = { lat, lon, precision, direccion: `${lat.toFixed(5)}, ${lon.toFixed(5)}` };
        this.gpsEstado = 'ok';

        this.svc.reverseGeocode(lat, lon).subscribe((dir) => {
          if (this.gpsInfo) this.gpsInfo = { ...this.gpsInfo, direccion: dir };
        });
      },
      () => {
        this.gpsEstado = 'denegado';
        this.gpsInfo   = null;
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
    );
  }

  reintentarGps(): void {
    this.gpsInfo   = null;
    this.iniciarGps();
  }
}

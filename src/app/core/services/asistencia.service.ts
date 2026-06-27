import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, of } from 'rxjs';
import { map, catchError } from 'rxjs/operators';
import { environment } from '../../../environments/environment';

export interface EstadoHoyDto {
  tiene_entrada: boolean;
  tiene_salida: boolean;
  tiene_foto_base: boolean;
  jornada_completa: boolean;
  entrada_hora: string | null;
  salida_hora: string | null;
  tiene_inicio_almuerzo: boolean;
  tiene_fin_almuerzo: boolean;
  inicio_almuerzo_hora: string | null;
  fin_almuerzo_hora: string | null;
  en_almuerzo: boolean;
}

export interface MarcarResponse {
  registro_id: string;
  status: string;
  score: number;
  motivo: string;
  timestamp: string;
  gps_guardado: boolean;
  foto_url: string | null;
  resultado_ia: string;
}

export interface DiaSemanalDto {
  fecha: string;
  label: string;
  es_hoy: boolean;
  minutos_trabajados: number | null;
  entrada_hora: string | null;
  salida_hora: string | null;
  llego_tarde: boolean;
  minutos_tarde: number | null;
  es_excepcion: boolean;
}

export interface ResumenSemanalDto {
  semana_inicio: string;
  meta_horas: number;
  minutos_trabajados_semana: number;
  dias_trabajados: number;
  promedio_min_diario: number;
  puntualidad_pct: number | null;
  dias: DiaSemanalDto[];
}

export interface TurnoDto {
  id: string;
  nombre: string;
  hora_entrada: string;
  hora_salida: string;
  duracion_almuerzo_minutos: number;
  tolerancia_minutos: number;
  horas_netas: number;
}

export interface TurnoAsignacionDto {
  id:              string;
  empleado_id:     string;
  nombre_empleado: string;
  cargo:           string;
  turno_id:        string;
  turno_nombre:    string;
  hora_entrada:    string;
  hora_salida:     string;
  horas_netas:     number;
  fecha_desde:     string | null;
  fecha_hasta:     string | null;
}

export interface CrearTurnoIn {
  nombre: string;
  hora_entrada: string;
  hora_salida: string;
  duracion_almuerzo_minutos: number;
  tolerancia_minutos: number;
}

export interface AsignarTurnoIn {
  empleado_id: string;
  turno_id: string;
  fecha_desde?: string;
  fecha_hasta?: string;
}

@Injectable({ providedIn: 'root' })
export class AsistenciaService {
  private readonly api = environment.apiUrl;

  constructor(private http: HttpClient) {}

  getEstadoHoy(): Observable<EstadoHoyDto> {
    return this.http.get<EstadoHoyDto>(`${this.api}/asistencia/estado-hoy`);
  }

  marcar(
    tipo: 'entrada' | 'salida',
    coords?: { lat: number; lon: number; precision: number }
  ): Observable<MarcarResponse> {
    const uuidCliente = crypto.randomUUID();
    return this.http.post<MarcarResponse>(`${this.api}/asistencia/marcar`, {
      tipo,
      uuid_cliente: uuidCliente,
      ...(coords && {
        latitud:     coords.lat,
        longitud:    coords.lon,
        precision_m: coords.precision,
      }),
    });
  }

  getMiResumenSemanal(): Observable<ResumenSemanalDto> {
    return this.http.get<ResumenSemanalDto>(`${this.api}/asistencia/mi-resumen-semanal`);
  }

  getTurnos(): Observable<TurnoDto[]> {
    return this.http.get<TurnoDto[]>(`${this.api}/asistencia/turnos`);
  }

  crearTurno(body: CrearTurnoIn): Observable<{ ok: boolean; id: string }> {
    return this.http.post<{ ok: boolean; id: string }>(`${this.api}/asistencia/turnos`, body);
  }

  asignarTurno(body: AsignarTurnoIn): Observable<{ ok: boolean; id: string }> {
    return this.http.post<{ ok: boolean; id: string }>(`${this.api}/asistencia/turno-empleado`, body);
  }

  getTurnoAsignaciones(): Observable<TurnoAsignacionDto[]> {
    return this.http.get<TurnoAsignacionDto[]>(`${this.api}/asistencia/turno-empleado`);
  }

  reverseGeocode(lat: number, lon: number): Observable<string> {
    const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&accept-language=es`;
    return this.http.get<any>(url).pipe(
      map((r) => {
        const a = r?.address ?? {};
        const partes = [
          a.road ?? a.pedestrian ?? a.footway,
          a.suburb ?? a.neighbourhood ?? a.city_district ?? a.quarter,
          a.city   ?? a.town ?? a.village ?? a.municipality,
        ].filter(Boolean);
        return partes.length ? partes.join(', ') : `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
      }),
      catchError(() => of(`${lat.toFixed(5)}, ${lon.toFixed(5)}`))
    );
  }
}

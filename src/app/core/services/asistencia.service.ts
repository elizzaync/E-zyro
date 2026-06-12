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

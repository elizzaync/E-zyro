import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
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

  marcar(tipo: 'entrada' | 'salida'): Observable<MarcarResponse> {
    const uuidCliente = crypto.randomUUID();
    return this.http.post<MarcarResponse>(`${this.api}/asistencia/marcar`, {
      tipo,
      uuid_cliente: uuidCliente,
    });
  }
}

import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface CalibracionOut {
  id: string;
  equipo_id: string;
  equipo_nombre: string | null;
  fecha_ultima: string | null;
  fecha_proxima: string | null;
  empresa_responsable: string | null;
  certificado_url: string | null;
  observacion: string | null;
  total_eventos: number;
}

export interface EventoOut {
  id: string;
  equipo_id: string;
  equipo_nombre: string | null;
  fecha_realizada: string | null;
  periodicidad_meses: number | null;
  fecha_proxima: string | null;
  realizada_por: string | null;
  empresa_responsable: string | null;
  numero_certificado: string | null;
  resultado: string | null;
  certificado_url: string | null;
  observacion: string | null;
}

export interface EventoIn {
  equipo_id: string;
  fecha_realizada: string;
  periodicidad_meses?: number | null;
  fecha_proxima?: string | null;
  realizada_por?: string | null;
  empresa_responsable?: string | null;
  numero_certificado?: string | null;
  resultado?: string | null;
  observacion?: string | null;
}

@Injectable({ providedIn: 'root' })
export class CalibracionesService {
  private http = inject(HttpClient);
  private api  = environment.apiUrl;

  listar(porVencer = false): Observable<CalibracionOut[]> {
    const q = porVencer ? '?por_vencer=true' : '';
    return this.http.get<CalibracionOut[]>(`${this.api}/calibraciones${q}`);
  }

  listarEventos(equipoId: string): Observable<EventoOut[]> {
    return this.http.get<EventoOut[]>(`${this.api}/calibraciones/eventos?equipo_id=${equipoId}`);
  }

  crearEvento(body: EventoIn): Observable<EventoOut> {
    return this.http.post<EventoOut>(`${this.api}/calibraciones/eventos`, body);
  }

  subirCertificado(eventoId: string, archivo_base64: string, extension = 'pdf'): Observable<EventoOut> {
    return this.http.post<EventoOut>(`${this.api}/calibraciones/eventos/${eventoId}/certificado`, { archivo_base64, extension });
  }

  eliminarEvento(eventoId: string): Observable<void> {
    return this.http.delete<void>(`${this.api}/calibraciones/eventos/${eventoId}`);
  }

}

import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface Formato {
  id: string;
  nombre: string;
  tipo_formato: string | null;
  version_actual: number;
  archivo_url: string | null;
  nombre_archivo: string | null;
  actualizado_por_nombre: string | null;
  created_at: string | null;
  updated_at: string | null;
  total_versiones: number;
}

export interface FormatoVersion {
  id: string;
  numero_version: number;
  archivo_url: string;
  nombre_archivo: string | null;
  tamano_bytes: number | null;
  nota: string | null;
  origen: string;
  subido_por_nombre: string | null;
  created_at: string | null;
  es_vigente: boolean;
}

export interface CrearFormatoPayload {
  nombre: string;
  tipo_formato?: string | null;
  nota?: string | null;
  archivo_base64: string;
  archivo_nombre?: string | null;
}

export interface ActualizarFormatoPayload {
  nombre?: string | null;
  tipo_formato?: string | null;
  nota?: string | null;
  archivo_base64?: string | null;
  archivo_nombre?: string | null;
}

@Injectable({ providedIn: 'root' })
export class FormatosService {
  private http = inject(HttpClient);
  private api  = environment.apiUrl;

  listar(filtros: { q?: string; tipo?: string } = {}): Observable<Formato[]> {
    let params = new HttpParams();
    if (filtros.q)    params = params.set('q', filtros.q);
    if (filtros.tipo) params = params.set('tipo', filtros.tipo);
    return this.http.get<Formato[]>(`${this.api}/formatos`, { params });
  }

  versiones(id: string): Observable<FormatoVersion[]> {
    return this.http.get<FormatoVersion[]>(`${this.api}/formatos/${id}/versiones`);
  }

  /** Devuelve la URL del PDF registrando la descarga en auditoría. */
  enlace(id: string, version?: number): Observable<{ url: string; version: number; nombre_archivo: string | null }> {
    let params = new HttpParams();
    if (version) params = params.set('version', version);
    return this.http.get<{ url: string; version: number; nombre_archivo: string | null }>(
      `${this.api}/formatos/${id}/enlace`, { params });
  }

  crear(body: CrearFormatoPayload): Observable<Formato> {
    return this.http.post<Formato>(`${this.api}/formatos`, body);
  }

  actualizar(id: string, body: ActualizarFormatoPayload): Observable<Formato> {
    return this.http.put<Formato>(`${this.api}/formatos/${id}`, body);
  }
}

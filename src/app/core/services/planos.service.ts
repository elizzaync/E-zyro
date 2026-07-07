import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface CarpetaOut {
  id: string;
  nombre: string;
  padre_id: string | null;
  proyecto_id: string | null;
  sub_carpetas: number;
  planos: number;
  created_at: string | null;
}

export interface VersionOut {
  id: string;
  version: string;
  url: string;
  formato: string | null;
  bytes: number | null;
  fecha: string | null;
  es_activa: boolean;
  subido_por: string | null;
}

export interface PlanoOut {
  id: string;
  nombre: string;
  disciplina: string | null;
  descripcion: string | null;
  carpeta_id: string | null;
  proyecto_id: string | null;
  url: string | null;
  formato: string | null;
  bytes: number | null;
  version_activa: string | null;
  num_versiones: number;
  created_at: string | null;
}

export interface PlanoDetalleOut extends PlanoOut {
  versiones: VersionOut[];
}

@Injectable({ providedIn: 'root' })
export class PlanosService {
  private http = inject(HttpClient);
  private base = `${environment.apiUrl}/planos`;

  listarCarpetas(padreId = '', proyectoId = ''): Observable<CarpetaOut[]> {
    let params = new HttpParams();
    if (padreId) params = params.set('padre_id', padreId);
    if (proyectoId) params = params.set('proyecto_id', proyectoId);
    return this.http.get<CarpetaOut[]>(`${this.base}/carpetas`, { params });
  }

  crearCarpeta(nombre: string, padreId?: string): Observable<CarpetaOut> {
    return this.http.post<CarpetaOut>(`${this.base}/carpetas`, {
      nombre,
      padre_id: padreId || null,
    });
  }

  renombrarCarpeta(id: string, nombre: string): Observable<CarpetaOut> {
    return this.http.patch<CarpetaOut>(`${this.base}/carpetas/${id}`, { nombre });
  }

  eliminarCarpeta(id: string): Observable<void> {
    return this.http.delete<void>(`${this.base}/carpetas/${id}`);
  }

  listarPlanos(carpetaId = '', q = ''): Observable<PlanoOut[]> {
    let params = new HttpParams();
    if (carpetaId) params = params.set('carpeta_id', carpetaId);
    if (q) params = params.set('q', q);
    return this.http.get<PlanoOut[]>(this.base, { params });
  }

  crearPlano(body: {
    nombre: string;
    archivo_base64: string;
    filename: string;
    disciplina?: string;
    descripcion?: string;
    carpeta_id?: string;
  }): Observable<PlanoDetalleOut> {
    return this.http.post<PlanoDetalleOut>(this.base, body);
  }

  detallePlano(id: string): Observable<PlanoDetalleOut> {
    return this.http.get<PlanoDetalleOut>(`${this.base}/${id}`);
  }

  subirVersion(planoId: string, body: {
    archivo_base64: string;
    filename: string;
    version?: string;
  }): Observable<PlanoDetalleOut> {
    return this.http.post<PlanoDetalleOut>(`${this.base}/${planoId}/versiones`, body);
  }

  eliminarPlano(id: string): Observable<void> {
    return this.http.delete<void>(`${this.base}/${id}`);
  }

  moverPlano(id: string, carpetaId: string | null): Observable<PlanoOut> {
    return this.http.patch<PlanoOut>(`${this.base}/${id}/mover`, { carpeta_id: carpetaId });
  }

  formatBytes(bytes: number | null): string {
    if (!bytes) return '—';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
}

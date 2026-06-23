import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export type TipoDocSst = 'homologacion' | 'ats' | 'petar';
export type EstadoDocSst = 'vigente' | 'por_vencer' | 'vencida' | 'sin_fecha';

export interface DocumentoSst {
  id: string;
  tipo: string;
  titulo: string;
  cliente_id: string | null;
  cliente_nombre: string | null;
  entidad_emisora: string | null;
  codigo: string | null;
  fecha_emision: string | null;
  fecha_vencimiento: string | null;
  estado: EstadoDocSst;
  dias_para_vencer: number | null;
  archivo_url: string | null;
  nombre_archivo: string | null;
  formato: string | null;
  observaciones: string | null;
  created_at: string | null;
}

export interface CrearDocSstPayload {
  titulo: string;
  tipo: TipoDocSst;
  cliente_id?: string | null;
  entidad_emisora?: string | null;
  codigo?: string | null;
  fecha_emision?: string | null;
  fecha_vencimiento?: string | null;
  observaciones?: string | null;
  archivo_base64?: string | null;
  archivo_nombre?: string | null;
}

@Injectable({ providedIn: 'root' })
export class DocumentosSstService {
  private http = inject(HttpClient);
  private api  = environment.apiUrl;

  listar(filtros: { tipo?: string; estado?: string; q?: string; cliente_id?: string } = {}): Observable<DocumentoSst[]> {
    let params = new HttpParams();
    if (filtros.tipo)       params = params.set('tipo', filtros.tipo);
    if (filtros.estado)     params = params.set('estado', filtros.estado);
    if (filtros.q)          params = params.set('q', filtros.q);
    if (filtros.cliente_id) params = params.set('cliente_id', filtros.cliente_id);
    return this.http.get<DocumentoSst[]>(`${this.api}/documentos-sst`, { params });
  }

  crear(body: CrearDocSstPayload): Observable<DocumentoSst> {
    return this.http.post<DocumentoSst>(`${this.api}/documentos-sst`, body);
  }

  editar(id: string, body: Partial<CrearDocSstPayload>): Observable<DocumentoSst> {
    return this.http.put<DocumentoSst>(`${this.api}/documentos-sst/${id}`, body);
  }

  eliminar(id: string): Observable<void> {
    return this.http.delete<void>(`${this.api}/documentos-sst/${id}`);
  }
}

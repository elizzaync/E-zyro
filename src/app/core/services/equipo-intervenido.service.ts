import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface EquipoIntervenidoFiltros {
  clienteId?: string;
  proyectoId?: string;
  estado?: string;
  ubicacionId?: string;
  zonaId?: string;
  areaId?: string;
  activo?: boolean;
}

@Injectable({ providedIn: 'root' })
export class EquipoIntervenidoService {
  private http = inject(HttpClient);
  private readonly api = environment.apiUrl;

  listar(filtros?: EquipoIntervenidoFiltros): Observable<any[]> {
    let p = new HttpParams();
    if (filtros?.clienteId)   p = p.set('cliente_id', filtros.clienteId);
    if (filtros?.proyectoId)  p = p.set('proyecto_id', filtros.proyectoId);
    if (filtros?.estado)      p = p.set('estado', filtros.estado);
    if (filtros?.ubicacionId) p = p.set('ubicacion_id', filtros.ubicacionId);
    if (filtros?.zonaId)      p = p.set('zona_id', filtros.zonaId);
    if (filtros?.areaId)      p = p.set('area_id', filtros.areaId);
    if (filtros?.activo !== undefined) p = p.set('activo', String(filtros.activo));
    return this.http.get<any[]>(`${this.api}/equipos-intervenidos`, { params: p });
  }

  obtener(id: string): Observable<any> {
    return this.http.get<any>(`${this.api}/equipos-intervenidos/${id}`);
  }

  crear(body: any): Observable<any> {
    return this.http.post<any>(`${this.api}/equipos-intervenidos`, body);
  }

  actualizar(id: string, body: any): Observable<any> {
    return this.http.patch<any>(`${this.api}/equipos-intervenidos/${id}`, body);
  }

  eliminar(id: string): Observable<any> {
    return this.http.delete<any>(`${this.api}/equipos-intervenidos/${id}`);
  }

  listarMantenimientos(id: string): Observable<any[]> {
    return this.http.get<any[]>(`${this.api}/equipos-intervenidos/${id}/mantenimientos`);
  }
}

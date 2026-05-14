import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, of } from 'rxjs';
import { environment } from '../../../environments/environment';
export interface MaterialBusqueda {
  id: string;
  nombre: string;
  unidad: string;
  stock: number;
}

@Injectable({ providedIn: 'root' })
export class OperacionesService {
  private http = inject(HttpClient);
  private readonly api = 'https://e-zyro-production.up.railway.app/api';

  getDashboardData(): Observable<any> {
    return this.http.get(`${this.api}/operaciones/dashboard`);
  }

  getDetalleServicio(id: string): Observable<any> {
    return this.http.get(`${this.api}/operaciones/servicio/${id}`);
  }

  actualizarEstado(psId: string, estado: string): Observable<any> {
    return this.http.patch(`${this.api}/operaciones/servicio/${psId}/estado`, { estado });
  }

  toggleProcedimiento(procId: string, estado: string): Observable<any> {
    return this.http.patch(`${this.api}/operaciones/procedimiento/${procId}/estado`, { estado });
  }

  subirEvidencia(procId: string, formData: FormData): Observable<any> {
    return this.http.post(`${this.api}/operaciones/procedimiento/${procId}/evidencia`, formData);
  }

  buscarMateriales(q: string): Observable<MaterialBusqueda[]> {
    if (!q || q.length < 2) return of([]);
    const params = new HttpParams().set('q', q);
    return this.http.get<MaterialBusqueda[]>(`${this.api}/operaciones/materiales/buscar`, { params });
  }

  solicitarMaterial(psId: string, body: object): Observable<any> {
    return this.http.post(`${this.api}/operaciones/servicio/${psId}/requerimiento`, body);
  }

  actualizarRequerimientoDetalle(rdId: string, body: object): Observable<any> {
    return this.http.patch(`${this.api}/operaciones/requerimiento-detalle/${rdId}`, body);
  }

  agregarNota(psId: string, body: { descripcion: string }): Observable<any> {
    return this.http.post(`${this.api}/operaciones/servicio/${psId}/nota`, body);
  }
}

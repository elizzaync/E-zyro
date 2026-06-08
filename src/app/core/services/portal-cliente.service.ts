import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class PortalClienteService {
  private http   = inject(HttpClient);
  private base   = `${environment.apiUrl}/portal-cliente`;

  getDashboard(): Observable<any> {
    return this.http.get(`${this.base}/dashboard`);
  }

  getProyectos(): Observable<any[]> {
    return this.http.get<any[]>(`${this.base}/proyectos`);
  }

  getProyectoDetalle(id: string): Observable<any> {
    return this.http.get(`${this.base}/proyecto/${id}/detalles`);
  }

  getDocumentos(): Observable<any[]> {
    return this.http.get<any[]>(`${this.base}/documentos`);
  }
}

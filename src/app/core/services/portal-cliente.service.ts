import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class PortalClienteService {
  private http = inject(HttpClient);
  private base = `${environment.apiUrl}/portal-cliente`;

  getDashboard(): Observable<any> {
    return this.http.get(`${this.base}/dashboard`);
  }

  getKpis(): Observable<any> {
    return this.http.get(`${this.base}/dashboard/kpis`);
  }

  getHistorial(): Observable<any[]> {
    return this.http.get<any[]>(`${this.base}/equipos/historial`);
  }

  getMantenimientoDetalle(id: string): Observable<any> {
    return this.http.get(`${this.base}/mantenimiento/${id}/detalles`);
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

  getPortalPerfil(): Observable<any> {
    return this.http.get(`${this.base}/perfil`);
  }

  // ── Soporte técnico (tickets — reusa ticket_soporte de Gestión TIC) ──

  getTickets(): Observable<any[]> {
    return this.http.get<any[]>(`${this.base}/tickets`);
  }

  crearTicket(body: { titulo: string; descripcion: string; categoria: string; prioridad: string }): Observable<any> {
    return this.http.post(`${this.base}/tickets`, body);
  }
}

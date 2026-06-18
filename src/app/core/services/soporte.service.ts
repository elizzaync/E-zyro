import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface TicketSoporteDto {
  id: string;
  codigo: string;
  titulo: string;
  descripcion: string;
  categoria: string;
  prioridad: string;
  estado: string;
  pantalla?: string;
  dispositivo?: string;
  adjunto_url?: string;
  respuesta_ti?: string;
  reportado_por: string;
  reportante_nombre: string;
  atendido_por?: string;
  atendido_por_nombre?: string;
  creado_en: string;
  actualizado_en?: string;
}

export interface ActividadDto {
  id: string;
  tipo: string;
  texto?: string;
  adjunto_url?: string;
  es_solucion: boolean;
  version_solucion?: number;
  autor_id: string;
  autor_nombre: string;
  creado_en: string;
}

export interface SesionDto {
  id: string;
  usuario_id: string;
  usuario_nombre: string;
  dispositivo?: string;
  ip?: string;
  activa: boolean;
  fecha_expiracion: string;
  fecha_cierre?: string;
  created_at: string;
}

export interface AuditoriaDto {
  id: string;
  usuario_id?: string;
  usuario_nombre?: string;
  tabla_afectada: string;
  registro_id?: string;
  accion: string;
  modulo?: string;
  descripcion?: string;
  ip?: string;
  fecha: string;
  datos_anteriores?: any;
  datos_nuevos?: any;
}

@Injectable({ providedIn: 'root' })
export class SoporteService {
  private http = inject(HttpClient);
  private base = environment.apiUrl;

  getTickets(params?: { estado?: string; alcance?: string }): Observable<TicketSoporteDto[]> {
    let p = new HttpParams();
    if (params?.estado) p = p.set('estado', params.estado);
    if (params?.alcance) p = p.set('alcance', params.alcance);
    return this.http.get<TicketSoporteDto[]>(`${this.base}/soporte`, { params: p });
  }

  getTicket(id: string): Observable<TicketSoporteDto> {
    return this.http.get<TicketSoporteDto>(`${this.base}/soporte/${id}`);
  }

  gestionarTicket(id: string, body: { estado?: string; respuesta_ti?: string }): Observable<TicketSoporteDto> {
    return this.http.patch<TicketSoporteDto>(`${this.base}/soporte/${id}`, body);
  }

  tomarTicket(id: string): Observable<TicketSoporteDto> {
    return this.http.post<TicketSoporteDto>(`${this.base}/soporte/${id}/tomar`, {});
  }

  getActividades(ticketId: string): Observable<ActividadDto[]> {
    return this.http.get<ActividadDto[]>(`${this.base}/soporte/${ticketId}/actividades`);
  }

  crearActividad(ticketId: string, body: { tipo?: string; texto?: string; es_solucion?: boolean }): Observable<ActividadDto> {
    return this.http.post<ActividadDto>(`${this.base}/soporte/${ticketId}/actividades`, body);
  }

  getSesiones(params?: {
    usuario_id?: string;
    fecha_desde?: string;
    fecha_hasta?: string;
    page?: number;
    page_size?: number;
  }): Observable<SesionDto[]> {
    let p = new HttpParams();
    if (params?.usuario_id) p = p.set('usuario_id', params.usuario_id);
    if (params?.fecha_desde) p = p.set('fecha_desde', params.fecha_desde);
    if (params?.fecha_hasta) p = p.set('fecha_hasta', params.fecha_hasta);
    if (params?.page != null) p = p.set('page', params.page.toString());
    if (params?.page_size != null) p = p.set('page_size', params.page_size.toString());
    return this.http.get<SesionDto[]>(`${this.base}/soporte/monitoreo/sesiones`, { params: p });
  }

  getAuditoria(params?: {
    modulo?: string;
    accion?: string;
    q?: string;
    fecha_desde?: string;
    fecha_hasta?: string;
    usuario_id?: string;
    buscar_usuario?: string;
    page?: number;
    page_size?: number;
  }): Observable<AuditoriaDto[]> {
    let p = new HttpParams();
    if (params?.modulo) p = p.set('modulo', params.modulo);
    if (params?.accion) p = p.set('accion', params.accion);
    if (params?.q) p = p.set('q', params.q);
    if (params?.fecha_desde) p = p.set('fecha_desde', params.fecha_desde);
    if (params?.fecha_hasta) p = p.set('fecha_hasta', params.fecha_hasta);
    if (params?.usuario_id) p = p.set('usuario_id', params.usuario_id);
    if (params?.buscar_usuario) p = p.set('buscar_usuario', params.buscar_usuario);
    if (params?.page != null) p = p.set('page', params.page.toString());
    if (params?.page_size != null) p = p.set('page_size', params.page_size.toString());
    return this.http.get<AuditoriaDto[]>(`${this.base}/auditoria`, { params: p });
  }
}

import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface UsuarioPrivilegio {
  id: string;
  nombre: string;
  apellido: string;
  username: string;
  rol: string | null;
  activo: boolean;
  permisos_directos: number;
}

export interface PermisoDetalle {
  id: string;
  modulo: string;
  accion: string;
  descripcion: string | null;
  via_rol: boolean;
  directo: boolean;
}

@Injectable({ providedIn: 'root' })
export class PrivilegiosService {
  private http   = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}/privilegios`;

  private headers(): HttpHeaders {
    return new HttpHeaders({ Authorization: `Bearer ${localStorage.getItem('ezyro_token')}` });
  }

  listarUsuarios(): Observable<UsuarioPrivilegio[]> {
    return this.http.get<UsuarioPrivilegio[]>(`${this.apiUrl}/usuarios`, { headers: this.headers() });
  }

  permisosUsuario(usuarioId: string): Observable<PermisoDetalle[]> {
    return this.http.get<PermisoDetalle[]>(`${this.apiUrl}/usuarios/${usuarioId}/permisos`, { headers: this.headers() });
  }

  otorgarPermiso(usuarioId: string, permisoId: string): Observable<any> {
    return this.http.post(`${this.apiUrl}/usuarios/${usuarioId}/permisos`, { permiso_id: permisoId }, { headers: this.headers() });
  }

  revocarPermiso(usuarioId: string, permisoId: string): Observable<any> {
    return this.http.delete(`${this.apiUrl}/usuarios/${usuarioId}/permisos/${permisoId}`, { headers: this.headers() });
  }

  otorgarTodos(usuarioId: string): Observable<any> {
    return this.http.post(`${this.apiUrl}/usuarios/${usuarioId}/permisos/todos`, {}, { headers: this.headers() });
  }

  revocarTodos(usuarioId: string): Observable<any> {
    return this.http.delete(`${this.apiUrl}/usuarios/${usuarioId}/permisos`, { headers: this.headers() });
  }
}

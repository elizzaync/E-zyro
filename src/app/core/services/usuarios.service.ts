import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface UsuarioOut {
  id: string;
  nombre: string;
  apellido: string;
  email: string;
  username: string;
  rol: string | null;
  rol_id: string | null;
  activo: boolean;
  tiene_ficha: boolean;
}

export interface RolOut {
  id: string;
  nombre: string;
}

export interface CrearUsuarioIn {
  nombre: string;
  apellido: string;
  email: string;
  username: string;
  password: string;
  rol_id: string;
  telefono?: string;
  crear_ficha: boolean;
  cargo?: string;
  area?: string;
  tipo?: string;
  codigo?: string;
  tipo_documento?: string;
  numero_documento?: string;
  sexo?: string;
  fecha_ingreso?: string;
}

@Injectable({ providedIn: 'root' })
export class UsuariosService {
  private http = inject(HttpClient);
  private api  = environment.apiUrl;

  listar(): Observable<UsuarioOut[]> {
    return this.http.get<UsuarioOut[]>(`${this.api}/usuarios`);
  }

  getRoles(): Observable<RolOut[]> {
    return this.http.get<RolOut[]>(`${this.api}/usuarios/roles`);
  }

  crear(body: CrearUsuarioIn): Observable<UsuarioOut> {
    return this.http.post<UsuarioOut>(`${this.api}/usuarios`, body);
  }

  cambiarRol(id: string, rol_id: string): Observable<UsuarioOut> {
    return this.http.put<UsuarioOut>(`${this.api}/usuarios/${id}/rol`, { rol_id });
  }

  cambiarActivo(id: string, activo: boolean): Observable<UsuarioOut> {
    return this.http.put<UsuarioOut>(`${this.api}/usuarios/${id}/activo`, { activo });
  }

  resetPassword(id: string, password: string): Observable<{ status: string; mensaje: string }> {
    return this.http.post<{ status: string; mensaje: string }>(`${this.api}/usuarios/${id}/reset-password`, { password });
  }
}

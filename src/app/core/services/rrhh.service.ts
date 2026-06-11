import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface EmpleadoLegajoDto {
  id: string;
  nombreCompleto: string;
  cargo: string;
  area: string;
  estado: 'Activo' | 'Inactivo';
  documentosCount: number;
  iniciales: string;
  fotoUrl: string;
  ultimaActualizacion: string;
}

export interface DocumentoDto {
  id: string;
  tipo: string;
  nombre: string;
  url_archivo: string;
  fecha_emision: string | null;
  created_at: string | null;
  firmado: boolean;
  firmado_en: string | null;
}

export interface EmpleadoInfoDto {
  id: string;
  usuarioId: string;
  nombreCompleto: string;
  cargo: string;
  area: string;
  estado: string;
  fotoUrl: string;
  iniciales: string;
  fechaIngreso: string | null;
}

@Injectable({ providedIn: 'root' })
export class RrhhService {
  private readonly api = environment.apiUrl;

  constructor(private http: HttpClient) {}

  getEmpleados(): Observable<{ empleados: EmpleadoLegajoDto[] }> {
    return this.http.get<{ empleados: EmpleadoLegajoDto[] }>(`${this.api}/rrhh/legajo/empleados`);
  }

  getEmpleadoDetalle(empleadoId: string): Observable<{ empleado: EmpleadoInfoDto; documentos: DocumentoDto[] }> {
    return this.http.get<{ empleado: EmpleadoInfoDto; documentos: DocumentoDto[] }>(
      `${this.api}/rrhh/legajo/${empleadoId}`
    );
  }

  subirDocumento(empleadoId: string, form: FormData): Observable<{ id: string; url_archivo: string; mensaje: string }> {
    return this.http.post<any>(`${this.api}/rrhh/legajo/${empleadoId}/documento`, form);
  }

  eliminarDocumento(docId: string): Observable<{ mensaje: string }> {
    return this.http.delete<{ mensaje: string }>(`${this.api}/rrhh/documento/${docId}`);
  }

  firmarDocumento(docId: string): Observable<{ mensaje: string; firmado_en: string }> {
    return this.http.post<any>(`${this.api}/rrhh/documento/${docId}/firmar`, {});
  }

  getMisDocumentosPendientes(): Observable<{ documentos: DocumentoDto[] }> {
    return this.http.get<{ documentos: DocumentoDto[] }>(`${this.api}/rrhh/mis-documentos-pendientes`);
  }

  getMiFirma(): Observable<{ firma: { id: string; url_cloudinary: string; primera_vez: boolean } | null }> {
    return this.http.get<any>(`${this.api}/rrhh/mi-firma`);
  }
}

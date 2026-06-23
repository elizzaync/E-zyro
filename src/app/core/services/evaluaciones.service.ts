import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface DetalleEval {
  id: string;
  criterio_id: string;
  criterio_nombre: string | null;
  peso: number | null;
  puntaje: number;
  comentario: string | null;
}

export interface Evaluacion {
  id: string;
  empleado_id: string;
  empleado_nombre: string | null;
  evaluador_id: string;
  evaluador_nombre: string | null;
  tipo: string;
  periodo: string;
  estado: string;
  fecha: string | null;
  promedio: number | null;
  detalles: DetalleEval[];
}

export interface EmpleadoEval {
  id: string;
  nombre: string | null;
  cargo: string | null;
  area: string | null;
  foto_url: string | null;
}

export interface CriterioEval {
  id: string;
  nombre: string;
  descripcion: string | null;
  peso: number;
  tipo: string;
}

export interface LoteIn {
  tipo: string;
  periodo: string;
  fecha?: string | null;
  empleado_ids: string[];
  todos: boolean;
  criterio_ids: string[];
}

@Injectable({ providedIn: 'root' })
export class EvaluacionesService {
  private http = inject(HttpClient);
  private api  = environment.apiUrl;

  getMisEvaluaciones(): Observable<Evaluacion[]> {
    return this.http.get<Evaluacion[]>(`${this.api}/evaluaciones/mias`);
  }

  getDetalle(id: string): Observable<Evaluacion> {
    return this.http.get<Evaluacion>(`${this.api}/evaluaciones/${id}`);
  }

  getPersonal(): Observable<EmpleadoEval[]> {
    return this.http.get<EmpleadoEval[]>(`${this.api}/personal?solo_activos=true`);
  }

  getCriterios(tipo?: string): Observable<CriterioEval[]> {
    const url = tipo
      ? `${this.api}/evaluaciones/criterios?tipo=${tipo}`
      : `${this.api}/evaluaciones/criterios`;
    return this.http.get<CriterioEval[]>(url);
  }

  crearLote(body: LoteIn): Observable<{ creadas: number; evaluaciones: Evaluacion[] }> {
    return this.http.post<any>(`${this.api}/evaluaciones/lote`, body);
  }

  cambiarEstado(id: string, estado: string): Observable<Evaluacion> {
    return this.http.post<Evaluacion>(`${this.api}/evaluaciones/${id}/estado`, { estado });
  }

  crearCriterio(body: { nombre: string; descripcion?: string; peso: number; tipo: string }): Observable<CriterioEval> {
    return this.http.post<CriterioEval>(`${this.api}/evaluaciones/criterios`, body);
  }

  eliminarCriterio(id: string): Observable<void> {
    return this.http.delete<void>(`${this.api}/evaluaciones/criterios/${id}`);
  }
}

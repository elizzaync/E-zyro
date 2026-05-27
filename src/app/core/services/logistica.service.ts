import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  MaterialLog,
  EquipoHerramienta,
  LogisticaKpis,
} from '../../features/logistica/logistica.models';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICIO DE LOGÍSTICA (INVENTARIO)
// Conectado al backend FastAPI en `/logistica/*`.
// La auditoría se registra automáticamente por el listener global de
// SQLAlchemy en cada INSERT/UPDATE/DELETE (tabla `auditoria`).
// ═══════════════════════════════════════════════════════════════════════════

interface MaterialesListResponse {
  items: MaterialLog[];
  total: number;
  page: number;
  pageSize: number;
}

interface EquiposListResponse {
  items: EquipoHerramienta[];
  total: number;
  page: number;
  pageSize: number;
}

export interface MaterialesFiltros {
  q?: string;
  categoria?: string;
  estado?: 'todos' | 'activos' | 'inactivos' | 'stock_bajo';
  page?: number;
  pageSize?: number;
}

export interface EquiposFiltros {
  q?: string;
  clase?: 'todas' | 'equipo' | 'herramienta';
  estado?: 'todos' | 'operativo' | 'en_mantenimiento' | 'fuera_de_servicio' | 'baja';
  page?: number;
  pageSize?: number;
}

@Injectable({ providedIn: 'root' })
export class LogisticaService {
  private http = inject(HttpClient);
  private readonly api = environment.apiUrl;

  // ─────────────────────────────────────────────────────────────────────────
  // MATERIALES
  // ─────────────────────────────────────────────────────────────────────────

  getMateriales(filtros: MaterialesFiltros = {}): Observable<MaterialLog[]> {
    let params = new HttpParams()
      .set('page',      String(filtros.page ?? 1))
      .set('page_size', String(filtros.pageSize ?? 200));
    if (filtros.q)         params = params.set('q', filtros.q);
    if (filtros.categoria) params = params.set('categoria', filtros.categoria);
    if (filtros.estado)    params = params.set('estado', filtros.estado);
    return this.http
      .get<MaterialesListResponse>(`${this.api}/logistica/materiales`, { params })
      .pipe(map(r => r.items));
  }

  crearMaterial(data: Omit<MaterialLog, 'id'>): Observable<MaterialLog> {
    return this.http.post<MaterialLog>(`${this.api}/logistica/materiales`, data);
  }

  actualizarMaterial(id: string, data: Partial<MaterialLog>): Observable<MaterialLog> {
    return this.http.patch<MaterialLog>(`${this.api}/logistica/materiales/${id}`, data);
  }

  eliminarMaterial(id: string): Observable<void> {
    return this.http.delete<void>(`${this.api}/logistica/materiales/${id}`);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EQUIPOS Y HERRAMIENTAS
  // ─────────────────────────────────────────────────────────────────────────

  getEquipos(filtros: EquiposFiltros = {}): Observable<EquipoHerramienta[]> {
    let params = new HttpParams()
      .set('page',      String(filtros.page ?? 1))
      .set('page_size', String(filtros.pageSize ?? 200));
    if (filtros.q)      params = params.set('q', filtros.q);
    if (filtros.clase)  params = params.set('clase', filtros.clase);
    if (filtros.estado) params = params.set('estado', filtros.estado);
    return this.http
      .get<EquiposListResponse>(`${this.api}/logistica/equipos`, { params })
      .pipe(map(r => r.items));
  }

  crearEquipo(data: Omit<EquipoHerramienta, 'id'>): Observable<EquipoHerramienta> {
    return this.http.post<EquipoHerramienta>(`${this.api}/logistica/equipos`, data);
  }

  actualizarEquipo(id: string, data: Partial<EquipoHerramienta>): Observable<EquipoHerramienta> {
    return this.http.patch<EquipoHerramienta>(`${this.api}/logistica/equipos/${id}`, data);
  }

  eliminarEquipo(id: string): Observable<void> {
    return this.http.delete<void>(`${this.api}/logistica/equipos/${id}`);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // KPIs
  // ─────────────────────────────────────────────────────────────────────────

  getKpis(): Observable<LogisticaKpis> {
    return this.http.get<LogisticaKpis>(`${this.api}/logistica/kpis`);
  }
}

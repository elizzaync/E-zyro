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
  private readonly api = environment.apiUrl;

  getDashboardData(): Observable<any> {
    return this.http.get(`${this.api}/operaciones/dashboard`);
  }

  getProyectos(): Observable<any> {
    return this.http.get<any>(`${this.api}/operaciones/proyectos`);
  }

  getServiciosPorProyecto(proyectoId: string): Observable<any[]> {
    return this.http.get<any[]>(`${this.api}/operaciones/proyecto/${proyectoId}/servicios`);
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

  getBorrador(psId: string): Observable<any> {
    return this.http.get(`${this.api}/operaciones/servicio/${psId}/borrador`);
  }

  agregarItemBorrador(psId: string, body: object): Observable<any> {
    return this.http.post(`${this.api}/operaciones/servicio/${psId}/borrador/item`, body);
  }

  removerItemBorrador(rdId: string): Observable<any> {
    return this.http.delete(`${this.api}/operaciones/borrador-detalle/${rdId}`);
  }

  enviarBorrador(psId: string): Observable<any> {
    return this.http.post(`${this.api}/operaciones/servicio/${psId}/borrador/enviar`, {});
  }

  // ─────────────────────────────────────────────────────────────────────
  // HU-13: Asignación de Personal y Avisos
  // ─────────────────────────────────────────────────────────────────────

  /**
   * Obtiene la lista de técnicos disponibles para asignar a un servicio.
   * GET /operaciones/personal/tecnicos
   */
  getPersonalTecnicos(): Observable<any[]> {
    return this.http.get<any[]>(`${this.api}/operaciones/personal/tecnicos`);
  }

  /**
   * Configura un servicio: asigna el equipo técnico y crea/actualiza el
   * cronograma de procedimientos con sus fechas (para el Diagrama de Gantt).
   *
   * POST /operaciones/servicio/{psId}/configurar
   * Body: { equipo: string[], procedimientos: TareaPayload[] }
   */
  configurarServicio(psId: string, payload: {
    equipo: string[];
    procedimientos: {
      id?: string;
      nombre: string;
      responsable_id: string;
      fecha_inicio: string;
      fecha_fin: string;
    }[];
  }): Observable<any> {
    return this.http.post(`${this.api}/operaciones/servicio/${psId}/configurar`, payload);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Proyectos CRUD
  // ─────────────────────────────────────────────────────────────────────

  getDetalleProyecto(proyectoId: string): Observable<any> {
    return this.http.get(`${this.api}/operaciones/proyecto/${proyectoId}`);
  }

  crearProyecto(payload: object): Observable<any> {
    return this.http.post(`${this.api}/operaciones/proyectos`, payload);
  }

  actualizarProyecto(proyectoId: string, payload: object): Observable<any> {
    return this.http.patch(`${this.api}/operaciones/proyecto/${proyectoId}`, payload);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Clientes
  // ─────────────────────────────────────────────────────────────────────

  getClientes(): Observable<any> {
    return this.http.get(`${this.api}/operaciones/clientes`);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Catálogo de servicios
  // ─────────────────────────────────────────────────────────────────────

  getCatalogoServicios(): Observable<any> {
    return this.http.get(`${this.api}/operaciones/catalogo-servicios`);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Servicios (proyecto_servicio) CRUD
  // ─────────────────────────────────────────────────────────────────────

  crearServicio(proyectoId: string, payload: object): Observable<any> {
    return this.http.post(`${this.api}/operaciones/proyecto/${proyectoId}/servicios`, payload);
  }

  actualizarServicio(servicioId: string, payload: object): Observable<any> {
    return this.http.patch(`${this.api}/operaciones/servicio/${servicioId}`, payload);
  }
}

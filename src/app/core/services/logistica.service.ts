import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  MaterialLog,
  EquipoHerramienta,
  LogisticaKpis,
  CatalogoItem,
  AlmacenItem,
  UnidadItem,
  ModeloItem,
  Requerimiento,
  AprobarItemDecision,
  EntregarPayload,
  TicketCompra,
  EstadoCompra,
  ProcesarCompraPayload,
  Proveedor,
  Salida,
  SalidasKpis,
  RegistrarIngresoPayload,
  Retorno,
  Incidencia, EquipoStockDesglose, CategoriaEquipoItem,
} from '../../features/logistica/logistica.models';

interface RequerimientosListResponse {
  items: Requerimiento[];
  total: number;
  page: number;
  pageSize: number;
}

interface ComprasListResponse {
  items: TicketCompra[];
  total: number;
  page: number;
  pageSize: number;
}

export interface ComprasFiltros {
  estado?: EstadoCompra;
  proyectoId?: string;
  q?: string;
  page?: number;
  pageSize?: number;
}

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

  crearMaterial(data: any): Observable<MaterialLog> {
    return this.http.post<MaterialLog>(`${this.api}/logistica/materiales`, data);
  }

  actualizarMaterial(id: string, data: any): Observable<MaterialLog> {
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

  crearEquipo(data: any): Observable<EquipoHerramienta> {
    return this.http.post<EquipoHerramienta>(`${this.api}/logistica/equipos`, data);
  }

  actualizarEquipo(id: string, data: any): Observable<EquipoHerramienta> {
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

  // ─────────────────────────────────────────────────────────────────────────
  // CATÁLOGOS (selects)
  // ─────────────────────────────────────────────────────────────────────────

  getCategorias(): Observable<CatalogoItem[]> {
    return this.http.get<CatalogoItem[]>(`${this.api}/logistica/categorias`);
  }
  crearCategoria(nombre: string): Observable<CatalogoItem> {
    return this.http.post<CatalogoItem>(`${this.api}/logistica/categorias`, { nombre });
  }

  getAlmacenes(): Observable<AlmacenItem[]> {
    return this.http.get<AlmacenItem[]>(`${this.api}/logistica/almacenes`);
  }
  crearAlmacen(nombre: string, ubicacion?: string): Observable<AlmacenItem> {
    return this.http.post<AlmacenItem>(`${this.api}/logistica/almacenes`, { nombre, ubicacion });
  }

  getUnidades(): Observable<UnidadItem[]> {
    return this.http.get<UnidadItem[]>(`${this.api}/logistica/unidades`);
  }
  crearUnidad(nombre: string, abreviatura?: string): Observable<UnidadItem> {
    return this.http.post<UnidadItem>(`${this.api}/logistica/unidades`, { nombre, abreviatura });
  }

  getTiposEquipo(): Observable<CatalogoItem[]> {
    return this.http.get<CatalogoItem[]>(`${this.api}/logistica/tipos-equipo`);
  }
  crearTipoEquipo(nombre: string): Observable<CatalogoItem> {
    return this.http.post<CatalogoItem>(`${this.api}/logistica/tipos-equipo`, { nombre });
  }

  getCategoriasEquipo(): Observable<CategoriaEquipoItem[]> {
    return this.http.get<CategoriaEquipoItem[]>(`${this.api}/logistica/categorias-equipo`);
  }
  crearCategoriaEquipo(nombre: string): Observable<CatalogoItem> {
    return this.http.post<CatalogoItem>(`${this.api}/logistica/categorias-equipo`, { nombre });
  }
  getProcedimientosTipoEquipo(tipoId: string): Observable<{ tipo_equipo_id: string; nombre: string; procedimientos: any[] }> {
    return this.http.get<any>(`${this.api}/logistica/tipos-equipo/${tipoId}/procedimientos`);
  }
  actualizarProcedimientosTipoEquipo(tipoId: string, procedimientos: { orden: number; nombre: string; descripcion?: string }[]): Observable<any> {
    return this.http.patch<any>(`${this.api}/logistica/tipos-equipo/${tipoId}/procedimientos`, { procedimientos });
  }

  getMarcas(): Observable<CatalogoItem[]> {
    return this.http.get<CatalogoItem[]>(`${this.api}/logistica/marcas`);
  }
  crearMarca(nombre: string): Observable<CatalogoItem> {
    return this.http.post<CatalogoItem>(`${this.api}/logistica/marcas`, { nombre });
  }

  getModelos(marcaId?: string): Observable<ModeloItem[]> {
    let params = new HttpParams();
    if (marcaId) params = params.set('marca_id', marcaId);
    return this.http.get<ModeloItem[]>(`${this.api}/logistica/modelos`, { params });
  }
  crearModelo(nombre: string, marcaId: string): Observable<ModeloItem> {
    return this.http.post<ModeloItem>(`${this.api}/logistica/modelos`, { nombre, marcaId });
  }

  getSiguienteCodigo(tipo: 'material' | 'equipo' | 'herramienta' | 'equipo_tecnologico'): Observable<{ codigo: string }> {
    // equipo_tecnologico comparte prefijo EQ con equipo
    const t = tipo === 'equipo_tecnologico' ? 'equipo' : tipo;
    const params = new HttpParams().set('tipo', t);
    return this.http.get<{ codigo: string }>(`${this.api}/logistica/siguiente-codigo`, { params });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUERIMIENTOS (HU-16)
  // ─────────────────────────────────────────────────────────────────────────

  getRequerimientos(filtros: {
    estado?: string; proyectoId?: string; servicioId?: string; q?: string;
  } = {}): Observable<Requerimiento[]> {
    let params = new HttpParams().set('estado', filtros.estado ?? 'pendiente');
    if (filtros.proyectoId) params = params.set('proyecto_id', filtros.proyectoId);
    if (filtros.servicioId) params = params.set('servicio_id', filtros.servicioId);
    if (filtros.q)          params = params.set('q', filtros.q);
    return this.http
      .get<RequerimientosListResponse>(`${this.api}/logistica/requerimientos`, { params })
      .pipe(map(r => r.items));
  }

  getHistorialRequerimientos(filtros: { proyectoId?: string; servicioId?: string } = {}): Observable<Requerimiento[]> {
    let params = new HttpParams();
    if (filtros.proyectoId) params = params.set('proyecto_id', filtros.proyectoId);
    if (filtros.servicioId) params = params.set('servicio_id', filtros.servicioId);
    return this.http
      .get<RequerimientosListResponse>(`${this.api}/logistica/requerimientos/historial`, { params })
      .pipe(map(r => r.items));
  }

  getRequerimiento(id: string): Observable<Requerimiento> {
    return this.http.get<Requerimiento>(`${this.api}/logistica/requerimientos/${id}`);
  }

  aprobarRequerimiento(id: string, body: {
    almacenId?: string; decisiones?: AprobarItemDecision[]; observacion?: string;
  }): Observable<Requerimiento> {
    return this.http.post<Requerimiento>(`${this.api}/logistica/requerimientos/${id}/aprobar`, body);
  }

  rechazarRequerimiento(id: string, observacion: string): Observable<Requerimiento> {
    return this.http.post<Requerimiento>(`${this.api}/logistica/requerimientos/${id}/rechazar`, { observacion });
  }

  firmarRequerimiento(id: string, recibidoPorId: string, firmaUrl: string): Observable<Requerimiento> {
    return this.http.post<Requerimiento>(`${this.api}/logistica/requerimientos/${id}/firmar`, { recibidoPorId, firmaUrl });
  }

  entregarRequerimiento(id: string, payload: EntregarPayload = {}): Observable<Requerimiento> {
    return this.http.post<Requerimiento>(`${this.api}/logistica/requerimientos/${id}/entregar`, payload);
  }

  bloquearFirma(reqId: string): Observable<{ ok: boolean }> {
    return this.http.post<{ ok: boolean }>(`${this.api}/logistica/requerimientos/${reqId}/bloquear-firma`, {});
  }

  liberarFirma(reqId: string): Observable<{ ok: boolean }> {
    return this.http.delete<{ ok: boolean }>(`${this.api}/logistica/requerimientos/${reqId}/bloquear-firma`);
  }

  getFirmaGuardada(): Observable<{ url: string } | null> {
    return this.http.get<{ url: string } | null>(`${this.api}/permisos/mi-firma`);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPRAS (HU-17)
  // ─────────────────────────────────────────────────────────────────────────

  getProveedores(q?: string): Observable<Proveedor[]> {
    let params = new HttpParams().set('solo_activos', 'true');
    if (q) params = params.set('q', q);
    return this.http.get<Proveedor[]>(`${this.api}/logistica/proveedores`, { params });
  }

  crearProveedor(data: { nombre: string; ruc?: string; contacto?: string; email?: string }): Observable<Proveedor> {
    return this.http.post<Proveedor>(`${this.api}/logistica/proveedores`, data);
  }

  getComprasResumen(): Observable<{ pendiente: number; en_proceso: number; completado: number; cancelado: number }> {
    return this.http.get<{ pendiente: number; en_proceso: number; completado: number; cancelado: number }>(
      `${this.api}/logistica/compras/resumen`
    );
  }

  getTicketsCompra(filtros: ComprasFiltros = {}): Observable<TicketCompra[]> {
    let params = new HttpParams()
      .set('page',      String(filtros.page     ?? 1))
      .set('page_size', String(filtros.pageSize ?? 200));
    if (filtros.estado)     params = params.set('estado',      filtros.estado);
    if (filtros.proyectoId) params = params.set('proyecto_id', filtros.proyectoId);
    if (filtros.q)          params = params.set('q',           filtros.q);
    return this.http
      .get<ComprasListResponse>(`${this.api}/logistica/compras`, { params })
      .pipe(map(r => r.items));
  }

  getTicketCompra(id: string): Observable<TicketCompra> {
    return this.http.get<TicketCompra>(`${this.api}/logistica/compras/${id}`);
  }

  procesarCompra(id: string, payload: ProcesarCompraPayload): Observable<TicketCompra> {
    return this.http.patch<TicketCompra>(`${this.api}/logistica/compras/${id}/procesar`, payload);
  }

  cancelarCompra(id: string, motivo?: string): Observable<TicketCompra> {
    return this.http.post<TicketCompra>(`${this.api}/logistica/compras/${id}/cancelar`, { motivo: motivo ?? null });
  }

  registrarIngreso(ticketId: string, payload: RegistrarIngresoPayload): Observable<TicketCompra> {
    return this.http.post<TicketCompra>(`${this.api}/logistica/compras/${ticketId}/registrar-ingreso`, payload);
  }

  vincularInventario(ticketId: string, itemId: string, payload: import('../../features/logistica/logistica.models').VincularInventarioPayload): Observable<import('../../features/logistica/logistica.models').TicketCompraItem> {
    return this.http.post<import('../../features/logistica/logistica.models').TicketCompraItem>(
      `${this.api}/logistica/compras/${ticketId}/items/${itemId}/vincular-inventario`, payload
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SALIDAS DE MATERIALES (HU-18)
  // ─────────────────────────────────────────────────────────────────────────

  getSalidasKpis(): Observable<SalidasKpis> {
    return this.http.get<SalidasKpis>(`${this.api}/logistica/salidas/kpis`);
  }

  getSalidas(filtros: {
    q?: string;
    proyectoId?: string;
    desde?: string;
    hasta?: string;
    page?: number;
    pageSize?: number;
  } = {}): Observable<{ items: Salida[]; total: number }> {
    let params = new HttpParams()
      .set('page',      String(filtros.page     ?? 1))
      .set('page_size', String(filtros.pageSize ?? 30));
    if (filtros.q)          params = params.set('q',           filtros.q);
    if (filtros.proyectoId) params = params.set('proyecto_id', filtros.proyectoId);
    if (filtros.desde)      params = params.set('desde',       filtros.desde);
    if (filtros.hasta)      params = params.set('hasta',       filtros.hasta);
    return this.http
      .get<{ items: Salida[]; total: number; page: number; pageSize: number }>(
        `${this.api}/logistica/salidas`, { params }
      )
      .pipe(map(r => ({ items: r.items, total: r.total })));
  }

  getIngresos(filtros: {
    q?: string;
    desde?: string;
    hasta?: string;
    page?: number;
    pageSize?: number;
  } = {}): Observable<{ items: import('../../features/logistica/logistica.models').Ingreso[]; total: number }> {
    let params = new HttpParams()
      .set('page',      String(filtros.page     ?? 1))
      .set('page_size', String(filtros.pageSize ?? 30));
    if (filtros.q)     params = params.set('q',     filtros.q);
    if (filtros.desde) params = params.set('desde', filtros.desde);
    if (filtros.hasta) params = params.set('hasta', filtros.hasta);
    return this.http
      .get<{ items: import('../../features/logistica/logistica.models').Ingreso[]; total: number; page: number; pageSize: number }>(
        `${this.api}/logistica/ingresos`, { params }
      )
      .pipe(map(r => ({ items: r.items, total: r.total })));
  }

  // ── Retornos ──────────────────────────────────────────────────────────
  crearRetorno(body: { requerimientoId: string; items: { detalleId: string; cantidadRetornada: number }[]; notaTecnico?: string }): Observable<Retorno> {
    return this.http.post<Retorno>(`${this.api}/logistica/retornos`, body);
  }

  crearRetornoDesdeServicio(body: { proyectoServicioId: string; items: { detalleId: string; cantidadRetornada: number }[]; notaTecnico?: string }): Observable<Retorno> {
    return this.http.post<Retorno>(`${this.api}/logistica/retornos/desde-servicio`, body);
  }

  checkRetornoServicio(servicioId: string): Observable<{ tieneRetorno: boolean; retornoId: string | null; estado: string | null }> {
    return this.http.get<{ tieneRetorno: boolean; retornoId: string | null; estado: string | null }>(
      `${this.api}/logistica/retornos/check-servicio/${servicioId}`
    );
  }

  getRetornos(filtros: { q?: string; estado?: string; desde?: string; hasta?: string; page?: number; pageSize?: number } = {}): Observable<{ items: Retorno[]; total: number }> {
    let params = new HttpParams()
      .set('page',      String(filtros.page     ?? 1))
      .set('page_size', String(filtros.pageSize ?? 30));
    if (filtros.q)      params = params.set('q',      filtros.q);
    if (filtros.estado) params = params.set('estado', filtros.estado);
    if (filtros.desde)  params = params.set('desde',  filtros.desde);
    if (filtros.hasta)  params = params.set('hasta',  filtros.hasta);
    return this.http
      .get<{ items: Retorno[]; total: number; page: number; pageSize: number }>(`${this.api}/logistica/retornos`, { params })
      .pipe(map(r => ({ items: r.items, total: r.total })));
  }

  getRetorno(id: string): Observable<Retorno> {
    return this.http.get<Retorno>(`${this.api}/logistica/retornos/${id}`);
  }

  inspeccionarRetorno(id: string, body: { items: { detalleId: string; cantidadConfirmada: number }[]; notaLogistica?: string }): Observable<Retorno> {
    return this.http.patch<Retorno>(`${this.api}/logistica/retornos/${id}/inspeccionar`, body);
  }

  completarRetorno(id: string): Observable<Retorno> {
    return this.http.patch<Retorno>(`${this.api}/logistica/retornos/${id}/completar`, {});
  }

  // ── Incidencias ────────────────────────────────────────────────────────
  crearIncidencia(body: {
    equipoId: string; proyectoServicioId?: string | null;
    numeroSerie?: string | null; cantidadAfectada?: number;
    tipoFalla?: string; descripcion: string;
  }): Observable<Incidencia> {
    return this.http.post<Incidencia>(`${this.api}/logistica/incidencias`, body);
  }

  getIncidencias(filtros: { q?: string; clase?: string; estado?: string; desde?: string; hasta?: string; page?: number; pageSize?: number } = {}): Observable<{ items: Incidencia[]; total: number }> {
    let params = new HttpParams()
      .set('page',      String(filtros.page     ?? 1))
      .set('page_size', String(filtros.pageSize ?? 30));
    if (filtros.q)      params = params.set('q',      filtros.q);
    if (filtros.clase)  params = params.set('clase',  filtros.clase);
    if (filtros.estado) params = params.set('estado', filtros.estado);
    if (filtros.desde)  params = params.set('desde',  filtros.desde);
    if (filtros.hasta)  params = params.set('hasta',  filtros.hasta);
    return this.http
      .get<{ items: Incidencia[]; total: number; page: number; pageSize: number }>(`${this.api}/logistica/incidencias`, { params })
      .pipe(map(r => ({ items: r.items, total: r.total })));
  }

  resolverIncidencia(id: string, body: { estado: string; resolucionNota?: string }): Observable<Incidencia> {
    return this.http.patch<Incidencia>(`${this.api}/logistica/incidencias/${id}/resolver`, body);
  }

  getDesgloseEquipo(equipoId: string): Observable<EquipoStockDesglose> {
    return this.http.get<EquipoStockDesglose>(`${this.api}/logistica/incidencias/equipo/${equipoId}/desglose`);
  }

  getServiciosGlobal(): Observable<any[]> {
    return this.http.get<any[]>(`${this.api}/logistica/servicios`);
  }

  getMantenimientoGlobal(): Observable<any[]> {
    return this.http.get<any[]>(`${this.api}/logistica/mantenimiento`);
  }

  // ── Historial de movimientos de un equipo/herramienta ─────────────────
  getMovimientosEquipo(equipoId: string): Observable<any[]> {
    return this.http.get<any[]>(`${this.api}/logistica/equipos/${equipoId}/movimientos`);
  }

  // ── Firmas digitales de un requerimiento ──────────────────────────────
  getFirmasRequerimiento(reqId: string): Observable<any[]> {
    return this.http.get<any[]>(`${this.api}/logistica/requerimientos/${reqId}/firmas`);
  }

  verificarFirma(eventoId: string): Observable<any> {
    return this.http.get<any>(`${this.api}/logistica/firmas/${eventoId}/verificar`);
  }

  // ── Búsqueda por código de artículo ───────────────────────────────────
  getArticuloPorCodigo(codigo: string): Observable<any> {
    return this.http.get<any>(`${this.api}/logistica/articulos/by-codigo/${encodeURIComponent(codigo)}`);
  }

  // ── Ingreso directo de inventario ─────────────────────────────────────
  ingresarDirecto(body: any): Observable<any> {
    return this.http.post<any>(`${this.api}/logistica/ingreso-directo`, body);
  }

  // ── Ajuste / reposición de stock de material ──────────────────────────
  ajustarStockMaterial(materialId: string, cantidad: number, motivo: string): Observable<any> {
    return this.http.post<any>(`${this.api}/logistica/inventario/ajuste`, {
      material_id: materialId, tipo: 'entrada', cantidad, motivo,
    });
  }
}

import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, map } from 'rxjs';
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
  fechaIngreso: string | null;
}

export interface DocumentoDto {
  id: string;
  tipo: string;
  nombre: string;
  url_archivo: string;
  fecha_emision: string | null;
  created_at: string | null;
  requiere_firma: boolean;
  firma_estado: 'pendiente' | 'firmado' | 'no_aplica';
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

export interface LegajoStatsDto {
  total: number;
  contratos: number;
  firmados: number;
  pendientes_firma: number;
}

export interface SolicitudEmpleadoDto {
  id: string;
  nombreCompleto: string;
  cargo: string;
  area: string;
  iniciales: string;
  fotoUrl: string;
}

export interface SolicitudLaboralDto {
  id: string;
  tipo: string;
  estado: 'pendiente' | 'aprobada' | 'rechazada';
  descripcion: string;
  fecha_inicio: string | null;
  fecha_fin: string | null;
  dias: number | null;
  url_pdf: string | null;
  observacion: string | null;
  aprobado_por: string | null;
  fecha_aprobacion: string | null;
  created_at: string;
  empleado: SolicitudEmpleadoDto;
}

export interface JustificacionTardanzaDto {
  id: string;
  estado: 'pendiente' | 'aprobada' | 'rechazada';
  fecha_tardanza: string | null;
  descripcion: string;
  observacion: string;
  created_at: string | null;
  fecha_aprobacion: string | null;
  empleado: {
    id: string;
    nombreCompleto: string;
    cargo: string;
    iniciales: string;
    fotoUrl: string;
  };
}

export interface PeriodoDto {
  fecha_inicio: string;
  fecha_fin: string;
  meta_horas: number;
}

export interface ResumenEmpleadoDto {
  id: string;
  nombreCompleto: string;
  cargo: string;
  area: string;
  iniciales: string;
  fotoUrl: string;
  tipo_contrato: 'planilla' | 'contrato' | 'practicante' | string;
  codigo: string | null;
  tipo_documento?: string | null;
  numero_documento?: string | null;
  cuspp?: string | null;
  fecha_ingreso: string | null;
  horas_reales: number;
  horas_justificadas: number;
  horas_total: number;
  horas_faltantes: number;
  horas_extra: number;
  horas_extra_aprobadas: number;
  horas_extra_no_autor: number;
  dias_laborados?: number;
  meta_horas: number;
  porcentaje: number;
  advertencias: number;
}

export interface GeoDto {
  lat: number;
  lng: number;
  precision: number | null;
}

export interface DetalleDiaDto {
  fecha: string;
  dia_nombre: string;
  hora_ingreso: string | null;
  hora_salida: string | null;
  almuerzo_inicio: string | null;
  almuerzo_fin: string | null;
  almuerzo_real_min: number | null;
  almuerzo_limite_min: number | null;
  almuerzo_exceso_min: number | null;
  horas_trabajadas: number;
  estado: string;
  geo_ingreso: GeoDto | null;
  geo_salida: GeoDto | null;
}

export interface AsistenciaDiariaItemDto {
  empleado_id: string;
  nombreCompleto: string;
  cargo: string;
  area: string;
  iniciales: string;
  fotoUrl: string;
  hora_ingreso: string | null;
  hora_salida: string | null;
  almuerzo_inicio: string | null;
  almuerzo_fin: string | null;
  horas_trabajadas: number;
  lat_ingreso: number | null;
  lng_ingreso: number | null;
  lat_salida: number | null;
  lng_salida: number | null;
  geo_ingreso: GeoDto | null;
  geo_salida: GeoDto | null;
  estado: string;
  turno_label?: string;
  justificado?: boolean;
}

export interface PaginatedDiaria {
  fecha: string;
  empleados: AsistenciaDiariaItemDto[];
  total: number;
  page: number;
  limit: number;
  total_paginas: number;
}

export interface PaginatedEmpleados {
  empleados: EmpleadoLegajoDto[];
  total: number;
  page: number;
  limit: number;
  total_paginas: number;
}

export interface PaginatedResumen {
  periodo: PeriodoDto;
  empleados: ResumenEmpleadoDto[];
  total: number;
  page: number;
  limit: number;
  total_paginas: number;
}

export interface DetalleDiarioResponse {
  empleado_id: string;
  periodo: { fecha_inicio: string; fecha_fin: string };
  dias: DetalleDiaDto[];
  total: number;
  page: number;
  limit: number;
  total_paginas: number;
}

export interface FeriadoDto {
  id:     string;
  fecha:  string;
  nombre: string;
  tipo:   'nacional' | 'empresa';
}

export interface FeriadoNacionalDto {
  fecha:  string;
  nombre: string;
  tipo:   'nacional';
}

export interface DetalleSolicitudVac {
  fecha_inicio:     string;
  fecha_fin:        string;
  dias:             number;
  fecha_aprobacion: string | null;
}

export interface SaldoVacacionesDto {
  empleado_id:          string;
  empleado_nombre:      string | null;
  cargo:                string | null;
  fecha_ingreso:        string | null;
  meses_servicio:       number;
  anos_servicio:        number;
  dias_por_anio:        number;
  devengado:            number;
  ajuste_dias:          number;
  gozado:               number;
  disponible:           number;
  tope_acumulacion:     number;
  estado_vacaciones:    'sin_derecho' | 'agotado' | 'disponible';
  solicitudes_gozadas:  DetalleSolicitudVac[];
}

@Injectable({ providedIn: 'root' })
export class RrhhService {
  private readonly api = environment.apiUrl;

  constructor(private http: HttpClient) {}

  // ── Legajo ───────────────────────────────────────────────────────────────

  getEmpleados(page = 1, limit = 10): Observable<PaginatedEmpleados> {
    return this.http.get<PaginatedEmpleados>(
      `${this.api}/rrhh/legajo/empleados?page=${page}&limit=${limit}`
    );
  }

  getEmpleadoDetalle(empleadoId: string): Observable<{
    empleado: EmpleadoInfoDto;
    documentos: DocumentoDto[];
    stats: LegajoStatsDto;
  }> {
    return this.http.get<any>(`${this.api}/rrhh/legajo/${empleadoId}`);
  }

  getDocumentosEmpleado(
    empleadoId: string,
    categoria?: string
  ): Observable<{ documentos: DocumentoDto[]; total: number }> {
    let url = `${this.api}/rrhh/legajo/${empleadoId}/documentos`;
    if (categoria) url += `?categoria=${categoria}`;
    return this.http.get<any>(url);
  }

  subirDocumento(empleadoId: string, form: FormData): Observable<{
    id: string;
    url_archivo: string;
    requiere_firma: boolean;
    mensaje: string;
  }> {
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

  // Antes apuntaba a `/rrhh/mi-firma` (ruta duplicada del backend que consulta
  // la misma tabla FirmaDigital). Se unificó contra `/permisos/mi-firma` para
  // no depender de un endpoint redundante. Esa ruta responde
  // { status, data: { url_firma } | null }; se adapta aquí al shape original
  // ({ firma: { id, url_cloudinary, primera_vez } | null }) para no romper a
  // legajo-detalle.component.ts, que solo lee `firma?.url_cloudinary`.
  getMiFirma(): Observable<{ firma: { id: string; url_cloudinary: string; primera_vez: boolean } | null }> {
    return this.http
      .get<{ status: string; data: { url_firma: string } | null }>(`${this.api}/permisos/mi-firma`)
      .pipe(map(r => ({
        firma: r.data ? { id: '', url_cloudinary: r.data.url_firma, primera_vez: false } : null,
      })));
  }

  // ── Solicitudes Laborales ────────────────────────────────────────────────

  getSolicitudes(params?: { categoria?: string; estado?: string }): Observable<{ solicitudes: SolicitudLaboralDto[] }> {
    let url = `${this.api}/rrhh/solicitudes`;
    const qs: string[] = [];
    if (params?.categoria) qs.push(`categoria=${params.categoria}`);
    if (params?.estado)    qs.push(`estado=${params.estado}`);
    if (qs.length) url += '?' + qs.join('&');
    return this.http.get<{ solicitudes: SolicitudLaboralDto[] }>(url);
  }

  evaluarSolicitud(id: string, estado: string, observacion: string): Observable<any> {
    return this.http.put(`${this.api}/rrhh/solicitudes/${id}/evaluar`, { estado, observacion });
  }

  getJustificacionesTardanza(params?: {
    estado?: string;
    empleado_id?: string;
    fecha_inicio?: string;
    fecha_fin?: string;
  }): Observable<{ justificaciones: JustificacionTardanzaDto[] }> {
    const qs: string[] = [];
    if (params?.estado)      qs.push(`estado=${params.estado}`);
    if (params?.empleado_id) qs.push(`empleado_id=${params.empleado_id}`);
    if (params?.fecha_inicio) qs.push(`fecha_inicio=${params.fecha_inicio}`);
    if (params?.fecha_fin)   qs.push(`fecha_fin=${params.fecha_fin}`);
    const url = `${this.api}/rrhh/asistencia/justificaciones` + (qs.length ? '?' + qs.join('&') : '');
    return this.http.get<{ justificaciones: JustificacionTardanzaDto[] }>(url);
  }

  // ── Asistencia ───────────────────────────────────────────────────────────

  getAsistenciaDiaria(fecha: string, page = 1, limit = 10): Observable<PaginatedDiaria> {
    return this.http.get<PaginatedDiaria>(
      `${this.api}/rrhh/asistencia/diario?fecha=${fecha}&page=${page}&limit=${limit}`
    );
  }

  getTodosEmpleados(): Observable<PaginatedEmpleados> {
    return this.http.get<PaginatedEmpleados>(
      `${this.api}/rrhh/legajo/empleados?page=1&limit=100`
    );
  }

  getResumenAsistencia(params?: {
    fecha_inicio?: string;
    fecha_fin?: string;
    page?: number;
    limit?: number;
  }): Observable<PaginatedResumen> {
    const qs: string[] = [];
    if (params?.fecha_inicio) qs.push(`fecha_inicio=${params.fecha_inicio}`);
    if (params?.fecha_fin)    qs.push(`fecha_fin=${params.fecha_fin}`);
    if (params?.page)         qs.push(`page=${params.page}`);
    if (params?.limit)        qs.push(`limit=${params.limit}`);
    const url = `${this.api}/rrhh/asistencia/resumen` + (qs.length ? '?' + qs.join('&') : '');
    return this.http.get<PaginatedResumen>(url);
  }

  getDetalleDiario(empleadoId: string, params?: {
    fecha_inicio?: string;
    fecha_fin?: string;
    page?: number;
    limit?: number;
  }): Observable<DetalleDiarioResponse> {
    const qs: string[] = [];
    if (params?.fecha_inicio) qs.push(`fecha_inicio=${params.fecha_inicio}`);
    if (params?.fecha_fin)    qs.push(`fecha_fin=${params.fecha_fin}`);
    if (params?.page)         qs.push(`page=${params.page}`);
    if (params?.limit)        qs.push(`limit=${params.limit}`);
    const url = `${this.api}/rrhh/asistencia/${empleadoId}/detalle` + (qs.length ? '?' + qs.join('&') : '');
    return this.http.get<DetalleDiarioResponse>(url);
  }

  emitirAdvertencia(empleadoId: string): Observable<{
    id: string;
    mensaje: string;
    numero_advertencia: number;
    advertencias_restantes: number;
  }> {
    return this.http.post<any>(`${this.api}/rrhh/asistencia/${empleadoId}/advertencia`, {});
  }

  // ── Planillas ────────────────────────────────────────────────────────────────────

  getPlanillas(): Observable<any> {
    return this.http.get<any>(`${this.api}/planilla`);
  }

  calcularPlanilla(periodo: string): Observable<any> {
    return this.http.post<any>(`${this.api}/planilla/calcular?periodo=${encodeURIComponent(periodo)}`, {});
  }

  aprobarPlanilla(id: string): Observable<any> {
    return this.http.post<any>(`${this.api}/planilla/${id}/aprobar`, {});
  }

  marcarPagadaPlanilla(id: string): Observable<any> {
    return this.http.post<any>(`${this.api}/planilla/${id}/marcar-pagada`, {});
  }

  anularPlanilla(id: string): Observable<any> {
    return this.http.post<any>(`${this.api}/planilla/${id}/anular`, {});
  }

  getBoletasPlanilla(planillaId: string): Observable<any> {
    return this.http.get<any>(`${this.api}/planilla/${planillaId}/boletas`);
  }

  actualizarModalidad(empleadoId: string, tipo: 'planilla' | 'contrato' | 'practicante'): Observable<any> {
    return this.http.put<any>(`${this.api}/planilla/empleados/${empleadoId}/modalidad`, { tipo });
  }

  actualizarPerfilEmpleado(empleadoId: string, datos: Partial<{ cuspp: string; numero_documento: string; tipo_documento: string; sexo: string }>): Observable<any> {
    return this.http.patch<any>(`${this.api}/rrhh/legajo/${empleadoId}/perfil`, datos);
  }

  getEmpresaInfo(): Observable<{ razon_social: string; ruc: string; regimen_tributario: string; direccion?: string; telefono?: string }> {
    return this.http.get<any>(`${this.api}/planilla/empresa-info`);
  }

  // ── Feriados ─────────────────────────────────────────────────────────────

  getFeriados(anio?: number): Observable<{ feriados: FeriadoDto[] }> {
    const qs = anio ? `?anio=${anio}` : '';
    return this.http.get<{ feriados: FeriadoDto[] }>(`${this.api}/rrhh/feriados${qs}`);
  }

  getFeriadosNacionales(anio?: number): Observable<{ feriados: FeriadoNacionalDto[] }> {
    const qs = anio ? `?anio=${anio}` : '';
    return this.http.get<{ feriados: FeriadoNacionalDto[] }>(
      `${this.api}/rrhh/feriados/nacionales${qs}`
    );
  }

  crearFeriado(body: { fecha: string; nombre: string; tipo: string }): Observable<FeriadoDto> {
    return this.http.post<FeriadoDto>(`${this.api}/rrhh/feriados`, body);
  }

  eliminarFeriado(id: string): Observable<{ mensaje: string }> {
    return this.http.delete<{ mensaje: string }>(`${this.api}/rrhh/feriados/${id}`);
  }

  // ── Reportes asistencia ───────────────────────────────────────────────────

  descargarReporte(tipo: string, params: Record<string, string>): Observable<Blob> {
    const qs = Object.entries(params)
      .filter(([, v]) => v !== undefined && v !== '')
      .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
      .join('&');
    const url = `${this.api}/rrhh/asistencia/reportes/${tipo}${qs ? '?' + qs : ''}`;
    return this.http.get(url, { responseType: 'blob' });
  }

  // ── Vacaciones ────────────────────────────────────────────────────────────

  getSaldosVacaciones(): Observable<SaldoVacacionesDto[]> {
    return this.http.get<SaldoVacacionesDto[]>(`${this.api}/vacaciones/saldos`);
  }

  getMiSaldoVacaciones(): Observable<SaldoVacacionesDto> {
    return this.http.get<SaldoVacacionesDto>(`${this.api}/vacaciones/mi-saldo`);
  }

  descargarReporteVacaciones(formato: 'xlsx' | 'pdf'): Observable<Blob> {
    return this.http.get(`${this.api}/vacaciones/reporte.${formato}`, { responseType: 'blob' });
  }
}

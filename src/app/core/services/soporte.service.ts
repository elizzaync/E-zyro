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

export interface IpBloqueadaDto {
  id: string;
  ip: string;
  motivo?: string;
  bloqueada_por_nombre?: string;
  activa: boolean;
  created_at: string;
  desbloqueada_en?: string;
}

export interface SesionActivaDto {
  id: string;
  usuario_id: string;
  usuario_nombre: string;
  ip?: string;
  dispositivo?: string;
  user_agent?: string;
  created_at: string;
  fecha_expiracion: string;
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
  user_agent?: string;
  fecha: string;
  datos_anteriores?: any;
  datos_nuevos?: any;
}

export interface IpFrecuenteDto {
  ip: string;
  total: number;
  ultima_vez: string;
  ya_bloqueada: boolean;
}

export interface DispositivoDto {
  id: string;
  dispositivo: string;
  ip: string;
  user_agent: string;
  plataforma: 'Web' | 'Móvil';
  vigente: boolean;
  minutos_restantes: number | null;
  created_at: string;
  fecha_expiracion: string;
}

export interface ReporteDispositivosDto {
  usuario_id: string;
  usuario_nombre: string;
  email: string;
  total_sesiones_activas: number;
  sesiones_vigentes: number;
  sesiones_expiradas_sin_cerrar: number;
  alerta: 'normal' | 'advertencia' | 'critico' | 'expirada';
  dispositivos: DispositivoDto[];
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

  // ── Centro de Seguridad ──────────────────────────────────────────────────

  getIpsBloqueadas(mostrarHistorial = false): Observable<IpBloqueadaDto[]> {
    let p = new HttpParams();
    if (mostrarHistorial) p = p.set('mostrar_historial', 'true');
    return this.http.get<IpBloqueadaDto[]>(`${this.base}/soporte/seguridad/ips`, { params: p });
  }

  bloquearIp(body: { ip: string; motivo?: string }): Observable<IpBloqueadaDto> {
    return this.http.post<IpBloqueadaDto>(`${this.base}/soporte/seguridad/ips`, body);
  }

  desbloquearIp(ipId: string): Observable<{ detail: string }> {
    return this.http.delete<{ detail: string }>(`${this.base}/soporte/seguridad/ips/${ipId}`);
  }

  getSesionesActivas(): Observable<SesionActivaDto[]> {
    return this.http.get<SesionActivaDto[]>(`${this.base}/soporte/seguridad/sesiones-activas`);
  }

  cerrarSesionRemota(sesionId: string): Observable<{ detail: string }> {
    return this.http.post<{ detail: string }>(`${this.base}/soporte/seguridad/sesiones/${sesionId}/cerrar`, {});
  }

  getIpsFrecuentes(): Observable<IpFrecuenteDto[]> {
    return this.http.get<IpFrecuenteDto[]>(`${this.base}/soporte/seguridad/ips-frecuentes`);
  }

  getReporteDispositivos(): Observable<ReporteDispositivosDto[]> {
    return this.http.get<ReporteDispositivosDto[]>(`${this.base}/soporte/seguridad/reporte-dispositivos`);
  }

  limpiarSesionesExpiradas(): Observable<{ detail: string; limpiadas: number }> {
    return this.http.post<{ detail: string; limpiadas: number }>(`${this.base}/soporte/seguridad/limpiar-sesiones-expiradas`, {});
  }

  cerrarTodasSesiones(usuarioId: string): Observable<{ detail: string; cerradas: number }> {
    return this.http.post<{ detail: string; cerradas: number }>(`${this.base}/soporte/seguridad/usuarios/${usuarioId}/cerrar-todas-sesiones`, {});
  }

  revertirAuditoria(auditoriaId: string): Observable<{ detail: string }> {
    return this.http.post<{ detail: string }>(`${this.base}/auditoria/${auditoriaId}/revertir`, {});
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

  // ── Backups (Gestión de TIC) — backend router /backups ──────────────────

  getBackups(estado = 'todos', page = 1, pageSize = 20): Observable<BackupsListDto> {
    const p = new HttpParams().set('estado', estado).set('page', page).set('page_size', pageSize);
    return this.http.get<BackupsListDto>(`${this.base}/backups`, { params: p });
  }

  getBackup(id: string): Observable<BackupJobDto> {
    return this.http.get<BackupJobDto>(`${this.base}/backups/${id}`);
  }

  crearBackup(alcance: 'bd' | 'completo'): Observable<BackupJobDto> {
    return this.http.post<BackupJobDto>(`${this.base}/backups`, { alcance });
  }

  getBackupConfig(): Observable<BackupConfigDto> {
    return this.http.get<BackupConfigDto>(`${this.base}/backups/config`);
  }

  actualizarBackupConfig(cfg: BackupConfigEdit): Observable<BackupConfigDto> {
    return this.http.put<BackupConfigDto>(`${this.base}/backups/config`, cfg);
  }

  cancelarBackup(id: string): Observable<BackupJobDto> {
    return this.http.post<BackupJobDto>(`${this.base}/backups/${id}/cancelar`, {});
  }

  descargarBackup(id: string): Observable<Blob> {
    return this.http.get(`${this.base}/backups/${id}/descargar`, { responseType: 'blob' });
  }

  // ── Seguridad TIC (monitoreo de eventos y alertas) ───────────────────────

  private paramsEventosSeguridad(f: FiltrosEventosSeguridad): HttpParams {
    let p = new HttpParams();
    if (f.accion && f.accion !== 'todas') p = p.set('accion', f.accion);
    if (f.usuarioNombre) p = p.set('usuarioNombre', f.usuarioNombre);
    if (f.ip) p = p.set('ip', f.ip);
    if (f.desde) p = p.set('desde', f.desde);
    if (f.hasta) p = p.set('hasta', f.hasta);
    if (f.resultado && f.resultado !== 'todos') p = p.set('resultado', f.resultado);
    p = p.set('page', (f.page ?? 1).toString()).set('page_size', (f.page_size ?? 25).toString());
    return p;
  }

  getSeguridadMetricas(): Observable<MetricasSeguridadDto> {
    return this.http.get<MetricasSeguridadDto>(`${this.base}/seguridad-tic/metricas`);
  }

  getSeguridadEventos(f: FiltrosEventosSeguridad): Observable<EventosSeguridadListDto> {
    return this.http.get<EventosSeguridadListDto>(`${this.base}/seguridad-tic/eventos`, { params: this.paramsEventosSeguridad(f) });
  }

  getSeguridadAlertas(estado: 'abierta' | 'revisada' | 'todas' = 'abierta'): Observable<AlertasSeguridadListDto> {
    const p = new HttpParams().set('estado', estado);
    return this.http.get<AlertasSeguridadListDto>(`${this.base}/seguridad-tic/alertas`, { params: p });
  }

  revisarAlerta(id: string): Observable<AlertaSeguridadDto> {
    return this.http.post<AlertaSeguridadDto>(`${this.base}/seguridad-tic/alertas/${id}/revisar`, {});
  }

  // ── Auditoría de eventos de acceso (audit-log) ───────────────────────────

  getAuditLog(f: FiltrosEventosSeguridad): Observable<EventosSeguridadListDto> {
    return this.http.get<EventosSeguridadListDto>(`${this.base}/audit-log`, { params: this.paramsEventosSeguridad(f) });
  }

  exportAuditLog(f: FiltrosEventosSeguridad): Observable<Blob> {
    return this.http.get(`${this.base}/audit-log/export`, { params: this.paramsEventosSeguridad(f), responseType: 'blob' });
  }

  // ── Documentos generados por el sistema ──────────────────────────────────

  getDocumentos(f: FiltrosDocumentos): Observable<DocumentosListDto> {
    let p = new HttpParams();
    if (f.tipo && f.tipo !== 'todos') p = p.set('tipo', f.tipo);
    if (f.modulo) p = p.set('modulo', f.modulo);
    if (f.q) p = p.set('q', f.q);
    p = p.set('page', (f.page ?? 1).toString()).set('page_size', (f.page_size ?? 25).toString());
    return this.http.get<DocumentosListDto>(`${this.base}/documentos`, { params: p });
  }
}

// ── DTOs de Backups ──────────────────────────────────────────────────────────

export interface BackupJobDto {
  id: string;
  tipo: 'auto' | 'manual';
  nivel: string;
  disparadoPorNombre: string | null;
  fechaInicio: string;
  fechaFin: string | null;
  estado: 'pendiente' | 'en_proceso' | 'completado' | 'fallido' | 'cancelado';
  contenido: string;               // csv: bd,pdfs,cloudinary
  tamanoBytes: number | null;
  hashSha256: string | null;
  errorDetalle: string | null;
  retencion: string | null;
  expiraEn: string | null;
  descargable: boolean;
  duracionSegundos: number | null;
  nombreArchivo: string | null;    // nombre real del artefacto (.sql / .tar.gz)
}

export interface BackupsListDto {
  items: BackupJobDto[];
  total: number;
  page: number;
  pageSize: number;
}

// Programación editable de los backups automáticos (PUT /backups/config)
export interface BackupConfigEdit {
  bdAuto: boolean;
  bdFrecuencia: 'cada_hora' | 'diario' | 'semanal';
  bdHora: string;                  // "HH:MM" hora local
  bdDiaSemana: number;             // 0=lunes … 6=domingo (solo semanal)
  bdCorreo: boolean;
  archivosAuto: boolean;
}

export interface BackupConfigDto extends BackupConfigEdit {
  resumen: Record<string, string>;
  backupDir: string;
  retencionDias: Record<string, number>;
}

// ── DTOs de Seguridad TIC / Auditoría de eventos ─────────────────────────────

export interface MetricasSeguridadDto {
  loginsFallidos24h: number;
  permisosDenegados24h: number;
  sesionesActivas: number;
  alertasAbiertas: number;
  descargas24h: number;
  loginsExitosos24h: number;
}

export type AccionEventoSeguridad =
  'LOGIN' | 'LOGIN_FALLIDO' | 'LOGOUT' | 'DOWNLOAD' | 'EXPORT' |
  'PERMISSION_DENIED' | 'RATE_LIMITED' | 'BACKUP' | 'SECURITY' | 'VIEW_SENSITIVE';

export interface EventoSeguridadDto {
  id: string;
  fecha: string;                    // ISO
  accion: AccionEventoSeguridad | string;
  usuarioNombre: string | null;
  rol: string | null;
  ip: string | null;
  ruta: string | null;
  metodoHttp: string | null;
  resultado: 'exito' | 'fallo' | 'denegado';
  entidad: string | null;
  entidadId: string | null;
  detalle: any | null;
  userAgent: string | null;
}

export interface EventosSeguridadListDto {
  items: EventoSeguridadDto[];
  total: number;
  page: number;
  pageSize: number;
}

// Filtros comunes de /seguridad-tic/eventos y /audit-log
export interface FiltrosEventosSeguridad {
  accion?: string;                  // 'todas' u omitido = sin filtro
  usuarioNombre?: string;
  ip?: string;
  desde?: string;                   // 'YYYY-MM-DD'
  hasta?: string;                   // 'YYYY-MM-DD'
  resultado?: string;               // 'todos' u omitido = sin filtro
  page?: number;
  page_size?: number;
}

export interface AlertaSeguridadDto {
  id: string;
  tipo: 'fuerza_bruta' | 'denegados_repetidos' | 'descarga_masiva' | 'logins_fallidos_usuario';
  severidad: 'baja' | 'media' | 'alta';
  titulo: string;
  detalle: any;
  ip: string | null;
  usuarioNombre: string | null;
  fecha: string;                    // ISO
  estado: 'abierta' | 'revisada';
  revisadaPorNombre: string | null;
  fechaRevision: string | null;
}

export interface AlertasSeguridadListDto {
  items: AlertaSeguridadDto[];
  total: number;
}

// ── DTOs de Documentos ───────────────────────────────────────────────────────

export interface DocumentoArchivoDto {
  id: string;
  nombre: string;
  tipo: 'pdf' | 'excel' | 'csv' | 'export' | 'otro';
  moduloOrigen: string | null;
  entidadTipo: string | null;
  generadoPorNombre: string | null;
  fechaCreacion: string;            // ISO
  fechaActualizacion: string | null;
  tamanoBytes: number | null;
  hashSha256: string | null;
  cloudinaryUrl: string | null;
  version: number;
  descargas: number;
}

export interface DocumentosListDto {
  items: DocumentoArchivoDto[];
  total: number;
  page: number;
  pageSize: number;
}

export interface FiltrosDocumentos {
  tipo?: string;                    // 'todos' u omitido = sin filtro
  modulo?: string;
  q?: string;
  page?: number;
  page_size?: number;
}

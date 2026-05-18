import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, Subject, BehaviorSubject } from 'rxjs'; // 👈 Eliminamos timer y Subscription
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class DashboardService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}/dashboard`;

  // 👇 CANAL DE COMUNICACIÓN DE PERFIL
  private perfilActualizadoSource = new Subject<string>();
  perfilActualizado$ = this.perfilActualizadoSource.asObservable();

  // 🔥 BUSES DE DATOS REACTIVOS
  public notificaciones$ = new BehaviorSubject<any[]>([]);
  public refreshWidgets$ = new BehaviorSubject<boolean>(true);

  constructor() {
    // 🔥 NUEVO MOTOR: Ya no pregunta cada 4 segundos.
    // Ahora, cada vez que Firebase o una acción local lance un refreshWidgets$.next(true),
    // actualizamos la lista de notificaciones en memoria.
    this.refreshWidgets$.subscribe(() => {
      this.cargarNotificacionesSilencioso();
    });
  }

  notificarPerfilActualizado(nombre: string) {
    this.perfilActualizadoSource.next(nombre);
  }

  private getHeaders(): HttpHeaders {
    return new HttpHeaders({
      'Authorization': `Bearer ${localStorage.getItem('ezyro_token')}`,
      'Content-Type': 'application/json'
    });
  }

  // 🔥 ACTUALIZACIÓN SILENCIOSA
  private cargarNotificacionesSilencioso() {
    this.getNotificaciones().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.notificaciones$.next(res.data);
        }
      },
      error: (err) => console.error("Error al refrescar notificaciones internas", err)
    });
  }

  // --- RUTAS DEL DASHBOARD ---
  getResumenKPIs(): Observable<any> { return this.http.get(`${this.apiUrl}/resumen`, { headers: this.getHeaders() }); }
  getProximosServicios(): Observable<any> { return this.http.get(`${this.apiUrl}/proximos-servicios`, { headers: this.getHeaders() }); }
  getRendimientoMensual(): Observable<any> { return this.http.get(`${this.apiUrl}/rendimiento-mensual`, { headers: this.getHeaders() }); }
  getCalendarioEventos(): Observable<any> { return this.http.get(`${this.apiUrl}/calendario`, { headers: this.getHeaders() }); }
  guardarNotaCalendario(fecha: string, texto: string): Observable<any> { return this.http.post(`${this.apiUrl}/calendario/nota`, { fecha, texto }, { headers: this.getHeaders() }); }
  getDetalleServicioDia(fecha: string): Observable<any> { return this.http.get(`${this.apiUrl}/calendario/servicio/${fecha}`, { headers: this.getHeaders() }); }

  // --- RUTAS DEL PERFIL ---
  getPerfilUsuario(): Observable<any> { return this.http.get(`${this.apiUrl}/perfil`, { headers: this.getHeaders() }); }
  actualizarPerfil(datos: any): Observable<any> { return this.http.put(`${this.apiUrl}/perfil`, datos, { headers: this.getHeaders() }); }
  getCapacitaciones(): Observable<any> { return this.http.get(`${this.apiUrl}/perfil/capacitaciones`, { headers: this.getHeaders() }); }
  getActividadReciente(): Observable<any> { return this.http.get(`${this.apiUrl}/perfil/actividad`, { headers: this.getHeaders() }); }
  getPerfilEstadisticas(): Observable<any> { return this.http.get(`${this.apiUrl}/perfil/estadisticas`, { headers: this.getHeaders() }); }
  getAsistencia(): Observable<any> { return this.http.get(`${this.apiUrl}/perfil/asistencia`, { headers: this.getHeaders() }); }
  getContratos(): Observable<any> { return this.http.get(`${this.apiUrl}/perfil/contratos`, { headers: this.getHeaders() }); }
  getBoletas(): Observable<any> { return this.http.get(`${this.apiUrl}/perfil/boletas`, { headers: this.getHeaders() }); }
  getPermisos(): Observable<any> { return this.http.get(`${this.apiUrl}/perfil/permisos`, { headers: this.getHeaders() }); }

  // --- RUTAS DE NOTIFICACIONES Y FIREBASE ---
  getNotificaciones(): Observable<any> { return this.http.get(`${this.apiUrl}/notificaciones`, { headers: this.getHeaders() }); }
  ignorarNotificacion(id: string): Observable<any> { return this.http.put(`${this.apiUrl}/notificaciones/${id}/ignorar`, {}, { headers: this.getHeaders() }); }
  guardarTokenPush(token: string): Observable<any> { return this.http.post(`${this.apiUrl}/guardar-token-push`, { token, plataforma: 'web' }, { headers: this.getHeaders() }); }
}
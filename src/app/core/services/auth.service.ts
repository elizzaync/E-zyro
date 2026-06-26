import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Router } from '@angular/router';
import { Observable, tap, catchError, of, BehaviorSubject } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private http = inject(HttpClient);
  private router = inject(Router);

  private apiUrl = `${environment.apiUrl}/auth`;

  // ==========================================
  // ESTADO GLOBAL DEL MODAL DE CERRAR SESIÓN
  // ==========================================
  private showLogoutModalSubject = new BehaviorSubject<boolean>(false);
  showLogoutModal$ = this.showLogoutModalSubject.asObservable();

  // ==========================================
  // ESTADO GLOBAL DEL AVISO DE SESIÓN
  // ==========================================
  private showSessionWarningSubject = new BehaviorSubject<boolean>(false);
  showSessionWarning$ = this.showSessionWarningSubject.asObservable();

  private sessionTimers: ReturnType<typeof setTimeout>[] = [];

  // ==========================================
  // MÉTODOS DE LOGIN Y RECUPERACIÓN
  // ==========================================
  login(credentials: any): Observable<any> {
    return this.http.post(`${this.apiUrl}/login`, credentials).pipe(
      tap((response: any) => {
        if (response.status === 'success' && response.data.token) {
          localStorage.setItem('ezyro_token', response.data.token);

          const userData = {
            id:              response.data.id,
            nombre_completo: response.data.nombre_completo,
            rol:             response.data.rol,
            foto_url:        response.data.foto_url ?? ''
          };
          localStorage.setItem('ezyro_user', JSON.stringify(userData));
          this.startSessionTimer();
          this.connectSessionSocket();
        }
      })
    );
  }

  solicitarCodigoRecuperacion(email: string): Observable<any> {
    return this.http.post(`${this.apiUrl}/password-recovery/request`, { email });
  }

  verificarCodigo(email: string, code: string): Observable<any> {
    return this.http.post(`${this.apiUrl}/password-recovery/verify`, { email, code });
  }

  actualizarPassword(email: string, code: string, nuevaPassword: string): Observable<any> {
    return this.http.post(`${this.apiUrl}/password-recovery/reset`, {
      email: email,
      code: code,
      new_password: nuevaPassword
    });
  }

  // ==========================================
  // CONTROL DEL MODAL Y CIERRE DE SESIÓN
  // ==========================================

  // 1. Abre el modal desde cualquier parte del sistema
  solicitarCerrarSesion() {
    this.showLogoutModalSubject.next(true);
    document.body.style.overflow = 'hidden';
  }

  // 2. Cancela el modal
  cancelarCerrarSesion() {
    this.showLogoutModalSubject.next(false);
    document.body.style.overflow = '';
  }

  // 3. Ejecuta la decisión de salir
  ejecutarCerrarSesion() {
    this.showLogoutModalSubject.next(false);
    document.body.style.overflow = '';
    document.documentElement.removeAttribute('data-theme');
    this.logout();
  }

  // 4. Lógica de logout que notifica al backend y limpia sesión
  logout(): void {
    this.clearSessionTimers();
    this.disconnectSessionSocket();
    this.showSessionWarningSubject.next(false);
    this.showNewDeviceWarningSubject.next(false);
    const token = localStorage.getItem('ezyro_token');
    const headers = new HttpHeaders({ 'Authorization': `Bearer ${token}` });

    this.http.post(`${this.apiUrl}/logout`, {}, { headers }).pipe(
      catchError(() => of(null))
    ).subscribe(() => {
      localStorage.removeItem('ezyro_token');
      localStorage.removeItem('ezyro_user');
      this.router.navigate(['/']);
    });
  }

  logoutAllDevices(): Observable<any> {
    const token = localStorage.getItem('ezyro_token');
    const headers = new HttpHeaders({ 'Authorization': `Bearer ${token}` });
    // Cierra todas las demás sesiones (mantiene la actual). El backend revoca
    // los tokens y empuja "sesion_cerrada" a cada equipo por WebSocket.
    return this.http.post(`${this.apiUrl}/logout-all`, {}, { headers }).pipe(
      catchError(() => of(null))
    );
  }

  // ==========================================
  // UTILIDADES
  // ==========================================
  isAuthenticated(): boolean {
    const token = localStorage.getItem('ezyro_token');
    if (!token) return false;
    try {
      const payload = JSON.parse(atob(token.split('.')[1]));
      // Rechaza tokens expirados (exp está en segundos UNIX)
      if (payload?.exp && payload.exp < Math.floor(Date.now() / 1000)) {
        this.logout();
        return false;
      }
      return true;
    } catch {
      // Token malformado → limpiar y redirigir
      localStorage.removeItem('ezyro_token');
      localStorage.removeItem('ezyro_user');
      return false;
    }
  }

  getToken(): string | null {
    return localStorage.getItem('ezyro_token');
  }

  getUsuario(): { id: string; nombre_completo: string; rol: string; foto_url: string } | null {
    try {
      const raw = localStorage.getItem('ezyro_user');
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  }

  isClienteExterno(): boolean {
    const u = this.getUsuario();
    return (u?.rol || '').toLowerCase().replace(' ', '') === 'clienteexterno';
  }

  isTecnico(): boolean {
    const u = this.getUsuario();
    return (u?.rol || '').trim() === 'Técnico';
  }

  isJefeOperaciones(): boolean {
    const u = this.getUsuario();
    return (u?.rol || '').trim() === 'Jefe de Operaciones';
  }

  isLogistica(): boolean {
    const u = this.getUsuario();
    return (u?.rol || '').trim() === 'Logística';
  }

  // ==========================================
  // MULTI-DEVICE SECURITY
  // ==========================================
  private showNewDeviceWarningSubject = new BehaviorSubject<boolean>(false);
  showNewDeviceWarning$ = this.showNewDeviceWarningSubject.asObservable();

  // ==========================================
  // CUENTA DESACTIVADA
  // ==========================================
  private showCuentaDesactivadaSubject = new BehaviorSubject<boolean>(false);
  showCuentaDesactivada$ = this.showCuentaDesactivadaSubject.asObservable();

  triggerCuentaDesactivada(): void {
    this.clearSessionTimers();
    this.disconnectSessionSocket();
    this.showSessionWarningSubject.next(false);
    this.showNewDeviceWarningSubject.next(false);
    localStorage.removeItem('ezyro_token');
    localStorage.removeItem('ezyro_user');
    this.showCuentaDesactivadaSubject.next(true);
    document.body.style.overflow = 'hidden';
  }

  confirmarCuentaDesactivada(): void {
    this.showCuentaDesactivadaSubject.next(false);
    document.body.style.overflow = '';
    this.router.navigate(['/']);
  }

  newDeviceInfo: any = null;

  // ── WebSocket de sesiones (reemplaza el polling de 60s) ───────────────────
  private sessionSocket: WebSocket | null = null;
  private sessionReconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private sessionReconnectAttempts = 0;
  private sessionManualClose = false;

  getSesionesActivas(): Observable<any> {
    return this.http.get<any>(`${this.apiUrl}/sesiones`);
  }

  cerrarSesionRemota(sessionId: string): Observable<any> {
    return this.http.delete<any>(`${this.apiUrl}/sesiones/${sessionId}`);
  }

  /**
   * Abre el WebSocket /ws/sesiones para recibir avisos instantáneos:
   *  - nuevo_dispositivo → muestra el aviso en este equipo.
   *  - sesion_cerrada     → este equipo fue expulsado → logout forzado.
   * Reconecta con backoff exponencial si la conexión cae.
   */
  connectSessionSocket(): void {
    this.disconnectSessionSocket(false);
    const token = this.getToken();
    if (!token) return;

    this.sessionManualClose = false;
    const wsBase = environment.apiUrl.replace(/^http/, 'ws');

    let socket: WebSocket;
    try {
      socket = new WebSocket(`${wsBase}/ws/sesiones?token=${token}`);
    } catch {
      this.scheduleSessionReconnect();
      return;
    }
    this.sessionSocket = socket;

    socket.onopen = () => { this.sessionReconnectAttempts = 0; };

    socket.onmessage = (ev: MessageEvent) => {
      let data: any;
      try { data = JSON.parse(ev.data); } catch { return; }

      if (data?.tipo === 'nuevo_dispositivo') {
        this.newDeviceInfo = {
          dispositivo: data.dispositivo,
          ip:          data.ip,
          sesion_id:   data.sesion_id,
          fecha:       data.fecha,
        };
        this.showNewDeviceWarningSubject.next(true);
        document.body.style.overflow = 'hidden';
      } else if (data?.tipo === 'sesion_cerrada') {
        // Este equipo fue cerrado desde otro dispositivo → expulsión real.
        this.forceLogout();
      }
    };

    socket.onclose = (ev: CloseEvent) => {
      this.sessionSocket = null;
      if (this.sessionManualClose) return;
      // 4001 token inválido · 4002 sesión cerrada → no reconectar.
      if (ev.code === 4001 || ev.code === 4002) return;
      if (this.isAuthenticated()) this.scheduleSessionReconnect();
    };

    socket.onerror = () => { /* onclose gestiona la reconexión */ };
  }

  private scheduleSessionReconnect(): void {
    if (this.sessionReconnectTimer) return;
    // Backoff exponencial con techo de 30s.
    const delay = Math.min(30_000, 1_000 * Math.pow(2, this.sessionReconnectAttempts));
    this.sessionReconnectAttempts++;
    this.sessionReconnectTimer = setTimeout(() => {
      this.sessionReconnectTimer = null;
      if (this.isAuthenticated() && !this.sessionManualClose) {
        this.connectSessionSocket();
      }
    }, delay);
  }

  disconnectSessionSocket(manual = true): void {
    this.sessionManualClose = manual;
    if (this.sessionReconnectTimer) {
      clearTimeout(this.sessionReconnectTimer);
      this.sessionReconnectTimer = null;
    }
    if (this.sessionSocket) {
      try { this.sessionSocket.close(); } catch { /* noop */ }
      this.sessionSocket = null;
    }
  }

  /** Logout forzado (sin llamar al backend): el servidor ya cerró la sesión. */
  private forceLogout(): void {
    this.clearSessionTimers();
    this.disconnectSessionSocket();
    this.showSessionWarningSubject.next(false);
    this.showNewDeviceWarningSubject.next(false);
    this.newDeviceInfo = null;
    document.body.style.overflow = '';
    localStorage.removeItem('ezyro_token');
    localStorage.removeItem('ezyro_user');
    this.router.navigate(['/']);
  }

  dismissNewDeviceWarning(): void {
    this.newDeviceInfo = null;
    this.showNewDeviceWarningSubject.next(false);
    document.body.style.overflow = '';
  }

  cerrarSesionDesconocida(): void {
    const id = this.newDeviceInfo?.sesion_id;
    this.newDeviceInfo = null;
    this.showNewDeviceWarningSubject.next(false);
    document.body.style.overflow = '';
    if (!id) return;
    // Cierra la sesión del equipo intruso; el backend lo expulsa al instante.
    this.cerrarSesionRemota(id).pipe(
      catchError(() => of(null))
    ).subscribe();
  }

  // ==========================================
  // REFRESH TOKEN Y TEMPORIZADOR DE SESIÓN
  // ==========================================

  getTokenExp(): number | null {
    const token = this.getToken();
    if (!token) return null;
    try {
      const payload = JSON.parse(atob(token.split('.')[1]));
      return payload?.exp ?? null;
    } catch { return null; }
  }

  refreshToken(): Observable<any> {
    const token = this.getToken();
    const headers = new HttpHeaders({ 'Authorization': `Bearer ${token}` });
    return this.http.post(`${this.apiUrl}/refresh`, {}, { headers }).pipe(
      tap((res: any) => {
        if (res.status === 'success' && res.data?.token) {
          localStorage.setItem('ezyro_token', res.data.token);
        }
      })
    );
  }

  extenderSesion(): void {
    this.refreshToken().pipe(
      catchError(() => {
        this.logout();
        return of(null);
      })
    ).subscribe((res: any) => {
      if (res) {
        this.showSessionWarningSubject.next(false);
        document.body.style.overflow = '';
        this.startSessionTimer();
      }
    });
  }

  dismissSessionWarning(): void {
    this.showSessionWarningSubject.next(false);
    document.body.style.overflow = '';
  }

  clearSessionTimers(): void {
    this.sessionTimers.forEach(t => clearTimeout(t));
    this.sessionTimers = [];
  }

  startSessionTimer(): void {
    this.clearSessionTimers();
    const exp = this.getTokenExp();
    if (!exp) return;

    const now = Math.floor(Date.now() / 1000);
    const ttlMs = (exp - now) * 1000;

    if (ttlMs <= 0) {
      this.logout();
      return;
    }

    const warningMs = ttlMs - 5 * 60 * 1000;

    if (warningMs > 0) {
      this.sessionTimers.push(setTimeout(() => {
        this.showSessionWarningSubject.next(true);
        document.body.style.overflow = 'hidden';
      }, warningMs));
    } else {
      // Less than 5 min left — show warning immediately
      this.showSessionWarningSubject.next(true);
      document.body.style.overflow = 'hidden';
    }

    // Auto-logout at expiry
    this.sessionTimers.push(setTimeout(() => {
      this.showSessionWarningSubject.next(false);
      document.body.style.overflow = '';
      this.logout();
    }, ttlMs));
  }
}
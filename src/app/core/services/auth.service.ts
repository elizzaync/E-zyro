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
          this.startDevicePolling();
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
    this.stopDevicePolling();
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
    return this.http.post(`${this.apiUrl}/password-recovery/logout-all`, {}, { headers }).pipe(
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

  // ==========================================
  // MULTI-DEVICE SECURITY
  // ==========================================
  private showNewDeviceWarningSubject = new BehaviorSubject<boolean>(false);
  showNewDeviceWarning$ = this.showNewDeviceWarningSubject.asObservable();

  newDeviceInfo: any = null;
  private knownSessionIds = new Set<string>();
  private devicePollingTimer: ReturnType<typeof setInterval> | null = null;

  getSesionesActivas(): Observable<any> {
    return this.http.get<any>(`${this.apiUrl}/sesiones`);
  }

  cerrarSesionRemota(sessionId: string): Observable<any> {
    return this.http.delete<any>(`${this.apiUrl}/sesiones/${sessionId}`);
  }

  startDevicePolling(): void {
    this.stopDevicePolling();
    // Initial fetch to establish baseline known sessions
    this.getSesionesActivas().pipe(
      catchError(() => of(null))
    ).subscribe((res: any) => {
      if (res?.status === 'success') {
        this.knownSessionIds = new Set(res.data.map((s: any) => s.id));
      }
    });
    // Poll every 60 seconds for new sessions
    this.devicePollingTimer = setInterval(() => {
      if (!this.isAuthenticated()) {
        this.stopDevicePolling();
        return;
      }
      this.getSesionesActivas().pipe(
        catchError(() => of(null))
      ).subscribe((res: any) => {
        if (!res?.data) return;
        const newSessions = res.data.filter(
          (s: any) => !s.es_actual && !this.knownSessionIds.has(s.id)
        );
        if (newSessions.length > 0) {
          this.newDeviceInfo = newSessions[0];
          this.showNewDeviceWarningSubject.next(true);
          document.body.style.overflow = 'hidden';
        }
        // Update known set to include ALL current sessions
        res.data.forEach((s: any) => this.knownSessionIds.add(s.id));
      });
    }, 60_000);
  }

  stopDevicePolling(): void {
    if (this.devicePollingTimer !== null) {
      clearInterval(this.devicePollingTimer);
      this.devicePollingTimer = null;
    }
  }

  dismissNewDeviceWarning(): void {
    if (this.newDeviceInfo) {
      this.knownSessionIds.add(this.newDeviceInfo.id);
    }
    this.newDeviceInfo = null;
    this.showNewDeviceWarningSubject.next(false);
    document.body.style.overflow = '';
  }

  cerrarSesionDesconocida(): void {
    if (!this.newDeviceInfo) return;
    const id = this.newDeviceInfo.id;
    this.cerrarSesionRemota(id).pipe(
      catchError(() => of(null))
    ).subscribe(() => {
      this.knownSessionIds.add(id);
      this.newDeviceInfo = null;
      this.showNewDeviceWarningSubject.next(false);
      document.body.style.overflow = '';
    });
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
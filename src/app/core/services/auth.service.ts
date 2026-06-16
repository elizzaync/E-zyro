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
    this.showSessionWarningSubject.next(false);
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
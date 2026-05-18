import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Router } from '@angular/router';
import { Observable, tap, catchError, of, BehaviorSubject } from 'rxjs'; // 👈 Añadido BehaviorSubject
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
  // MÉTODOS DE LOGIN Y RECUPERACIÓN
  // ==========================================
  login(credentials: any): Observable<any> {
    // Le agregamos el "/login" solo a esta petición
    return this.http.post(`${this.apiUrl}/login`, credentials).pipe(
      tap((response: any) => {
        if (response.status === 'success' && response.data.token) {
          localStorage.setItem('ezyro_token', response.data.token);

          const userData = {
            nombre_completo: response.data.nombre_completo,
            rol: response.data.rol
          };
          localStorage.setItem('ezyro_user', JSON.stringify(userData));
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
    // Ocultamos el modal y limpiamos el scroll/tema
    this.showLogoutModalSubject.next(false);
    document.body.style.overflow = '';
    document.documentElement.removeAttribute('data-theme');

    // Llamamos a tu lógica real de logout
    this.logout();
  }

  // 4. Tu lógica original intacta que avisa al backend
  logout(): void {
    const token = localStorage.getItem('ezyro_token');
    const headers = new HttpHeaders({ 'Authorization': `Bearer ${token}` });

    // Notifica al backend para registrar fecha_cierre en sesion_usuario
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
    return !!token;
  }

  getToken(): string | null {
    return localStorage.getItem('ezyro_token');
  }
}
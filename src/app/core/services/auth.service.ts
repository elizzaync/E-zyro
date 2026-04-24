import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { Observable, tap } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private http = inject(HttpClient);
  private router = inject(Router);

  // Dejamos la URL base limpia hasta "auth"
  private apiUrl = 'https://e-zyro-production.up.railway.app/auth';

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

  // --- FLUJO DE RECUPERACIÓN DE CONTRASEÑA ---

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

  logout(): void {
    localStorage.removeItem('ezyro_token');
    localStorage.removeItem('ezyro_user');

    //CORRECCIÓN: Te mandamos a la ruta raíz vacía, que es donde está el Login
    this.router.navigate(['/']);
  }

  isAuthenticated(): boolean {
    const token = localStorage.getItem('ezyro_token');
    return !!token;
  }

  getToken(): string | null {
    return localStorage.getItem('ezyro_token');
  }
}
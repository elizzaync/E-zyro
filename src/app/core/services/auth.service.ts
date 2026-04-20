import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private http = inject(HttpClient);

  // URL exacta de tu backend en Railway apuntando al router de auth
  private apiUrl = 'https://e-zyro-production.up.railway.app/auth/login';

  login(credentials: { username: string; password: string }): Observable<any> {
    return this.http.post(this.apiUrl, credentials);
  }
}
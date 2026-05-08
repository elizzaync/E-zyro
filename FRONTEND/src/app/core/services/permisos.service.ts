import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class PermisosService {
  private http   = inject(HttpClient);
  private apiUrl = 'https://e-zyro-production.up.railway.app/permisos';

  private getHeaders(): HttpHeaders {
    return new HttpHeaders({
      'Authorization': `Bearer ${localStorage.getItem('ezyro_token')}`,
      'Content-Type': 'application/json',
    });
  }

  getMiFirma(): Observable<any> {
    return this.http.get(`${this.apiUrl}/mi-firma`, { headers: this.getHeaders() });
  }

  enviarSolicitud(datos: {
    tipo:             string;
    tipo_label:       string;
    fecha_inicio?:    string;
    fecha_fin?:       string;
    hora_inicio?:     string;
    hora_fin?:        string;
    motivo?:          string;
    lugar_destino?:   string;
    horas_calculadas?: number | null;
    total_dias?:      number | null;
    firma_base64:     string;
    adjunto_nombre?:  string;
  }): Observable<any> {
    return this.http.post(`${this.apiUrl}/enviar-solicitud`, datos, { headers: this.getHeaders() });
  }
}

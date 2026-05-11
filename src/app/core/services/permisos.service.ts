import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class PermisosService {
  private http   = inject(HttpClient);
  private apiUrl = 'https://e-zyro-production.up.railway.app/permisos';

  private getAuthHeader(): HttpHeaders {
    return new HttpHeaders({
      Authorization: `Bearer ${localStorage.getItem('ezyro_token')}`,
    });
  }

  getMiFirma(): Observable<any> {
    return this.http.get(`${this.apiUrl}/mi-firma`, {
      headers: this.getAuthHeader(),
    });
  }

  /**
   * Envía la solicitud como multipart/form-data.
   * El FormData contiene:
   *   - pdf_file     : File  — PDF generado por pdf-lib en el cliente
   *   - tipo         : string
   *   - tipo_label   : string
   *   - firma_base64 : string (data URI o URL cloudinary)
   *   - (resto de campos opcionales: fecha_inicio, motivo, etc.)
   *
   * NO se establece Content-Type manualmente: el browser lo añade
   * con el boundary correcto al detectar FormData.
   */
  enviarSolicitud(formData: FormData): Observable<any> {
    return this.http.post(`${this.apiUrl}/enviar-solicitud`, formData, {
      headers: this.getAuthHeader(),
    });
  }
}

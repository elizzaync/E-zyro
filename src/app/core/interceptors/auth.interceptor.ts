import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { retry, timer } from 'rxjs';
import { AuthService } from '../services/auth.service';

// Reintentos para "cold start" de Railway: el backend dormido devuelve un
// error de red (status 0, sin headers CORS) mientras termina de arrancar.
const COLD_START_RETRIES = 2;
const COLD_START_DELAY_MS = 2000;

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const token = authService.getToken();

  // Si hay un token, clonamos la petición original y le inyectamos el Header
  const request = token
    ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : req; // Si no hay token (ej. durante el login), la petición pasa limpia

  return next(request).pipe(
    retry({
      count: COLD_START_RETRIES,
      delay: (error, retryCount) => {
        if (error instanceof HttpErrorResponse && error.status === 0) {
          return timer(COLD_START_DELAY_MS * retryCount);
        }
        throw error;
      }
    })
  );
};
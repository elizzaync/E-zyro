import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, retry, throwError, timer } from 'rxjs';
import { AuthService } from '../services/auth.service';

// Reintentos para "cold start" de Railway: el backend dormido devuelve un
// error de red (status 0, sin headers CORS) mientras termina de arrancar.
const COLD_START_RETRIES = 2;
const COLD_START_DELAY_MS = 2000;

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const token = authService.getToken();

  const request = token
    ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : req;

  return next(request).pipe(
    retry({
      count: COLD_START_RETRIES,
      delay: (error, retryCount) => {
        if (error instanceof HttpErrorResponse && error.status === 0) {
          return timer(COLD_START_DELAY_MS * retryCount);
        }
        throw error;
      }
    }),
    catchError((error: HttpErrorResponse) => {
      if (error.status === 403 && error.error?.detail === 'cuenta_desactivada') {
        authService.triggerCuentaDesactivada();
      } else if (error.status === 401 && !req.url.includes('/auth/')) {
        // Token rechazado por el backend → cerrar sesión automáticamente
        // Excluir rutas /auth/ para evitar bucles en login/logout/refresh
        authService.logout();
      }
      return throwError(() => error);
    })
  );
};
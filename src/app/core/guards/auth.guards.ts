import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  // Si el usuario tiene un token, lo dejamos pasar
  if (authService.isAuthenticated()) {
    return true;
  }

  // Si no tiene token, lo devolvemos al Login
  router.navigate(['/']); // '/' es tu ruta de login
  return false;
};
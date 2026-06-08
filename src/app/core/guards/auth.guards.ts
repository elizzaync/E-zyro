import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

// src/app/core/guards/auth.guard.ts
export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (!authService.isAuthenticated()) {
    router.navigate(['/']);
    return false;
  }

  // Usuarios del portal cliente no pueden acceder a rutas internas
  if (authService.isClienteExterno()) {
    router.navigate(['/portal-cliente/dashboard']);
    return false;
  }

  return true;
};
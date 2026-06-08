import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

export const clientPortalGuard: CanActivateFn = () => {
  const auth   = inject(AuthService);
  const router = inject(Router);

  if (!auth.isAuthenticated()) {
    router.navigate(['/']);
    return false;
  }

  const user = auth.getUsuario();
  const rol  = (user?.rol || '').toLowerCase().replace(' ', '');
  if (rol === 'clienteexterno') return true;

  // Usuarios internos que intenten acceder al portal → redirigir a home
  router.navigate(['/home']);
  return false;
};

import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

/**
 * Guard parametrizable por rol.
 * Uso en rutas:
 *   canActivate: [authGuard, rolesGuard(['Administrador', 'Jefe de Operaciones'])]
 *
 * - Si el usuario NO está en la lista de roles permitidos → redirige a /home con un mensaje.
 * - Si la lista está vacía → bloquea a todos.
 */
export function rolesGuard(rolesPermitidos: string[]): CanActivateFn {
  return (_route, _state) => {
    const auth   = inject(AuthService);
    const router = inject(Router);

    if (!auth.isAuthenticated()) {
      router.navigate(['/']);
      return false;
    }

    const user = auth.getUsuario();
    const rol  = (user?.rol || '').trim();

    if (rolesPermitidos.includes(rol)) return true;

    router.navigate(['/home']);
    return false;
  };
}

/**
 * Guard que bloquea roles específicos (lista negra).
 * Uso: canActivate: [authGuard, bloquearRolesGuard(['Técnico de Campo', 'Jefe de Operaciones'])]
 */
export function bloquearRolesGuard(rolesBloqueados: string[]): CanActivateFn {
  return (_route, _state) => {
    const auth   = inject(AuthService);
    const router = inject(Router);

    if (!auth.isAuthenticated()) {
      router.navigate(['/']);
      return false;
    }

    const user = auth.getUsuario();
    const rol  = (user?.rol || '').trim();

    if (rolesBloqueados.includes(rol)) {
      router.navigate(['/home']);
      return false;
    }

    return true;
  };
}

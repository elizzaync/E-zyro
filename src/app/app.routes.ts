import { Routes } from '@angular/router';
import { LoginComponent } from './features/auth/login/login.component';
// --- NUESTRO NUEVO COMPONENTE UNIFICADO ---
import { ResetPasswordComponent } from './features/auth/reset-password/reset-password.component';
// --- IMPORTAMOS EL DASHBOARD Y EL GUARDIÁN ---
import { DashboardComponent } from './features/dashboard/dashboard.component';
import { authGuard } from './core/guards/auth.guards';

export const routes: Routes = [
  {
    path: '',
    component: LoginComponent,
    title: 'Login | E-System Tic'
  },
  {
    path: 'reset-password',
    component: ResetPasswordComponent, // <-- Ahora este maneja todo el flujo de 4 pasos
    title: 'Recuperar Contraseña | E-System Tic'
  },
  // --- RUTA PROTEGIDA ---
  {
    path: 'dashboard',
    component: DashboardComponent,
    title: 'Dashboard | E-System Tic',
    canActivate: [authGuard] // Esto bloquea a los que no tienen Token JWT
  },
  // --- RUTA COMODÍN (Si escriben una URL que no existe, los manda al login) ---
  {
    path: '**',
    redirectTo: ''
  }
];
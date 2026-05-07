import { Routes } from '@angular/router';
import { LoginComponent } from './features/auth/login/login.component';
import { ResetPasswordComponent } from './features/auth/reset-password/reset-password.component';
import { HomeComponent } from './features/home/home.component';
import { authGuard } from './core/guards/auth.guards';
import { PersonalComponent } from './features/personal/personal.component';
import { PermisosComponent } from './features/permisos/permisos.component';
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
  {
    path: 'home',
    component: HomeComponent,
    title: 'Inicio | E-System Tic',
    canActivate: [authGuard] // Esto bloquea a los que no tienen Token JWT
  },
    {
    path: 'personal',
    component: PersonalComponent,
    title: 'Personal | E-System Tic',
    canActivate: [authGuard]
  },
    { path: 'permisos',
    component: PermisosComponent,
    canActivate: [authGuard] },
  {
    path: '**',
    redirectTo: ''
  }
];
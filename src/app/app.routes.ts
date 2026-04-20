import { Routes } from '@angular/router';
import { LoginComponent } from './features/auth/login/login.component';
import { ForgotPasswordComponent } from './features/auth/reset-password/reset-password.component';
import { NewPasswordComponent } from './features/auth/new-password/new-password.component';

export const routes: Routes = [
  {
    path: '',
    component: LoginComponent,
    title: 'Login'
  },
  {
    path: 'reset-password',
    component: ForgotPasswordComponent,
    title: 'Reseteo de contraseña'
  },
  {
    path: 'new-password',
    component: NewPasswordComponent,
    title: 'Nueva contraseña'
  }
];
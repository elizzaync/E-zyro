import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div style="padding: 2rem; font-family: sans-serif;">
      <h1 style="color: #2e7d32;">E-System Tic - Dashboard</h1>
      <p>Bienvenido(a), <strong>{{ userData?.nombre_completo }}</strong></p>
      <p>Tu rol asignado es: <span style="background: #e8f5e9; padding: 4px 8px; border-radius: 4px;">{{ userData?.rol }}</span></p>

      <button (click)="logout()" style="margin-top: 2rem; padding: 10px 20px; cursor: pointer; background: #d32f2f; color: white; border: none; border-radius: 5px;">
        Cerrar Sesión
      </button>
    </div>
  `
})
export class DashboardComponent {
  private authService = inject(AuthService);
  private router = inject(Router);

  // Leemos los datos que guardamos en el login
  userData = JSON.parse(localStorage.getItem('ezyro_user') || '{}');

  logout() {
    this.authService.logout();
    this.router.navigate(['/login']);
  }
}
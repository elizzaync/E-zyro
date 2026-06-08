import { Component, inject } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-client-layout',
  standalone: true,
  imports: [CommonModule, RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './client-layout.component.html',
  styleUrls: ['./client-layout.component.css'],
})
export class ClientLayoutComponent {
  private authService = inject(AuthService);

  get usuario() { return this.authService.getUsuario(); }
  get empresa() { return this.usuario?.nombre_completo?.split(' ')[0] ?? 'Cliente'; }

  menuAbierto = false;
  confirmarSalida = false;

  toggleMenu(): void { this.menuAbierto = !this.menuAbierto; }

  solicitarSalir(): void { this.confirmarSalida = true; }
  cancelarSalir(): void  { this.confirmarSalida = false; }
  salir(): void          { this.authService.ejecutarCerrarSesion(); }
}

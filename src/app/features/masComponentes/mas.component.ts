import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';
import { DashboardService } from '../../core/services/dashboard.service';

@Component({
  selector: 'app-mas',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './mas.component.html',
  styleUrls: ['./mas.component.css']
})
export class MasComponent implements OnInit {
  // Inicializamos con valores por defecto
  usuarioActual = { nombre: 'Cargando...', rol: '...', iniciales: '', foto: '' };
  showLogoutModal = false;

  constructor(
    private authService: AuthService,
    private dashboardService: DashboardService
  ) {}

  ngOnInit(): void {
    this.cargarDatosDeUsuario();
  }

  cargarDatosDeUsuario(): void {
    // 1. Carga inicial rápida desde LocalStorage (Igual que en tu Navbar)
    const userDataString = localStorage.getItem('ezyro_user');
    if (userDataString) {
      const u = JSON.parse(userDataString);
      this.usuarioActual.nombre = u.nombre_completo || 'Usuario';
      this.usuarioActual.iniciales = this.generarIniciales(this.usuarioActual.nombre, '');
    }

    // 2. Consulta en tiempo real para obtener datos completos (foto, rol real)
    this.dashboardService.getPerfilUsuario().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          const personal = res.data.personal;
          this.usuarioActual = {
            nombre: `${personal.nombre} ${personal.apellido}`,
            rol: personal.rol,
            iniciales: this.generarIniciales(personal.nombre, personal.apellido),
            foto: personal.fotoUrl
          };
        }
      },
      error: (err) => console.error('Error cargando perfil en Más:', err)
    });
  }

  generarIniciales(nombre: string, apellido: string): string {
    const inicialNombre = nombre ? nombre.charAt(0).toUpperCase() : '';
    const inicialApellido = apellido ? apellido.charAt(0).toUpperCase() : '';
    return (inicialNombre + inicialApellido) || 'U';
  }

  confirmarCerrarSesion() {
    this.authService.solicitarCerrarSesion();
  }

  cerrarModalLogout() {
    this.showLogoutModal = false;
    document.body.style.overflow = '';
  }

  ejecutarCerrarSesion() {
    this.showLogoutModal = false;
    document.body.style.overflow = '';
    document.documentElement.removeAttribute('data-theme');
    this.authService.logout();
  }
}
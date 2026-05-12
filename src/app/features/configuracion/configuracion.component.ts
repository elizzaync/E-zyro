import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';
import { DashboardService } from '../../core/services/dashboard.service';

@Component({
  selector: 'app-configuracion',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './configuracion.component.html',
  styleUrls: ['./configuracion.component.css']
})
export class ConfiguracionComponent implements OnInit {
  usuarioActual = { nombre: 'Cargando...', rol: '...', iniciales: '', foto: '' };
  showLogoutModal = false;
  temaActual: string = 'claro';

  constructor(
    private authService: AuthService,
    private dashboardService: DashboardService
  ) {}

  ngOnInit(): void {
    this.cargarDatosDeUsuario();
    this.verificarTemaActual();
  }

  cargarDatosDeUsuario(): void {
    // Jalamos nombre desde cache local rápido
    const userDataString = localStorage.getItem('ezyro_user');
    if (userDataString) {
      const u = JSON.parse(userDataString);
      this.usuarioActual.nombre = u.nombre_completo || 'Usuario';
      this.usuarioActual.iniciales = this.generarIniciales(this.usuarioActual.nombre, '');
    }

    // Jalamos correo y foto real del endpoint
    this.dashboardService.getPerfilUsuario().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          const personal = res.data.personal;
          this.usuarioActual = {
            nombre: `${personal.nombre} ${personal.apellido}`,
            rol: personal.rol || 'Usuario',
            iniciales: this.generarIniciales(personal.nombre, personal.apellido),
            foto: personal.fotoUrl
          };
        }
      },
      error: (err) => console.error('Error cargando perfil en Configuración:', err)
    });
  }

  verificarTemaActual() {
    const t = localStorage.getItem('ezyro_tema') || 'claro';
    this.temaActual = t === 'dark' ? 'oscuro' : 'claro';
  }

  alternarTema() {
    const html = document.documentElement;
    const nuevo = html.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    html.setAttribute('data-theme', nuevo);
    localStorage.setItem('ezyro_tema', nuevo);
    this.verificarTemaActual(); // Actualiza el texto en la vista
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
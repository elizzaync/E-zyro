import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-navbar',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './navbar.component.html',
  styleUrls: ['./navbar.component.css']
})
export class NavbarComponent implements OnInit {
  usuarioActual = { nombre: 'Cargando...', rol: '...', iniciales: '', id: 'EMP-0000' };

  // Control del menú
  isMenuOpen = false;

  constructor(private authService: AuthService) {}

  ngOnInit(): void {
    this.cargarDatosDeUsuario();
    this.inicializarTema();
  }

  // --- LÓGICA DEL MENÚ ---
  toggleMenu(): void {
    this.isMenuOpen = !this.isMenuOpen;
  }

  cerrarMenu(): void {
    this.isMenuOpen = false;
  }

  cerrarSesion(): void {
    // CLAVE: Limpiamos la configuración manual del HTML antes de salir.
    // Así el Login vuelve a comportarse de forma 100% automática.
    document.documentElement.removeAttribute('data-theme');

    this.authService.logout();
  }

  // --- LÓGICA DEL TEMA ---
  inicializarTema(): void {
    // Al entrar al Home, leemos la memoria y aplicamos el tema forzado si existe
    const temaGuardado = localStorage.getItem('ezyro_tema');
    if (temaGuardado) {
      document.documentElement.setAttribute('data-theme', temaGuardado);
    }
  }

  alternarTema(): void {
    const html = document.documentElement;
    // Evaluamos si estamos en oscuro (ya sea porque el HTML lo dice o por el navegador)
    const isDark = html.getAttribute('data-theme') === 'dark' ||
                   (!html.hasAttribute('data-theme') && window.matchMedia('(prefers-color-scheme: dark)').matches);

    // Cambiamos al tema opuesto
    const nuevoTema = isDark ? 'light' : 'dark';
    html.setAttribute('data-theme', nuevoTema);
    localStorage.setItem('ezyro_tema', nuevoTema);
  }
  // --- TUS FUNCIONES BLINDADAS ---
  cargarDatosDeUsuario(): void {
    try {
      const userDataString = localStorage.getItem('ezyro_user');
      if (userDataString) {
        const userData = JSON.parse(userDataString);
        const nombreReal = userData.nombre_completo || 'Usuario E-zyro';
        const rolReal = userData.rol || 'Técnico';

        this.usuarioActual.nombre = nombreReal;
        this.usuarioActual.rol = rolReal;
        this.usuarioActual.iniciales = this.generarIniciales(nombreReal);
        // Generamos un ID ficticio para el diseño, luego lo puedes traer de tu BD
        this.usuarioActual.id = 'EMP-' + Math.floor(1000 + Math.random() * 9000);
      }
    } catch (error) {
      console.error("Error al cargar usuario:", error);
    }
  }

  generarIniciales(nombreCompleto: string): string {
    if (!nombreCompleto || typeof nombreCompleto !== 'string') return 'U';
    const partes = nombreCompleto.trim().split(' ');
    if (partes.length >= 2) return (partes[0][0] + partes[1][0]).toUpperCase();
    else if (nombreCompleto.length >= 2) return nombreCompleto.substring(0, 2).toUpperCase();
    else return nombreCompleto.toUpperCase();
  }
}
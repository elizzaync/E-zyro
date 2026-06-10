import { Component, OnInit } from '@angular/core';
import { RouterOutlet, Router, NavigationEnd } from '@angular/router';
import { filter } from 'rxjs/operators';
import { CommonModule } from '@angular/common';
import { ToastComponent } from './shared/components/toast/toast.component';
import { NavbarComponent } from './shared/components/navbar/navbar.component';
import { AuthService } from './core/services/auth.service';
import { ChatbotComponent } from './shared/components/chatbot/chatbot.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, ToastComponent, NavbarComponent, ChatbotComponent, CommonModule],
  templateUrl: './app.html',
})
export class App implements OnInit {
  title = 'e-zyro';
  mostrarNavbar = false;

  // Variable local para controlar la vista del modal
  showLogoutModal = false;

  constructor(
    private router: Router,
    private authService: AuthService
  ) {
    this.verificarRuta(window.location.pathname);
    this.router.events.pipe(
      filter(event => event instanceof NavigationEnd)
    ).subscribe((event: any) => {
      this.verificarRuta(event.urlAfterRedirects || event.url);
    });
  }

  ngOnInit(): void {
    this.authService.showLogoutModal$.subscribe(estado => {
      this.showLogoutModal = estado;
    });
  }

  verificarRuta(url: string) {
    if (url.includes('/login') || url.includes('/reset-password') || url === '/') {
      this.mostrarNavbar = false;
    } else {
      this.mostrarNavbar = true;
    }

    // Fondo de partículas (public/background.js): SOLO portal cliente
    // (rutas /portal-cliente/* protegidas por clientPortalGuard → rol ClienteExterno)
    const esPortal = url.startsWith('/portal-cliente');
    (window as any).__particleBgEnabled = esPortal;
    (window as any).setParticleBackground?.(esPortal);
  }

  get esPortalCliente(): boolean {
    return window.location.pathname.startsWith('/portal-cliente');
  }

  cancelarSalir() {
    this.authService.cancelarCerrarSesion();
  }

  confirmarSalir() {
    this.authService.ejecutarCerrarSesion();
  }
}
import { Component } from '@angular/core';
import { RouterOutlet, Router, NavigationEnd } from '@angular/router';
import { filter } from 'rxjs/operators';
import { ToastComponent } from './shared/components/toast/toast.component';
import { NavbarComponent } from './shared/components/navbar/navbar.component';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, ToastComponent, NavbarComponent],
  templateUrl: './app.html',
})
export class App {
  title = 'e-zyro';

  // Por defecto lo ocultamos hasta saber en qué página estamos
  mostrarNavbar = false;

  constructor(private router: Router) {
    // 1. Revisamos la ruta inicial justo cuando arranca la app
    this.verificarRuta(window.location.pathname);

    // 2. Revisamos la ruta cada vez que el usuario navega a otra pantalla
    this.router.events.pipe(
      filter(event => event instanceof NavigationEnd)
    ).subscribe((event: any) => {
      // urlAfterRedirects captura la URL final, incluso si hubo una redirección
      this.verificarRuta(event.urlAfterRedirects || event.url);
    });
  }

  // Función maestra que decide si se muestra o no
  verificarRuta(url: string) {
    // Si la URL tiene '/login' o es exactamente la ruta raíz '/', ocultamos el Navbar
    if (url.includes('/login') || url === '/') {
      this.mostrarNavbar = false;
    } else {
      this.mostrarNavbar = true;
    }
  }
}
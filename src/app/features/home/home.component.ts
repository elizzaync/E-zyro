import { Component, OnInit, AfterViewInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { SummaryCardComponent } from './components/summary-card/summary-card.component';
import { CalendarWidgetComponent } from './components/calendar-widget/calendar-widget.component';
import { MonthlySummaryWidgetComponent } from './components/monthly-summary-widget/monthly-summary-widget.component';
import { UpcomingServicesWidgetComponent } from './components/upcoming-services-widget/upcoming-services-widget.component';
import { QuickActionsWidgetComponent } from './components/quick-actions-widget/quick-actions-widget.component';
import { DashboardService } from '../../core/services/dashboard.service';
import { Subscription } from 'rxjs';
import { FcmService } from '../../core/services/fcm.service';
@Component({
  selector: 'app-home',
  standalone: true,
  imports: [
    CommonModule,
    SummaryCardComponent,
    CalendarWidgetComponent,
    MonthlySummaryWidgetComponent,
    UpcomingServicesWidgetComponent,
    QuickActionsWidgetComponent
  ],
  templateUrl: './home.component.html',
  styleUrls: ['./home.component.css']
})
export class HomeComponent implements OnInit, AfterViewInit, OnDestroy {
  private dashboardService = inject(DashboardService);
  private fcmService = inject(FcmService);
  private http = inject(HttpClient);

  nombreUsuario = 'Cargando...';
  saludoTiempo = 'Hola';
  fechaActual = '';

  climaData: { icono: string; temperatura: number; descripcion: string; ciudad: string } | null = null;

  perfilSub!: Subscription;
  private refreshWidgetsSub!: Subscription;

  // 👇 AQUÍ ESTÁ LA VARIABLE QUE SOLUCIONA TU ERROR
  permisosUsuario: string[] = [];

  tarjetasHome: any[] = [
    { titulo: 'Activos', valor: '...', icono: 'clock', tema: 'theme-yellow', subtitulo: 'En proceso' },
    { titulo: 'Pendientes', valor: '...', icono: 'wrench', tema: 'theme-gray', subtitulo: 'Esperando asignación' },
    { titulo: 'Completados', valor: '...', icono: 'check', tema: 'theme-green', subtitulo: 'Últimos 7 días' }
  ];

  constructor() {}

ngOnInit(): void {
    this.configurarSaludoYFecha();
    this.cargarUsuario();
    this.cargarClima();

    this.refreshWidgetsSub = this.dashboardService.refreshWidgets$.subscribe(() => {
      this.cargarTarjetasDesdeBackend();
    });

    if (this.dashboardService.perfilActualizado$) {
      this.perfilSub = this.dashboardService.perfilActualizado$.subscribe((nuevoNombre: string) => {
        this.nombreUsuario = nuevoNombre.split(' ')[0];
      });
    }
  }

  ngOnDestroy(): void {
    if (this.perfilSub) this.perfilSub.unsubscribe();
    if (this.refreshWidgetsSub) this.refreshWidgetsSub.unsubscribe();
  }

  ngAfterViewInit(): void {
    const observerOptions = { threshold: 0.1, rootMargin: '0px' };
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
        } else {
          entry.target.classList.remove('is-visible');
        }
      });
    }, observerOptions);

    const revealElements = document.querySelectorAll('.reveal-on-scroll');
    revealElements.forEach(el => observer.observe(el));
  }

  cargarUsuario(): void {
    try {
      // 1. Cargamos el nombre rápido para que no se vea vacío
      const userDataString = localStorage.getItem('ezyro_user');
      if (userDataString) {
        const userData = JSON.parse(userDataString);
        if (userData.nombre_completo) {
          this.nombreUsuario = userData.nombre_completo.split(' ')[0];
        }
      }

      // 👇 2. Leemos los permisos del caché rápido para pintar los widgets al instante
      const permisosString = localStorage.getItem('ezyro_permisos');
      if (permisosString) {
        this.permisosUsuario = JSON.parse(permisosString);
      }
    } catch (error) {
      console.error("Error al cargar datos de usuario en caché:", error);
    }

    // 3. Confirmamos los permisos 100% reales con PostgreSQL
    this.dashboardService.getPerfilUsuario().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.nombreUsuario = res.data.personal.nombre.split(' ')[0];

          // 👇 ACTUALIZAMOS LOS PERMISOS EN TIEMPO REAL DESDE EL BACKEND
          this.permisosUsuario = res.data.personal.permisos_modulo || [];
          localStorage.setItem('ezyro_permisos', JSON.stringify(this.permisosUsuario));
        }
      },
      error: (err) => console.error("Error al cargar nombre real desde BD:", err)
    });
  }

  cargarClima(): void {
    const url = 'https://api.open-meteo.com/v1/forecast?latitude=-12.046&longitude=-77.043&current_weather=true&timezone=America%2FLima';
    this.http.get<any>(url).subscribe({
      next: (res) => {
        const cw = res.current_weather;
        const { icono, descripcion } = this.mapearClima(cw.weathercode);
        this.climaData = { icono, descripcion, temperatura: Math.round(cw.temperature), ciudad: 'Lima, PE' };
      },
      error: () => { this.climaData = null; }
    });
  }

  private mapearClima(code: number): { icono: string; descripcion: string } {
    if (code === 0)  return { icono: '☀️', descripcion: 'Despejado' };
    if (code <= 3)   return { icono: '⛅', descripcion: 'Nublado' };
    if (code <= 48)  return { icono: '🌫️', descripcion: 'Neblina' };
    if (code <= 55)  return { icono: '🌦️', descripcion: 'Llovizna' };
    if (code <= 65)  return { icono: '🌧️', descripcion: 'Lluvia' };
    if (code <= 82)  return { icono: '🌦️', descripcion: 'Chubascos' };
    return { icono: '⛈️', descripcion: 'Tormenta' };
  }

  configurarSaludoYFecha(): void {
    const hora = new Date().getHours();
    if (hora < 12) {
      this.saludoTiempo = 'Buenos días';
    } else if (hora < 19) {
      this.saludoTiempo = 'Buenas tardes';
    } else {
      this.saludoTiempo = 'Buenas noches';
    }

    const opciones: Intl.DateTimeFormatOptions = { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' };
    let fecha = new Date().toLocaleDateString('es-ES', opciones);
    this.fechaActual = fecha.charAt(0).toUpperCase() + fecha.slice(1);
  }

  cargarTarjetasDesdeBackend(): void {
    this.dashboardService.getResumenKPIs().subscribe({
      next: (response: any) => {
        if (response.status === 'success' && response.data) {
          this.tarjetasHome[0].valor = response.data.activos;
          this.tarjetasHome[1].valor = response.data.pendientes;
          this.tarjetasHome[2].valor = response.data.completados;
        }
      },
      error: (error) => {
        console.error("Error al obtener datos:", error);
        this.tarjetasHome[0].valor = 0;
        this.tarjetasHome[1].valor = 0;
        this.tarjetasHome[2].valor = 0;
      }
    });
  }
}
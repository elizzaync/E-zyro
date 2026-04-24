import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NavbarComponent } from '../../shared/components/navbar/navbar.component';
import { SummaryCardComponent } from '../../shared/components/summary-card/summary-card.component';
import { CalendarWidgetComponent } from '../../shared/components/calendar-widget/calendar-widget.component';
@Component({
  selector: 'app-home',
  standalone: true,
  imports: [CommonModule, NavbarComponent, SummaryCardComponent, CalendarWidgetComponent],
  templateUrl: './home.component.html',
  styleUrls: ['./home.component.css']
})
export class HomeComponent implements OnInit {
  nombreUsuario = 'Usuario';
  saludoTiempo = 'Hola';
  fechaActual = '';

  // Agregamos un 'subtitulo' para darle más contexto a la tarjeta
  tarjetasHome: any[] = [
    { titulo: 'Activos', valor: 2, icono: 'clock', tema: 'theme-yellow', subtitulo: 'En proceso' },
    { titulo: 'Pendientes', valor: 3, icono: 'wrench', tema: 'theme-gray', subtitulo: 'Esperando asignación' },
    { titulo: 'Completados', valor: 8, icono: 'check', tema: 'theme-green', subtitulo: 'Últimos 7 días' }
  ];

  ngOnInit(): void {
    this.cargarUsuario();
    this.configurarSaludoYFecha();
  }

  cargarUsuario(): void {
    try {
      const userDataString = localStorage.getItem('ezyro_user');
      if (userDataString) {
        const userData = JSON.parse(userDataString);
        const nombreCompleto = userData.nombre_completo || 'Usuario';
        this.nombreUsuario = nombreCompleto.split(' ')[0];
      }
    } catch (error) {
      console.error("Error al cargar usuario en home:", error);
    }
  }

  configurarSaludoYFecha(): void {
    // 1. Saludo según la hora
    const hora = new Date().getHours();
    if (hora < 12) {
      this.saludoTiempo = 'Buenos días';
    } else if (hora < 19) {
      this.saludoTiempo = 'Buenas tardes';
    } else {
      this.saludoTiempo = 'Buenas noches';
    }

    // 2. Fecha formateada (Ej: "viernes, 24 de abril de 2026")
    const opcionesFecha: Intl.DateTimeFormatOptions = {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
    };
    this.fechaActual = new Date().toLocaleDateString('es-ES', opcionesFecha);
    // Capitalizar la primera letra
    this.fechaActual = this.fechaActual.charAt(0).toUpperCase() + this.fechaActual.slice(1);
  }
}
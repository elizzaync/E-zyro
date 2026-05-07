import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DashboardService } from '../../../../core/services/dashboard.service';

interface StatCard {
  valor: string;
  etiqueta: string;
  icono: 'check' | 'briefcase' | 'solicitud' | 'time';
  clase: 'green' | 'light-green' | 'info' | 'time';
}

@Component({
  selector: 'app-profile-cards',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './profile-cards.component.html',
  styleUrls: ['./profile-cards.component.css']
})
export class ProfileCardsComponent implements OnInit {
  private dashboardService = inject(DashboardService);

  cargando = true;
  estadisticas: StatCard[] = [];

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.cargando = true;
    this.dashboardService.getPerfilEstadisticas().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          const d = res.data;
          this.estadisticas = [
            { valor: String(d.servicios_completados), etiqueta: 'Servicios Completados', icono: 'check',     clase: 'green' },
            { valor: String(d.asistencias_mes),       etiqueta: 'Asistencias del Mes',   icono: 'briefcase', clase: 'light-green' },
            { valor: String(d.solicitudes_pendientes), etiqueta: 'Solicitudes Pendientes', icono: 'solicitud', clase: 'info' },
            { valor: d.tiempo_promedio,                etiqueta: 'Tiempo Promedio',        icono: 'time',      clase: 'time' }
          ];
        }
        this.cargando = false;
      },
      error: () => { this.cargando = false; }
    });
  }
}

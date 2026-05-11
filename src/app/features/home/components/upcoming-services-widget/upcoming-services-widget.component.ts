import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DashboardService } from '../../../../core/services/dashboard.service'; // Ajusta la ruta si es necesario

@Component({
  selector: 'app-upcoming-services-widget',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './upcoming-services-widget.component.html',
  styleUrls: ['./upcoming-services-widget.component.css']
})
export class UpcomingServicesWidgetComponent implements OnInit {

  servicios: any[] = [];

  constructor(private dashboardService: DashboardService) {}

  ngOnInit(): void {
    this.cargarServicios();
  }

  cargarServicios() {
    this.dashboardService.getProximosServicios().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.servicios = res.data;
        }
      },
      error: (err) => {
        console.error('Error al cargar próximos servicios', err);
      }
    });
  }
}
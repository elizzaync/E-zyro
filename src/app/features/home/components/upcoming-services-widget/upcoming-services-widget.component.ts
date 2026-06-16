import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { DashboardService } from '../../../../core/services/dashboard.service';
import { Subscription } from 'rxjs';

@Component({
  selector: 'app-upcoming-services-widget',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './upcoming-services-widget.component.html',
  styleUrls: ['./upcoming-services-widget.component.css']
})
export class UpcomingServicesWidgetComponent implements OnInit, OnDestroy {
  servicios: any[] = [];
  isLoading = true;
  hasError = false;
  private refreshSub!: Subscription;

  constructor(private dashboardService: DashboardService) {}

  ngOnInit(): void {
    this.cargarServicios();
    this.refreshSub = this.dashboardService.refreshWidgets$.subscribe(() => {
      this.cargarServicios();
    });
  }

  ngOnDestroy(): void {
    this.refreshSub?.unsubscribe();
  }

  cargarServicios(): void {
    this.isLoading = true;
    this.hasError = false;
    this.dashboardService.getProximosServicios().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.servicios = res.data ?? [];
        }
        this.isLoading = false;
      },
      error: () => {
        this.hasError = true;
        this.isLoading = false;
      }
    });
  }

  estadoClass(estado: string): string {
    const map: Record<string, string> = {
      'Activo': 'badge-active',
      'Pendiente': 'badge-pending',
      'En_Proceso': 'badge-active',
      'Completado': 'badge-done',
      'Cancelado': 'badge-cancel',
    };
    return map[estado] ?? 'badge-pending';
  }

  estadoLabel(estado: string): string {
    return estado === 'En_Proceso' ? 'En Proceso' : estado;
  }
}

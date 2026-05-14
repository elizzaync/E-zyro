import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { OperacionesCardsComponent, MetricaOperacion } from './components/operaciones-cards/operaciones-cards.component';
import { OperacionesServiciosComponent, ServicioOperacion } from './components/operaciones-servicios/operaciones-servicios.component';
import { OperacionesService } from '../../core/services/operaciones.service';
import { ToastService } from '../../core/services/toast.service';
import { AlertComponent } from '../../shared/components/login/alert.component';

@Component({
  selector: 'app-operaciones',
  standalone: true,
  imports: [CommonModule, OperacionesCardsComponent, OperacionesServiciosComponent, AlertComponent],
  templateUrl: './operaciones.component.html',
  styleUrls: ['./operaciones.component.css']
})
export class OperacionesComponent implements OnInit {

  private svc    = inject(OperacionesService);
  private toast  = inject(ToastService);
  private router = inject(Router);

  datosTarjetas:  MetricaOperacion[]  = [];
  listaServicios: ServicioOperacion[] = [];

  isLoading    = true;
  errorMessage: string | null = null;

  ngOnInit(): void {
    this.cargarDashboard();
  }

  cargarDashboard(): void {
    this.isLoading    = true;
    this.errorMessage = null;

    this.svc.getDashboardData().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.datosTarjetas  = res.data.metricas;
          this.listaServicios = res.data.servicios;
        } else {
          this.errorMessage = 'No se pudieron cargar los datos operativos.';
        }
        this.isLoading = false;
      },
      error: (err: any) => {
        console.error('Error cargando operaciones:', err);
        this.errorMessage = 'Error de conexión con el servidor. Intenta nuevamente.';
        this.toast.mostrar('Error de conexión', 'error');
        this.isLoading = false;
      }
    });
  }

  irAlCalendario(): void {
    this.router.navigate(['/home']);
  }
}

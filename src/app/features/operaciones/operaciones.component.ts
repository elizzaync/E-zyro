import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { OperacionesService } from '../../core/services/operaciones.service';
import { ToastService } from '../../core/services/toast.service';
import { AlertComponent } from '../../shared/components/login/alert.component';

export interface ProyectoOperacion {
  id: string;
  orden_trabajo: string;
  nombre_proyecto: string;
  estado: string;
  fecha_inicio: string | null;
  cliente: string;
  total_servicios: number;
}

@Component({
  selector: 'app-operaciones',
  standalone: true,
  imports: [CommonModule, AlertComponent],
  templateUrl: './operaciones.component.html',
  styleUrls: ['./operaciones.component.css']
})
export class OperacionesComponent implements OnInit {
  private svc    = inject(OperacionesService);
  private toast  = inject(ToastService);
  private router = inject(Router);

  proyectos: ProyectoOperacion[] = [];
  isLoading    = true;
  errorMessage: string | null = null;

  ngOnInit(): void { this.cargarProyectos(); }

  cargarProyectos(): void {
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.getProyectos().subscribe({
      next: (res: any) => {
        this.proyectos = res;
        this.isLoading = false;
      },
      error: (err: any) => {
        console.error('Error cargando proyectos:', err);
        this.errorMessage = 'Error de conexión con el servidor. Intenta nuevamente.';
        this.toast.mostrar('Error de conexión', 'error');
        this.isLoading = false;
      }
    });
  }

  irAProyecto(id: string): void {
    this.router.navigate(['/operaciones/proyecto', id]);
  }

  estadoClass(estado: string): string {
    const map: Record<string, string> = {
      'Pendiente':  'estado-pendiente',
      'En_Proceso': 'estado-en-proceso',
      'En_Pausa':   'estado-en-pausa',
      'Completado': 'estado-completado',
      'Cancelado':  'estado-cancelado',
    };
    return map[estado] ?? 'estado-pendiente';
  }

  estadoLabel(estado: string): string {
    const map: Record<string, string> = {
      'En_Proceso': 'En Proceso',
      'En_Pausa':   'En Pausa',
    };
    return map[estado] ?? estado;
  }
}

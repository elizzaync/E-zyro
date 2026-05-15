import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { ActivatedRoute, Router } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';

export interface ServicioProyecto {
  id: string;
  nombre: string;
  descripcion: string | null;
  estado: string;
  orden: number;
  fecha_programada: string | null;
  estado_color: 'rojo' | 'amarillo' | 'verde';
}

@Component({
  selector: 'app-operaciones-servicios-lista',
  standalone: true,
  imports: [CommonModule, SpinnerComponent],
  templateUrl: './operaciones-servicios-lista.component.html',
  styleUrls: ['./operaciones-servicios-lista.component.css']
})
export class OperacionesServiciosListaComponent implements OnInit {
  private route  = inject(ActivatedRoute);
  private router = inject(Router);
  private svc    = inject(OperacionesService);

  proyectoId: string | null = null;
  servicios: ServicioProyecto[] = [];
  isLoading    = true;
  errorMessage: string | null = null;

  filtros      = ['Todos', 'Pendiente', 'En_Proceso', 'Completado'];
  filtroActual = 'Todos';

  get serviciosFiltrados(): ServicioProyecto[] {
    if (this.filtroActual === 'Todos') return this.servicios;
    return this.servicios.filter(s => s.estado === this.filtroActual);
  }

  ngOnInit(): void {
    this.proyectoId = this.route.snapshot.paramMap.get('id');
    this.cargarServicios();
  }

  cargarServicios(): void {
    if (!this.proyectoId) {
      this.errorMessage = 'ID de proyecto inválido.';
      this.isLoading = false;
      return;
    }
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.getServiciosPorProyecto(this.proyectoId).subscribe({
      next: (res: any) => {
        this.servicios = res;
        this.isLoading = false;
      },
      error: (err: any) => {
        console.error('Error cargando servicios:', err);
        this.errorMessage = err?.error?.detail ?? 'Error al cargar los servicios del proyecto.';
        this.isLoading = false;
      }
    });
  }

  setFiltro(filtro: string): void { this.filtroActual = filtro; }

  volver(): void { this.router.navigate(['/operaciones']); }

  irAlServicio(id: string): void { this.router.navigate(['/operaciones/servicio', id]); }

  estadoLabel(estado: string): string {
    const map: Record<string, string> = { 'En_Proceso': 'En Proceso' };
    return map[estado] ?? estado;
  }
}

import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router'; // 👈 1. AÑADE ESTA LÍNEA

export interface ServicioOperacion {
  id: string;
  cliente: string;
  tipoServicio: string;
  ubicacion: string;
  fechaStr: string;
  horaStr: string;
  estado: 'Pendiente' | 'Activo' | 'Completado';
  alerta?: boolean;
  estadoColor?: 'rojo' | 'amarillo' | 'verde';
}

@Component({
  selector: 'app-operaciones-servicios',
  standalone: true,
  imports: [
    CommonModule,
    RouterModule // 👈 2. AÑADE ESTO AQUÍ
  ],
  templateUrl: './operaciones-servicios.component.html',
  styleUrls: ['./operaciones-servicios.component.css']
})
export class OperacionesServiciosComponent {
  @Input() servicios: ServicioOperacion[] = [];

  filtros: string[] = ['Todos', 'Pendiente', 'Activos', 'Completado'];
  filtroActual: string = 'Todos';

  get serviciosFiltrados() {
    if (this.filtroActual === 'Todos') {
      return this.servicios;
    }
    const estadoFiltro = this.filtroActual === 'Activos' ? 'Activo' : this.filtroActual;
    return this.servicios.filter(s => s.estado === estadoFiltro);
  }

  setFiltro(filtro: string) {
    this.filtroActual = filtro;
  }
}
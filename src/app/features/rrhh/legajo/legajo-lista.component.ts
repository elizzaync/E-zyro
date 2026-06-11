import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';

export interface EmpleadoLegajo {
  id: string;
  nombreCompleto: string;
  cargo: string;
  estado: 'Activo' | 'Inactivo';
  documentosCount: number;
  iniciales: string;
  ultimaActualizacion: string;
}

@Component({
  selector: 'app-legajo-lista',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './legajo-lista.component.html',
  styleUrls: ['./legajo-lista.component.css']
})
export class LegajoListaComponent implements OnInit {
  searchTerm: string = '';
  filtroEstado: 'Todos' | 'Activo' | 'Inactivo' = 'Todos';

  // Mock Data extendida
  empleados: EmpleadoLegajo[] = [
    { id: '1', nombreCompleto: 'Carlos Mendoza', cargo: 'Jefe de Operaciones', estado: 'Activo', documentosCount: 12, iniciales: 'CM', ultimaActualizacion: 'Hoy, 09:30 AM' },
    { id: '2', nombreCompleto: 'Lucía Díaz', cargo: 'Supervisor', estado: 'Activo', documentosCount: 8, iniciales: 'LD', ultimaActualizacion: 'Ayer' },
    { id: '3', nombreCompleto: 'Marco Quispe', cargo: 'Técnico Mecánico', estado: 'Activo', documentosCount: 4, iniciales: 'MQ', ultimaActualizacion: 'Hace 3 días' },
    { id: '4', nombreCompleto: 'Rosa Huanca', cargo: 'Técnico de Campo', estado: 'Activo', documentosCount: 5, iniciales: 'RH', ultimaActualizacion: 'Hace 1 sem.' },
    { id: '5', nombreCompleto: 'Luis Vargas', cargo: 'Logístico', estado: 'Inactivo', documentosCount: 15, iniciales: 'LV', ultimaActualizacion: 'Hace 2 meses' }
  ];

  constructor() {}

  ngOnInit(): void {}

  // Cálculo de KPIs en tiempo real
  get stats() {
    return {
      total: this.empleados.length,
      activos: this.empleados.filter(e => e.estado === 'Activo').length,
      totalDocs: this.empleados.reduce((acc, curr) => acc + curr.documentosCount, 0)
    };
  }

  // Filtrado doble (por texto y por pestaña de estado)
  get filteredEmpleados(): EmpleadoLegajo[] {
    return this.empleados.filter(emp => {
      const matchName = !this.searchTerm ||
        emp.nombreCompleto.toLowerCase().includes(this.searchTerm.toLowerCase()) ||
        emp.cargo.toLowerCase().includes(this.searchTerm.toLowerCase());

      const matchEstado = this.filtroEstado === 'Todos' || emp.estado === this.filtroEstado;

      return matchName && matchEstado;
    });
  }

  setFiltro(estado: 'Todos' | 'Activo' | 'Inactivo') {
    this.filtroEstado = estado;
  }
}
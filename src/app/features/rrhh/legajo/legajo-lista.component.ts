import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { RrhhService, EmpleadoLegajoDto } from '../../../core/services/rrhh.service';

@Component({
  selector: 'app-legajo-lista',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './legajo-lista.component.html',
  styleUrls: ['./legajo-lista.component.css']
})
export class LegajoListaComponent implements OnInit {
  searchTerm = '';
  filtroEstado: 'Todos' | 'Activo' | 'Inactivo' = 'Todos';
  empleados: EmpleadoLegajoDto[] = [];
  cargando = true;
  error = '';

  constructor(private rrhhService: RrhhService, private router: Router) {}

  ngOnInit(): void {
    this.rrhhService.getEmpleados().subscribe({
      next: (res) => {
        this.empleados = res.empleados;
        this.cargando = false;
      },
      error: () => {
        this.error = 'No se pudo cargar el listado de empleados.';
        this.cargando = false;
      }
    });
  }

  get stats() {
    return {
      total: this.empleados.length,
      activos: this.empleados.filter(e => e.estado === 'Activo').length,
      totalDocs: this.empleados.reduce((acc, e) => acc + e.documentosCount, 0)
    };
  }

  get filteredEmpleados(): EmpleadoLegajoDto[] {
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

  abrirExpediente(empleado: EmpleadoLegajoDto) {
    this.router.navigate(['/rrhh/legajo', empleado.id]);
  }
}

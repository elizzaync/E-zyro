import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { RrhhService, EmpleadoLegajoDto } from '../../../core/services/rrhh.service';

@Component({
  selector: 'app-legajo-lista',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './legajo-lista.component.html',
  styleUrls: ['./legajo-lista.component.css']
})
export class LegajoListaComponent implements OnInit {
  searchTerm    = '';
  filtroEstado: 'Todos' | 'Activo' | 'Inactivo' = 'Todos';
  empleados: EmpleadoLegajoDto[] = [];
  cargando = true;
  error    = '';

  // ── Paginación ─────────────────────────────────────────────────────────
  currentPage    = 1;
  readonly PER_PAGE = 10;
  totalRegistros = 0;
  totalPaginas   = 1;

  constructor(private rrhhService: RrhhService, private router: Router) {}

  ngOnInit(): void {
    this.cargar();
  }

  private cargar(): void {
    this.cargando = true;
    this.rrhhService.getEmpleados(this.currentPage, this.PER_PAGE).subscribe({
      next: (res) => {
        this.empleados      = res.empleados;
        this.totalRegistros = res.total;
        this.totalPaginas   = res.total_paginas;
        this.cargando = false;
      },
      error: () => {
        this.error   = 'No se pudo cargar el listado de empleados.';
        this.cargando = false;
      }
    });
  }

  get stats() {
    return {
      total:     this.totalRegistros,
      activos:   this.empleados.filter(e => e.estado === 'Activo').length,
      totalDocs: this.empleados.reduce((acc, e) => acc + e.documentosCount, 0)
    };
  }

  get filteredEmpleados(): EmpleadoLegajoDto[] {
    return this.empleados.filter(emp => {
      const matchName  = !this.searchTerm ||
        emp.nombreCompleto.toLowerCase().includes(this.searchTerm.toLowerCase()) ||
        emp.cargo.toLowerCase().includes(this.searchTerm.toLowerCase());
      const matchEstado = this.filtroEstado === 'Todos' || emp.estado === this.filtroEstado;
      return matchName && matchEstado;
    });
  }

  get rangoMostrando() {
    const desde = (this.currentPage - 1) * this.PER_PAGE + 1;
    const hasta = Math.min(this.currentPage * this.PER_PAGE, this.totalRegistros);
    return { desde, hasta, total: this.totalRegistros };
  }

  setFiltro(estado: 'Todos' | 'Activo' | 'Inactivo') {
    this.filtroEstado = estado;
    this.currentPage  = 1;
    this.cargar();
  }

  irPagina(p: number): void {
    if (p < 1 || p > this.totalPaginas) return;
    this.currentPage = p;
    this.cargar();
  }

  get paginasBotones(): number[] {
    const total = this.totalPaginas;
    const cur   = this.currentPage;
    const pages: number[] = [];
    const start = Math.max(1, cur - 2);
    const end   = Math.min(total, cur + 2);
    for (let i = start; i <= end; i++) pages.push(i);
    return pages;
  }

  abrirExpediente(empleado: EmpleadoLegajoDto) {
    this.router.navigate(['/rrhh/legajo', empleado.id]);
  }
}

import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DashboardService } from '../../../../core/services/dashboard.service';

@Component({
  selector: 'app-monthly-summary-widget',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './monthly-summary-widget.component.html',
  styleUrls: ['./monthly-summary-widget.component.css']
})
export class MonthlySummaryWidgetComponent implements OnInit {

  // 🔥 1. Inicializamos con el mes real del navegador para que no diga "Resumen de "
  mesActual = this.obtenerNombreMesActual();

  // 🔥 2. Creamos la estructura visual vacía para que se dibujen las 4 barras grises al instante
  semanas: any[] = [
    { nombre: 'Semana 1', completados: 0, total: 0 },
    { nombre: 'Semana 2', completados: 0, total: 0 },
    { nombre: 'Semana 3', completados: 0, total: 0 },
    { nombre: 'Semana 4', completados: 0, total: 0 }
  ];

  // 🔥 3. Estadísticas en cero para mantener la forma
  stats: any = { tasaExito: '0%', totalServicios: 0, esteMes: 0 };

  constructor(private dashboardService: DashboardService) {}

ngOnInit(): void {
    // 🔥 Escucha en tiempo real
    this.dashboardService.refreshWidgets$.subscribe(() => {
      this.cargarRendimiento();
    });
  }

  obtenerNombreMesActual(): string {
    const meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    const hoy = new Date();
    return `${meses[hoy.getMonth()]} ${hoy.getFullYear()}`;
  }

  cargarRendimiento() {
    this.dashboardService.getRendimientoMensual().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          // Cuando llega la data real, sobreescribe nuestra estructura vacía
          this.mesActual = res.data.mesActual;
          this.semanas = res.data.semanas;
          this.stats = res.data.stats;
        }
      },
      error: (err) => {
        console.error('Error al cargar el resumen mensual', err);
      }
    });
  }

  getPorcentaje(completados: number, total: number): number {
    if (total === 0) return 0;
    return (completados / total) * 100;
  }
}
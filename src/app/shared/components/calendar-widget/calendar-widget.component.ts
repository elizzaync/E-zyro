import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-calendar-widget',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './calendar-widget.component.html',
  styleUrls: ['./calendar-widget.component.css']
})
export class CalendarWidgetComponent implements OnInit {
  mesActual: string = '';
  diasSemana = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];
  diasMes: { num: number | null, isHoy: boolean, hasEvent: boolean }[] = [];

  ngOnInit() {
    this.generarCalendario();
  }

  generarCalendario() {
    const hoy = new Date();
    const mes = hoy.getMonth();
    const anio = hoy.getFullYear();

    // Nombres de meses en español
    const meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    this.mesActual = `${meses[mes]} ${anio}`;

    // Lógica para llenar los días
    const primerDia = new Date(anio, mes, 1).getDay();
    const diasEnMes = new Date(anio, mes + 1, 0).getDate();

    // Espacios vacíos antes del primer día
    for (let i = 0; i < primerDia; i++) {
      this.diasMes.push({ num: null, isHoy: false, hasEvent: false });
    }

    // Días reales
    for (let i = 1; i <= diasEnMes; i++) {
      const isHoy = (i === hoy.getDate());
      // Simulamos que algunos días tienen eventos (un puntito abajo)
      const hasEvent = [18, 22, 25].includes(i);
      this.diasMes.push({ num: i, isHoy, hasEvent });
    }
  }
}
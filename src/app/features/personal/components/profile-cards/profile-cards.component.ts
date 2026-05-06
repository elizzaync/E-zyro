import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-profile-cards', // Tu nombre correcto
  standalone: true,
  imports: [CommonModule],
  templateUrl: './profile-cards.component.html',
  styleUrls: ['./profile-cards.component.css']
})
export class ProfileCardsComponent {
  estadisticas = [
    { valor: '265', etiqueta: 'Órdenes Completadas', icono: 'check', clase: 'green' },
    { valor: '18', etiqueta: 'Asistencias del Mes', icono: 'briefcase', clase: 'light-green' },
    { valor: '5', etiqueta: 'Tickets Activos', icono: 'warning', clase: 'warning' },
    { valor: '1h 24m', etiqueta: 'Tiempo Promedio', icono: 'time', clase: 'time' }
  ];
}
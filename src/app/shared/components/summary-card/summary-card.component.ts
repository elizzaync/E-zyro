import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-summary-card',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './summary-card.component.html',
  styleUrls: ['./summary-card.component.css']
})
export class SummaryCardComponent {
  // Estos son los "huecos" que llenaremos desde el componente padre
  @Input() titulo: string = '';
  @Input() valor: number | string = 0;
  @Input() icono: 'clock' | 'wrench' | 'check' | 'calendar' = 'clock';
  @Input() tema: 'theme-yellow' | 'theme-gray' | 'theme-green' | 'theme-blue' = 'theme-gray';
  @Input() subtitulo: string = ''; // 👈 Nuevo input
}
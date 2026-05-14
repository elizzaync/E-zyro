import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

export interface MetricaOperacion {
  id: string;
  titulo: string;
  valor: number;
  colorIcono: string;
  resaltado?: boolean;
}

@Component({
  selector: 'app-operaciones-cards',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './operaciones-cards.component.html',
  styleUrls: ['./operaciones-cards.component.css']
})
export class OperacionesCardsComponent {
  @Input() metricas: MetricaOperacion[] = [];
}
import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-spinner',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './spinner.component.html',
  styleUrls: ['./spinner.component.css']
})
export class SpinnerComponent {
  @Input() size: number = 40; // Tamaño en píxeles
  @Input() thickness: number = 3; // Grosor del borde
  @Input() theme: 'primary' | 'light' = 'primary'; // 'primary' = verde, 'light' = blanco
  @Input() variant: 'ring' | 'loader' = 'ring'; // 'ring' = circular (botones), 'loader' = cuadrado (pantallas)
}
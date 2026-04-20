import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-alert',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './alert.component.html',
  styleUrls: ['./alert.component.css']
})
export class AlertComponent {
  // Recibe el mensaje a mostrar
  @Input({ required: true }) message!: string;

  // Define el estilo (por defecto será de error)
  @Input() type: 'error' | 'success' | 'warning' | 'info' = 'error';
}
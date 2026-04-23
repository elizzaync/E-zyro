import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-success-checkmark',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './success-checkmark.component.html',
  styleUrls: ['./success-checkmark.component.css']
})
export class SuccessCheckmarkComponent {
  @Input() message: string = 'Contraseña cambiada';
}
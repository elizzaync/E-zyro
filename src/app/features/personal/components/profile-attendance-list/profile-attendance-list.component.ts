import { Component, Input, OnChanges, SimpleChanges } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-profile-attendance-list',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './profile-attendance-list.component.html',
  styleUrls: ['./profile-attendance-list.component.css']
})
export class ProfileAttendanceListComponent implements OnChanges {
  @Input() registros: any[] = [];

  registroHoy: any = null;

  ngOnChanges(changes: SimpleChanges) {
    if (changes['registros'] && this.registros && this.registros.length > 0) {
      // Buscamos si el empleado tiene un turno activo hoy para mostrar el banner verde
      this.registroHoy = this.registros.find(r => r.estado === 'en_curso') || null;
    } else {
      this.registroHoy = null;
    }
  }
}
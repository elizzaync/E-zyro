import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { PermisoTramiteCardComponent, Solicitud } from '../permiso-tramite-card/permiso-tramite-card.component';

@Component({
  selector: 'app-permiso-historial',
  standalone: true,
  imports: [CommonModule, PermisoTramiteCardComponent],
  templateUrl: './permiso-historial.component.html',
  styleUrls: ['./permiso-historial.component.css']
})
export class PermisoHistorialComponent {
  @Input() tramites: Solicitud[] = [];
}

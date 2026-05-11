import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

export interface Solicitud {
  id:           string;
  tipo:         string;
  fechaEmision: string;
  estadoActual: 'enviado' | 'visto' | 'proceso' | 'aceptado' | 'rechazado';
  urlPdf?:      string;
}

@Component({
  selector: 'app-permiso-tramite-card',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './permiso-tramite-card.component.html',
  styleUrls: ['./permiso-tramite-card.component.css']
})
export class PermisoTramiteCardComponent {
  @Input() tramite!: Solicitud;

  verPdf(): void {
    if (this.tramite.urlPdf) {
      window.open(this.tramite.urlPdf, '_blank');
    }
  }
}

import { Component, Input, OnChanges } from '@angular/core';
import { CommonModule } from '@angular/common';
import { PermisoTramiteCardComponent, Solicitud } from '../permiso-tramite-card/permiso-tramite-card.component';

@Component({
  selector: 'app-permiso-historial',
  standalone: true,
  imports: [CommonModule, PermisoTramiteCardComponent],
  templateUrl: './permiso-historial.component.html',
  styleUrls: ['./permiso-historial.component.css']
})
export class PermisoHistorialComponent implements OnChanges {
  @Input() tramites: Solicitud[] = [];

  readonly pageSize = 3;
  currentPage = 1;

  ngOnChanges(): void {
    this.currentPage = 1;
  }

  get totalPages(): number {
    return Math.max(1, Math.ceil(this.tramites.length / this.pageSize));
  }

  get tramitesPaginados(): Solicitud[] {
    const start = (this.currentPage - 1) * this.pageSize;
    return this.tramites.slice(start, start + this.pageSize);
  }

  get totalCount():     number { return this.tramites.length; }
  get pendientesCount():number { return this.tramites.filter(t => t.estadoActual === 'enviado' || t.estadoActual === 'visto').length; }
  get procesoCount():   number { return this.tramites.filter(t => t.estadoActual === 'proceso').length; }
  get aprobadosCount(): number { return this.tramites.filter(t => t.estadoActual === 'aceptado').length; }
  get rechazadosCount():number { return this.tramites.filter(t => t.estadoActual === 'rechazado').length; }

  prevPage(): void { if (this.currentPage > 1) this.currentPage--; }
  nextPage(): void { if (this.currentPage < this.totalPages) this.currentPage++; }

  getEstadoLabel(estado: Solicitud['estadoActual']): string {
    const map: Record<string, string> = {
      enviado:   'Pendiente',
      visto:     'En revisión',
      proceso:   'En proceso',
      aceptado:  'Aprobado',
      rechazado: 'Rechazado',
    };
    return map[estado] ?? estado;
  }
}

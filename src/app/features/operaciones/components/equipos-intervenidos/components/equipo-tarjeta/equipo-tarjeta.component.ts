import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

import { EquipoEI } from '../../equipos-intervenidos.component';
import { ProcedimientoItemComponent } from '../procedimiento-item/procedimiento-item.component';

@Component({
  selector: 'app-equipo-tarjeta',
  standalone: true,
  imports: [CommonModule, ProcedimientoItemComponent],
  templateUrl: './equipo-tarjeta.component.html',
  styleUrls: ['./equipo-tarjeta.component.css'],
})
export class EquipoTarjetaComponent {
  @Input({ required: true }) equipo!: EquipoEI;

  expandido = false;

  toggleExpand(): void {
    this.expandido = !this.expandido;
  }

  estadoLabel(estado: string): string {
    const map: Record<string, string> = {
      pendiente:   'Pendiente',
      en_proceso:  'En Proceso',
      completado:  'Completado',
    };
    return map[estado] ?? estado;
  }

  /** Porcentaje de procedimientos completados dentro del equipo. */
  get progresoEquipo(): number {
    const total = this.equipo.procedimientos.length;
    if (total === 0) return 0;
    const done = this.equipo.procedimientos.filter(p => p.estado === 'completado').length;
    return Math.round((done / total) * 100);
  }
}

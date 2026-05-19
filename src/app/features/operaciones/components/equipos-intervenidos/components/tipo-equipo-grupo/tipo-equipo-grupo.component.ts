import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

import { TipoEquipoGrupoEI } from '../../equipos-intervenidos.component';
import { EquipoTarjetaComponent } from '../equipo-tarjeta/equipo-tarjeta.component';

@Component({
  selector: 'app-tipo-equipo-grupo',
  standalone: true,
  imports: [CommonModule, EquipoTarjetaComponent],
  templateUrl: './tipo-equipo-grupo.component.html',
  styleUrls: ['./tipo-equipo-grupo.component.css'],
})
export class TipoEquipoGrupoComponent {
  @Input({ required: true }) grupo!: TipoEquipoGrupoEI;
  @Input() progreso: number = 0;

  get bloqueado(): boolean {
    return this.progreso < 100;
  }

  get progresoColor(): string {
    if (this.progreso === 100) return '#22c55e';
    if (this.progreso >= 50)  return '#f59e0b';
    return '#94a3b8';
  }
}

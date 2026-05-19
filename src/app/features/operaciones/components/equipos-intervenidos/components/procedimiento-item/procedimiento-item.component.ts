import { Component, Input, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';

import { ProcedimientoEI } from '../../equipos-intervenidos.component';

@Component({
  selector: 'app-procedimiento-item',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './procedimiento-item.component.html',
  styleUrls: ['./procedimiento-item.component.css'],
})
export class ProcedimientoItemComponent {
  @Input({ required: true }) procedimiento!: ProcedimientoEI;
  @Input() esUltimo = false;

  @Output() subirFoto = new EventEmitter<{ proc: ProcedimientoEI; file: File }>();

  estadoLabel(estado: string): string {
    const map: Record<string, string> = {
      pendiente:  'Pendiente',
      en_proceso: 'En Proceso',
      completado: 'Completado',
    };
    return map[estado] ?? estado;
  }

  onFileSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    if (!input.files?.length) return;
    const file = input.files[0];

    // Vista previa local inmediata
    const reader = new FileReader();
    reader.onload = (e) => {
      this.procedimiento.fotoUrl = e.target?.result as string;
    };
    reader.readAsDataURL(file);

    this.subirFoto.emit({ proc: this.procedimiento, file });

    // Resetea el input para permitir seleccionar el mismo archivo de nuevo
    input.value = '';
  }
}

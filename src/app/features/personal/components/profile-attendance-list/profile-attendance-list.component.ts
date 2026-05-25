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

  private readonly MESES: Record<string, number> = {
    'enero': 0, 'febrero': 1, 'marzo': 2, 'abril': 3,
    'mayo': 4, 'junio': 5, 'julio': 6, 'agosto': 7,
    'septiembre': 8, 'octubre': 9, 'noviembre': 10, 'diciembre': 11
  };

  ngOnChanges(changes: SimpleChanges) {
    if (changes['registros'] && this.registros?.length > 0) {
      const hoy = new Date();
      hoy.setHours(0, 0, 0, 0);

      // Solo muestra el banner verde si el turno activo corresponde a HOY
      this.registroHoy = this.registros.find(r => {
        if (r.estado !== 'en_curso') return false;
        const fecha = this.parsearFecha(r);
        return fecha?.getTime() === hoy.getTime();
      }) || null;
    } else {
      this.registroHoy = null;
    }
  }

  esIncompleto(reg: any): boolean {
    if (reg.estado !== 'en_curso') return false;
    const hoy = new Date();
    hoy.setHours(0, 0, 0, 0);
    const fecha = this.parsearFecha(reg);
    return fecha ? fecha.getTime() < hoy.getTime() : false;
  }

  textoSalida(reg: any): string {
    if (reg.salida) return reg.salida;
    if (this.esIncompleto(reg)) return 'Sin salida';
    if (reg.estado === 'en_curso') return 'Activo';
    return '--:--';
  }

  private parsearFecha(reg: any): Date | null {
    const mes = this.MESES[String(reg.mes).toLowerCase().trim()];
    if (mes === undefined) return null;
    const fecha = new Date(Number(reg.anio), mes, Number(reg.dia));
    fecha.setHours(0, 0, 0, 0);
    return fecha;
  }
}
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

  // Hora de corte de jornada (17:00)
  private readonly HORA_CIERRE = 17;

  ngOnChanges(changes: SimpleChanges) {
    if (changes['registros'] && this.registros?.length > 0) {
      const ahora = new Date();
      const hoy   = new Date(ahora);
      hoy.setHours(0, 0, 0, 0);
      const pasaronLas17 = ahora.getHours() >= this.HORA_CIERRE;

      // Muestra banner "En Servicio" solo si: es hoy + en_curso + no tiene salida + aún no son las 17:00
      this.registroHoy = this.registros.find(r => {
        if (r.estado !== 'en_curso' || r.salida) return false;
        const fecha = this.parsearFecha(r);
        if (!fecha || fecha.getTime() !== hoy.getTime()) return false;
        return !pasaronLas17;
      }) || null;
    } else {
      this.registroHoy = null;
    }
  }

  /**
   * Un registro es "incompleto" cuando tiene entrada pero no salida y ya terminó la jornada:
   * - La fecha es anterior a hoy (días pasados), O
   * - La fecha es hoy pero ya pasaron las 17:00
   * También cubre el caso en que el mes no se puede parsear (datos malformados):
   * si no hay salida y el estado sigue en_curso con fecha irreconocible, lo marca incompleto.
   */
  esIncompleto(reg: any): boolean {
    if (reg.estado !== 'en_curso') return false;
    if (reg.salida) return false;

    const ahora = new Date();
    const hoy   = new Date(ahora);
    hoy.setHours(0, 0, 0, 0);

    const fecha = this.parsearFecha(reg);

    // Fecha no parseable → asumimos que es un registro viejo sin salida
    if (!fecha) return true;

    // Día anterior a hoy → definitivamente incompleto
    if (fecha.getTime() < hoy.getTime()) return true;

    // Mismo día pero ya pasaron las 17:00 → cortar la jornada
    if (fecha.getTime() === hoy.getTime()) {
      return ahora.getHours() >= this.HORA_CIERRE;
    }

    return false;
  }

  textoSalida(reg: any): string {
    if (reg.salida) return reg.salida;
    if (this.esIncompleto(reg)) return 'Sin salida';
    if (reg.estado === 'en_curso') return 'Activo';
    return '--:--';
  }

  /** 'tarde' si salió después de 17:00, 'temprano' si salió antes, null si no aplica */
  estadoSalida(reg: any): 'tarde' | 'temprano' | null {
    if (!reg.salida) return null;
    const [h, m] = String(reg.salida).split(':').map(Number);
    if (isNaN(h)) return null;
    const minutos = h * 60 + (m || 0);
    const cierre  = this.HORA_CIERRE * 60; // 17:00 = 1020 min
    if (minutos > cierre)  return 'tarde';
    if (minutos < cierre)  return 'temprano';
    return null;
  }

  /**
   * Parsea la fecha de un registro con múltiples estrategias:
   * 1. Campo fecha ISO directo (reg.fecha = "2026-06-17")
   * 2. Nombre de mes en español (reg.mes = "junio")
   * 3. Mes numérico como string (reg.mes = "06" o "6")
   */
  private parsearFecha(reg: any): Date | null {
    // Estrategia 1: campo fecha ISO
    if (reg.fecha) {
      const iso = String(reg.fecha).split('T')[0];
      const d   = new Date(iso + 'T00:00:00');
      if (!isNaN(d.getTime())) { d.setHours(0,0,0,0); return d; }
    }

    if (!reg.anio || !reg.dia) return null;

    const mesStr = String(reg.mes ?? '').toLowerCase().trim();

    // Estrategia 2: nombre de mes en español
    let mesNum = this.MESES[mesStr];

    // Estrategia 3: mes numérico ("06", "6", etc.)
    if (mesNum === undefined) {
      const n = parseInt(mesStr, 10);
      if (!isNaN(n) && n >= 1 && n <= 12) mesNum = n - 1;
    }

    if (mesNum === undefined) return null;

    const fecha = new Date(Number(reg.anio), mesNum, Number(reg.dia));
    fecha.setHours(0, 0, 0, 0);
    return fecha;
  }
}
import { Component, Input, Output, EventEmitter, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

interface Movimiento {
  id: string;
  tipo: string;
  detalle: string;
  fecha: string | null;
  responsable_nombre: string | null;
  referencia_tipo: string | null;
}

@Component({
  selector: 'app-equipo-movimientos-modal',
  standalone: true,
  imports: [CommonModule, SpinnerComponent, AppModalComponent],
  templateUrl: './equipo-movimientos-modal.component.html',
  styleUrls: ['./equipo-movimientos-modal.component.css'],
})
export class EquipoMovimientosModalComponent implements OnInit {
  @Input() equipoId!: string;
  @Input() equipoNombre = '';
  @Output() closed = new EventEmitter<void>();

  private svc = inject(LogisticaService);

  movimientos: Movimiento[] = [];
  cargando = true;
  error = '';

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.error = '';
    this.svc.getMovimientosEquipo(this.equipoId).subscribe({
      next: (data) => { this.movimientos = data; this.cargando = false; },
      error: () => { this.error = 'No se pudo cargar el historial.'; this.cargando = false; },
    });
  }

  cerrar(): void { this.closed.emit(); }

  tipoLabel(tipo: string): string {
    const m: Record<string, string> = {
      entrada: 'Entrada', salida: 'Salida', ajuste: 'Ajuste',
      transferencia: 'Transferencia', mantenimiento: 'Mantenimiento',
      ingreso_directo: 'Ingreso directo', retorno: 'Retorno',
    };
    return m[tipo] ?? tipo;
  }

  tipoIcono(tipo: string): string {
    if (tipo === 'entrada' || tipo === 'ingreso_directo') return 'in';
    if (tipo === 'salida') return 'out';
    if (tipo === 'mantenimiento') return 'maint';
    if (tipo === 'retorno') return 'ret';
    return 'other';
  }

  formatFecha(f: string | null): string {
    if (!f) return '—';
    const d = new Date(f);
    return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' })
      + ' ' + d.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' });
  }
}

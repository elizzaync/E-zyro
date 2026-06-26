import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, CuentaBancaria, MovimientoBancario } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';

@Component({
  selector: 'app-conciliacion',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './conciliacion.component.html',
  styleUrls: ['./conciliacion.component.css']
})
export class ConciliacionComponent implements OnInit {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  cargando = false;
  cuentas: CuentaBancaria[] = [];
  cuentaSeleccionada: CuentaBancaria | null = null;
  movimientos: MovimientoBancario[] = [];
  cargandoMov = false;
  filtroEstadoMov = 'pendiente';

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getCuentasBancarias().subscribe({
      next: d => { this.cuentas = d; this.cargando = false; },
      error: () => { this.cargando = false; }
    });
  }

  seleccionarCuenta(c: CuentaBancaria): void {
    this.cuentaSeleccionada = this.cuentaSeleccionada?.id === c.id ? null : c;
    if (this.cuentaSeleccionada) this.cargarMovimientos();
  }

  cargarMovimientos(): void {
    if (!this.cuentaSeleccionada) return;
    this.cargandoMov = true;
    this.svc.getMovimientosBancarios(this.cuentaSeleccionada.id, this.filtroEstadoMov).subscribe({
      next: d => { this.movimientos = d; this.cargandoMov = false; },
      error: () => { this.cargandoMov = false; }
    });
  }

  desconciliar(m: MovimientoBancario): void {
    this.svc.desconciliarMovimiento(m.id).subscribe({
      next: () => { m.estado = 'pendiente'; this.toast.mostrar('Movimiento desconciliado', 'success'); },
      error: () => this.toast.mostrar('Error al desconciliar', 'error')
    });
  }

  get diferenciaTotalCuentas(): number {
    return this.cuentas.reduce((acc, c) => acc + c.diferencia, 0);
  }
}

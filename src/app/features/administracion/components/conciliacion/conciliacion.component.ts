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

  pageMov = 1;
  readonly PER_MOV = 12;

  get movimientosPaginados(): MovimientoBancario[] {
    const s = (this.pageMov - 1) * this.PER_MOV;
    return this.movimientos.slice(s, s + this.PER_MOV);
  }
  get totalPaginasMov(): number { return Math.max(1, Math.ceil(this.movimientos.length / this.PER_MOV)); }
  get totalMovItems(): number { return this.movimientos.length; }
  get botonesPageMov(): number[] {
    const pp: number[] = [];
    for (let i = Math.max(1, this.pageMov - 2); i <= Math.min(this.totalPaginasMov, this.pageMov + 2); i++) pp.push(i);
    return pp;
  }
  irPaginaMov(p: number): void { if (p >= 1 && p <= this.totalPaginasMov) this.pageMov = p; }

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
    this.pageMov = 1;
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

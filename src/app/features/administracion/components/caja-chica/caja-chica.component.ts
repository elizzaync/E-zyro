import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, CajaChica, MovimientoCaja } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

@Component({
  selector: 'app-caja-chica',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
  templateUrl: './caja-chica.component.html',
  styleUrls: ['./caja-chica.component.css']
})
export class CajaChicaComponent implements OnInit {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  cargando = false;
  cajas: CajaChica[] = [];
  cajaSeleccionada: CajaChica | null = null;
  movimientos: MovimientoCaja[] = [];
  cargandoMov = false;

  showNuevaCaja = false;
  nuevaCajaNombre = '';
  nuevaCajaSaldo = 0;
  guardandoCaja = false;

  showNuevoMov = false;
  nuevoMov: Partial<MovimientoCaja> = {};
  guardandoMov = false;

  pageMov = 1;
  readonly PER_MOV = 12;

  get movimientosPaginados(): MovimientoCaja[] {
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
    this.svc.getCajas().subscribe({
      next: d => { this.cajas = d; this.cargando = false; },
      error: () => { this.cargando = false; }
    });
  }

  seleccionarCaja(c: CajaChica): void {
    this.cajaSeleccionada = this.cajaSeleccionada?.id === c.id ? null : c;
    if (this.cajaSeleccionada) this.cargarMovimientos(c.id);
  }

  cargarMovimientos(id: string): void {
    this.cargandoMov = true;
    this.pageMov = 1;
    this.svc.getMovimientosCaja(id).subscribe({
      next: d => { this.movimientos = d; this.cargandoMov = false; },
      error: () => { this.cargandoMov = false; }
    });
  }

  crearCaja(): void {
    if (!this.nuevaCajaNombre.trim()) return;
    this.guardandoCaja = true;
    this.svc.crearCaja(this.nuevaCajaNombre, this.nuevaCajaSaldo).subscribe({
      next: () => {
        this.toast.mostrar('Caja creada', 'success');
        this.showNuevaCaja = false;
        this.nuevaCajaNombre = '';
        this.nuevaCajaSaldo = 0;
        this.guardandoCaja = false;
        this.cargar();
      },
      error: () => { this.guardandoCaja = false; this.toast.mostrar('Error al crear caja', 'error'); }
    });
  }

  cerrarCaja(c: CajaChica): void {
    if (!confirm(`¿Cerrar la caja "${c.nombre}"?`)) return;
    this.svc.cerrarCaja(c.id).subscribe({
      next: () => { c.estado = 'cerrada'; this.toast.mostrar('Caja cerrada', 'success'); },
      error: () => this.toast.mostrar('Error al cerrar caja', 'error')
    });
  }

  registrarMovimiento(): void {
    if (!this.cajaSeleccionada) return;
    this.guardandoMov = true;
    this.svc.registrarMovimientoCaja(this.cajaSeleccionada.id, this.nuevoMov).subscribe({
      next: () => {
        this.toast.mostrar('Movimiento registrado', 'success');
        this.showNuevoMov = false;
        this.nuevoMov = {};
        this.guardandoMov = false;
        this.cargarMovimientos(this.cajaSeleccionada!.id);
        this.cargar();
      },
      error: () => { this.guardandoMov = false; this.toast.mostrar('Error al registrar movimiento', 'error'); }
    });
  }
}

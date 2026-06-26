import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, FacturaCxC, CobroCxC, SaldoCliente } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';

type TabCxC = 'facturas' | 'cobros' | 'saldos';

@Component({
  selector: 'app-cxc',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './cxc.component.html',
  styleUrls: ['./cxc.component.css']
})
export class CxcComponent implements OnInit {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  tab: TabCxC = 'facturas';
  cargando = false;

  facturas: FacturaCxC[] = [];
  cobros: CobroCxC[] = [];
  saldos: SaldoCliente[] = [];

  filtroEstado = '';
  filtroVence = '';
  busqueda = '';

  ngOnInit(): void { this.cargar(); }

  setTab(t: TabCxC): void { this.tab = t; this.cargar(); }

  cargar(): void {
    this.cargando = true;
    if (this.tab === 'facturas') {
      const f: any = {};
      if (this.filtroEstado) f.estado = this.filtroEstado;
      if (this.filtroVence)  f.vence_hasta = this.filtroVence;
      this.svc.getFacturasCxC(f).subscribe({
        next: d => { this.facturas = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    } else if (this.tab === 'cobros') {
      this.svc.getCobros().subscribe({
        next: d => { this.cobros = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    } else {
      this.svc.getSaldosCxC().subscribe({
        next: d => { this.saldos = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    }
  }

  get facturasFiltradas(): FacturaCxC[] {
    const q = this.busqueda.toLowerCase().trim();
    return this.facturas.filter(f =>
      !q || f.numero_documento.toLowerCase().includes(q) ||
      (f.cliente_nombre ?? '').toLowerCase().includes(q)
    );
  }

  anular(f: FacturaCxC): void {
    if (!confirm(`¿Anular la factura ${f.numero_documento}?`)) return;
    this.svc.anularFacturaCxC(f.id).subscribe({
      next: () => { this.toast.mostrar('Factura anulada', 'success'); this.cargar(); },
      error: () => this.toast.mostrar('Error al anular', 'error')
    });
  }

  estadoClase(e: string): string {
    if (e === 'pendiente') return 'badge-warn';
    if (e === 'pagada')    return 'badge-ok';
    if (e === 'vencida')   return 'badge-danger';
    return 'badge-off';
  }

  get totalPendiente(): number {
    return this.saldos.reduce((acc, s) => acc + s.total_pendiente, 0);
  }
}

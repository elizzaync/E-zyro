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

  page = 1;
  readonly PER_PAGE = 10;

  private get listaActiva(): any[] {
    if (this.tab === 'facturas') return this.facturasFiltradas;
    if (this.tab === 'cobros') return this.cobros;
    return this.saldos;
  }
  get paginados(): any[] {
    const s = (this.page - 1) * this.PER_PAGE;
    return this.listaActiva.slice(s, s + this.PER_PAGE);
  }
  get totalPaginas(): number { return Math.max(1, Math.ceil(this.listaActiva.length / this.PER_PAGE)); }
  get totalItems(): number { return this.listaActiva.length; }
  get botonesPage(): number[] {
    const pp: number[] = [];
    for (let i = Math.max(1, this.page - 2); i <= Math.min(this.totalPaginas, this.page + 2); i++) pp.push(i);
    return pp;
  }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) this.page = p; }
  resetPage(): void { this.page = 1; }

  ngOnInit(): void { this.cargar(); }

  setTab(t: TabCxC): void { this.tab = t; this.page = 1; this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.page = 1;
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

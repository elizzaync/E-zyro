import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, FacturaCxP, PagoCxP, SaldoProveedor } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';

type TabCxP = 'facturas' | 'pagos' | 'saldos';

@Component({
  selector: 'app-cxp',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './cxp.component.html',
  styleUrls: ['./cxp.component.css']
})
export class CxpComponent implements OnInit {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  tab: TabCxP = 'facturas';
  cargando = false;

  facturas: FacturaCxP[] = [];
  pagos: PagoCxP[] = [];
  saldos: SaldoProveedor[] = [];

  filtroEstado = '';
  busqueda = '';

  page = 1;
  readonly PER_PAGE = 10;

  private get listaActiva(): any[] {
    if (this.tab === 'facturas') return this.facturasFiltradas;
    if (this.tab === 'pagos') return this.pagos;
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
  setTab(t: TabCxP): void { this.tab = t; this.page = 1; this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.page = 1;
    if (this.tab === 'facturas') {
      const f: any = {};
      if (this.filtroEstado) f.estado = this.filtroEstado;
      this.svc.getFacturasCxP(f).subscribe({
        next: d => { this.facturas = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    } else if (this.tab === 'pagos') {
      this.svc.getPagos().subscribe({
        next: d => { this.pagos = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    } else {
      this.svc.getSaldosCxP().subscribe({
        next: d => { this.saldos = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    }
  }

  get facturasFiltradas(): FacturaCxP[] {
    const q = this.busqueda.toLowerCase().trim();
    return this.facturas.filter(f =>
      !q || f.numero_documento.toLowerCase().includes(q) ||
      (f.proveedor_nombre ?? '').toLowerCase().includes(q)
    );
  }

  anular(f: FacturaCxP): void {
    if (!confirm(`¿Anular la factura ${f.numero_documento}?`)) return;
    this.svc.anularFacturaCxP(f.id).subscribe({
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

import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import {
  TicketCompra, Proveedor, EstadoCompra, ProcesarCompraPayload
} from '../../logistica.models';

interface ItemCompraForm {
  itemId: string;
  nombre: string;
  cantidad: number;
  unidad: string;
  cantidadComprada: number;
  precioUnitario: number | null;
  modoCustom: boolean;
  proveedorId: string | null;
  proveedorNombre: string | null;
  canalCustom: string;
  factura: string;
  nota: string;
}

type TabCompra = 'pendiente' | 'en_proceso' | 'completado' | 'cancelado';

@Component({
  selector: 'app-compras',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './compras.component.html',
  styleUrls: ['./compras.component.css']
})
export class ComprasComponent implements OnInit {
  private svc    = inject(LogisticaService);
  private toast  = inject(ToastService);
  private router = inject(Router);

  tab: TabCompra = 'pendiente';
  cargando  = true;
  procesando = false;

  tickets: TicketCompra[] = [];
  busqueda = '';

  // ── Modal de proceso ──
  ticketActivo: TicketCompra | null = null;
  modoUnificado = true;
  busquedaItems = '';
  proveedorUnicoId: string | null = null;
  proveedorUnicoNombre: string | null = null;
  canalUnicoCustom = false;
  canalUnicoTexto = '';
  notaTicket = '';
  itemsForm: ItemCompraForm[] = [];

  // ── Modal de detalle ──
  ticketDetalle: TicketCompra | null = null;

  // ── Modal de cancelación ──
  ticketCancelar: TicketCompra | null = null;
  motivoCancelacion = '';

  // Proveedores demo — reemplazar con API getProveedores() cuando exista
  readonly proveedores: Proveedor[] = [
    { id: 'p1', nombre: 'Distribuidora TecnoPlus',      ruc: '20123456789', contacto: '01-234-5678', email: 'ventas@tecnoplus.pe',  rating: 4, categorias: ['materiales','equipos'],      activo: true },
    { id: 'p2', nombre: 'Materiales Industriales Perú', ruc: '20987654321', contacto: '01-987-6543', email: 'pedidos@matind.pe',     rating: 3, categorias: ['materiales'],               activo: true },
    { id: 'p3', nombre: 'Soluciones Eléctricas SAC',    ruc: '20555010101', contacto: '01-555-0101', email: 'info@solelec.pe',       rating: 5, categorias: ['equipos','herramientas'],   activo: true },
    { id: 'p4', nombre: 'InduSupply Corp.',              ruc: '20333224400', contacto: '01-333-2244', email: 'supply@indusupply.pe',  rating: 4, categorias: ['materiales','herramientas'],activo: true },
    { id: 'p5', nombre: 'Ferretería Central Lima',       ruc: '20111222333', contacto: '01-111-2233', email: 'ventas@fercentral.pe',  rating: 3, categorias: ['herramientas','materiales'],activo: true },
    { id: 'p6', nombre: 'ProTech Equipos SAC',           ruc: '20444555666', contacto: '01-444-5566', email: 'ventas@protech.pe',     rating: 5, categorias: ['equipos'],                  activo: true },
  ];

  ngOnInit(): void { this.cargar(); }

  setTab(t: TabCompra): void { this.tab = t; this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getTicketsCompra({ estado: this.tab }).subscribe({
      next:  d => { this.tickets = d; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar compras.', 'error'); }
    });
  }

  get lista(): TicketCompra[] {
    const q = this.busqueda.toLowerCase().trim();
    if (!q) return this.tickets;
    return this.tickets.filter(t =>
      t.proyectoNombre.toLowerCase().includes(q) ||
      (t.servicioNombre ?? '').toLowerCase().includes(q) ||
      t.solicitanteNombre.toLowerCase().includes(q) ||
      t.codigo.toLowerCase().includes(q) ||
      t.items.some(i => i.nombre.toLowerCase().includes(q))
    );
  }

  // ── Computed (modal de proceso) ──
  get itemsFormFiltrados(): ItemCompraForm[] {
    const q = this.busquedaItems.toLowerCase().trim();
    if (!q) return this.itemsForm;
    return this.itemsForm.filter(f => f.nombre.toLowerCase().includes(q));
  }

  get totalEstimado(): number {
    return this.itemsForm.reduce((s, f) => s + (f.cantidadComprada * (f.precioUnitario ?? 0)), 0);
  }

  get itemsIngresadosCount(): number {
    return this.itemsForm.filter(f => f.cantidadComprada > 0).length;
  }

  get puedeCompletar(): boolean {
    if (!this.ticketActivo) return false;
    if (this.modoUnificado) {
      if (!this.canalUnicoCustom && !this.proveedorUnicoId) return false;
      if (this.canalUnicoCustom && !this.canalUnicoTexto.trim()) return false;
    }
    return this.itemsIngresadosCount > 0;
  }

  // ── Helpers ──
  estadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente: 'Pendiente', en_proceso: 'En proceso',
      completado: 'Completado', cancelado: 'Cancelado',
    };
    return m[e] ?? e;
  }
  estadoClase(e: string): string { return 'cp-est-' + e.replace('_', '-'); }

  starsText(n: number): string { return '★'.repeat(n) + '☆'.repeat(5 - n); }

  totalTicket(t: TicketCompra): number {
    return t.totalReal
      ?? t.items.reduce((s, i) => s + ((i.cantidadComprada ?? 0) * (i.precioUnitario ?? 0)), 0);
  }

  itemsPendientesCount(t: TicketCompra): number {
    return t.items.filter(i => i.estadoItem === 'pendiente').length;
  }

  // ── Modal proceso ──
  abrirProceso(t: TicketCompra): void {
    this.ticketActivo = t;
    this.modoUnificado = t.modoUnificado ?? true;
    this.busquedaItems = '';
    this.proveedorUnicoId   = t.proveedorUnicoId;
    this.proveedorUnicoNombre = t.proveedorUnicoNombre;
    this.canalUnicoCustom = !!t.canalUnico;
    this.canalUnicoTexto  = t.canalUnico ?? '';
    this.notaTicket = t.nota ?? '';
    this.itemsForm = t.items.map(it => ({
      itemId:           it.id,
      nombre:           it.nombre,
      cantidad:         it.cantidad,
      unidad:           it.unidad,
      cantidadComprada: it.cantidadComprada ?? it.cantidad,
      precioUnitario:   it.precioUnitario,
      modoCustom:       !!it.canalPersonalizado,
      proveedorId:      it.proveedorId,
      proveedorNombre:  it.proveedorNombre,
      canalCustom:      it.canalPersonalizado ?? '',
      factura:          it.factura ?? '',
      nota:             it.nota ?? '',
    }));
  }

  cerrarProceso(): void { this.ticketActivo = null; this.itemsForm = []; }

  selProvUnico(p: Proveedor): void {
    if (this.proveedorUnicoId === p.id) {
      this.proveedorUnicoId = null; this.proveedorUnicoNombre = null;
    } else {
      this.proveedorUnicoId = p.id; this.proveedorUnicoNombre = p.nombre;
      this.canalUnicoCustom = false; this.canalUnicoTexto = '';
    }
  }

  toggleCanalUnico(): void {
    this.canalUnicoCustom = !this.canalUnicoCustom;
    if (this.canalUnicoCustom) { this.proveedorUnicoId = null; this.proveedorUnicoNombre = null; }
    else { this.canalUnicoTexto = ''; }
  }

  onProvItemChange(f: ItemCompraForm, id: string | null): void {
    f.proveedorId = id;
    f.proveedorNombre = this.proveedores.find(p => p.id === id)?.nombre ?? null;
    if (id) { f.modoCustom = false; f.canalCustom = ''; }
  }

  toggleCustomItem(f: ItemCompraForm): void {
    f.modoCustom = !f.modoCustom;
    if (f.modoCustom) { f.proveedorId = null; f.proveedorNombre = null; }
    else { f.canalCustom = ''; }
  }

  private _buildPayload(completado: boolean): ProcesarCompraPayload {
    return {
      modoUnificado: this.modoUnificado,
      proveedorUnicoId:     this.modoUnificado && !this.canalUnicoCustom ? this.proveedorUnicoId     : null,
      proveedorUnicoNombre: this.modoUnificado && !this.canalUnicoCustom ? this.proveedorUnicoNombre : null,
      canalUnico:           this.modoUnificado &&  this.canalUnicoCustom ? this.canalUnicoTexto.trim() : null,
      nota: this.notaTicket.trim() || null,
      completado,
      items: this.itemsForm.map(f => ({
        itemId:           f.itemId,
        cantidadComprada: f.cantidadComprada,
        precioUnitario:   f.precioUnitario,
        proveedorId:      this.modoUnificado
          ? (this.canalUnicoCustom ? null : this.proveedorUnicoId)
          : (f.modoCustom ? null : f.proveedorId),
        proveedorNombre:  this.modoUnificado
          ? (this.canalUnicoCustom ? null : this.proveedorUnicoNombre)
          : (f.modoCustom ? null : f.proveedorNombre),
        canalPersonalizado: this.modoUnificado
          ? (this.canalUnicoCustom ? this.canalUnicoTexto.trim() : null)
          : (f.modoCustom ? f.canalCustom.trim() : null),
        factura: f.factura.trim() || null,
        nota:    f.nota.trim()    || null,
      })),
    };
  }

  guardarProgreso(): void {
    if (!this.ticketActivo) return;
    this.procesando = true;
    this.svc.procesarCompra(this.ticketActivo.id, this._buildPayload(false)).subscribe({
      next:  () => { this.procesando = false; this.toast.mostrar('Progreso guardado.', 'success'); this.cerrarProceso(); this.cargar(); },
      error: err => { this.procesando = false; this.toast.mostrar(err?.error?.detail ?? 'No se pudo guardar.', 'error'); }
    });
  }

  confirmarCompra(): void {
    if (!this.ticketActivo || !this.puedeCompletar) return;
    this.procesando = true;
    this.svc.procesarCompra(this.ticketActivo.id, this._buildPayload(true)).subscribe({
      next:  () => { this.procesando = false; this.toast.mostrar('Compra completada.', 'success'); this.cerrarProceso(); this.cargar(); },
      error: err => { this.procesando = false; this.toast.mostrar(err?.error?.detail ?? 'Error al completar.', 'error'); }
    });
  }

  // ── Modal cancelación ──
  abrirCancelar(t: TicketCompra): void { this.ticketCancelar = t; this.motivoCancelacion = ''; }
  cerrarCancelar(): void { this.ticketCancelar = null; this.motivoCancelacion = ''; }

  confirmarCancelacion(): void {
    if (!this.ticketCancelar) return;
    this.procesando = true;
    this.svc.cancelarCompra(this.ticketCancelar.id, this.motivoCancelacion.trim() || undefined).subscribe({
      next:  () => { this.procesando = false; this.toast.mostrar('Ticket cancelado.', 'success'); this.cerrarCancelar(); this.cargar(); },
      error: () => { this.procesando = false; this.toast.mostrar('No se pudo cancelar.', 'error'); }
    });
  }

  // ── Modal detalle ──
  abrirDetalle(t: TicketCompra): void { this.ticketDetalle = t; }
  cerrarDetalle(): void { this.ticketDetalle = null; }

  volverInventario(): void { this.router.navigate(['/logistica']); }

  // KPI — calculated from ALL loaded tickets (regardless of tab filter)
  get kpiPendiente():  number { return this.tickets.filter(t => t.estado === 'pendiente').length; }
  get kpiEnProceso():  number { return this.tickets.filter(t => t.estado === 'en_proceso').length; }
  get kpiCompletado(): number { return this.tickets.filter(t => t.estado === 'completado').length; }
}

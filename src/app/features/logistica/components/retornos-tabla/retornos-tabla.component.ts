import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { Retorno, RetornoDetalle } from '../../logistica.models';

interface ItemInspeccionForm {
  detalleId:          string;
  nombre:             string;
  unidad:             string;
  tipoItem:           string;
  esObligatorio:      boolean;
  cantidadEntregada:  number;
  cantidadRetornada:  number;
  cantidadConfirmada: number;
  estadoItem:         string;
}

@Component({
  selector: 'app-retornos-tabla',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './retornos-tabla.component.html',
  styleUrls: ['./retornos-tabla.component.css'],
})
export class RetornosTablaComponent implements OnInit {
  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  cargando = true;
  retornos: Retorno[] = [];
  total    = 0;
  page     = 1;
  pageSize = 20;

  busqueda    = '';
  filtroEstado = '';

  // ── Modal de inspección ──
  retornoActivo: Retorno | null = null;
  itemsForm: ItemInspeccionForm[] = [];
  notaLogistica = '';
  procesando    = false;
  completando   = false;

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getRetornos({ q: this.busqueda || undefined, estado: this.filtroEstado || undefined, page: this.page, pageSize: this.pageSize }).subscribe({
      next:  r => { this.retornos = r.items; this.total = r.total; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar retornos.', 'error'); },
    });
  }

  buscar(): void { this.page = 1; this.cargar(); }
  limpiar(): void { this.busqueda = ''; this.filtroEstado = ''; this.page = 1; this.cargar(); }

  get totalPaginas(): number { return Math.ceil(this.total / this.pageSize); }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) { this.page = p; this.cargar(); } }

  // ── Modal ──
  abrirInspeccion(r: Retorno): void {
    this.retornoActivo = r;
    this.notaLogistica = r.notaLogistica || '';
    this.itemsForm = r.items.map(it => ({
      detalleId:          it.id,
      nombre:             it.nombre,
      unidad:             it.unidad,
      tipoItem:           it.tipoItem,
      esObligatorio:      it.esObligatorio,
      cantidadEntregada:  it.cantidadEntregada,
      cantidadRetornada:  it.cantidadRetornada ?? 0,
      cantidadConfirmada: it.cantidadConfirmada ?? it.cantidadRetornada ?? 0,
      estadoItem:         it.estadoItem,
    }));
  }

  cerrarInspeccion(): void { this.retornoActivo = null; this.itemsForm = []; }

  confirmarTodos(): void {
    this.itemsForm.forEach(f => f.cantidadConfirmada = f.cantidadRetornada);
  }

  guardarInspeccion(): void {
    if (!this.retornoActivo) return;
    this.procesando = true;
    this.svc.inspeccionarRetorno(this.retornoActivo.id, {
      items: this.itemsForm.map(f => ({ detalleId: f.detalleId, cantidadConfirmada: f.cantidadConfirmada })),
      notaLogistica: this.notaLogistica.trim() || undefined,
    }).subscribe({
      next: updated => {
        this.procesando   = false;
        this.retornoActivo = updated;
        this.itemsForm    = updated.items.map(it => ({
          detalleId:          it.id,
          nombre:             it.nombre,
          unidad:             it.unidad,
          tipoItem:           it.tipoItem,
          esObligatorio:      it.esObligatorio,
          cantidadEntregada:  it.cantidadEntregada,
          cantidadRetornada:  it.cantidadRetornada ?? 0,
          cantidadConfirmada: it.cantidadConfirmada ?? 0,
          estadoItem:         it.estadoItem,
        }));
        this.toast.mostrar('Inspección guardada.', 'success');
        this.cargar();
      },
      error: err => { this.procesando = false; this.toast.mostrar(err?.error?.detail ?? 'Error al guardar.', 'error'); },
    });
  }

  completarRetorno(): void {
    if (!this.retornoActivo) return;
    this.completando = true;
    this.svc.completarRetorno(this.retornoActivo.id).subscribe({
      next: () => {
        this.completando = false;
        this.toast.mostrar('Retorno completado. Stock actualizado.', 'success');
        this.cerrarInspeccion();
        this.cargar();
      },
      error: err => { this.completando = false; this.toast.mostrar(err?.error?.detail ?? 'Error al completar.', 'error'); },
    });
  }

  // ── Helpers ──
  estadoLabel(e: string): string {
    return e === 'enviado' ? 'Enviado' : e === 'inspeccion' ? 'En inspección' : 'Completado';
  }

  itemEstadoBadge(estado: string): string {
    return estado === 'confirmado' ? 'ret-it-ok' : estado === 'faltante' ? 'ret-it-miss' : 'ret-it-pend';
  }

  itemEstadoLabel(estado: string): string {
    return estado === 'confirmado' ? 'Confirmado' : estado === 'faltante' ? 'Faltante' : 'Pendiente';
  }

  fechaCorta(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  get puedeCompletar(): boolean {
    return !!this.retornoActivo && this.retornoActivo.estado === 'inspeccion';
  }
}

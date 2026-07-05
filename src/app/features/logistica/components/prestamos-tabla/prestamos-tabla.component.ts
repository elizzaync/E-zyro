import { Component, OnInit, inject, ViewChild, ElementRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { Prestamo, PrestamoEstado } from '../../logistica.models';

interface ItemEntregaForm {
  item_id: string;
  equipo_nombre: string;
  clase: string;
  cantidad_solicitada: number;
  cantidad_entregada: number;
}

@Component({
  selector: 'app-prestamos-tabla',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './prestamos-tabla.component.html',
  styleUrls: ['./prestamos-tabla.component.css'],
})
export class PrestamosTablaComponent implements OnInit {
  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  cargando = true;
  prestamos: Prestamo[] = [];
  filtroEstado = 'todos';

  // ── Modal detalle ──
  prestamoActivo: Prestamo | null = null;
  procesando = false;

  // ── Sub-modal: entregar (requiere firma) ──
  entregaAbierta = false;
  itemsEntrega: ItemEntregaForm[] = [];
  isDrawing = false;
  firmaVacia = true;
  firmaGuardadaUrl = '';
  usandoFirmaGuardada = false;
  @ViewChild('firmaCanvas') firmaCanvasEl?: ElementRef<HTMLCanvasElement>;

  // ── Sub-modal: rechazar ──
  rechazoAbierto = false;
  motivoRechazo = '';

  // ── Sub-modal: observar devolución ──
  observarAbierto = false;
  motivoObservar = '';

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getPrestamos(this.filtroEstado).subscribe({
      next:  p => { this.prestamos = p; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar préstamos.', 'error'); },
    });
  }

  filtrar(): void { this.cargar(); }

  // ── Detalle ──
  abrirDetalle(p: Prestamo): void {
    this.prestamoActivo = p;
    document.body.style.overflow = 'hidden';
  }

  cerrarDetalle(): void {
    this.prestamoActivo = null;
    this.entregaAbierta = false;
    this.rechazoAbierto = false;
    this.observarAbierto = false;
    document.body.style.overflow = '';
  }

  // ── Entregar (firma) ──
  abrirEntrega(): void {
    if (!this.prestamoActivo) return;
    this.itemsEntrega = this.prestamoActivo.items.map(it => ({
      item_id: it.id,
      equipo_nombre: it.equipo_nombre,
      clase: it.clase,
      cantidad_solicitada: it.cantidad_solicitada,
      cantidad_entregada: it.cantidad_solicitada,
    }));
    this.entregaAbierta = true;
    this.firmaVacia = true;
    this.usandoFirmaGuardada = false;
    this.firmaGuardadaUrl = '';
    this.svc.getFirmaGuardada().subscribe({
      next: f => { this.firmaGuardadaUrl = f?.url ?? ''; },
      error: () => {},
    });
    setTimeout(() => this._initCanvas(), 60);
  }

  cerrarEntrega(): void { this.entregaAbierta = false; }

  // Reutilizar la firma ya guardada en la cuenta (sin volver a dibujar).
  usarFirmaGuardada(): void {
    if (!this.firmaGuardadaUrl) return;
    this.usandoFirmaGuardada = true;
  }

  // Volver al canvas en blanco para dibujar una firma nueva. El canvas se
  // destruye/recrea al alternar la rama del @if, así que hay que reinicializar
  // sus handlers de dibujo.
  dibujarNuevaFirma(): void {
    this.usandoFirmaGuardada = false;
    this.firmaVacia = true;
    setTimeout(() => this._initCanvas(), 50);
  }

  confirmarEntrega(): void {
    if (!this.prestamoActivo) return;

    let firmaEntregadorUrl: string;
    let firmaEsNueva: boolean;
    if (this.usandoFirmaGuardada && this.firmaGuardadaUrl) {
      firmaEntregadorUrl = this.firmaGuardadaUrl;
      firmaEsNueva = false;
    } else {
      const canvas = this.firmaCanvasEl?.nativeElement;
      if (!canvas || this.firmaVacia) {
        this.toast.mostrar('Se requiere la firma de logística para despachar.', 'error');
        return;
      }
      firmaEntregadorUrl = canvas.toDataURL('image/png');
      firmaEsNueva = true;
    }

    this.procesando = true;
    this.svc.entregarPrestamo(this.prestamoActivo.id, {
      items: this.itemsEntrega.map(f => ({ item_id: f.item_id, cantidad_entregada: f.cantidad_entregada })),
      firmaEntregadorUrl,
    }).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Préstamo entregado. Queda a la espera de la firma de recepción del técnico.', 'success');
        this.cerrarDetalle();
        this.cargar();
      },
      error: err => { this.procesando = false; this.toast.mostrar(err?.error?.detail ?? 'Error al entregar.', 'error'); },
    });

    // Firma dibujada de nuevo (no la precargada) → guardarla para reutilizar
    // después. Fire-and-forget, no bloquea el flujo de entrega.
    if (firmaEsNueva) {
      this.svc.guardarFirma(firmaEntregadorUrl).subscribe({
        error: err => console.error('No se pudo guardar la firma para reutilizar después.', err),
      });
    }
  }

  limpiarFirma(): void {
    const canvas = this.firmaCanvasEl?.nativeElement;
    if (canvas) canvas.getContext('2d')?.clearRect(0, 0, canvas.width, canvas.height);
    this.firmaVacia = true;
  }

  private _initCanvas(): void {
    const canvas = this.firmaCanvasEl?.nativeElement;
    if (!canvas) return;
    const ctx = canvas.getContext('2d')!;
    ctx.strokeStyle = '#0f172a';
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';

    const getPos = (e: MouseEvent | Touch) => {
      const r = canvas.getBoundingClientRect();
      return { x: (e.clientX - r.left) * (canvas.width / r.width), y: (e.clientY - r.top) * (canvas.height / r.height) };
    };

    canvas.onmousedown = e => { this.isDrawing = true; this.firmaVacia = false; const p = getPos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); };
    canvas.onmousemove = e => { if (!this.isDrawing) return; const p = getPos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); };
    canvas.onmouseup = canvas.onmouseleave = () => { this.isDrawing = false; };
    canvas.ontouchstart = e => { e.preventDefault(); this.isDrawing = true; this.firmaVacia = false; const p = getPos(e.touches[0]); ctx.beginPath(); ctx.moveTo(p.x, p.y); };
    canvas.ontouchmove  = e => { e.preventDefault(); if (!this.isDrawing) return; const p = getPos(e.touches[0]); ctx.lineTo(p.x, p.y); ctx.stroke(); };
    canvas.ontouchend   = () => { this.isDrawing = false; };
  }

  // ── Rechazar ──
  abrirRechazo(): void { this.rechazoAbierto = true; this.motivoRechazo = ''; }
  cerrarRechazo(): void { this.rechazoAbierto = false; }
  confirmarRechazo(): void {
    if (!this.prestamoActivo || !this.motivoRechazo.trim()) return;
    this.procesando = true;
    this.svc.rechazarPrestamo(this.prestamoActivo.id, this.motivoRechazo.trim()).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Préstamo rechazado.', 'success');
        this.cerrarDetalle();
        this.cargar();
      },
      error: err => { this.procesando = false; this.toast.mostrar(err?.error?.detail ?? 'Error al rechazar.', 'error'); },
    });
  }

  // ── Confirmar / observar devolución ──
  confirmarRecepcion(): void {
    if (!this.prestamoActivo) return;
    this.procesando = true;
    this.svc.confirmarDevolucionPrestamo(this.prestamoActivo.id, true).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Devolución confirmada. Equipos de vuelta en almacén.', 'success');
        this.cerrarDetalle();
        this.cargar();
      },
      error: err => { this.procesando = false; this.toast.mostrar(err?.error?.detail ?? 'Error al confirmar.', 'error'); },
    });
  }

  abrirObservar(): void { this.observarAbierto = true; this.motivoObservar = ''; }
  cerrarObservar(): void { this.observarAbierto = false; }
  confirmarObservar(): void {
    if (!this.prestamoActivo || !this.motivoObservar.trim()) return;
    this.procesando = true;
    this.svc.confirmarDevolucionPrestamo(this.prestamoActivo.id, false, this.motivoObservar.trim()).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Devolución observada. El técnico deberá corregir.', 'success');
        this.cerrarDetalle();
        this.cargar();
      },
      error: err => { this.procesando = false; this.toast.mostrar(err?.error?.detail ?? 'Error al observar.', 'error'); },
    });
  }

  // ── Helpers de presentación ──
  estadoLabel(e: PrestamoEstado): string {
    const m: Record<PrestamoEstado, string> = {
      solicitado: 'Solicitado', por_recibir: 'Por recibir (firma técnico)',
      entregado: 'En uso en servicio', devuelto: 'Devuelto · por confirmar',
      confirmado: 'Confirmado', rechazado: 'Rechazado',
    };
    return m[e] ?? e;
  }

  estadoClase(e: PrestamoEstado): string { return 'pre-est-' + e.replace(/_/g, '-'); }

  fechaCorta(iso: string | null): string {
    if (!iso) return '—';
    const d = new Date(iso.replace(' ', 'T'));
    if (isNaN(d.getTime())) return '—';
    return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }
}

import {
  Component, OnInit, OnDestroy, inject,
  ViewChildren, QueryList, ElementRef
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { Requerimiento, RequerimientoItem, AprobarItemDecision, EntregarPayload } from '../../logistica.models';

type TabReq = 'activos' | 'historial';
type PadRole = 'entregador' | 'receptor';

interface PadState {
  firmando: boolean;     // canvas open
  firma: string;         // data-url result
  bloqueadoPor: string | null;
  timerSecs: number;
  timerInterval: ReturnType<typeof setInterval> | null;
  isDrawing: boolean;
  lastX: number;
  lastY: number;
}

@Component({
  selector: 'app-requerimientos',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './requerimientos.component.html',
  styleUrls: ['./requerimientos.component.css'],
})
export class RequerimientosComponent implements OnInit, OnDestroy {
  private svc    = inject(LogisticaService);
  private toast  = inject(ToastService);
  private router = inject(Router);

  tab: TabReq = 'activos';
  cargando = true;

  activos:  Requerimiento[] = [];
  historial: Requerimiento[] = [];

  busqueda = '';

  // ── Modal de revisión / aprobación ──
  reqActivo: Requerimiento | null = null;
  decisiones: Record<string, 'aprobar' | 'compra' | 'rechazar'> = {};
  procesando = false;

  // ── Modal de detalle de ítems ──
  reqDetalle: Requerimiento | null = null;

  // ── Modal de rechazo ──
  reqRechazar: Requerimiento | null = null;
  motivoRechazo = '';

  // ── Modal de entrega con firma dual ──
  reqEntrega: Requerimiento | null = null;
  firmaGuardadaUrl: string | null = null;
  notasEntrega = '';
  enviandoEntrega = false;

  padEntregador: PadState = this._newPad();
  padReceptor:   PadState = this._newPad();

  @ViewChildren('canvasRef') canvasRefs!: QueryList<ElementRef<HTMLCanvasElement>>;

  // ── Reporte de impresión ──
  reqReporte: Requerimiento | null = null;

  ngOnInit(): void { this.cargar(); }

  ngOnDestroy(): void {
    this._clearTimer(this.padEntregador);
    this._clearTimer(this.padReceptor);
  }

  setTab(t: TabReq): void { this.tab = t; this.cargar(); }

  cargar(): void {
    this.cargando = true;
    if (this.tab === 'activos') {
      this.svc.getRequerimientos({ estado: 'activos' } as any).subscribe({
        next: d => { this.activos = d; this.cargando = false; },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar requerimientos.', 'error'); },
      });
    } else {
      this.svc.getHistorialRequerimientos().subscribe({
        next: d => { this.historial = d; this.cargando = false; },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar el historial.', 'error'); },
      });
    }
  }

  get lista(): Requerimiento[] {
    const base = this.tab === 'activos' ? this.activos : this.historial;
    const q = this.busqueda.toLowerCase().trim();
    if (!q) return base;
    return base.filter(r =>
      r.proyectoNombre.toLowerCase().includes(q) ||
      (r.servicioNombre ?? '').toLowerCase().includes(q) ||
      r.solicitanteNombre.toLowerCase().includes(q) ||
      r.items.some(i => i.nombre.toLowerCase().includes(q))
    );
  }

  get pendientesCount(): number { return this.activos.filter(r => r.estado === 'pendiente').length; }

  // ── Helpers de presentación ──
  estadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente:  'Pendiente',
      comprando:  'Comprando',
      aprobado:   'Aprobado',
      listo:      'Listo para entrega',
      entregado:  'Entregado',
      rechazado:  'Rechazado',
    };
    return m[e] ?? e;
  }

  estadoLabelTecnico(e: string): string {
    const m: Record<string, string> = {
      pendiente: 'Gestionando',
      comprando: 'Gestionando',
      aprobado:  'Gestionando',
      listo:     'Listo para retirar',
      entregado: 'Entregado',
      rechazado: 'Rechazado',
    };
    return m[e] ?? e;
  }

  estadoClase(e: string): string { return 'est-' + e.replace('_', '-'); }

  itemEstadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente:  'Pendiente',
      aprobado:   'De stock',
      para_compra:'Compra',
      rechazado:  'Rechazado',
    };
    return m[e] ?? e;
  }

  itemEstadoClase(e: string): string {
    const m: Record<string, string> = {
      pendiente: 'rie-pend', aprobado: 'rie-stock',
      para_compra: 'rie-compra', rechazado: 'rie-rech',
    };
    return m[e] ?? 'rie-pend';
  }

  // ── Modal de revisión ──
  get itemsDeStock(): RequerimientoItem[] {
    return !this.reqActivo ? [] : this.reqActivo.items.filter(it => this.decisiones[it.id] === 'aprobar');
  }
  get itemsDeCompra(): RequerimientoItem[] {
    return !this.reqActivo ? [] : this.reqActivo.items.filter(it => this.decisiones[it.id] === 'compra');
  }
  get itemsRechazados(): RequerimientoItem[] {
    return !this.reqActivo ? [] : this.reqActivo.items.filter(it => this.decisiones[it.id] === 'rechazar');
  }
  get todasDecididas(): boolean {
    return !!this.reqActivo && this.reqActivo.items.every(it => !!this.decisiones[it.id]);
  }

  abrirRevision(r: Requerimiento): void {
    this.reqActivo = r;
    this.decisiones = {};
    for (const it of r.items) {
      this.decisiones[it.id] = it.esCompraExterna || !it.enStock ? 'compra' : 'aprobar';
    }
  }
  cerrarRevision(): void { this.reqActivo = null; this.decisiones = {}; }
  setDecision(itemId: string, d: 'aprobar' | 'compra' | 'rechazar'): void { this.decisiones[itemId] = d; }

  confirmarAprobacion(): void {
    if (!this.reqActivo) return;
    this.procesando = true;
    const decisiones: AprobarItemDecision[] = this.reqActivo.items.map(it => ({
      detalleId: it.id,
      decision: this.decisiones[it.id] ?? 'aprobar',
    }));
    this.svc.aprobarRequerimiento(this.reqActivo.id, { decisiones }).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Requerimiento procesado. Stock actualizado.', 'success');
        this.cerrarRevision();
        this.cargar();
      },
      error: err => {
        this.procesando = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo procesar.', 'error');
      },
    });
  }

  // ── Modal detalle ──
  abrirDetalle(r: Requerimiento): void { this.reqDetalle = r; }
  cerrarDetalle(): void { this.reqDetalle = null; }

  countItemsStock(r: Requerimiento): number  { return r.items.filter(it => !it.esCompraExterna).length; }
  countItemsCompra(r: Requerimiento): number { return r.items.filter(it => it.esCompraExterna).length; }

  proyeccion(it: RequerimientoItem): number {
    return Math.max(0, it.stockDisponible - it.cantidad);
  }

  // ── Modal rechazo ──
  abrirRechazo(r: Requerimiento): void { this.reqRechazar = r; this.motivoRechazo = ''; }
  cerrarRechazo(): void { this.reqRechazar = null; this.motivoRechazo = ''; }
  confirmarRechazo(): void {
    if (!this.reqRechazar || !this.motivoRechazo.trim()) return;
    this.procesando = true;
    this.svc.rechazarRequerimiento(this.reqRechazar.id, this.motivoRechazo.trim()).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Requerimiento rechazado.', 'success');
        this.cerrarRechazo();
        this.cargar();
      },
      error: () => { this.procesando = false; this.toast.mostrar('No se pudo rechazar.', 'error'); },
    });
  }

  // ── Modal entrega con firma dual ──
  abrirEntrega(r: Requerimiento): void {
    this.reqEntrega = r;
    this.notasEntrega = '';
    this.padEntregador = this._newPad();
    this.padReceptor   = this._newPad();
    // Prefill saved firma for entregador (current user)
    this.svc.getFirmaGuardada().subscribe({
      next: f => { if (f?.url) this.padEntregador.firma = f.url; },
      error: () => {},
    });
  }

  cerrarEntrega(): void {
    if (this.reqEntrega) {
      this.svc.liberarFirma(this.reqEntrega.id).subscribe({ error: () => {} });
    }
    this._clearTimer(this.padEntregador);
    this._clearTimer(this.padReceptor);
    this.reqEntrega = null;
  }

  get puedeEntregar(): boolean {
    return !!this.padReceptor.firma;
  }

  // ── Cinema-seat: iniciar firma en un pad ──
  iniciarFirma(role: PadRole): void {
    const pad = role === 'entregador' ? this.padEntregador : this.padReceptor;
    if (pad.bloqueadoPor) return;

    if (!this.reqEntrega) return;
    this.svc.bloquearFirma(this.reqEntrega.id).subscribe({
      next: () => {
        pad.firmando = true;
        pad.timerSecs = 120;
        pad.timerInterval = setInterval(() => {
          pad.timerSecs--;
          if (pad.timerSecs <= 0) this._lockExpired(role);
        }, 1000);
        setTimeout(() => this._initCanvas(role), 50);
      },
      error: err => {
        const detail: string = err?.error?.detail ?? '';
        if (detail.startsWith('firmando_por:')) {
          pad.bloqueadoPor = detail.split(':')[1];
          this.toast.mostrar(`${pad.bloqueadoPor} está firmando. Espera 2 minutos.`, 'info');
        } else {
          this.toast.mostrar('No se pudo iniciar la firma.', 'error');
        }
      },
    });
  }

  cancelarFirma(role: PadRole): void {
    const pad = role === 'entregador' ? this.padEntregador : this.padReceptor;
    this._clearTimer(pad);
    pad.firmando = false;
    if (this.reqEntrega) {
      this.svc.liberarFirma(this.reqEntrega.id).subscribe({ error: () => {} });
    }
  }

  confirmarFirma(role: PadRole): void {
    const canvas = this._getCanvas(role);
    if (!canvas) return;
    const pad = role === 'entregador' ? this.padEntregador : this.padReceptor;
    pad.firma = canvas.toDataURL('image/png');
    this._clearTimer(pad);
    pad.firmando = false;
    if (this.reqEntrega) {
      this.svc.liberarFirma(this.reqEntrega.id).subscribe({ error: () => {} });
    }
  }

  limpiarFirma(role: PadRole): void {
    const canvas = this._getCanvas(role);
    if (!canvas) return;
    canvas.getContext('2d')?.clearRect(0, 0, canvas.width, canvas.height);
  }

  usarFirmaGuardada(role: PadRole): void {
    const pad = role === 'entregador' ? this.padEntregador : this.padReceptor;
    this.svc.getFirmaGuardada().subscribe({
      next: f => {
        if (f?.url) {
          pad.firma = f.url;
          pad.firmando = false;
          this._clearTimer(pad);
          if (this.reqEntrega) this.svc.liberarFirma(this.reqEntrega.id).subscribe({ error: () => {} });
        }
      },
      error: () => {},
    });
  }

  quitarFirma(role: PadRole): void {
    const pad = role === 'entregador' ? this.padEntregador : this.padReceptor;
    pad.firma = '';
  }

  confirmarEntrega(): void {
    if (!this.reqEntrega || !this.puedeEntregar) return;
    this.enviandoEntrega = true;
    const payload: EntregarPayload = {
      firmaUrl:           this.padReceptor.firma || null,
      firmaEntregadorUrl: this.padEntregador.firma || null,
      notas:              this.notasEntrega.trim() || null,
    };
    this.svc.entregarRequerimiento(this.reqEntrega.id, payload).subscribe({
      next: r => {
        this.enviandoEntrega = false;
        this.toast.mostrar('Entrega registrada exitosamente.', 'success');
        this.reqReporte = r;   // abrir reporte tras entregar
        this.cerrarEntrega();
        this.cargar();
      },
      error: err => {
        this.enviandoEntrega = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo registrar la entrega.', 'error');
      },
    });
  }

  // ── Reporte de impresión ──
  abrirReporte(r: Requerimiento): void { this.reqReporte = r; }
  cerrarReporte(): void { this.reqReporte = null; }
  imprimirReporte(): void { window.print(); }

  fechaHoy(): string {
    return new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' });
  }

  volverInventario(): void { this.router.navigate(['/logistica']); }

  // ─────────────────────────── Canvas helpers ───────────────────────────────

  private _newPad(): PadState {
    return { firmando: false, firma: '', bloqueadoPor: null, timerSecs: 120, timerInterval: null, isDrawing: false, lastX: 0, lastY: 0 };
  }

  private _getCanvas(role: PadRole): HTMLCanvasElement | null {
    const idx = role === 'entregador' ? 0 : 1;
    return this.canvasRefs?.get(idx)?.nativeElement ?? null;
  }

  private _initCanvas(role: PadRole): void {
    const canvas = this._getCanvas(role);
    if (!canvas) return;
    const pad = role === 'entregador' ? this.padEntregador : this.padReceptor;
    const ctx = canvas.getContext('2d')!;
    ctx.strokeStyle = '#0f172a';
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';

    const getPos = (e: MouseEvent | Touch) => {
      const rect = canvas.getBoundingClientRect();
      return { x: (e.clientX - rect.left) * (canvas.width / rect.width), y: (e.clientY - rect.top) * (canvas.height / rect.height) };
    };

    canvas.onmousedown = e => {
      pad.isDrawing = true;
      const p = getPos(e);
      pad.lastX = p.x; pad.lastY = p.y;
      ctx.beginPath(); ctx.moveTo(p.x, p.y);
    };
    canvas.onmousemove = e => {
      if (!pad.isDrawing) return;
      const p = getPos(e);
      ctx.lineTo(p.x, p.y); ctx.stroke();
      pad.lastX = p.x; pad.lastY = p.y;
    };
    canvas.onmouseup = canvas.onmouseleave = () => { pad.isDrawing = false; };

    canvas.ontouchstart = e => {
      e.preventDefault();
      const t = e.touches[0];
      pad.isDrawing = true;
      const p = getPos(t);
      pad.lastX = p.x; pad.lastY = p.y;
      ctx.beginPath(); ctx.moveTo(p.x, p.y);
    };
    canvas.ontouchmove = e => {
      e.preventDefault();
      if (!pad.isDrawing) return;
      const p = getPos(e.touches[0]);
      ctx.lineTo(p.x, p.y); ctx.stroke();
      pad.lastX = p.x; pad.lastY = p.y;
    };
    canvas.ontouchend = () => { pad.isDrawing = false; };
  }

  private _lockExpired(role: PadRole): void {
    const pad = role === 'entregador' ? this.padEntregador : this.padReceptor;
    this._clearTimer(pad);
    pad.firmando = false;
    pad.bloqueadoPor = null;
    if (this.reqEntrega) this.svc.liberarFirma(this.reqEntrega.id).subscribe({ error: () => {} });
    this.toast.mostrar('Tiempo de firma expirado. Puedes intentar de nuevo.', 'info');
  }

  private _clearTimer(pad: PadState): void {
    if (pad.timerInterval) { clearInterval(pad.timerInterval); pad.timerInterval = null; }
  }

  // ── Proveedores sugeridos (modal revisión) ──
  private readonly _proveedores = [
    { nombre: 'Distribuidora TecnoPlus', estrellas: '★★★★☆', contacto: '01-234-5678' },
    { nombre: 'Materiales Industriales Perú', estrellas: '★★★☆☆', contacto: '01-987-6543' },
    { nombre: 'Soluciones Eléctricas SAC', estrellas: '★★★★★', contacto: '01-555-0101' },
    { nombre: 'InduSupply Corp.', estrellas: '★★★★☆', contacto: '01-333-2244' },
  ];
  getProveedoresSugeridos(it: RequerimientoItem) {
    const seed = it.nombre.charCodeAt(0) % this._proveedores.length;
    const count = (seed % 2) + 2;
    return this._proveedores.slice(seed, seed + count)
      .concat(this._proveedores.slice(0, Math.max(0, count - (this._proveedores.length - seed))))
      .slice(0, count);
  }
}

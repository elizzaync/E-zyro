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
type PadRole = 'entregador';

interface PadState {
  firmando: boolean;
  firma: string;
  bloqueadoPor: string | null;
  timerSecs: number;
  timerInterval: ReturnType<typeof setInterval> | null;
  isDrawing: boolean;
  lastX: number;
  lastY: number;
}

interface GrupoServicio {
  key: string;
  servicioId: string | null;
  servicioNombre: string;
  proyectoNombre: string;
  reqs: Requerimiento[];
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

  // ── Agrupación por servicio ──
  gruposExpandidos  = new Set<string>();
  solicitadoAbierto = new Set<string>();

  // ── Modal de revisión / aprobación ──
  reqActivo: Requerimiento | null = null;
  decisiones: Record<string, 'aprobar' | 'compra' | 'rechazar'> = {};
  procesando = false;

  // ── Modal de detalle de ítems ──
  reqDetalle: Requerimiento | null = null;

  // ── Modal de rechazo ──
  reqRechazar: Requerimiento | null = null;
  motivoRechazo = '';

  // ── Modal de cierre de entrega (solo firma logística — Híbrido paso 2) ──
  reqEntrega:         Requerimiento | null = null;
  reqsEntregaGlobal:  Requerimiento[]      = [];
  notasEntrega        = '';
  enviandoEntrega     = false;
  padEntregador: PadState = this._newPad();

  @ViewChildren('canvasRef') canvasRefs!: QueryList<ElementRef<HTMLCanvasElement>>;

  // ── Reporte de impresión ──
  reqReporte: Requerimiento | null = null;

  ngOnInit(): void {
    this.cargar();
    // Los grupos se expanden por defecto al cargar
  }

  ngOnDestroy(): void {
    this._clearTimer(this.padEntregador);
  }

  setTab(t: TabReq): void { this.tab = t; this.cargar(); }

  cargar(): void {
    this.cargando = true;
    if (this.tab === 'activos') {
      this.svc.getRequerimientos({ estado: 'activos' } as any).subscribe({
        next: d => {
          this.activos = d;
          this.cargando = false;
          // Expandir todos los grupos por defecto
          this._inicializarGrupos();
        },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar requerimientos.', 'error'); },
      });
    } else {
      this.svc.getHistorialRequerimientos().subscribe({
        next: d => { this.historial = d; this.cargando = false; },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar el historial.', 'error'); },
      });
    }
  }

  private _inicializarGrupos(): void {
    for (const g of this.gruposPorServicio) {
      this.gruposExpandidos.add(g.key);
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

  // ── Agrupación ──
  get gruposPorServicio(): GrupoServicio[] {
    const map = new Map<string, GrupoServicio>();
    for (const r of this.lista) {
      const key = r.servicioId ?? ('proy-' + (r.proyectoId ?? 'general'));
      if (!map.has(key)) {
        map.set(key, {
          key,
          servicioId: r.servicioId,
          servicioNombre: r.servicioNombre ?? r.proyectoNombre,
          proyectoNombre: r.proyectoNombre,
          reqs: [],
        });
      }
      map.get(key)!.reqs.push(r);
    }
    return Array.from(map.values());
  }

  toggleGrupo(key: string): void {
    if (this.gruposExpandidos.has(key)) this.gruposExpandidos.delete(key);
    else this.gruposExpandidos.add(key);
  }
  isGrupoExpandido(key: string): boolean { return this.gruposExpandidos.has(key); }

  toggleSolicitado(key: string): void {
    if (this.solicitadoAbierto.has(key)) this.solicitadoAbierto.delete(key);
    else this.solicitadoAbierto.add(key);
  }
  isSolicitadoAbierto(key: string): boolean { return this.solicitadoAbierto.has(key); }

  cuentaEstado(grupo: GrupoServicio, estado: string): number {
    return grupo.reqs.filter(r => r.estado === estado).length;
  }

  itemsTodosSolicitados(grupo: GrupoServicio): RequerimientoItem[] {
    return grupo.reqs.flatMap(r => r.items);
  }

  grupoTieneListos(grupo: GrupoServicio):    boolean { return grupo.reqs.some(r => r.estado === 'listo'); }
  grupoTieneAprobados(grupo: GrupoServicio): boolean { return grupo.reqs.some(r => r.estado === 'aprobado'); }

  // ── Helpers de presentación ──
  estadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente:  'Pendiente',
      comprando:  'En compra',
      aprobado:   'Recibido',
      listo:      'Falta firma técnico',
      entregado:  'Entregado',
      rechazado:  'Rechazado',
    };
    return m[e] ?? e;
  }

  estadoClase(e: string): string { return 'est-' + e.replace('_', '-'); }

  itemEstadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente:   'Pendiente',
      aprobado:    'De stock',
      para_compra: 'Compra',
      rechazado:   'Rechazado',
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
      decision:  this.decisiones[it.id] ?? 'aprobar',
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

  // Aprobación automática (backend decide por stock disponible)
  aprobarAuto(r: Requerimiento): void {
    if (this.procesando) return;
    this.procesando = true;
    this.svc.aprobarRequerimiento(r.id, { decisiones: [] }).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Aprobado automáticamente: stock asignado, faltante enviado a compras.', 'success');
        this.cargar();
      },
      error: err => {
        this.procesando = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo aprobar.', 'error');
      },
    });
  }

  // ── Modal detalle ──
  abrirDetalle(r: Requerimiento): void { this.reqDetalle = r; }
  cerrarDetalle(): void { this.reqDetalle = null; }

  countItemsStock(r: Requerimiento): number  { return r.items.filter(it => !it.esCompraExterna).length; }
  countItemsCompra(r: Requerimiento): number { return r.items.filter(it =>  it.esCompraExterna).length; }

  proyeccion(it: RequerimientoItem): number { return Math.max(0, it.stockDisponible - it.cantidad); }

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

  // ── Modal cierre de entrega (Híbrido paso 2 — solo firma logística) ──
  abrirEntrega(r: Requerimiento): void {
    this.reqEntrega       = r;
    this.reqsEntregaGlobal = [r];
    this.notasEntrega     = '';
    this.padEntregador    = this._newPad();
    this.svc.getFirmaGuardada().subscribe({
      next: f => { if (f?.url) this.padEntregador.firma = f.url; },
      error: () => {},
    });
  }

  abrirEntregaGlobal(grupo: GrupoServicio): void {
    const aprobados = grupo.reqs.filter(r => r.estado === 'aprobado');
    if (!aprobados.length) return;
    this.reqsEntregaGlobal = aprobados;
    this.reqEntrega        = aprobados[0];
    this.notasEntrega      = '';
    this.padEntregador     = this._newPad();
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
    this.reqEntrega        = null;
    this.reqsEntregaGlobal = [];
  }

  get puedeEntregar(): boolean { return !!this.padEntregador.firma; }

  // ── Cinema-seat: solo pad del entregador (logística) ──
  iniciarFirma(): void {
    const pad = this.padEntregador;
    if (pad.bloqueadoPor || !this.reqEntrega) return;
    this.svc.bloquearFirma(this.reqEntrega.id).subscribe({
      next: () => {
        pad.firmando = true;
        pad.timerSecs = 120;
        pad.timerInterval = setInterval(() => {
          pad.timerSecs--;
          if (pad.timerSecs <= 0) this._lockExpired();
        }, 1000);
        setTimeout(() => this._initCanvas(), 50);
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

  cancelarFirma(): void {
    this._clearTimer(this.padEntregador);
    this.padEntregador.firmando = false;
    if (this.reqEntrega) this.svc.liberarFirma(this.reqEntrega.id).subscribe({ error: () => {} });
  }

  confirmarFirma(): void {
    const canvas = this._getCanvas();
    if (!canvas) return;
    this.padEntregador.firma = canvas.toDataURL('image/png');
    this._clearTimer(this.padEntregador);
    this.padEntregador.firmando = false;
    if (this.reqEntrega) this.svc.liberarFirma(this.reqEntrega.id).subscribe({ error: () => {} });
  }

  limpiarFirma(): void {
    const canvas = this._getCanvas();
    if (!canvas) return;
    canvas.getContext('2d')?.clearRect(0, 0, canvas.width, canvas.height);
  }

  usarFirmaGuardada(): void {
    this.svc.getFirmaGuardada().subscribe({
      next: f => {
        if (f?.url) {
          this.padEntregador.firma    = f.url;
          this.padEntregador.firmando = false;
          this._clearTimer(this.padEntregador);
          if (this.reqEntrega) this.svc.liberarFirma(this.reqEntrega.id).subscribe({ error: () => {} });
        }
      },
      error: () => {},
    });
  }

  quitarFirma(): void { this.padEntregador.firma = ''; }

  confirmarEntrega(): void {
    if (!this.reqEntrega || !this.puedeEntregar) return;
    this.enviandoEntrega = true;
    const payload: EntregarPayload = {
      firmaEntregadorUrl: this.padEntregador.firma || null,
      notas:              this.notasEntrega.trim() || null,
    };

    const reqs = this.reqsEntregaGlobal.length > 0 ? this.reqsEntregaGlobal : [this.reqEntrega];
    let completadas = 0;
    let lastResult: Requerimiento | null = null;

    for (const req of reqs) {
      this.svc.entregarRequerimiento(req.id, payload).subscribe({
        next: r => {
          completadas++;
          lastResult = r;
          if (completadas === reqs.length) {
            this.enviandoEntrega = false;
            const msg = reqs.length > 1
              ? `${completadas} entregas cerradas exitosamente.`
              : 'Entrega cerrada exitosamente.';
            this.toast.mostrar(msg, 'success');
            if (lastResult) this.generarPDFSalida(lastResult);
            this.cerrarEntrega();
            this.cargar();
          }
        },
        error: err => {
          this.enviandoEntrega = false;
          this.toast.mostrar(err?.error?.detail ?? 'No se pudo cerrar la entrega.', 'error');
        },
      });
    }
  }

  // ── Reporte de impresión ──
  abrirReporte(r: Requerimiento): void { this.reqReporte = r; }
  cerrarReporte(): void { this.reqReporte = null; }
  imprimirReporte(): void { window.print(); }

  fechaHoy(): string {
    return new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' });
  }

  volverInventario(): void { this.router.navigate(['/logistica']); }

  // ── Generación de PDF Salida de Equipos y Herramientas ──
  async generarPDFSalida(req: Requerimiento): Promise<void> {
    try {
      const { PDFDocument, rgb, StandardFonts } = await import('pdf-lib');
      const INK    = rgb(0.09, 0.12, 0.18);
      const MUTED  = rgb(0.40, 0.46, 0.56);
      const RULE   = rgb(0.88, 0.90, 0.93);
      const HDR_BG = rgb(0.96, 0.97, 0.98);
      const ACCENT = rgb(0.569, 0.827, 0.216);
      const PW = 595, PH = 842, ML = 44, MR = 44;
      const BODY_W = PW - ML - MR;
      const doc     = await PDFDocument.create();
      const regular = await doc.embedFont(StandardFonts.Helvetica);
      const bold    = await doc.embedFont(StandardFonts.HelveticaBold);
      const page    = doc.addPage([PW, PH]);
      let y = PH - 50;
      const ROW_H = 20;
      const ty = (topY: number) => topY - ROW_H + 6;
      const hLine = (yy: number) => {
        page.drawLine({ start: { x: ML, y: yy }, end: { x: PW - MR, y: yy }, thickness: 0.5, color: RULE });
      };

      // Encabezado
      page.drawText('REPORTE DE SALIDA DE EQUIPOS Y HERRAMIENTAS', { x: ML, y, size: 13, font: bold, color: INK });
      y -= 18;
      page.drawText('E-System TIC · Gestión de Logística de Campo', { x: ML, y, size: 8.5, font: regular, color: MUTED });
      y -= 8;
      page.drawLine({ start: { x: ML, y }, end: { x: PW - MR, y }, thickness: 1.5, color: ACCENT });
      y -= 20;

      const emitDate = new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' });
      const C2 = ML + Math.floor(BODY_W / 2) + 8;

      page.drawText('Proyecto', { x: ML, y, size: 7.5, font: regular, color: MUTED });
      page.drawText('Fecha de emisión', { x: C2, y, size: 7.5, font: regular, color: MUTED });
      y -= 13;
      const proj = req.proyectoNombre.length > 38 ? req.proyectoNombre.slice(0, 35) + '…' : req.proyectoNombre;
      page.drawText(proj, { x: ML, y, size: 9, font: bold, color: INK });
      page.drawText(emitDate, { x: C2, y, size: 9, font: bold, color: INK });
      y -= 18;

      page.drawText('Servicio', { x: ML, y, size: 7.5, font: regular, color: MUTED });
      page.drawText('N° Requerimiento', { x: C2, y, size: 7.5, font: regular, color: MUTED });
      y -= 13;
      page.drawText(req.servicioNombre ?? '—', { x: ML, y, size: 9, font: bold, color: INK });
      page.drawText(req.id.slice(0, 8).toUpperCase(), { x: C2, y, size: 9, font: bold, color: INK });
      y -= 18;

      page.drawText('Entregado por (Logística)', { x: ML, y, size: 7.5, font: regular, color: MUTED });
      page.drawText('Recibido por (Técnico responsable)', { x: C2, y, size: 7.5, font: regular, color: MUTED });
      y -= 13;
      page.drawText(req.entregadoPorNombre ?? '—', { x: ML, y, size: 9, font: bold, color: INK });
      page.drawText(req.recibidoPorNombre  ?? '—', { x: C2, y, size: 9, font: bold, color: INK });
      y -= 22;

      hLine(y); y -= 14;
      page.drawText(
        'NOTA: El técnico que firma la recepción asume responsabilidad sobre todos los equipos y herramientas (no consumibles) listados a continuación.',
        { x: ML, y, size: 7.5, font: regular, color: MUTED }
      );
      y -= 22;

      // Tabla de ítems
      page.drawText('DETALLE DE MATERIALES, EQUIPOS Y HERRAMIENTAS', { x: ML, y, size: 9, font: bold, color: INK });
      y -= 14;
      hLine(y);
      page.drawRectangle({ x: ML, y: y - ROW_H, width: BODY_W, height: ROW_H, color: HDR_BG });
      page.drawText('#',           { x: ML + 4,        y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Descripción', { x: ML + 24,       y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Tipo',        { x: PW - MR - 160, y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Cant.',       { x: PW - MR - 82,  y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Unidad',      { x: PW - MR - 50,  y: ty(y), size: 7.5, font: bold, color: MUTED });
      y -= ROW_H; hLine(y);

      const items = req.items.filter(it => it.estadoItem !== 'rechazado');
      for (let i = 0; i < items.length; i++) {
        const it = items[i];
        if (y - ROW_H < 170) break;
        const nom  = it.nombre.length > 46 ? it.nombre.slice(0, 43) + '…' : it.nombre;
        const espec = it.especificacion?.toLowerCase() ?? '';
        const tipo  = espec.includes('equipo')       ? 'Equipo' :
                      espec.includes('herramienta')  ? 'Herramienta' :
                      it.esCompraExterna             ? 'Compra ext.' : 'Material';
        const esNC = tipo === 'Equipo' || tipo === 'Herramienta';
        page.drawText(`${i + 1}`, { x: ML + 4, y: ty(y), size: 8, font: regular, color: MUTED });
        page.drawText(nom, { x: ML + 24, y: ty(y), size: 8, font: esNC ? bold : regular, color: INK });
        page.drawText(tipo, { x: PW - MR - 160, y: ty(y), size: 7.5, font: regular, color: esNC ? rgb(0.56, 0.27, 0.87) : MUTED });
        page.drawText(`${it.cantidadAprobada ?? it.cantidad}`, { x: PW - MR - 82, y: ty(y), size: 8, font: bold, color: INK });
        page.drawText(it.unidad, { x: PW - MR - 50, y: ty(y), size: 7.5, font: regular, color: MUTED });
        y -= ROW_H; hLine(y);
      }
      y -= 20;

      // Área de firmas
      const SIG_TOP = Math.max(y, 170);
      const SIG_W   = Math.floor(BODY_W / 2) - 20;
      hLine(SIG_TOP + 60);
      page.drawText('ENTREGADO POR (LOGÍSTICA)', { x: ML, y: SIG_TOP + 70, size: 7, font: bold, color: MUTED });
      page.drawText('RECIBIDO POR (TÉCNICO RESPONSABLE)', { x: ML + SIG_W + 40, y: SIG_TOP + 70, size: 7, font: bold, color: MUTED });

      if (req.firmaEntregadorUrl?.startsWith('data:image')) {
        try {
          const b64  = req.firmaEntregadorUrl.split(',')[1];
          const imgB = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
          const img  = await doc.embedPng(imgB.buffer as ArrayBuffer);
          const d    = img.scaleToFit(SIG_W, 50);
          page.drawImage(img, { x: ML, y: SIG_TOP + 8, width: d.width, height: d.height });
        } catch { /* no se pudo embeber */ }
      }

      if (req.firmaUrl?.startsWith('data:image')) {
        try {
          const b64  = req.firmaUrl.split(',')[1];
          const imgB = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
          const img  = await doc.embedPng(imgB.buffer as ArrayBuffer);
          const d    = img.scaleToFit(SIG_W, 50);
          page.drawImage(img, { x: ML + SIG_W + 40, y: SIG_TOP + 8, width: d.width, height: d.height });
        } catch { /* no se pudo embeber */ }
      }

      page.drawText(req.entregadoPorNombre ?? '________________________________', { x: ML, y: SIG_TOP - 4, size: 8, font: regular, color: INK });
      page.drawText('Responsable de Logística', { x: ML, y: SIG_TOP - 16, size: 7.5, font: regular, color: MUTED });
      page.drawText(req.recibidoPorNombre ?? '________________________________', { x: ML + SIG_W + 40, y: SIG_TOP - 4, size: 8, font: regular, color: INK });
      page.drawText('Técnico / Resp. de Recepción', { x: ML + SIG_W + 40, y: SIG_TOP - 16, size: 7.5, font: regular, color: MUTED });

      // Pie de página
      page.drawLine({ start: { x: ML, y: 46 }, end: { x: PW - MR, y: 46 }, thickness: 0.5, color: RULE });
      page.drawText('E-System TIC Perú S.A.C. · Reporte de Salida de Equipos y Herramientas · Documento Oficial de Control', {
        x: ML, y: 33, size: 7, font: regular, color: MUTED
      });

      const bytes = await doc.save();
      const blob  = new Blob([bytes.buffer as ArrayBuffer], { type: 'application/pdf' });
      const url   = URL.createObjectURL(blob);
      const a     = document.createElement('a');
      a.href     = url;
      a.download = `salida-equipos-${req.proyectoNombre.replace(/\s+/g, '-').slice(0, 20)}-${req.id.slice(0, 6)}.pdf`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 3000);
    } catch (err) {
      console.error('Error generando PDF de salida:', err);
    }
  }

  // ─────────────────────────── Canvas helpers ───────────────────────────────

  private _newPad(): PadState {
    return { firmando: false, firma: '', bloqueadoPor: null, timerSecs: 120, timerInterval: null, isDrawing: false, lastX: 0, lastY: 0 };
  }

  private _getCanvas(): HTMLCanvasElement | null {
    return this.canvasRefs?.get(0)?.nativeElement ?? null;
  }

  private _initCanvas(): void {
    const canvas = this._getCanvas();
    if (!canvas) return;
    const pad = this.padEntregador;
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

  private _lockExpired(): void {
    this._clearTimer(this.padEntregador);
    this.padEntregador.firmando    = false;
    this.padEntregador.bloqueadoPor = null;
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
    const seed  = it.nombre.charCodeAt(0) % this._proveedores.length;
    const count = (seed % 2) + 2;
    return this._proveedores.slice(seed, seed + count)
      .concat(this._proveedores.slice(0, Math.max(0, count - (this._proveedores.length - seed))))
      .slice(0, count);
  }
}

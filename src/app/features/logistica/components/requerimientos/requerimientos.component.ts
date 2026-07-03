import {
  Component, OnInit, OnDestroy, inject,
  ViewChild, ElementRef
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { Requerimiento, RequerimientoItem, AprobarItemDecision, EntregarPayload } from '../../logistica.models';

type TabReq = 'activos' | 'historial';

interface PadState {
  firmando: boolean;
  firma: string;
  bloqueadoPor: string | null;
  timerSecs: number;
  timerInterval: ReturnType<typeof setInterval> | null;
  isDrawing: boolean;
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
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './requerimientos.component.html',
  styleUrls: ['./requerimientos.component.css'],
})
export class RequerimientosComponent implements OnInit, OnDestroy {
  private svc    = inject(LogisticaService);
  private toast  = inject(ToastService);
  private router = inject(Router);

  tab: TabReq = 'activos';
  cargando = true;

  activos:   Requerimiento[] = [];
  historial: Requerimiento[] = [];
  busqueda = '';

  // ── Paginación del historial (server-side) ──
  historialPage     = 1;
  historialPageSize = 20;
  historialTotal    = 0;

  get historialTotalPaginas(): number {
    return Math.max(1, Math.ceil(this.historialTotal / this.historialPageSize));
  }

  // ── Modal de gestión del servicio ──
  servicioModal: GrupoServicio | null = null;
  firmaModalAbierta = false;
  firmaGuardadaUrl  = '';
  padFirma: PadState = this._newPad();
  entregandoServicio = false;

  @ViewChild('firmaModalCanvas') firmaModalCanvasEl?: ElementRef<HTMLCanvasElement>;

  // ── Modal revisión / aprobación ──
  reqActivo: Requerimiento | null = null;
  decisiones: Record<string, 'aprobar' | 'compra' | 'rechazar'> = {};
  procesando = false;

  // ── Modal rechazo ──
  reqRechazar: Requerimiento | null = null;
  motivoRechazo = '';

  // ── Reporte / comprobante ──
  reqReporte: Requerimiento | null = null;

  // ── Panel de firmas ──
  firmasReqId:  string | null = null;
  firmasData:   any[]         = [];
  firmasCargando = false;

  ngOnInit(): void { this.cargar(); }

  ngOnDestroy(): void { this._clearTimer(this.padFirma); }

  setTab(t: TabReq): void {
    this.tab = t;
    if (t === 'historial') this.historialPage = 1;
    this.cargar();
  }

  cargar(): void {
    this.cargando = true;
    if (this.tab === 'activos') {
      this.svc.getRequerimientos({ estado: 'activos' } as any).subscribe({
        next: d => { this.activos = d; this.cargando = false; },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar requerimientos.', 'error'); },
      });
    } else {
      this.svc.getHistorialRequerimientos({
        q: this.busqueda || undefined,
        page: this.historialPage,
        pageSize: this.historialPageSize,
      }).subscribe({
        next: r => { this.historial = r.items; this.historialTotal = r.total; this.cargando = false; },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar historial.', 'error'); },
      });
    }
  }

  // Buscador: en "Activos" filtra en memoria (get lista); en "Historial" es
  // server-side (paginado), así que hay que recargar desde la página 1.
  buscarHistorial(): void {
    this.historialPage = 1;
    this.cargar();
  }

  irPaginaHistorial(p: number): void {
    if (p < 1 || p > this.historialTotalPaginas) return;
    this.historialPage = p;
    this.cargar();
  }

  get lista(): Requerimiento[] {
    if (this.tab === 'historial') return this.historial;
    const q = this.busqueda.toLowerCase().trim();
    if (!q) return this.activos;
    return this.activos.filter(r =>
      r.proyectoNombre.toLowerCase().includes(q) ||
      (r.servicioNombre ?? '').toLowerCase().includes(q) ||
      r.solicitanteNombre.toLowerCase().includes(q) ||
      r.items.some(i => i.nombre.toLowerCase().includes(q))
    );
  }

  verDetalleHistorial(r: Requerimiento): void {
    this.abrirModalServicio({
      key: r.id,
      servicioId: r.servicioId,
      servicioNombre: r.servicioNombre ?? r.proyectoNombre,
      proyectoNombre: r.proyectoNombre,
      reqs: [r],
    });
  }

  get pendientesCount(): number { return this.activos.filter(r => r.estado === 'pendiente').length; }

  // ── Agrupación por servicio ──
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

  // ── Helpers de estado del grupo ──
  cuentaEstado(g: GrupoServicio, e: string): number {
    return g.reqs.filter(r => r.estado === e).length;
  }

  estadoGlobal(g: GrupoServicio): 'pendiente' | 'comprando' | 'listo' | 'aprobado' | 'entregado' | 'mixto' {
    const estados = new Set(g.reqs.map(r => r.estado));
    if (estados.size === 1) return [...estados][0] as any;
    if (estados.has('pendiente')) return 'pendiente';
    if (estados.has('comprando')) return 'comprando';
    if (estados.has('listo')) return 'listo';
    return 'mixto';
  }

  todosListosParaEntregar(g: GrupoServicio): boolean {
    return g.reqs.length > 0 &&
      g.reqs.every(r => r.estado === 'listo' || r.estado === 'aprobado' || r.estado === 'entregado' || r.estado === 'rechazado') &&
      g.reqs.some(r => r.estado === 'listo');
  }

  razonNoPuedeEntregar(g: GrupoServicio): string {
    const pend = g.reqs.filter(r => r.estado === 'pendiente').length;
    const comp  = g.reqs.filter(r => r.estado === 'comprando').length;
    if (pend) return `${pend} requerimiento${pend > 1 ? 's' : ''} sin aprobar`;
    if (comp)  return `${comp} compra${comp > 1 ? 's' : ''} pendiente${comp > 1 ? 's' : ''} de recibir`;
    return '';
  }

  // Items agrupados para el modal del servicio
  itemsModalServicio(g: GrupoServicio): { req: Requerimiento; it: RequerimientoItem }[] {
    return g.reqs.flatMap(r => r.items.map(it => ({ req: r, it })));
  }

  itemsDeStock(g: GrupoServicio): RequerimientoItem[] {
    return g.reqs.flatMap(r => r.items.filter(it => it.estadoItem === 'aprobado' && !it.esCompraExterna));
  }

  itemsDeCompraRecibida(g: GrupoServicio): RequerimientoItem[] {
    return g.reqs.flatMap(r => r.items.filter(it => it.estadoItem === 'aprobado' && it.esCompraExterna));
  }

  itemsEnCompra(g: GrupoServicio): RequerimientoItem[] {
    return g.reqs.flatMap(r => r.items.filter(it => it.estadoItem === 'para_compra'));
  }

  itemsPendientes(g: GrupoServicio): RequerimientoItem[] {
    return g.reqs.flatMap(r => r.items.filter(it => it.estadoItem === 'pendiente'));
  }

  // ── Abrir / cerrar modal de servicio ──
  abrirModalServicio(g: GrupoServicio): void {
    this.servicioModal = g;
    this.firmaModalAbierta = false;
    this.firmaGuardadaUrl = '';
    this.padFirma = this._newPad();
    this.svc.getFirmaGuardada().subscribe({
      next: f => { if (f?.url) this.firmaGuardadaUrl = f.url; },
      error: () => {},
    });
  }

  cerrarModalServicio(): void {
    if (this.padFirma.firmando && this.servicioModal) {
      const req = this.servicioModal.reqs.find(r => r.estado === 'listo');
      if (req) this.svc.liberarFirma(req.id).subscribe({ error: () => {} });
    }
    this._clearTimer(this.padFirma);
    this.servicioModal = null;
    this.firmaModalAbierta = false;
  }

  actualizarModalServicio(): void {
    if (!this.servicioModal) return;
    this.cargar();
    // Re-sync modal group after reload
    setTimeout(() => {
      if (!this.servicioModal) return;
      const key = this.servicioModal.key;
      const found = this.gruposPorServicio.find(g => g.key === key);
      if (found) this.servicioModal = found;
    }, 600);
  }

  // ── Firma dentro del modal de servicio ──
  abrirSeccionFirma(): void {
    this.firmaModalAbierta = true;
    if (this.firmaGuardadaUrl) {
      this.padFirma.firma = this.firmaGuardadaUrl;
    } else {
      setTimeout(() => this._initModalCanvas(), 80);
    }
  }

  usarFirmaGuardadaModal(): void {
    this.padFirma.firma = this.firmaGuardadaUrl;
    this._clearTimer(this.padFirma);
    this.padFirma.firmando = false;
  }

  iniciarFirmaModal(): void {
    if (!this.servicioModal) return;
    const req = this.servicioModal.reqs.find(r => r.estado === 'listo');
    if (!req) return;
    this.svc.bloquearFirma(req.id).subscribe({
      next: () => {
        this.padFirma.firmando = true;
        this.padFirma.firma = '';
        this.padFirma.timerSecs = 120;
        this.padFirma.timerInterval = setInterval(() => {
          this.padFirma.timerSecs--;
          if (this.padFirma.timerSecs <= 0) {
            this._clearTimer(this.padFirma);
            this.padFirma.firmando = false;
            if (req) this.svc.liberarFirma(req.id).subscribe({ error: () => {} });
          }
        }, 1000);
        setTimeout(() => this._initModalCanvas(), 50);
      },
      error: err => {
        const d: string = err?.error?.detail ?? '';
        this.toast.mostrar(d.startsWith('firmando_por:')
          ? `${d.split(':')[1]} está firmando. Espera.`
          : 'No se pudo iniciar firma.', 'error');
      },
    });
  }

  confirmarFirmaModal(): void {
    const canvas = this.firmaModalCanvasEl?.nativeElement;
    if (!canvas) return;
    this.padFirma.firma = canvas.toDataURL('image/png');
    this._clearTimer(this.padFirma);
    this.padFirma.firmando = false;
    if (this.servicioModal) {
      const req = this.servicioModal.reqs.find(r => r.estado === 'listo');
      if (req) this.svc.liberarFirma(req.id).subscribe({ error: () => {} });
    }
  }

  limpiarFirmaModal(): void {
    const canvas = this.firmaModalCanvasEl?.nativeElement;
    if (canvas) canvas.getContext('2d')?.clearRect(0, 0, canvas.width, canvas.height);
  }

  cancelarFirmaModal(): void {
    this._clearTimer(this.padFirma);
    this.padFirma.firmando = false;
    if (this.servicioModal) {
      const req = this.servicioModal.reqs.find(r => r.estado === 'listo');
      if (req) this.svc.liberarFirma(req.id).subscribe({ error: () => {} });
    }
  }

  quitarFirmaModal(): void { this.padFirma.firma = ''; }

  // ── Confirmar entrega del servicio (logística firma → aprobado) ──
  confirmarEntregaServicio(): void {
    if (!this.servicioModal || !this.padFirma.firma) return;
    const reqs = this.servicioModal.reqs.filter(r => r.estado === 'listo');
    if (!reqs.length) return;

    this.entregandoServicio = true;
    let done = 0;

    for (const req of reqs) {
      this.svc.firmarRequerimiento(req.id, '', this.padFirma.firma).subscribe({
        next: () => {
          done++;
          if (done === reqs.length) {
            this.entregandoServicio = false;
            this.toast.mostrar(
              `Entrega confirmada. ${done > 1 ? done + ' requerimientos enviados' : 'Requerimiento enviado'} al técnico para su firma.`,
              'success'
            );
            this.cerrarModalServicio();
            this.cargar();
          }
        },
        error: err => {
          this.entregandoServicio = false;
          this.toast.mostrar(err?.error?.detail ?? 'Error al confirmar entrega.', 'error');
        },
      });
    }
  }

  // ── Modal de revisión ──
  get itemsDeStockRev(): RequerimientoItem[] {
    return !this.reqActivo ? [] : this.reqActivo.items.filter(it => this.decisiones[it.id] === 'aprobar');
  }
  get itemsDeCompraRev(): RequerimientoItem[] {
    return !this.reqActivo ? [] : this.reqActivo.items.filter(it => this.decisiones[it.id] === 'compra');
  }
  get itemsRechazadosRev(): RequerimientoItem[] {
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
  setDecision(id: string, d: 'aprobar' | 'compra' | 'rechazar'): void {
    if (d === 'aprobar') {
      const item = this.reqActivo?.items.find(it => it.id === id);
      if (item && !item.enStock && !item.esCompraExterna) {
        this.toast.mostrar('Sin stock disponible. Ítem redirigido a compra.', 'info');
        this.decisiones[id] = 'compra';
        return;
      }
    }
    this.decisiones[id] = d;
  }

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
        this.toast.mostrar('Requerimiento procesado.', 'success');
        this.cerrarRevision();
        this.cargar();
        // Sync modal if open
        if (this.servicioModal) this.actualizarModalServicio();
      },
      error: err => {
        this.procesando = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo procesar.', 'error');
      },
    });
  }

  aprobarAuto(r: Requerimiento): void {
    if (this.procesando) return;
    this.procesando = true;
    this.svc.aprobarRequerimiento(r.id, { decisiones: [] }).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Aprobado automáticamente.', 'success');
        this.cargar();
        if (this.servicioModal) this.actualizarModalServicio();
      },
      error: err => {
        this.procesando = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo aprobar.', 'error');
      },
    });
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

  // ── Reporte ──
  abrirReporte(r: Requerimiento): void { this.reqReporte = r; }
  cerrarReporte(): void { this.reqReporte = null; }
  imprimirReporte(): void { window.print(); }

  // ── Firmas ──
  verFirmas(r: Requerimiento): void {
    this.firmasReqId  = r.id;
    this.firmasData   = [];
    this.firmasCargando = true;
    this.svc.getFirmasRequerimiento(r.id).subscribe({
      next:  d => { this.firmasData = d; this.firmasCargando = false; },
      error: () => { this.firmasCargando = false; this.toast.mostrar('Error al cargar firmas.', 'error'); },
    });
  }
  cerrarFirmas(): void { this.firmasReqId = null; this.firmasData = []; }
  formatFechaFirma(f: string | null): string {
    if (!f) return '—';
    const d = new Date(f);
    return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' })
      + ' ' + d.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' });
  }

  volverInventario(): void { this.router.navigate(['/logistica']); }

  fechaHoy(): string {
    return new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' });
  }

  // ── Helpers de presentación ──
  estadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente: 'Pendiente', comprando: 'En compra',
      listo: 'Listo para entrega', aprobado: 'Entregado · esp. técnico',
      entregado: 'Entregado', rechazado: 'Rechazado',
    };
    return m[e] ?? e;
  }
  estadoClase(e: string): string { return 'est-' + e.replace('_', '-'); }

  fechaCortaReq(f: string | null): string {
    if (!f) return '—';
    const d = new Date(f);
    if (isNaN(d.getTime())) return '—';
    return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  itemEstadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente: 'Pendiente', aprobado: 'Listo', para_compra: 'En compra', rechazado: 'Rechazado',
    };
    return m[e] ?? e;
  }
  itemEstadoClase(e: string): string {
    const m: Record<string, string> = {
      pendiente: 'rie-pend', aprobado: 'rie-stock', para_compra: 'rie-compra', rechazado: 'rie-rech',
    };
    return m[e] ?? 'rie-pend';
  }

  proyeccion(it: RequerimientoItem): number {
    return Math.max(0, it.stockDisponible - it.cantidad);
  }

  // ── Generación de PDF con watermark + logo ──
  async generarPDFSalida(grupo: GrupoServicio | null, reqSingle?: Requerimiento): Promise<void> {
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

      // Cargar imágenes
      const fetchImg = async (url: string): Promise<ArrayBuffer | null> => {
        try { const r = await fetch(url); return r.ok ? await r.arrayBuffer() : null; } catch { return null; }
      };
      const [wmBytes, logoBytes] = await Promise.all([
        fetchImg('/assets/img/logo_difuminado.png'),
        fetchImg('/assets/img/index.png'),
      ]);
      let wmImg:   any = null;
      let logoImg: any = null;
      if (wmBytes)   try { wmImg   = await doc.embedPng(wmBytes);   } catch { wmImg = null; }
      if (logoBytes) try { logoImg = await doc.embedPng(logoBytes); } catch { logoImg = null; }

      const ROW_H = 20;
      const ty = (topY: number) => topY - ROW_H + 6;

      const addPage = () => {
        const p = doc.addPage([PW, PH]);
        // Watermark en cada página
        if (wmImg) {
          const d = wmImg.scaleToFit(260, 260);
          p.drawImage(wmImg, {
            x: PW / 2 - d.width / 2, y: PH / 2 - d.height / 2,
            width: d.width, height: d.height, opacity: 0.07,
          });
        }
        return p;
      };

      let page = addPage();
      let y = PH - 50;

      const hLine = (yy: number) =>
        page.drawLine({ start: { x: ML, y: yy }, end: { x: PW - MR, y: yy }, thickness: 0.5, color: RULE });

      const checkPage = (need = 80) => {
        if (y - need < 80) {
          drawFooter();
          page = addPage();
          // Cabecera de continuación
          page.drawText('REPORTE DE SALIDA DE EQUIPOS Y HERRAMIENTAS — Continuación', {
            x: ML, y: PH - 34, size: 8.5, font: bold, color: INK,
          });
          page.drawLine({ start: { x: ML, y: PH - 43 }, end: { x: PW - MR, y: PH - 43 }, thickness: 0.5, color: RULE });
          y = PH - 62;
        }
      };

      const drawFooter = () => {
        page.drawLine({ start: { x: ML, y: 46 }, end: { x: PW - MR, y: 46 }, thickness: 0.5, color: RULE });
        page.drawText(
          'E-System TIC Perú S.A.C. · Reporte de Salida de Equipos y Herramientas · Documento Oficial de Control',
          { x: ML, y: 33, size: 7, font: regular, color: MUTED }
        );
        const pg = String(doc.getPageCount());
        page.drawText(pg, { x: PW - MR - regular.widthOfTextAtSize(pg, 7), y: 33, size: 7, font: regular, color: MUTED });
      };

      // ── Encabezado página 1 ──
      // Logo en esquina superior derecha
      if (logoImg) {
        const d = logoImg.scaleToFit(80, 40);
        page.drawImage(logoImg, { x: PW - MR - d.width, y: PH - 46, width: d.width, height: d.height });
      }

      page.drawText('REPORTE DE SALIDA DE EQUIPOS Y HERRAMIENTAS', { x: ML, y, size: 13, font: bold, color: INK });
      y -= 18;
      page.drawText('E-System TIC · Gestión de Logística de Campo', { x: ML, y, size: 8.5, font: regular, color: MUTED });
      y -= 8;
      page.drawLine({ start: { x: ML, y }, end: { x: PW - MR, y }, thickness: 1.5, color: ACCENT });
      y -= 20;

      // Metadatos
      const reqs = grupo ? grupo.reqs : (reqSingle ? [reqSingle] : []);
      const firstReq = reqs[0];
      if (!firstReq) { this.toast.mostrar('Sin datos para generar PDF.', 'error'); return; }

      const emitDate = new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' });
      const C2 = ML + Math.floor(BODY_W / 2) + 8;

      const metaRow = (l1: string, v1: string, l2: string, v2: string) => {
        checkPage(32);
        page.drawText(l1, { x: ML, y, size: 7.5, font: regular, color: MUTED });
        page.drawText(l2, { x: C2, y, size: 7.5, font: regular, color: MUTED });
        y -= 13;
        page.drawText(v1.length > 38 ? v1.slice(0, 35) + '…' : v1, { x: ML, y, size: 9, font: bold, color: INK });
        page.drawText(v2.length > 38 ? v2.slice(0, 35) + '…' : v2, { x: C2, y, size: 9, font: bold, color: INK });
        y -= 18;
      };

      const servicioNombre = grupo ? grupo.servicioNombre : (reqSingle?.servicioNombre ?? '—');
      const proyectoNombre = grupo ? grupo.proyectoNombre : (reqSingle?.proyectoNombre ?? '—');

      metaRow('Proyecto', proyectoNombre, 'Fecha de emisión', emitDate);
      metaRow('Servicio', servicioNombre, 'N° documentos', reqs.map(r => r.id.slice(0, 6).toUpperCase()).join(', '));
      metaRow('Entregado por (Logística)', firstReq.recibidoPorNombre ?? '—', 'Solicitado por', firstReq.solicitanteNombre);
      y -= 4;
      hLine(y); y -= 14;

      page.drawText(
        'NOTA: El técnico que confirme la recepción asume responsabilidad de todos los equipos y herramientas (no consumibles).',
        { x: ML, y, size: 7.5, font: regular, color: MUTED }
      );
      y -= 22;

      // ── Tabla de ítems ──
      page.drawText('DETALLE DE MATERIALES, EQUIPOS Y HERRAMIENTAS', { x: ML, y, size: 9, font: bold, color: INK });
      y -= 14;

      checkPage(ROW_H * 3);
      hLine(y);
      page.drawRectangle({ x: ML, y: y - ROW_H, width: BODY_W, height: ROW_H, color: HDR_BG });
      page.drawText('#',           { x: ML + 4,        y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Descripción', { x: ML + 24,       y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Tipo',        { x: PW - MR - 160, y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Cant.',       { x: PW - MR - 82,  y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Unidad',      { x: PW - MR - 50,  y: ty(y), size: 7.5, font: bold, color: MUTED });
      y -= ROW_H; hLine(y);

      const allItems = reqs.flatMap(r => r.items.filter(it => it.estadoItem !== 'rechazado'));
      let rowNum = 0;
      for (const it of allItems) {
        checkPage(ROW_H + 8);
        rowNum++;
        const nom  = it.nombre.length > 46 ? it.nombre.slice(0, 43) + '…' : it.nombre;
        const espec = it.especificacion?.toLowerCase() ?? '';
        const tipo  = espec.includes('equipo')      ? 'Equipo' :
                      espec.includes('herramienta') ? 'Herramienta' :
                      it.esCompraExterna            ? 'Compra ext.' : 'Material';
        const esNC = tipo === 'Equipo' || tipo === 'Herramienta';
        page.drawText(`${rowNum}`, { x: ML + 4, y: ty(y), size: 8, font: regular, color: MUTED });
        page.drawText(nom,         { x: ML + 24, y: ty(y), size: 8, font: esNC ? bold : regular, color: INK });
        page.drawText(tipo,        { x: PW - MR - 160, y: ty(y), size: 7.5, font: regular, color: esNC ? rgb(0.56, 0.27, 0.87) : MUTED });
        page.drawText(`${it.cantidadAprobada ?? it.cantidad}`, { x: PW - MR - 82, y: ty(y), size: 8, font: bold, color: INK });
        page.drawText(it.unidad,   { x: PW - MR - 50, y: ty(y), size: 7.5, font: regular, color: MUTED });
        y -= ROW_H; hLine(y);
      }
      y -= 16;

      // ── Sección de firmas (SIEMPRE con espacio suficiente, nueva página si falta) ──
      const SIG_NEEDED = 155;
      if (y - SIG_NEEDED < 80) {
        drawFooter();
        page = addPage();
        y = PH - 70;
      }

      // Cajas de firma con borde
      const SIG_BOX_W = Math.floor(BODY_W / 2) - 16;
      const SIG_BOX_H = 90;
      const SIG_Y     = y - SIG_BOX_H;

      // Títulos sobre las cajas
      page.drawText('ENTREGADO POR — LOGÍSTICA', { x: ML, y: y + 6, size: 7, font: bold, color: MUTED });
      page.drawText('RECIBIDO POR — TÉCNICO RESPONSABLE', { x: ML + SIG_BOX_W + 32, y: y + 6, size: 7, font: bold, color: MUTED });

      // Caja izquierda (logística)
      page.drawRectangle({ x: ML, y: SIG_Y, width: SIG_BOX_W, height: SIG_BOX_H, borderColor: RULE, borderWidth: 0.5, color: rgb(0.99, 0.99, 0.99) });
      // Caja derecha (técnico)
      page.drawRectangle({ x: ML + SIG_BOX_W + 32, y: SIG_Y, width: SIG_BOX_W, height: SIG_BOX_H, borderColor: RULE, borderWidth: 0.5, color: rgb(0.99, 0.99, 0.99) });

      // Embeber firma logística (firma_receptor_url = logistics signed via firmar)
      const firmaLog = firstReq.firmaUrl;
      if (firmaLog?.startsWith('data:image')) {
        try {
          const b64  = firmaLog.split(',')[1];
          const imgB = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
          const img  = await doc.embedPng(imgB.buffer as ArrayBuffer);
          const d    = img.scaleToFit(SIG_BOX_W - 8, SIG_BOX_H - 8);
          page.drawImage(img, { x: ML + 4 + (SIG_BOX_W - 8 - d.width) / 2, y: SIG_Y + 4, width: d.width, height: d.height });
        } catch { /* no se pudo embeber firma */ }
      }

      // Embeber firma técnico (firma_entregador_url = tech confirmed via entregar)
      const firmaTec = firstReq.firmaEntregadorUrl;
      if (firmaTec?.startsWith('data:image')) {
        try {
          const b64  = firmaTec.split(',')[1];
          const imgB = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
          const img  = await doc.embedPng(imgB.buffer as ArrayBuffer);
          const d    = img.scaleToFit(SIG_BOX_W - 8, SIG_BOX_H - 8);
          page.drawImage(img, { x: ML + SIG_BOX_W + 32 + 4 + (SIG_BOX_W - 8 - d.width) / 2, y: SIG_Y + 4, width: d.width, height: d.height });
        } catch { /* no se pudo embeber firma */ }
      }

      // Nombres y cargos debajo de las cajas
      const nameY = SIG_Y - 14;
      page.drawText(firstReq.recibidoPorNombre ?? '________________________________', { x: ML, y: nameY, size: 8, font: regular, color: INK });
      page.drawText('Responsable de Logística', { x: ML, y: nameY - 12, size: 7.5, font: regular, color: MUTED });
      page.drawText(firstReq.entregadoPorNombre ?? '________________________________', { x: ML + SIG_BOX_W + 32, y: nameY, size: 8, font: regular, color: INK });
      page.drawText('Técnico / Responsable de Recepción', { x: ML + SIG_BOX_W + 32, y: nameY - 12, size: 7.5, font: regular, color: MUTED });

      drawFooter();

      const bytes = await doc.save();
      const blob  = new Blob([bytes.buffer as ArrayBuffer], { type: 'application/pdf' });
      const url   = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `salida-${proyectoNombre.replace(/\s+/g, '-').slice(0, 20)}-${Date.now()}.pdf`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 3000);
    } catch (err) {
      console.error('Error generando PDF:', err);
      this.toast.mostrar('Error al generar el PDF.', 'error');
    }
  }

  // ─────────────────────────── Canvas helpers ───────────────────────────────

  private _newPad(): PadState {
    return { firmando: false, firma: '', bloqueadoPor: null, timerSecs: 120, timerInterval: null, isDrawing: false };
  }

  private _initModalCanvas(): void {
    const canvas = this.firmaModalCanvasEl?.nativeElement;
    if (!canvas) return;
    const pad = this.padFirma;
    const ctx  = canvas.getContext('2d')!;
    ctx.strokeStyle = '#0f172a';
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';

    const getPos = (e: MouseEvent | Touch) => {
      const r = canvas.getBoundingClientRect();
      return { x: (e.clientX - r.left) * (canvas.width / r.width), y: (e.clientY - r.top) * (canvas.height / r.height) };
    };

    canvas.onmousedown = e => { pad.isDrawing = true; const p = getPos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); };
    canvas.onmousemove = e => { if (!pad.isDrawing) return; const p = getPos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); };
    canvas.onmouseup = canvas.onmouseleave = () => { pad.isDrawing = false; };
    canvas.ontouchstart = e => { e.preventDefault(); pad.isDrawing = true; const p = getPos(e.touches[0]); ctx.beginPath(); ctx.moveTo(p.x, p.y); };
    canvas.ontouchmove  = e => { e.preventDefault(); if (!pad.isDrawing) return; const p = getPos(e.touches[0]); ctx.lineTo(p.x, p.y); ctx.stroke(); };
    canvas.ontouchend   = () => { pad.isDrawing = false; };
  }

  private _clearTimer(pad: PadState): void {
    if (pad.timerInterval) { clearInterval(pad.timerInterval); pad.timerInterval = null; }
  }

  // ── Proveedores sugeridos (revisión) ──
  private readonly _proveedores = [
    { nombre: 'Distribuidora TecnoPlus', estrellas: '★★★★☆', contacto: '01-234-5678' },
    { nombre: 'Materiales Industriales Perú', estrellas: '★★★☆☆', contacto: '01-987-6543' },
    { nombre: 'Soluciones Eléctricas SAC', estrellas: '★★★★★', contacto: '01-555-0101' },
    { nombre: 'InduSupply Corp.', estrellas: '★★★★☆', contacto: '01-333-2244' },
  ];
  getProveedoresSugeridos(it: RequerimientoItem) {
    const seed = it.nombre.charCodeAt(0) % this._proveedores.length;
    const count = (seed % 2) + 2;
    return this._proveedores
      .slice(seed, seed + count)
      .concat(this._proveedores.slice(0, Math.max(0, count - (this._proveedores.length - seed))))
      .slice(0, count);
  }
}

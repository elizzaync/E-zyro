import { Component, OnInit, OnDestroy, AfterViewChecked, ViewChild, ElementRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { environment } from '../../../../../environments/environment';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { webSocket, WebSocketSubject } from 'rxjs/webSocket';
import { Subscription } from 'rxjs';

import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

export interface MiembroEquipo {
  id: string;
  nombre: string;
  apellido: string;
  fotoUrl?: string;
  cargo: string;
  rolProyecto: string;
}

export interface EvidenciaProcedimiento {
  id: string;
  urlCloudinary: string;
  descripcion?: string;
  fechaCaptura: string;
  etapa: 'antes' | 'durante' | 'despues';
}

export interface MensajeChat {
  id?: string;
  contenido: string;
  remitente_id?: string;
  nombre_remitente: string;
  fecha: string | Date;
  destinatario_id?: string | null;
}

export interface Procedimiento {
  id: string;
  nombre: string;
  descripcion?: string;
  orden: number;
  estado: 'pendiente' | 'en_proceso' | 'completado' | 'bloqueado';
  evidencias: EvidenciaProcedimiento[];
}

export interface ItemMaterial {
  id: string;
  requerimientoId: string;
  nombre: string;
  unidad: string;
  cantidad: number;
  estadoReq: 'pendiente' | 'aprobado' | 'rechazado' | 'entregado' | 'anulado';
}

export interface ServicioDetalle {
  id: string;
  proyectoId: string;
  cliente: string;
  tipoServicio: string;
  ubicacion: string;
  fechaStr: string;
  horaStr: string;
  descripcion: string;
  estado: 'Pendiente' | 'En_Proceso' | 'Completado' | 'Cancelado';
  progreso: number;
  equipo: MiembroEquipo[];
  procedimientos: Procedimiento[];
  materialesAsignados: ItemMaterial[];
  materialesSolicitados: ItemMaterial[];
}

@Component({
  selector: 'app-operaciones-detalle',
  standalone: true,
  imports: [CommonModule, RouterModule, FormsModule, SpinnerComponent],
  templateUrl: './operaciones-detalle.component.html',
  styleUrls: ['./operaciones-detalle.component.css']
})
export class OperacionesDetalleComponent implements OnInit, OnDestroy, AfterViewChecked {
  private route     = inject(ActivatedRoute);
  private router    = inject(Router);
  private location  = inject(Location);
  private sanitizer = inject(DomSanitizer);
  private svc       = inject(OperacionesService);

  @ViewChild('chatScroll') private chatScrollEl!: ElementRef<HTMLDivElement>;

  servicioId: string | null = null;
  servicio: ServicioDetalle | null = null;
  cargando = true;
  error    = false;
  errorMsg = '';

  // ── Modal 1: Evidencia por etapas ─────────────────────────
  showModalEvidencia   = false;
  procedimientoActivo: Procedimiento | null = null;
  subiendoEvidencia    = false;
  errorEvidencia       = '';

  etapasLista: ('antes' | 'durante' | 'despues')[] = ['antes', 'durante', 'despues'];
  etapaActiva: 'antes' | 'durante' | 'despues' = 'antes';

  slotsEvidencia: {
    antes:   { file: File | null; preview: string | null };
    durante: { file: File | null; preview: string | null };
    despues: { file: File | null; preview: string | null };
  } = {
    antes:   { file: null, preview: null },
    durante: { file: null, preview: null },
    despues: { file: null, preview: null }
  };

  // ── Modal 2: Editar Material ───────────────────────────────
  showModalEditarMat = false;
  materialActivo: ItemMaterial | null = null;
  editNombre   = '';
  editCantidad = 1;
  guardandoMat = false;

  // ── Modal 3: Solicitar Material ────────────────────────────
  showModalSolicitar  = false;
  busquedaMaterial    = '';
  resultadosBusqueda: Array<{ id: string; nombre: string; unidad: string; stock: number }> = [];
  materialElegido: { id: string; nombre: string; unidad: string; stock: number } | null = null;
  cantidadSolicitar   = 1;
  buscandoMaterial    = false;
  solicitando         = false;

  // ── Modal 4: Pre-Informe PDF ───────────────────────────────
  showModalPDF  = false;
  pdfCargando   = false;
  pdfBlobUrl    = '';

  // ── Chat en tiempo real ────────────────────────────────────
  chatMensajes: MensajeChat[]     = [];
  nuevoMensajeChat                = '';
  chatDestinatario: string | null = null;
  soyJefeOperaciones              = false;

  private chatSocket$: WebSocketSubject<unknown> | null = null;
  private chatSub?: Subscription;
  private _scrollPending = false;

  _nombreUsuario = 'Yo';
  _usuarioId: string | null = null;

  get _idUsuario(): string {
    const stored = localStorage.getItem('ezyro_user');
    if (stored) {
      try { return JSON.parse(stored)?.id ?? ''; } catch { /* ignore */ }
    }
    return '';
  }

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id');
    const stored = localStorage.getItem('ezyro_user');
    if (stored) {
      try {
        const u = JSON.parse(stored);
        if (u?.nombre_completo) this._nombreUsuario = u.nombre_completo;
        if (u?.id)              this._usuarioId     = u.id;
        if (u?.rol === 'jefe_operaciones' || u?.rol === 'administrador') {
          this.soyJefeOperaciones = true;
        }
      } catch { /* ignore */ }
    }
    this.cargarDetalle();
  }

  ngAfterViewChecked(): void {
    if (this._scrollPending && this.chatScrollEl?.nativeElement) {
      const el = this.chatScrollEl.nativeElement;
      el.scrollTop = el.scrollHeight;
      this._scrollPending = false;
    }
  }

  ngOnDestroy(): void {
    if (this.pdfBlobUrl) URL.revokeObjectURL(this.pdfBlobUrl);
    this.chatSub?.unsubscribe();
    this.chatSocket$?.complete();
  }

  volver(): void { this.location.back(); }

  // ==========================================================
  // CARGA DE DATOS
  // ==========================================================
  cargarDetalle(): void {
    this.cargando = true;
    this.error    = false;
    if (!this.servicioId) {
      this.error    = true;
      this.errorMsg = 'ID de servicio inválido.';
      this.cargando = false;
      return;
    }
    this.svc.getDetalleServicio(this.servicioId).subscribe({
      next: (raw: any) => {
        this.servicio = this._mapServicio(raw);
        this.cargando = false;
        this._conectarChat(this.servicio.proyectoId);
        this._checkDeepLink();
      },
      error: (err: any) => {
        this.error    = true;
        this.errorMsg = err?.error?.detail ?? 'No se pudo cargar el detalle del servicio.';
        this.cargando = false;
      }
    });
  }

  private _mapMensaje(m: any): MensajeChat {
    return {
      id:               m.id,
      contenido:        m.contenido ?? '',
      remitente_id:     m.remitente_id,
      nombre_remitente: m.remitente_nombre ?? m.nombre_remitente ?? 'Equipo',
      fecha:            m.fecha ?? new Date().toISOString(),
      destinatario_id:  m.destinatario_id ?? null
    };
  }

  private _checkDeepLink(): void {
    const tareaId = this.route.snapshot.queryParamMap.get('abrirTareaId');
    if (!tareaId || !this.servicio) return;
    const tarea = this.servicio.procedimientos.find(p => p.id === tareaId);
    if (!tarea) return;
    this.router.navigate([], {
      queryParams: { abrirTareaId: null },
      queryParamsHandling: 'merge',
      replaceUrl: true
    });
    setTimeout(() => this.abrirModalEvidencia(tarea), 50);
  }

  private _conectarChat(projectId: string): void {
    const token  = localStorage.getItem('ezyro_token') ?? '';
    const wsBase = environment.apiUrl.replace(/^http/, 'ws');
    this.chatSub?.unsubscribe();
    this.chatSocket$?.complete();

    this.chatSocket$ = webSocket<unknown>(
      `${wsBase}/ws/chat/${projectId}?token=${token}`
    );

    this.chatSub = this.chatSocket$.subscribe({
      next: (msg: any) => {
        if (msg.tipo === 'historial') {
          this.chatMensajes = (msg.mensajes ?? []).map((m: any) => this._mapMensaje(m));
          this._scrollPending = true;
          return;
        }
        if (msg.tipo === 'error') return;
        this.chatMensajes.push(this._mapMensaje(msg));
        this._scrollPending = true;
      },
      error: () => { /* conexión cerrada */ }
    });
  }

  enviarMensajeChat(): void {
    const texto = this.nuevoMensajeChat.trim();
    if (!texto || !this.chatSocket$) return;
    this.chatSocket$.next({ contenido: texto, destinatario_id: this.chatDestinatario ?? null });
    this.nuevoMensajeChat = '';
    // El backend hace broadcast al remitente también, por lo que el mensaje llega por el WS
  }

  getChatInitiales(nombre: string): string {
    const parts = nombre.trim().split(/\s+/).filter(Boolean);
    if (parts.length >= 2) return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    return (parts[0]?.[0] ?? '?').toUpperCase();
  }

  getChatAvatarColor(id?: string): string {
    const palette = ['#91d337', '#3b82f6', '#8b5cf6', '#f59e0b', '#06b6d4', '#ec4899', '#ef4444', '#14b8a6'];
    if (!id) return '#334155';
    let h = 0;
    for (let i = 0; i < id.length; i++) h = id.charCodeAt(i) + ((h << 5) - h);
    return palette[Math.abs(h) % palette.length];
  }

  private _mapServicio(raw: any): ServicioDetalle {
    return {
      id:           raw.id,
      proyectoId:   raw.proyecto_id,
      cliente:      raw.cliente,
      tipoServicio: raw.tipo_servicio,
      ubicacion:    raw.ubicacion,
      fechaStr:     raw.fecha_str,
      horaStr:      raw.hora_str,
      descripcion:  raw.descripcion,
      estado:       raw.estado,
      progreso:     raw.progreso,
      equipo: (raw.equipo ?? []).map((m: any) => ({
        id:          m.id,
        nombre:      m.nombre,
        apellido:    m.apellido,
        fotoUrl:     m.foto_url,
        cargo:       m.cargo,
        rolProyecto: m.rol_proyecto ?? 'Técnico'
      })),
      procedimientos: (raw.procedimientos ?? []).map((p: any) => ({
        id:          p.id,
        nombre:      p.nombre,
        descripcion: p.descripcion,
        orden:       p.orden,
        estado:      p.estado,
        evidencias:  (p.evidencias ?? []).map((e: any) => ({
          id:            e.id,
          urlCloudinary: e.url_cloudinary,
          descripcion:   e.descripcion,
          fechaCaptura:  e.fecha_captura,
          etapa:         (e.etapa as 'antes' | 'durante' | 'despues') ?? 'antes'
        }))
      })),
      materialesAsignados:   this._mapMateriales(raw.materiales_asignados),
      materialesSolicitados: this._mapMateriales(raw.materiales_solicitados),
    };
  }

  private _mapMateriales(list: any[]): ItemMaterial[] {
    return (list ?? []).map((m: any) => ({
      id:              m.id,
      requerimientoId: m.requerimiento_id,
      nombre:          m.nombre,
      unidad:          m.unidad,
      cantidad:        m.cantidad,
      estadoReq:       m.estado_req
    }));
  }

  // ==========================================================
  // ESTADO DEL SERVICIO
  // ==========================================================
  cambiarEstado(estado: ServicioDetalle['estado']): void {
    if (!this.servicio) return;
    const prev = this.servicio.estado;
    this.servicio.estado = estado;
    this.svc.actualizarEstado(this.servicio.id, estado).subscribe({
      error: () => { this.servicio!.estado = prev; }
    });
  }

  // ==========================================================
  // PROCEDIMIENTOS
  // ==========================================================
  toggleProcedimiento(proc: Procedimiento): void {
    const nuevoEstado: Procedimiento['estado'] =
      proc.estado === 'completado' ? 'pendiente' : 'completado';
    const prevEstado = proc.estado;
    proc.estado = nuevoEstado;
    this.recalcularProgreso();
    this.svc.toggleProcedimiento(proc.id, nuevoEstado).subscribe({
      error: () => {
        proc.estado = prevEstado;
        this.recalcularProgreso();
      }
    });
  }

  recalcularProgreso(): void {
    if (!this.servicio?.procedimientos.length) return;
    const total     = this.servicio.procedimientos.length;
    const completos = this.servicio.procedimientos.filter(p => p.estado === 'completado').length;
    this.servicio.progreso = Math.round((completos / total) * 100);
  }

  get todasCompletadas(): boolean {
    return this.servicio?.progreso === 100;
  }

  get todasLasEvidencias(): EvidenciaProcedimiento[] {
    if (!this.servicio) return [];
    return this.servicio.procedimientos.flatMap(p => p.evidencias);
  }

  getIniciales(m: MiembroEquipo): string {
    return (m.nombre[0] + m.apellido[0]).toUpperCase();
  }

  getColorAvatar(i: number): string {
    const c = ['#91d337', '#3b82f6', '#8b5cf6', '#f59e0b', '#06b6d4', '#ec4899'];
    return c[i % c.length];
  }

  puedeEditar(mat: ItemMaterial): boolean {
    return mat.estadoReq !== 'entregado' && mat.estadoReq !== 'aprobado';
  }

  // ==========================================================
  // MODAL 1 — EVIDENCIA (slots por etapa)
  // ==========================================================
  getEvExistente(etapa: 'antes' | 'durante' | 'despues'): EvidenciaProcedimiento | undefined {
    return this.procedimientoActivo?.evidencias.find(e => e.etapa === etapa);
  }

  abrirModalEvidencia(proc: Procedimiento): void {
    this.procedimientoActivo  = proc;
    this.slotsEvidencia       = {
      antes:   { file: null, preview: null },
      durante: { file: null, preview: null },
      despues: { file: null, preview: null }
    };
    this.etapaActiva        = 'antes';
    this.errorEvidencia     = '';
    this.showModalEvidencia   = true;
  }

  cerrarModalEvidencia(): void {
    this.showModalEvidencia  = false;
    this.procedimientoActivo = null;
  }

  onFileSlotSelected(event: Event, etapa: 'antes' | 'durante' | 'despues'): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    this.slotsEvidencia[etapa].file    = file;
    this.slotsEvidencia[etapa].preview = null;
    if (file.type.startsWith('image/')) {
      const reader = new FileReader();
      reader.onload = e => (this.slotsEvidencia[etapa].preview = e.target?.result as string);
      reader.readAsDataURL(file);
    }
  }

  guardarEvidenciaPorEtapa(etapa: 'antes' | 'durante' | 'despues'): void {
    const slot = this.slotsEvidencia[etapa];
    if (!slot.file || !this.procedimientoActivo) return;
    this.subiendoEvidencia = true;
    this.errorEvidencia    = '';

    const formData = new FormData();
    formData.append('archivo', slot.file);
    formData.append('etapa',   etapa);

    this.svc.subirEvidencia(this.procedimientoActivo.id, formData).subscribe({
      next: (res: any) => {
        const ev: EvidenciaProcedimiento = {
          id:            res.evidencia_id,
          urlCloudinary: res.url,
          fechaCaptura:  new Date().toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' }),
          etapa
        };
        this.procedimientoActivo!.evidencias.push(ev);
        this.procedimientoActivo!.estado = 'completado';
        this.recalcularProgreso();
        this.slotsEvidencia[etapa] = { file: null, preview: null };
        this.subiendoEvidencia     = false;
      },
      error: (err: any) => {
        this.subiendoEvidencia = false;
        this.errorEvidencia    = err?.error?.detail ?? 'Error al subir la evidencia.';
      }
    });
  }

  // ==========================================================
  // MODAL 2 — EDITAR MATERIAL
  // ==========================================================
  abrirModalEditarMat(mat: ItemMaterial): void {
    if (!this.puedeEditar(mat)) return;
    this.materialActivo     = mat;
    this.editNombre         = mat.nombre;
    this.editCantidad       = mat.cantidad;
    this.showModalEditarMat = true;
  }

  cerrarModalEditarMat(): void {
    this.showModalEditarMat = false;
    this.materialActivo     = null;
  }

  guardarEditarMat(): void {
    if (!this.materialActivo || this.editCantidad < 1) return;
    this.guardandoMat = true;
    this.svc.actualizarRequerimientoDetalle(this.materialActivo.id, {
      cantidad: this.editCantidad
    }).subscribe({
      next: () => {
        this.materialActivo!.cantidad = this.editCantidad;
        this.guardandoMat = false;
        this.cerrarModalEditarMat();
      },
      error: () => { this.guardandoMat = false; }
    });
  }

  // ==========================================================
  // MODAL 3 — SOLICITAR MATERIAL
  // ==========================================================
  abrirModalSolicitar(): void {
    this.busquedaMaterial   = '';
    this.resultadosBusqueda = [];
    this.materialElegido    = null;
    this.cantidadSolicitar  = 1;
    this.showModalSolicitar = true;
  }

  cerrarModalSolicitar(): void { this.showModalSolicitar = false; }

  buscarMateriales(): void {
    const q = this.busquedaMaterial.trim();
    if (q.length < 2) { this.resultadosBusqueda = []; return; }
    this.buscandoMaterial = true;
    this.svc.buscarMateriales(q).subscribe({
      next: r => { this.resultadosBusqueda = r; this.buscandoMaterial = false; },
      error: () => { this.buscandoMaterial = false; }
    });
  }

  elegirMaterial(mat: { id: string; nombre: string; unidad: string; stock: number }): void {
    this.materialElegido    = mat;
    this.busquedaMaterial   = mat.nombre;
    this.resultadosBusqueda = [];
  }

  solicitarMaterial(): void {
    if (!this.materialElegido || !this.servicio || this.solicitando) return;
    this.solicitando = true;
    this.svc.solicitarMaterial(this.servicio.id, {
      material_id: this.materialElegido.id,
      cantidad:    this.cantidadSolicitar
    }).subscribe({
      next: (res: any) => {
        this.servicio!.materialesSolicitados.push({
          id:              res.detalle_id,
          requerimientoId: res.requerimiento_id,
          nombre:          this.materialElegido!.nombre,
          unidad:          this.materialElegido!.unidad,
          cantidad:        this.cantidadSolicitar,
          estadoReq:       'pendiente'
        });
        this.solicitando = false;
        this.cerrarModalSolicitar();
      },
      error: () => { this.solicitando = false; }
    });
  }

  // ==========================================================
  // MODAL 4 — PRE-INFORME PDF  (pdf-lib)
  // ==========================================================
  async abrirModalPreInforme(): Promise<void> {
    this.showModalPDF = true;
    this.pdfCargando  = true;
    if (this.pdfBlobUrl) { URL.revokeObjectURL(this.pdfBlobUrl); this.pdfBlobUrl = ''; }

    try {
      const { PDFDocument, rgb, StandardFonts } = await import('pdf-lib');
      const doc     = await PDFDocument.create();
      const regular = await doc.embedFont(StandardFonts.Helvetica);
      const bold    = await doc.embedFont(StandardFonts.HelveticaBold);
      const page    = doc.addPage([595, 842]);
      const W       = page.getWidth();
      const H       = page.getHeight();
      const GREEN   = rgb(0.357, 0.827, 0.216);
      const DARK    = rgb(0.06, 0.09, 0.13);
      const MUTED   = rgb(0.40, 0.45, 0.55);
      const WHITE   = rgb(1, 1, 1);

      page.drawRectangle({ x: 0, y: H - 64, width: W, height: 64, color: GREEN });
      page.drawText('PRE-INFORME DE SERVICIO', { x: 40, y: H - 35, size: 16, font: bold, color: WHITE });
      page.drawText(
        `Generado: ${new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' })}`,
        { x: 40, y: H - 54, size: 8, font: regular, color: rgb(0.92, 0.97, 0.87) }
      );

      let y = H - 84;

      const drawSection = (title: string) => {
        y -= 6;
        page.drawRectangle({ x: 36, y: y - 2, width: W - 72, height: 20, color: rgb(0.93, 0.97, 0.90), borderColor: GREEN, borderWidth: 0.5 });
        page.drawText(title, { x: 40, y: y + 3, size: 9, font: bold, color: GREEN });
        y -= 24;
      };

      const drawRow = (label: string, value: string) => {
        page.drawText(label, { x: 40,  y, size: 9, font: bold,    color: DARK });
        page.drawText(value, { x: 165, y, size: 9, font: regular, color: MUTED });
        y -= 16;
      };

      if (this.servicio) {
        drawSection('INFORMACIÓN DEL SERVICIO');
        drawRow('Cliente:',          this.servicio.cliente);
        drawRow('Tipo de Servicio:', this.servicio.tipoServicio);
        drawRow('Ubicación:',        this.servicio.ubicacion);
        drawRow('Fecha / Hora:',     `${this.servicio.fechaStr}  ${this.servicio.horaStr}`);
        drawRow('Estado actual:',    this.servicio.estado.replace('_', ' '));
        drawRow('Progreso:',         `${this.servicio.progreso}%`);
        y -= 4;

        drawSection('DESCRIPCIÓN DEL PROBLEMA');
        const words = this.servicio.descripcion.split(' ');
        let line = '';
        for (const w of words) {
          if (regular.widthOfTextAtSize(line + w + ' ', 9) < W - 80) {
            line += w + ' ';
          } else {
            page.drawText(line.trim(), { x: 40, y, size: 9, font: regular, color: DARK });
            y -= 14; line = w + ' ';
          }
        }
        if (line.trim()) { page.drawText(line.trim(), { x: 40, y, size: 9, font: regular, color: DARK }); y -= 14; }
        y -= 4;

        drawSection('TAREAS DEL SERVICIO');
        for (const p of this.servicio.procedimientos) {
          const done = p.estado === 'completado';
          page.drawText(done ? '✓' : '○', { x: 42, y, size: 10, font: done ? bold : regular, color: done ? GREEN : MUTED });
          page.drawText(`${p.orden}. ${p.nombre}`, { x: 58, y, size: 9, font: done ? bold : regular, color: done ? DARK : MUTED });
          if (p.evidencias.length) {
            page.drawText(`[${p.evidencias.length} evidencia(s)]`, { x: W - 110, y, size: 8, font: regular, color: GREEN });
          }
          y -= 15;
        }
        y -= 4;

        drawSection('MATERIALES ASIGNADOS');
        for (const m of this.servicio.materialesAsignados) {
          page.drawText(`• ${m.nombre}`, { x: 42, y, size: 9, font: regular, color: DARK });
          page.drawText(`x${m.cantidad}`, { x: W - 140, y, size: 9, font: bold, color: MUTED });
          page.drawText(m.estadoReq.toUpperCase(), { x: W - 100, y, size: 8, font: bold, color: m.estadoReq === 'entregado' ? GREEN : MUTED });
          y -= 15;
        }
        y -= 4;

        drawSection('EQUIPO DE TRABAJO');
        for (const m of this.servicio.equipo) {
          page.drawText(`• ${m.nombre} ${m.apellido}`, { x: 42, y, size: 9, font: bold, color: DARK });
          page.drawText(`${m.cargo}  ·  ${m.rolProyecto}`, { x: 165, y, size: 8, font: regular, color: MUTED });
          y -= 15;
        }

        page.drawLine({ start: { x: 40, y: 44 }, end: { x: W - 40, y: 44 }, thickness: 0.4, color: rgb(0.8, 0.8, 0.8) });
        page.drawText('E-System TIC — Panel de Gestión Técnica', { x: 40, y: 30, size: 8, font: regular, color: MUTED });
        page.drawText('Pre-informe preliminar · sujeto a revisión y firma final del cliente.', { x: 40, y: 18, size: 7, font: regular, color: MUTED });
      }

      const bytes = await doc.save();
      const blob  = new Blob([bytes.buffer as ArrayBuffer], { type: 'application/pdf' });
      this.pdfBlobUrl = URL.createObjectURL(blob);
    } catch (err) {
      console.error('Error generando PDF:', err);
    }
    this.pdfCargando = false;
  }

  get safePdfUrl(): SafeResourceUrl {
    return this.sanitizer.bypassSecurityTrustResourceUrl(this.pdfBlobUrl);
  }

  cerrarModalPDF(): void { this.showModalPDF = false; }

  descargarPDF(): void {
    if (!this.pdfBlobUrl || !this.servicio) return;
    const a    = document.createElement('a');
    a.href     = this.pdfBlobUrl;
    a.download = `pre-informe-${this.servicio.cliente.replace(/\s+/g, '-')}-${Date.now()}.pdf`;
    a.click();
  }

  // ==========================================================
  // INFORME TOTAL
  // ==========================================================
  async finalizarServicio(): Promise<void> {
    if (!this.todasCompletadas || !this.servicio) return;
    this.svc.actualizarEstado(this.servicio.id, 'Completado').subscribe({
      next: () => { this.servicio!.estado = 'Completado'; }
    });
    await this.abrirModalPreInforme();
  }
}

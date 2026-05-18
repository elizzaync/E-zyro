import { Component, OnInit, OnDestroy, AfterViewChecked, ViewChild, ElementRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { environment } from '../../../../../environments/environment';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { webSocket, WebSocketSubject } from 'rxjs/webSocket';
import { Subscription, forkJoin } from 'rxjs';

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
// ── Borrador de Materiales (Carrito) ───────────────────────
  materialesBorrador: Array<{
    material_id: string | null;
    nombre: string;
    unidad: string;
    cantidad: number;
    esNuevo: boolean;
    agregadoPor: string;
    especificacion?: string;
  }> = [];
  consensoEquipo = false;
  enviandoLote   = false;
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

  // ── Modal 3: Compra Externa (pestaña dual) ─────────────────
  modoCompraExterna    = false;
  manualNombre         = '';
  manualCantidad       = 1;
  manualUnidad         = 'Unidades';
  manualEspecificacion = '';

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
    document.body.style.overflow = '';
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
    this.busquedaMaterial    = '';
    this.resultadosBusqueda  = [];
    this.materialElegido     = null;
    this.cantidadSolicitar   = 1;
    this.modoCompraExterna   = false;
    this.manualNombre        = '';
    this.manualCantidad      = 1;
    this.manualUnidad        = 'Unidades';
    this.manualEspecificacion = '';
    this.showModalSolicitar  = true;
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
    if (!this.materialElegido || !this.servicio) return;

    this.materialesBorrador.push({
      material_id: this.materialElegido.id,
      nombre:      this.materialElegido.nombre,
      unidad:      this.materialElegido.unidad,
      cantidad:    this.cantidadSolicitar,
      esNuevo:     false,
      agregadoPor: this._nombreUsuario
    });
    this.materialElegido    = null;
    this.busquedaMaterial   = '';
    this.resultadosBusqueda = [];
    this.cantidadSolicitar  = 1;
  }

  solicitarMaterialManual(): void {
    if (!this.manualNombre.trim() || !this.manualEspecificacion.trim() || this.manualCantidad < 1) return;

    this.materialesBorrador.push({
      material_id:    null,
      nombre:         this.manualNombre.trim(),
      unidad:         this.manualUnidad,
      cantidad:       this.manualCantidad,
      esNuevo:        true,
      agregadoPor:    this._nombreUsuario,
      especificacion: this.manualEspecificacion.trim()
    });

    this.manualNombre        = '';
    this.manualCantidad      = 1;
    this.manualUnidad        = 'Unidades';
    this.manualEspecificacion = '';
  }

  // Nuevo: Quita un ítem de la lista temporal
  removerDelBorrador(index: number): void {
    this.materialesBorrador.splice(index, 1);
    if (this.materialesBorrador.length === 0) {
      this.consensoEquipo = false;
    }
  }

  // Nuevo: Envía todos los materiales de golpe a la BD
  enviarSolicitudLote(): void {
    if (!this.servicio || this.materialesBorrador.length === 0) return;
    this.enviandoLote = true;

    // Preparamos todas las peticiones a la API
    const peticiones = this.materialesBorrador.map(item =>
      this.svc.solicitarMaterial(this.servicio!.id, {
        material_id:    item.material_id,
        cantidad:       item.cantidad,
        nombre:         item.nombre,
        unidad:         item.unidad,
        especificacion: item.especificacion
      })
    );

    // forkJoin ejecuta todas las peticiones en paralelo
    forkJoin(peticiones).subscribe({
      next: (respuestas: any[]) => {
        // Por cada respuesta, pasamos el ítem del borrador a la lista oficial
        respuestas.forEach((res, index) => {
          const item = this.materialesBorrador[index];
          this.servicio!.materialesSolicitados.push({
            id:              res.detalle_id,
            requerimientoId: res.requerimiento_id,
            nombre:          item.nombre,
            unidad:          item.unidad,
            cantidad:        item.cantidad,
            estadoReq:       'pendiente'
          });
        });

        // Limpiamos el carrito
        this.materialesBorrador = [];
        this.consensoEquipo     = false;
        this.enviandoLote       = false;
      },
      error: () => {
        this.enviandoLote = false;
        alert('Hubo un error de conexión al enviar el lote a Logística.');
      }
    });
  }
  // ==========================================================
  // MODAL 4 — PRE-INFORME PDF  (pdf-lib)
  // ==========================================================
  async abrirModalPreInforme(): Promise<void> {
    this.showModalPDF = true;
    this.pdfCargando  = true;
    document.body.style.overflow = 'hidden';
    if (this.pdfBlobUrl) { URL.revokeObjectURL(this.pdfBlobUrl); this.pdfBlobUrl = ''; }

    try {
      const { PDFDocument, rgb, StandardFonts } = await import('pdf-lib');

      // ── Descarga segura de imagen (Cloudinary) ───────────────────────────
      const descargarImagenBytes = async (url: string): Promise<ArrayBuffer | null> => {
        try {
          const res = await fetch(url);
          if (!res.ok) return null;
          return await res.arrayBuffer();
        } catch { return null; }
      };

      // ── Paleta corporativa minimalista ────────────────────────────────────
      const PW = 595, PH = 842, ML = 44, MR = 44;
      const BODY_W = PW - ML - MR; // 507 px útiles

      const INK    = rgb(0.09, 0.12, 0.18);    // #171f2e  texto principal
      const MUTED  = rgb(0.40, 0.46, 0.56);    // #667690  texto secundario
      const RULE   = rgb(0.88, 0.90, 0.93);    // #e2e6ed  líneas/bordes sutiles
      const HDR_BG = rgb(0.96, 0.97, 0.98);    // #f5f7f8  fondo cab. tabla
      const ACCENT = rgb(0.569, 0.827, 0.216); // #91d337  verde marca (solo acentos)

      const doc     = await PDFDocument.create();
      const regular = await doc.embedFont(StandardFonts.Helvetica);
      const bold    = await doc.embedFont(StandardFonts.HelveticaBold);

      let page = doc.addPage([PW, PH]);
      let y    = 0;

      // ── Pie de página institucional ──────────────────────────────────────
      const drawFooter = () => {
        page.drawLine({
          start: { x: ML, y: 46 }, end: { x: PW - MR, y: 46 },
          thickness: 0.5, color: RULE
        });
        page.drawText(
          'E-System TIC Perú S.A.C. — Documento Técnico Confidencial · Sujeto a Control de Gestión',
          { x: ML, y: 33, size: 7, font: regular, color: MUTED }
        );
        const pg = `${doc.getPageCount()}`;
        page.drawText(pg, {
          x: PW - MR - regular.widthOfTextAtSize(pg, 7),
          y: 33, size: 7, font: regular, color: MUTED
        });
      };

      // ── Cabecera de primera página (tipografía limpia, sin rectángulos) ──
      const drawFirstHeader = () => {
        page.drawText('INFORME TÉCNICO DE CONFORMIDAD DE SERVICIO', {
          x: ML, y: PH - 42, size: 14, font: bold, color: INK
        });
        page.drawText('E-System TIC  ·  Gestión de Operaciones de Campo', {
          x: ML, y: PH - 59, size: 8.5, font: regular, color: MUTED
        });
        // Línea verde de identidad de marca — único uso del color ACCENT en cabecera
        page.drawLine({
          start: { x: ML, y: PH - 67 }, end: { x: PW - MR, y: PH - 67 },
          thickness: 1.5, color: ACCENT
        });
        y = PH - 88;
      };

      // ── Cabecera de página de continuación ───────────────────────────────
      const drawContinuationHeader = () => {
        page.drawText('INFORME TÉCNICO DE CONFORMIDAD DE SERVICIO — CONT.', {
          x: ML, y: PH - 34, size: 8.5, font: bold, color: INK
        });
        page.drawLine({
          start: { x: ML, y: PH - 43 }, end: { x: PW - MR, y: PH - 43 },
          thickness: 0.5, color: RULE
        });
        y = PH - 62;
      };

      // ── Auto-paginación (umbral estricto de 90 px) ───────────────────────
      const checkPage = (need = 90) => {
        if (y - need < 60) {
          drawFooter();
          page = doc.addPage([PW, PH]);
          drawContinuationHeader();
        }
      };

      // ── Separador de sección (label muted + regla sutil) ─────────────────
      const drawSection = (title: string) => {
        checkPage(50);
        y -= 14;
        page.drawText(title.toUpperCase(), {
          x: ML, y, size: 7.5, font: bold, color: MUTED
        });
        y -= 7;
        page.drawLine({
          start: { x: ML, y }, end: { x: PW - MR, y },
          thickness: 0.5, color: RULE
        });
        y -= 14;
      };

      // ── Regla horizontal completa en coordenada y actual ─────────────────
      const hRule = () => {
        page.drawLine({
          start: { x: ML, y }, end: { x: PW - MR, y },
          thickness: 0.5, color: RULE
        });
      };

      // ── Word-wrap seguro con checkPage automático ─────────────────────────
      const drawWrapped = (text: string, x0: number, maxW: number, sz: number, fnt: any, clr: any) => {
        const words = (text || '').split(' ');
        let line = '';
        for (const w of words) {
          if (fnt.widthOfTextAtSize(line + w + ' ', sz) < maxW) {
            line += w + ' ';
          } else {
            if (line.trim()) {
              checkPage(sz + 6);
              page.drawText(line.trim(), { x: x0, y, size: sz, font: fnt, color: clr });
              y -= sz + 6;
            }
            line = w + ' ';
          }
        }
        if (line.trim()) {
          checkPage(sz + 6);
          page.drawText(line.trim(), { x: x0, y, size: sz, font: fnt, color: clr });
          y -= sz + 6;
        }
      };

      // ════════════════════════════════════════════════════════════════════
      // RENDER
      // ════════════════════════════════════════════════════════════════════
      drawFirstHeader();

      if (!this.servicio) throw new Error('Sin datos.');
      const s = this.servicio;

      const emitDate = new Date().toLocaleDateString('es-PE', {
        day: '2-digit', month: 'long', year: 'numeric'
      });
      const otLabel = `OT-${s.id.slice(0, 8).toUpperCase()}`;

      // ── Bloque de metadatos en dos columnas alineadas ────────────────────
      const C1 = ML;
      const C2 = ML + Math.floor(BODY_W / 2) + 8;

      const metaRow = (lbl1: string, val1: string, lbl2: string, val2: string) => {
        checkPage(30);
        page.drawText(lbl1, { x: C1, y,      size: 7.5, font: regular, color: MUTED });
        page.drawText(lbl2, { x: C2, y,      size: 7.5, font: regular, color: MUTED });
        y -= 12;
        const v1 = val1.length > 38 ? val1.slice(0, 36) + '…' : val1;
        const v2 = val2.length > 38 ? val2.slice(0, 36) + '…' : val2;
        page.drawText(v1, { x: C1, y, size: 9, font: bold, color: INK });
        page.drawText(v2, { x: C2, y, size: 9, font: bold, color: INK });
        y -= 19;
      };

      metaRow('Orden de Trabajo',  otLabel,                        'Fecha de Emisión',    emitDate);
      metaRow('Cliente',           s.cliente,                      'Hora Programada',     s.horaStr  || '—');
      metaRow('Tipo de Servicio',  s.tipoServicio,                 'Estado del Servicio', s.estado.replace(/_/g, ' '));
      metaRow('Ubicación',         s.ubicacion,                    'Fecha del Servicio',  s.fechaStr || '—');

      // Técnico responsable del informe (cuenta logueada)
      checkPage(30);
      page.drawText('Técnico Responsable del Informe', { x: C1, y, size: 7.5, font: regular, color: MUTED });
      y -= 12;
      page.drawText(this._nombreUsuario, { x: C1, y, size: 9, font: bold, color: INK });
      y -= 19;

      y -= 4;
      hRule();
      y -= 13;

      // Indicador de progreso (texto plano, sin barra de color)
      const progStr = `Progreso de Ejecución: ${s.progreso}%${s.progreso === 100 ? '  —  COMPLETADO' : ''}`;
      page.drawText(progStr, {
        x: ML, y, size: 8.5, font: bold,
        color: s.progreso === 100 ? ACCENT : INK
      });
      y -= 22;

      // ── 1. Descripción del problema ──────────────────────────────────────
      drawSection('1. Descripción del Problema Técnico');
      drawWrapped(s.descripcion || 'Sin descripción.', ML, BODY_W, 9, regular, INK);
      y -= 4;

      // ── 2. Procedimientos y estado de ejecución ──────────────────────────
      drawSection('2. Procedimientos y Estado de Ejecución');

      // Altura de fila fija — garantiza que rect, texto y línea comparten los mismos límites
      const ROW_H = 20;
      // Baseline del texto a 6 px del borde inferior del row: centrado visual para font ≤ 8 pt
      const ty = (topY: number) => topY - ROW_H + 6;

      // Borde superior de la caja de tabla
      checkPage(ROW_H * 3);
      page.drawLine({ start: { x: ML, y }, end: { x: ML + BODY_W, y }, thickness: 0.5, color: RULE });
      // Fondo de cabecera — mismo x y width que las líneas
      page.drawRectangle({ x: ML, y: y - ROW_H, width: BODY_W, height: ROW_H, color: HDR_BG });
      page.drawText('N°',           { x: ML + 4,        y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Procedimiento',{ x: ML + 28,       y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Estado',       { x: PW - MR - 106, y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Evid.',        { x: PW - MR - 22,  y: ty(y), size: 7.5, font: bold, color: MUTED });
      y -= ROW_H;
      // Borde inferior de cabecera / divisor de primera fila
      page.drawLine({ start: { x: ML, y }, end: { x: ML + BODY_W, y }, thickness: 0.5, color: RULE });

      for (const p of s.procedimientos) {
        const done = p.estado === 'completado';
        checkPage(p.descripcion ? ROW_H * 3 : ROW_H + 5);

        page.drawText(`${p.orden}`, { x: ML + 4,  y: ty(y), size: 8, font: regular, color: MUTED });
        const nomT = p.nombre.length > 58 ? p.nombre.slice(0, 55) + '…' : p.nombre;
        page.drawText(nomT, { x: ML + 28, y: ty(y), size: 8, font: done ? bold : regular, color: done ? INK : MUTED });

        const stLabel = done
          ? '[ Completado ]'
          : p.estado === 'en_proceso' ? '[ En Proceso ]' : '[ Pendiente ]';
        page.drawText(stLabel, {
          x: PW - MR - 106, y: ty(y), size: 7.5, font: bold,
          color: done ? ACCENT : MUTED
        });

        if (p.evidencias.length)
          page.drawText(`${p.evidencias.length}`, {
            x: PW - MR - 12, y: ty(y), size: 8, font: bold, color: ACCENT
          });

        y -= ROW_H;
        page.drawLine({ start: { x: ML, y }, end: { x: ML + BODY_W, y }, thickness: 0.5, color: RULE });

        // Sub-fila de descripción (altura variable por word-wrap)
        if (p.descripcion) {
          checkPage(ROW_H);
          y -= 5;
          drawWrapped(p.descripcion, ML + 28, BODY_W - 120, 7.5, regular, MUTED);
          page.drawLine({ start: { x: ML, y }, end: { x: ML + BODY_W, y }, thickness: 0.5, color: RULE });
        }
      }
      y -= 8;

      // ── 3. Liquidación de materiales ─────────────────────────────────────
      drawSection('3. Liquidación de Materiales Utilizados');

      const renderMatTable = (items: ItemMaterial[]) => {
        if (!items.length) return;
        // Borde superior — mismo x/width que rect y líneas de fila
        checkPage(ROW_H * 3);
        page.drawLine({ start: { x: ML, y }, end: { x: ML + BODY_W, y }, thickness: 0.5, color: RULE });
        page.drawRectangle({ x: ML, y: y - ROW_H, width: BODY_W, height: ROW_H, color: HDR_BG });
        page.drawText('Ref.',        { x: ML + 4,        y: ty(y), size: 7.5, font: bold, color: MUTED });
        page.drawText('Descripción', { x: ML + 56,       y: ty(y), size: 7.5, font: bold, color: MUTED });
        page.drawText('Cant.',       { x: PW - MR - 104, y: ty(y), size: 7.5, font: bold, color: MUTED });
        page.drawText('Unidad',      { x: PW - MR - 72,  y: ty(y), size: 7.5, font: bold, color: MUTED });
        page.drawText('Estado',      { x: PW - MR - 38,  y: ty(y), size: 7.5, font: bold, color: MUTED });
        y -= ROW_H;
        page.drawLine({ start: { x: ML, y }, end: { x: ML + BODY_W, y }, thickness: 0.5, color: RULE });

        for (const m of items) {
          checkPage(ROW_H + 5);
          const ref  = (m.requerimientoId ?? '').slice(0, 8).toUpperCase() || '—';
          const nom  = m.nombre.length > 42 ? m.nombre.slice(0, 39) + '…' : m.nombre;
          const stC  = m.estadoReq === 'entregado' ? ACCENT : MUTED;
          const stLb = m.estadoReq.charAt(0).toUpperCase() + m.estadoReq.slice(1);
          page.drawText(ref,            { x: ML + 4,        y: ty(y), size: 7.5, font: regular, color: MUTED });
          page.drawText(nom,            { x: ML + 56,       y: ty(y), size: 8,   font: regular, color: INK  });
          page.drawText(`${m.cantidad}`,{ x: PW - MR - 104, y: ty(y), size: 8,   font: bold,    color: INK  });
          page.drawText(m.unidad,       { x: PW - MR - 72,  y: ty(y), size: 7.5, font: regular, color: MUTED });
          page.drawText(stLb,           { x: PW - MR - 38,  y: ty(y), size: 7.5, font: bold,    color: stC  });
          y -= ROW_H;
          page.drawLine({ start: { x: ML, y }, end: { x: ML + BODY_W, y }, thickness: 0.5, color: RULE });
        }
      };

      if (s.materialesAsignados.length > 0) {
        checkPage(26);
        page.drawText('Materiales Asignados Originalmente',
          { x: ML, y, size: 8.5, font: bold, color: INK });
        y -= 14;
        renderMatTable(s.materialesAsignados);
        y -= 8;
      }

      const matsExtra = s.materialesSolicitados.filter(m => ['aprobado', 'entregado'].includes(m.estadoReq));
      if (matsExtra.length > 0) {
        checkPage(26);
        page.drawText('Materiales Extra Aprobados  (Solicitudes / Compra Externa)',
          { x: ML, y, size: 8.5, font: bold, color: INK });
        y -= 14;
        renderMatTable(matsExtra);
        y -= 8;
      }

      // ── 4. Registro fotográfico de evidencias ────────────────────────────
      const procConEv = s.procedimientos.filter(p => p.evidencias.length > 0);
      if (procConEv.length > 0) {
        drawSection('4. Registro Fotográfico de Evidencias');

        const IW = 155, IH = 115, IGAP = 11, COLS = 3;
        const etLabel: Record<string, string> = {
          antes: 'Antes', durante: 'Durante', despues: 'Después'
        };

        for (const proc of procConEv) {
          checkPage(36);
          page.drawText(`Procedimiento ${proc.orden}:  ${proc.nombre}`,
            { x: ML, y, size: 8.5, font: bold, color: INK });
          y -= 5;
          hRule();
          y -= 14;

          const ordered = (['antes', 'durante', 'despues'] as const)
            .flatMap(etapa => proc.evidencias.filter(e => e.etapa === etapa));

          let col     = 0;
          let rowTopY = y;

          for (const ev of ordered) {
            if (col === COLS) {
              col = 0;
              y = rowTopY - IH - 28;
              rowTopY = y;
            }
            checkPage(IH + 40);
            if (col === 0) rowTopY = y;

            const ix = ML + col * (IW + IGAP);
            const iy = y - IH;

            // Marco limpio y delgado — sin fondo de color encendido
            page.drawRectangle({
              x: ix, y: iy, width: IW, height: IH,
              color: HDR_BG, borderColor: RULE, borderWidth: 0.5
            });

            const imgBytes = await descargarImagenBytes(ev.urlCloudinary);
            if (imgBytes) {
              try {
                let img: any;
                try   { img = await doc.embedPng(imgBytes); }
                catch { img = await doc.embedJpg(imgBytes); }
                const dims = img.scaleToFit(IW - 2, IH - 2);
                page.drawImage(img, {
                  x: ix + 1 + (IW - 2 - dims.width)  / 2,
                  y: iy + 1 + (IH - 2 - dims.height) / 2,
                  width: dims.width, height: dims.height
                });
              } catch {
                page.drawText('No se pudo cargar la imagen',
                  { x: ix + 10, y: iy + IH / 2, size: 7, font: regular, color: MUTED });
              }
            } else {
              page.drawText('Imagen no disponible',
                { x: ix + 18, y: iy + IH / 2, size: 7, font: regular, color: MUTED });
            }

            // Etiqueta inferior: texto plano sin fondo de color
            page.drawText(etLabel[ev.etapa] ?? ev.etapa,
              { x: ix, y: iy - 13, size: 7.5, font: bold, color: INK });
            if (ev.fechaCaptura) {
              const capStr = ev.fechaCaptura;
              page.drawText(capStr, {
                x: ix + IW - regular.widthOfTextAtSize(capStr, 7) - 1,
                y: iy - 13, size: 7, font: regular, color: MUTED
              });
            }
            col++;
          }

          y = rowTopY - IH - 30;
          y -= 10;
        }
      }

      drawFooter();

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

  cerrarModalPDF(): void { this.showModalPDF = false; document.body.style.overflow = ''; }

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
    // 1. Candado de seguridad: Solo Jefatura puede finalizar
    if (!this.soyJefeOperaciones) {
      alert('Acceso denegado: Solo el Jefe de Operaciones puede finalizar y cerrar este servicio.');
      return;
    }

    if (!this.todasCompletadas || !this.servicio) return;

    this.svc.actualizarEstado(this.servicio.id, 'Completado').subscribe({
      next: () => { this.servicio!.estado = 'Completado'; }
    });
    await this.abrirModalPreInforme();
  }
}

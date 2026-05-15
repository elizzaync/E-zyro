import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterModule } from '@angular/router';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';

import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

// ============================================================
// INTERFACES — alineadas 1:1 con bd.txt
// ============================================================

/** proyecto_miembro JOIN empleado JOIN usuario */
export interface MiembroEquipo {
  id: string;
  nombre: string;
  apellido: string;
  fotoUrl?: string;
  cargo: string;
  rolProyecto: string;
}

/** evidencia_procedimiento */
export interface EvidenciaProcedimiento {
  id: string;
  urlCloudinary: string;
  descripcion?: string;
  fechaCaptura: string;
}

/** procedimiento */
export interface Procedimiento {
  id: string;
  nombre: string;
  descripcion?: string;
  orden: number;
  estado: 'pendiente' | 'en_proceso' | 'completado' | 'bloqueado';
  evidencias: EvidenciaProcedimiento[];
}

/** requerimiento_detalle JOIN material */
export interface ItemMaterial {
  id: string;
  requerimientoId: string;
  nombre: string;
  unidad: string;
  cantidad: number;
  estadoReq: 'pendiente' | 'aprobado' | 'rechazado' | 'entregado' | 'anulado';
}

/** seguimiento_proyecto */
export interface NotaServicio {
  id: string;
  fecha: string;
  texto: string;
  autor: string;
}

/** Respuesta consolidada del endpoint GET /operaciones/servicio/:id */
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
  notas: NotaServicio[];
}

// ============================================================
// COMPONENTE
// ============================================================

@Component({
  selector: 'app-operaciones-detalle',
  standalone: true,
  imports: [CommonModule, RouterModule, FormsModule, SpinnerComponent],
  templateUrl: './operaciones-detalle.component.html',
  styleUrls: ['./operaciones-detalle.component.css']
})
export class OperacionesDetalleComponent implements OnInit, OnDestroy {
  private route     = inject(ActivatedRoute);
  private location  = inject(Location);
  private sanitizer = inject(DomSanitizer);
  private svc       = inject(OperacionesService);

  servicioId: string | null = null;
  servicio: ServicioDetalle | null = null;
  cargando = true;
  error    = false;
  errorMsg = '';

  // ── Modal 1: Evidencia ─────────────────────────────────────
  showModalEvidencia   = false;
  procedimientoActivo: Procedimiento | null = null;
  archivoEvidencia: File | null = null;
  archivoPreview: string | null = null;
  descripcionEvidencia = '';
  subiendoEvidencia    = false;
  errorEvidencia       = '';

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

  // ── Nota nueva ─────────────────────────────────────────────
  nuevaNota    = '';
  enviandoNota = false;

  // Nombre del usuario logueado para las notas
  private _nombreUsuario: string = 'Yo';

  // ==========================================================
  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id');
    const stored = localStorage.getItem('ezyro_user');
    if (stored) {
      try {
        const u = JSON.parse(stored);
        if (u?.nombre_completo) this._nombreUsuario = u.nombre_completo;
      } catch { /* ignore */ }
    }
    this.cargarDetalle();
  }

  ngOnDestroy(): void {
    if (this.pdfBlobUrl) URL.revokeObjectURL(this.pdfBlobUrl);
  }

  volver(): void { this.location.back(); }

  // ==========================================================
  // CARGA DE DATOS
  // ==========================================================
  cargarDetalle(): void {
    this.cargando = true;
    this.error    = false;
    if (!this.servicioId) {
      this.error   = true;
      this.errorMsg = 'ID de servicio inválido.';
      this.cargando = false;
      return;
    }
    this.svc.getDetalleServicio(this.servicioId).subscribe({
      next: (raw: any) => {
        this.servicio = this._mapServicio(raw);
        this.cargando = false;
      },
      error: (err: any) => {
        this.error    = true;
        this.errorMsg = err?.error?.detail ?? 'No se pudo cargar el detalle del servicio.';
        this.cargando = false;
      }
    });
  }

  /** Mapea la respuesta snake_case del backend a las interfaces camelCase del componente. */
  private _mapServicio(raw: any): ServicioDetalle {
    return {
      id:          raw.id,
      proyectoId:  raw.proyecto_id,
      cliente:     raw.cliente,
      tipoServicio: raw.tipo_servicio,
      ubicacion:   raw.ubicacion,
      fechaStr:    raw.fecha_str,
      horaStr:     raw.hora_str,
      descripcion: raw.descripcion,
      estado:      raw.estado,
      progreso:    raw.progreso,
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
          fechaCaptura:  e.fecha_captura
        }))
      })),
      materialesAsignados:  this._mapMateriales(raw.materiales_asignados),
      materialesSolicitados: this._mapMateriales(raw.materiales_solicitados),
      notas: (raw.notas ?? []).map((n: any) => ({
        id:    n.id,
        fecha: n.fecha,
        texto: n.texto,
        autor: n.autor
      }))
    };
  }

  private _mapMateriales(list: any[]): ItemMaterial[] {
    return (list ?? []).map((m: any) => ({
      id:             m.id,
      requerimientoId: m.requerimiento_id,
      nombre:         m.nombre,
      unidad:         m.unidad,
      cantidad:       m.cantidad,
      estadoReq:      m.estado_req
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

  // Helpers de avatar
  getIniciales(m: MiembroEquipo): string {
    return (m.nombre[0] + m.apellido[0]).toUpperCase();
  }
  getColorAvatar(i: number): string {
    const c = ['#91d337','#3b82f6','#8b5cf6','#f59e0b','#06b6d4','#ec4899'];
    return c[i % c.length];
  }

  // ==========================================================
  // REGLA DE NEGOCIO: solo editar si NO está entregado/aprobado
  // ==========================================================
  puedeEditar(mat: ItemMaterial): boolean {
    return mat.estadoReq !== 'entregado' && mat.estadoReq !== 'aprobado';
  }

  // ==========================================================
  // MODAL 1 — EVIDENCIA
  // ==========================================================
  abrirModalEvidencia(proc: Procedimiento): void {
    this.procedimientoActivo  = proc;
    this.archivoEvidencia     = null;
    this.archivoPreview       = null;
    this.descripcionEvidencia = '';
    this.errorEvidencia       = '';
    this.showModalEvidencia   = true;
  }

  cerrarModalEvidencia(): void {
    this.showModalEvidencia  = false;
    this.procedimientoActivo = null;
  }

  onFileSelected(event: Event): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    this.archivoEvidencia = file;
    this.errorEvidencia   = '';
    if (file.type.startsWith('image/')) {
      const reader = new FileReader();
      reader.onload = e => (this.archivoPreview = e.target?.result as string);
      reader.readAsDataURL(file);
    } else {
      this.archivoPreview = null;
    }
  }

  guardarEvidencia(): void {
    if (!this.archivoEvidencia || !this.procedimientoActivo) return;
    this.subiendoEvidencia = true;
    this.errorEvidencia    = '';

    const formData = new FormData();
    formData.append('archivo',     this.archivoEvidencia);
    formData.append('descripcion', this.descripcionEvidencia);

    this.svc.subirEvidencia(this.procedimientoActivo.id, formData).subscribe({
      next: (res: any) => {
        const ev: EvidenciaProcedimiento = {
          id:            res.evidencia_id,
          urlCloudinary: res.url,
          descripcion:   this.descripcionEvidencia || this.archivoEvidencia!.name,
          fechaCaptura:  new Date().toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' })
        };
        this.procedimientoActivo!.evidencias.push(ev);
        this.procedimientoActivo!.estado = 'completado';
        this.recalcularProgreso();
        this.subiendoEvidencia = false;
        this.cerrarModalEvidencia();
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
          id:             res.detalle_id,
          requerimientoId: res.requerimiento_id,
          nombre:         this.materialElegido!.nombre,
          unidad:         this.materialElegido!.unidad,
          cantidad:       this.cantidadSolicitar,
          estadoReq:      'pendiente'
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

      // Header bar
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
  // NOTAS
  // ==========================================================
  agregarNota(): void {
    if (!this.nuevaNota.trim() || !this.servicio || this.enviandoNota) return;
    const texto = this.nuevaNota.trim();
    this.enviandoNota = true;
    this.svc.agregarNota(this.servicio.id, { descripcion: texto }).subscribe({
      next: (res: any) => {
        this.servicio!.notas.push({
          id:    res.nota_id,
          fecha: new Date().toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' }),
          texto,
          autor: this._nombreUsuario
        });
        this.enviandoNota = false;
      },
      error: () => { this.enviandoNota = false; }
    });
    this.nuevaNota = '';
  }

  // ==========================================================
  // INFORME TOTAL (habilitado sólo al 100%)
  // ==========================================================
  async finalizarServicio(): Promise<void> {
    if (!this.todasCompletadas || !this.servicio) return;
    this.svc.actualizarEstado(this.servicio.id, 'Completado').subscribe({
      next: () => { this.servicio!.estado = 'Completado'; }
    });
    await this.abrirModalPreInforme();
  }
}

import { Component, OnInit, OnDestroy, AfterViewChecked, ViewChild, ElementRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { environment } from '../../../../../environments/environment';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { webSocket, WebSocketSubject } from 'rxjs/webSocket';
import { Subscription } from 'rxjs';

import { OperacionesService } from '../../../../core/services/operaciones.service';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { JustificacionModalComponent } from '../../../../shared/components/justificacion-modal/justificacion-modal.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { FASES_SERVICIO, faseClase as faseClaseServicio } from '../../fase-servicio';
import { Requerimiento } from '../../../logistica/logistica.models';

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
  responsableId?: string | null;
}

export interface ItemMaterial {
  id: string;
  requerimientoId: string;
  nombre: string;
  unidad: string;
  cantidad: number;
  estadoReq: 'pendiente' | 'aprobado' | 'rechazado' | 'entregado' | 'anulado';
  clase?: 'material' | 'herramienta' | 'equipo';
  estadoEquipo?: string;
  equipoId?: string | null;
  numeroSerie?: string | null;
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
  itemsAsignados: ItemMaterial[];
  itemsSolicitados: ItemMaterial[];
  zonaEjecucion?: string | null;
  esMantenimiento?: boolean;
}

export interface ComunicadoItem {
  id: string;
  titulo: string;
  mensaje: string;
  autor: string;
  fecha: string;
  adjunto_url?: string | null;
  leido: boolean;
}

export interface NotaItem {
  id: string;
  descripcion: string;
  autor: string;
  autor_id?: string | null;
  fecha: string;
  puede_editar: boolean;
}

@Component({
  selector: 'app-operaciones-detalle',
  standalone: true,
  imports: [CommonModule, RouterModule, FormsModule, SpinnerComponent, JustificacionModalComponent, AppModalComponent],
  templateUrl: './operaciones-detalle.component.html',
  styleUrls: ['./operaciones-detalle.component.css']
})
export class OperacionesDetalleComponent implements OnInit, OnDestroy, AfterViewChecked {
  private route     = inject(ActivatedRoute);
  private router    = inject(Router);
  private location  = inject(Location);
  private sanitizer = inject(DomSanitizer);
  private svc       = inject(OperacionesService);
  private logistica = inject(LogisticaService);
  private toast     = inject(ToastService);

  @ViewChild('chatScroll') private chatScrollEl!: ElementRef<HTMLDivElement>;
  @ViewChild('firmaCanvas') private firmaCanvasEl?: ElementRef<HTMLCanvasElement>;

  // ── HU-16: requerimientos entregados por logística, esperando firma del técnico ──
  reqsListos: Requerimiento[] = [];
  showFirmaModal   = false;
  reqAFirmar:  Requerimiento | null = null;
  firmando         = false;
  private _dibujando = false;
  private _hayTrazo  = false;

  // ── Firma global por servicio (técnico confirma recepción) ──
  showFirmaGlobalModal = false;
  firmaGlobalEnCurso   = false;
  firmaGlobalGuardada  = '';
  firmandoPorNombreGlobal = '';   // cinema-seat display

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
// ── Borrador de Materiales/Herramientas/Equipos (persistente en BD) ─────────
  materialesBorrador: Array<{
    id: string;
    material_id: string | null;
    nombre: string;
    unidad: string;
    cantidad: number;
    esNuevo: boolean;
    clase?: 'material' | 'herramienta' | 'equipo';
    agregadoPor: string;
    agregadoPorFoto: string;
    especificacion?: string;
    _avatarError?: boolean;
  }> = [];
  // ── Edición inline de borrador ─────────────────────────────
  editandoIndice:     number | null = null;
  editCantBorrador:   number        = 1;
  editNombreBorrador: string        = '';
  editEspecBorrador:  string        = '';
  consensoEquipo  = false;
  enviandoLote    = false;
  cargandoBorrador = false;
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

  // ── Modal 3: Solicitar Material/Equipo (3 pestañas) ────────
  showModalSolicitar  = false;
  tabSolicitar: 'materiales' | 'equipos' | 'compra' = 'materiales';

  busquedaMaterial    = '';
  resultadosBusqueda: Array<{ id: string; nombre: string; unidad: string; stock: number }> = [];
  materialElegido: { id: string; nombre: string; unidad: string; stock: number } | null = null;
  cantidadSolicitar   = 1;
  buscandoMaterial    = false;
  solicitando         = false;

  busquedaEquipo      = '';
  resultadosEquipos: Array<{ id: string; nombre: string; clase: string; cantidad: number; estado: string }> = [];
  equipoElegido: { id: string; nombre: string; clase: string; cantidad: number; estado: string } | null = null;
  cantidadEquipo      = 1;
  buscandoEquipo      = false;

  manualNombre          = '';
  manualCantidad        = 1;
  manualUnidad          = 'Unidades';
  manualEspecificacion  = '';
  manualTipoItem        = 'material';   // material | equipo | herramienta
  manualPrecioEstimado: number | null = null;
  // alias para compatibilidad con template existente
  get modoCompraExterna(): boolean { return this.tabSolicitar === 'compra'; }

  // ── Modal 4: Pre-Informe PDF ───────────────────────────────
  showModalPDF  = false;
  pdfCargando   = false;
  pdfBlobUrl    = '';

  // ── Modal Incidencia (técnico reporta daño) ───────────────
  showModalIncidencia       = false;
  incEquipoId               = '';
  incEquipoNombre           = '';
  incEquipoClase: 'equipo' | 'herramienta' = 'equipo';
  incEquipoSinSerie         = false;
  incNumeroSerie            = '';
  incCantidadAfectada       = 1;
  incTipoFalla              = 'otro';
  incDescripcion            = '';
  enviandoIncidencia        = false;
  // Lista de todos los equipos/herramientas del inventario para el modal
  incListaEquipos: { id: string; nombre: string; clase: string; numeroSerie: string | null }[] = [];
  incCargandoEquipos        = false;

  // ── Modal Retorno (técnico declara devolución al completar servicio) ──
  showModalRetorno         = false;
  retornoObligatorio       = false;   // true = no se puede cerrar sin completar
  retornoServicioId        = '';
  retornoItems: { detalleId: string; nombre: string; unidad: string; tipoItem: string; esObligatorio: boolean; cantidadEntregada: number; cantidadRetornada: number }[] = [];
  retornoNotaTecnico       = '';
  enviandoRetorno          = false;
  alertaRetornoPendiente   = false;

  // ── Chat en tiempo real ────────────────────────────────────
  chatMensajes: MensajeChat[]     = [];
  nuevoMensajeChat                = '';
  chatDestinatario: string | null = null;
  soyJefeOperaciones              = false;
  soyTecnico                      = false;

  // ── Modal de justificación (Jefe de Operaciones) ──────────
  showJustModal     = false;
  _pendingProcId    = '';
  _pendingEstado: 'completado' | 'pendiente' = 'completado';
  _pendingProcRef: any = null;
  _pendingEstadoPrev: string = '';

  // ── Comunicados (nivel proyecto) ───────────────────────────
  comunicados: ComunicadoItem[]   = [];
  cargandoComunicados             = false;
  errorComunicados                = '';
  showNuevoComunicado             = false;
  ncTitulo                        = '';
  ncMensaje                       = '';
  guardandoComunicado             = false;

  // ── Equipos Intervenidos (mantenimiento) ──────────────────────────────
  equiposIntervenidos: Array<{
    id: string; nombre: string; codigo?: string | null; tipoNombre?: string | null;
    tipoEquipoId?: string | null; marca?: string | null; modelo?: string | null;
    numeroSerie?: string | null; estadoIntervencion: string; estado: string;
  }> = [];
  equiposDisp: Array<{
    id: string; nombre: string; codigo?: string | null; tipoNombre?: string | null;
    marca?: string | null; modelo?: string | null; ubicacion?: string | null; estado: string;
  }> = [];
  cargandoEI      = false;
  showModalEI     = false;
  cargandoEIModal = false;
  filtroEI        = '';
  eiAgregando     = false;
  eiConfirmandoId: string | null = null;

  get equiposDispFiltrados() {
    const q = this.filtroEI.toLowerCase().trim();
    if (!q) return this.equiposDisp;
    return this.equiposDisp.filter(e =>
      e.nombre.toLowerCase().includes(q) ||
      (e.tipoNombre ?? '').toLowerCase().includes(q) ||
      (e.codigo ?? '').toLowerCase().includes(q)
    );
  }

  // ── Notas (nivel servicio) ─────────────────────────────────
  notas: NotaItem[]               = [];
  cargandoNotas                   = false;
  errorNotas                      = '';
  nuevaNota                       = '';
  guardandoNota                   = false;
  notaEditandoId: string | null   = null;
  notaEditTexto                   = '';
  notaEliminandoId: string | null = null;

  private chatSocket$: WebSocketSubject<unknown> | null = null;
  private chatSub?: Subscription;
  private _scrollPending = false;

  _nombreUsuario = 'Yo';
  _usuarioId:   string | null = null;
  _usuarioFoto  = '';

  get _idUsuario(): string {
    const stored = localStorage.getItem('ezyro_user');
    if (stored) {
      try { return JSON.parse(stored)?.id ?? ''; } catch { /* ignore */ }
    }
    return '';
  }

  esMiMensaje(msg: MensajeChat): boolean {
    if (!msg) return false;

    // Verificación primaria: por ID de usuario (fuente de verdad)
    const miId = this._usuarioId ?? this._idUsuario;
    if (miId && msg.remitente_id === miId) return true;

    // Verificación secundaria: por nombre completo (fallback para sesiones antiguas sin id cacheado)
    if (msg.nombre_remitente && this._nombreUsuario && this._nombreUsuario !== 'Yo') {
      return msg.nombre_remitente.toLowerCase() === this._nombreUsuario.toLowerCase();
    }

    return false;
  }

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id');
    const stored = localStorage.getItem('ezyro_user');
    if (stored) {
      try {
        const u = JSON.parse(stored);
        if (u?.nombre_completo) this._nombreUsuario = u.nombre_completo;
        if (u?.id)              this._usuarioId     = u.id;
        if (u?.foto_url)        this._usuarioFoto   = u.foto_url;
        const rol = (u?.rol || '').trim();
        if (['Jefe de Operaciones', 'Administrador', 'Administración'].includes(rol)) {
          this.soyJefeOperaciones = true;
        }
        this.soyTecnico = rol === 'Técnico';
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

  // ── Equipos Intervenidos ─────────────────────────────────────────────
  cargarEquiposIntervenidos(): void {
    if (!this.servicioId) return;
    this.cargandoEI = true;
    this.svc.getEquiposIntervenidos(this.servicioId).subscribe({
      next: (data) => {
        this.equiposIntervenidos = data.map((r: any) => ({
          id:                 r.id,
          nombre:             r.nombre,
          codigo:             r.codigo        ?? null,
          tipoNombre:         r.tipo_nombre   ?? null,
          tipoEquipoId:       r.tipo_equipo_id ?? null,
          marca:              r.marca         ?? null,
          modelo:             r.modelo        ?? null,
          numeroSerie:        r.numero_serie  ?? null,
          estadoIntervencion: r.estado_intervencion ?? 'pendiente',
          estado:             r.estado ?? 'operativo',
        }));
        this.cargandoEI = false;
      },
      error: () => { this.cargandoEI = false; }
    });
  }

  abrirModalEI(): void {
    this.showModalEI     = true;
    this.filtroEI        = '';
    this.cargandoEIModal = true;
    this.equiposDisp     = [];
    this.svc.getEquiposDisponibles(this.servicioId!).subscribe({
      next: (data) => {
        this.equiposDisp = data.map((r: any) => ({
          id:         r.id,
          nombre:     r.nombre,
          codigo:     r.codigo      ?? null,
          tipoNombre: r.tipo_nombre ?? null,
          marca:      r.marca       ?? null,
          modelo:     r.modelo      ?? null,
          ubicacion:  r.ubicacion   ?? null,
          estado:     r.estado,
        }));
        this.cargandoEIModal = false;
      },
      error: () => { this.cargandoEIModal = false; }
    });
  }

  eiAgregar(activo: { id: string; nombre: string }): void {
    if (this.eiAgregando) return;
    this.eiAgregando = true;
    this.svc.agregarEquipoIntervenido(this.servicioId!, activo.id).subscribe({
      next: (nuevo: any) => {
        this.equiposIntervenidos.push({
          id:                 nuevo.id,
          nombre:             nuevo.nombre,
          codigo:             nuevo.codigo        ?? null,
          tipoNombre:         nuevo.tipo_nombre   ?? null,
          tipoEquipoId:       nuevo.tipo_equipo_id ?? null,
          marca:              nuevo.marca         ?? null,
          modelo:             nuevo.modelo        ?? null,
          numeroSerie:        nuevo.numero_serie  ?? null,
          estadoIntervencion: nuevo.estado_intervencion ?? 'pendiente',
          estado:             nuevo.estado ?? 'operativo',
        });
        this.equiposDisp = this.equiposDisp.filter(e => e.id !== activo.id);
        this.eiAgregando = false;
        this.toast.mostrar('Activo agregado al servicio', 'success');
      },
      error: (err: any) => {
        this.eiAgregando = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al agregar el activo.', 'error');
      }
    });
  }

  eiQuitar(id: string): void {
    this.svc.quitarEquipoIntervenido(this.servicioId!, id).subscribe({
      next: () => {
        this.equiposIntervenidos = this.equiposIntervenidos.filter(e => e.id !== id);
        this.eiConfirmandoId = null;
        this.toast.mostrar('Activo quitado del servicio', 'success');
      },
      error: (err: any) => {
        this.eiConfirmandoId = null;
        this.toast.mostrar(err?.error?.detail ?? 'Error al quitar el activo.', 'error');
      }
    });
  }

  eiIntervenir(eq: { id: string; estadoIntervencion: string }): void {
    if (eq.estadoIntervencion === 'pendiente') {
      this.svc.actualizarEstadoIntervencion(this.servicioId!, eq.id, 'en_proceso').subscribe({
        next: () => { eq.estadoIntervencion = 'en_proceso'; }
      });
    }
    this.router.navigate(['/operaciones/servicio', this.servicioId, 'equipos-intervenidos', eq.id]);
  }

  irAEquiposIntervenidos(): void {
    this.router.navigate(['/operaciones/servicio', this.servicioId, 'equipos-intervenidos']);
  }

  eiEstadoLabel(e: string): string {
    return ({ pendiente: 'Pendiente', en_proceso: 'En Proceso', completado: 'Completado', cancelado: 'Cancelado' } as Record<string, string>)[e] ?? e;
  }

  eiEstadoClass(e: string): string {
    return ({ pendiente: 'ei-warn', en_proceso: 'ei-info', completado: 'ei-ok', cancelado: 'ei-muted' } as Record<string, string>)[e] ?? '';
  }

  // ==========================================================
  // STEPPER DE FASES + ACCIÓN DE INICIO
  // ==========================================================
  fasesLista = FASES_SERVICIO;

  faseClase(n: number): 'done' | 'active' | 'muted' {
    if (!this.servicio) return n === 1 ? 'active' : 'muted';
    return faseClaseServicio(n, this.servicio.estado, this.servicio.progreso);
  }

  get totalMateriales(): number {
    if (!this.servicio) return 0;
    return this.servicio.itemsAsignados.length + this.servicio.itemsSolicitados.length;
  }

  get tareasCompletadas(): number {
    return this.servicio?.procedimientos.filter(p => p.estado === 'completado').length ?? 0;
  }

  /** Items (materiales + herramientas) aún no entregados (pendientes o solo aprobados). */
  get materialesPendientesEntrega(): number {
    if (!this.servicio) return 0;
    const todos = [...this.servicio.itemsAsignados, ...this.servicio.itemsSolicitados];
    return todos.filter(m => m.estadoReq === 'pendiente' || m.estadoReq === 'aprobado').length;
  }

  // ── Sub-pasos de la Fase 1 (Preparación) ────────────────────────────────
  /** El equipo técnico ya fue asignado. */
  get prepEquipoListo(): boolean {
    return (this.servicio?.equipo.length ?? 0) > 0;
  }

  /** Todas las tareas existen y tienen responsable (tareas repartidas). */
  get prepTareasListo(): boolean {
    const procs = this.servicio?.procedimientos ?? [];
    return procs.length > 0 && procs.every(p => !!p.responsableId);
  }

  /** Materiales/herramientas elegidos, enviados a Logística y entregados. */
  get prepMaterialesListo(): boolean {
    return this.totalMateriales > 0
        && this.materialesBorrador.length === 0
        && this.materialesPendientesEntrega === 0;
  }

  /** Texto de ayuda del sub-paso de materiales. */
  get prepMaterialesHint(): string {
    if (this.materialesBorrador.length > 0) {
      return `${this.materialesBorrador.length} en borrador sin enviar a Logística`;
    }
    if (this.materialesPendientesEntrega > 0) {
      return `Esperando entrega de ${this.materialesPendientesEntrega}`;
    }
    if (this.totalMateriales === 0) {
      return 'Aún no se eligen materiales ni herramientas';
    }
    return `${this.totalMateriales} material(es)/herramienta(s) listos`;
  }

  /** Requisitos que faltan para poder iniciar el servicio. */
  get motivosInicio(): string[] {
    const m: string[] = [];
    if (!this.servicio) return m;
    if (this.servicio.equipo.length === 0) {
      m.push('asignar el equipo técnico');
    }
    if (this.servicio.procedimientos.length === 0) {
      m.push('repartir las tareas del servicio');
    } else if (this.servicio.procedimientos.some(p => !p.responsableId)) {
      m.push('asignar un responsable a todas las tareas');
    }
    // El equipo debe elegir los materiales/herramientas antes de avanzar de fase.
    if (this.totalMateriales === 0 && this.materialesBorrador.length === 0) {
      m.push('elegir los materiales y herramientas necesarios');
    }
    if (this.materialesBorrador.length > 0) {
      m.push('enviar el borrador de materiales a Logística');
    }
    if (this.materialesPendientesEntrega > 0) {
      m.push(`esperar la entrega de ${this.materialesPendientesEntrega} material(es)/herramienta(s)`);
    }
    return m;
  }

  get puedeIniciar(): boolean {
    return this.motivosInicio.length === 0;
  }

  /** Inicia el servicio (Pendiente → En_Proceso) solo si todo está listo. */
  iniciarServicio(): void {
    if (!this.servicio || this.servicio.estado !== 'Pendiente') return;

    const motivos = this.motivosInicio;
    if (motivos.length > 0) {
      this.toast.mostrar(
        'No puedes iniciar el servicio aún. Falta: ' + motivos.join(' · ') + '.',
        'error'
      );
      return;
    }

    this.svc.actualizarEstado(this.servicio.id, 'En_Proceso').subscribe({
      next: () => {
        this.servicio!.estado = 'En_Proceso';
        this.toast.mostrar('Servicio iniciado', 'success');
      },
      error: (err: any) => this.toast.mostrar(err?.error?.detail ?? 'No se pudo iniciar el servicio.', 'error')
    });
  }

  estadoLabel(estado: string): string {
    const m: Record<string, string> = { 'En_Proceso': 'En Proceso' };
    return m[estado] ?? estado;
  }

  procEstadoLabel(estado: string): string {
    const m: Record<string, string> = {
      'pendiente': 'No iniciado', 'en_proceso': 'En proceso',
      'completado': 'Completado', 'bloqueado': 'Bloqueado',
    };
    return m[estado] ?? estado;
  }

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
        this._conectarChat(this.servicio.id);
        this._checkDeepLink();
        this.cargarBorrador();
        this.cargarComunicados();
        this.cargarNotas();
        this.cargarReqsListos();
        if (this.servicio.esMantenimiento) {
          this.cargarEquiposIntervenidos();
        }
        // Si el servicio ya está Completado, verificar si falta registrar el retorno
        if (this.servicio.estado === 'Completado') {
          this._verificarRetornoPendiente(this.servicio.id);
        }
      },
      error: (err: any) => {
        this.error    = true;
        this.errorMsg = err?.error?.detail ?? 'No se pudo cargar el detalle del servicio.';
        this.cargando = false;
      }
    });
  }

  // ──────────────────────────────────────────────────────────
  // HU-16: requerimientos aprobados listos para firmar recepción
  // ──────────────────────────────────────────────────────────
  cargarReqsListos(): void {
    if (!this.servicioId) return;
    this.logistica.getRequerimientos({ estado: 'todos', servicioId: this.servicioId }).subscribe({
      next: (reqs) => {
        // aprobado = logística firmó, técnico debe confirmar recepción
        // comprando = en proceso de compra (informativo)
        this.reqsListos = reqs.filter(r =>
          r.estado === 'aprobado' || r.estado === 'comprando' || r.estado === 'listo'
        );
        // Actualizar cinema-seat display
        const firmando = reqs.find(r => r.firmandoPorNombre && r.estado === 'aprobado');
        this.firmandoPorNombreGlobal = firmando?.firmandoPorNombre ?? '';
      },
      error: () => { /* silencioso */ }
    });
  }

  get hayReqsPorFirmar(): boolean {
    // aprobado = logística entregó, técnico debe confirmar
    return this.reqsListos.some(r => r.estado === 'aprobado');
  }

  get reqsParaFirmar(): Requerimiento[] {
    return this.reqsListos.filter(r => r.estado === 'aprobado');
  }

  get reqsEntregados(): Requerimiento[] {
    return (this.reqsListos ?? []).filter(r => r.estado === 'entregado');
  }

  abrirFirma(req: Requerimiento): void {
    this.reqAFirmar = req;
    this.showFirmaModal = true;
    this._hayTrazo = false;
    document.body.style.overflow = 'hidden';
    setTimeout(() => this._initCanvas(), 50);
  }

  cerrarFirma(): void {
    this.showFirmaModal = false;
    this.reqAFirmar = null;
    document.body.style.overflow = '';
  }

  // ── Firma global del técnico (confirma recepción de todos los aprobados) ──
  abrirFirmaGlobal(): void {
    if (!this.reqsParaFirmar.length) return;
    this.showFirmaGlobalModal = true;
    this._hayTrazo = false;
    this.firmaGlobalGuardada = '';
    document.body.style.overflow = 'hidden';
    // Obtener firma guardada del usuario
    this.logistica.getFirmaGuardada().subscribe({
      next: f => { if (f?.url) this.firmaGlobalGuardada = f.url; },
      error: () => {},
    });
    // Cinema-seat: bloquear el primer req
    const primer = this.reqsParaFirmar[0];
    this.logistica.bloquearFirma(primer.id).subscribe({
      next: () => setTimeout(() => this._initCanvas(), 80),
      error: err => {
        const d: string = err?.error?.detail ?? '';
        if (d.startsWith('firmando_por:')) {
          const quien = d.split(':')[1];
          this.toast.mostrar(`${quien} está firmando ahora. Espera.`, 'info');
          this.firmandoPorNombreGlobal = quien;
          this.showFirmaGlobalModal = false;
          document.body.style.overflow = '';
        } else {
          this.toast.mostrar('No se pudo iniciar la firma. Intenta de nuevo.', 'error');
          this.showFirmaGlobalModal = false;
          document.body.style.overflow = '';
        }
        this.cargarReqsListos();
      },
    });
  }

  cerrarFirmaGlobal(): void {
    this.showFirmaGlobalModal = false;
    this._hayTrazo = false;
    document.body.style.overflow = '';
    // Liberar cinema-seat lock
    const primer = this.reqsParaFirmar[0];
    if (primer) this.logistica.liberarFirma(primer.id).subscribe({ error: () => {} });
    this.cargarReqsListos();
  }

  usarFirmaGuardadaGlobal(): void {
    if (!this.firmaGlobalGuardada) return;
    // Usar firma guardada como URL directamente → confirmar
    this.firmaGlobalEnCurso = true;
    this._entregarConFirma(this.firmaGlobalGuardada);
  }

  confirmarFirmaGlobal(): void {
    if (!this._hayTrazo) {
      this.toast.mostrar('Dibuja tu firma antes de confirmar.', 'error');
      return;
    }
    const canvas = this.firmaCanvasEl?.nativeElement;
    if (!canvas) return;
    const dataUrl = canvas.toDataURL('image/png');
    this.firmaGlobalEnCurso = true;
    this._entregarConFirma(dataUrl);
  }

  private _entregarConFirma(firmaUrl: string): void {
    const reqs = this.reqsParaFirmar;
    let done = 0;
    let lastReq: Requerimiento | null = null;

    for (const req of reqs) {
      this.logistica.entregarRequerimiento(req.id, { firmaEntregadorUrl: firmaUrl }).subscribe({
        next: r => {
          done++;
          lastReq = r;
          if (done === reqs.length) {
            this.firmaGlobalEnCurso = false;
            this.showFirmaGlobalModal = false;
            document.body.style.overflow = '';
            this.toast.mostrar('Recepción confirmada. Materiales recibidos.', 'success');
            this.cargarReqsListos();
            if (lastReq) this.generarPDFSalida(lastReq);
          }
        },
        error: err => {
          this.firmaGlobalEnCurso = false;
          this.toast.mostrar(err?.error?.detail ?? 'No se pudo confirmar.', 'error');
          // Liberar lock si falla
          const primer = reqs[0];
          if (primer) this.logistica.liberarFirma(primer.id).subscribe({ error: () => {} });
        },
      });
    }
  }

  private _initCanvas(): void {
    const canvas = this.firmaCanvasEl?.nativeElement;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.lineWidth = 2.5;
    ctx.lineCap = 'round';
    ctx.strokeStyle = '#0f172a';
  }

  private _pos(ev: MouseEvent | TouchEvent): { x: number; y: number } {
    const canvas = this.firmaCanvasEl!.nativeElement;
    const rect = canvas.getBoundingClientRect();
    const p = ev instanceof TouchEvent ? ev.touches[0] : ev;
    return { x: (p.clientX - rect.left), y: (p.clientY - rect.top) };
  }

  firmaStart(ev: MouseEvent | TouchEvent): void {
    ev.preventDefault();
    this._dibujando = true;
    const ctx = this.firmaCanvasEl!.nativeElement.getContext('2d')!;
    const { x, y } = this._pos(ev);
    ctx.beginPath();
    ctx.moveTo(x, y);
  }
  firmaMove(ev: MouseEvent | TouchEvent): void {
    if (!this._dibujando) return;
    ev.preventDefault();
    const ctx = this.firmaCanvasEl!.nativeElement.getContext('2d')!;
    const { x, y } = this._pos(ev);
    ctx.lineTo(x, y);
    ctx.stroke();
    this._hayTrazo = true;
  }
  firmaEnd(): void { this._dibujando = false; }

  limpiarFirma(): void {
    const canvas = this.firmaCanvasEl?.nativeElement;
    if (!canvas) return;
    canvas.getContext('2d')!.clearRect(0, 0, canvas.width, canvas.height);
    this._hayTrazo = false;
  }

  confirmarFirma(): void {
    // Este método confirma la recepción individual (para el modal individual)
    if (!this.reqAFirmar || !this._hayTrazo) {
      this.toast.mostrar('Dibuja la firma antes de confirmar.', 'error');
      return;
    }
    const dataUrl = this.firmaCanvasEl!.nativeElement.toDataURL('image/png');
    this.firmando = true;
    this.logistica.entregarRequerimiento(this.reqAFirmar.id, { firmaEntregadorUrl: dataUrl }).subscribe({
      next: (req) => {
        this.firmando = false;
        this.toast.mostrar('Recepción confirmada.', 'success');
        this.cerrarFirma();
        this.cargarReqsListos();
        this.generarPDFSalida(req);
      },
      error: (err: any) => {
        this.firmando = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo confirmar.', 'error');
      }
    });
  }

  async generarPDFSalida(req: import('../../../logistica/logistica.models').Requerimiento): Promise<void> {
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
      page.drawText('Responsable de recepción', { x: ML, y, size: 7.5, font: regular, color: MUTED });
      page.drawText('Solicitado por', { x: C2, y, size: 7.5, font: regular, color: MUTED });
      y -= 13;
      page.drawText(req.recibidoPorNombre ?? this._nombreUsuario, { x: ML, y, size: 9, font: bold, color: INK });
      page.drawText(req.solicitanteNombre, { x: C2, y, size: 9, font: bold, color: INK });
      y -= 22;
      hLine(y); y -= 14;

      page.drawText(
        'NOTA: El firmante es responsable de todos los productos no consumibles (equipos y herramientas).',
        { x: ML, y, size: 7.5, font: regular, color: MUTED }
      );
      y -= 22;

      page.drawText('DETALLE DE MATERIALES, EQUIPOS Y HERRAMIENTAS', { x: ML, y, size: 9, font: bold, color: INK });
      y -= 14;
      hLine(y);
      page.drawRectangle({ x: ML, y: y - ROW_H, width: BODY_W, height: ROW_H, color: HDR_BG });
      page.drawText('#',           { x: ML + 4,        y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Descripción', { x: ML + 24,       y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Tipo',        { x: PW - MR - 160, y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Cant.',       { x: PW - MR - 80,  y: ty(y), size: 7.5, font: bold, color: MUTED });
      page.drawText('Unidad',      { x: PW - MR - 46,  y: ty(y), size: 7.5, font: bold, color: MUTED });
      y -= ROW_H; hLine(y);

      const items = req.items.filter(it => it.estadoItem !== 'rechazado');
      for (let i = 0; i < items.length; i++) {
        const it = items[i];
        if (y - ROW_H < 160) break;
        const nom = it.nombre.length > 46 ? it.nombre.slice(0, 43) + '…' : it.nombre;
        const tipo = it.esCompraExterna ? 'Compra externa' :
                     (it.especificacion?.toLowerCase().includes('equipo') ? 'Equipo' :
                      it.especificacion?.toLowerCase().includes('herramienta') ? 'Herramienta' : 'Material');
        const esNC = tipo === 'Equipo' || tipo === 'Herramienta';
        page.drawText(`${i + 1}`, { x: ML + 4, y: ty(y), size: 8, font: regular, color: MUTED });
        page.drawText(nom, { x: ML + 24, y: ty(y), size: 8, font: esNC ? bold : regular, color: INK });
        page.drawText(tipo, { x: PW - MR - 160, y: ty(y), size: 7.5, font: regular, color: esNC ? rgb(0.56, 0.27, 0.87) : MUTED });
        page.drawText(`${it.cantidadAprobada ?? it.cantidad}`, { x: PW - MR - 80, y: ty(y), size: 8, font: bold, color: INK });
        page.drawText(it.unidad, { x: PW - MR - 46, y: ty(y), size: 7.5, font: regular, color: MUTED });
        y -= ROW_H; hLine(y);
      }
      y -= 20;

      const SIG_TOP = Math.max(y, 160);
      hLine(SIG_TOP + 60);
      const SIG_W = Math.floor(BODY_W / 2) - 20;
      page.drawText('RECIBIDO POR (TÉCNICO RESPONSABLE)', { x: ML, y: SIG_TOP + 70, size: 7, font: bold, color: MUTED });
      page.drawText('ENTREGADO POR (LOGÍSTICA)', { x: ML + SIG_W + 40, y: SIG_TOP + 70, size: 7, font: bold, color: MUTED });

      if (req.firmaUrl?.startsWith('data:image')) {
        try {
          const b64 = req.firmaUrl.split(',')[1];
          const imgB = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
          const img = await doc.embedPng(imgB.buffer as ArrayBuffer);
          const d = img.scaleToFit(SIG_W, 50);
          page.drawImage(img, { x: ML, y: SIG_TOP + 8, width: d.width, height: d.height });
        } catch { /* no se pudo embeber */ }
      }

      page.drawText(req.recibidoPorNombre ?? '________________________________', { x: ML, y: SIG_TOP - 4, size: 8, font: regular, color: INK });
      page.drawText('Técnico / Responsable de Recepción', { x: ML, y: SIG_TOP - 16, size: 7.5, font: regular, color: MUTED });
      page.drawText(req.entregadoPorNombre ?? '________________________________', { x: ML + SIG_W + 40, y: SIG_TOP - 4, size: 8, font: regular, color: INK });
      page.drawText('Responsable de Logística', { x: ML + SIG_W + 40, y: SIG_TOP - 16, size: 7.5, font: regular, color: MUTED });

      page.drawLine({ start: { x: ML, y: 46 }, end: { x: PW - MR, y: 46 }, thickness: 0.5, color: RULE });
      page.drawText('E-System TIC Perú S.A.C. · Reporte de Salida de Materiales · Documento Oficial de Control', {
        x: ML, y: 33, size: 7, font: regular, color: MUTED
      });

      const bytes = await doc.save();
      const blob  = new Blob([bytes.buffer as ArrayBuffer], { type: 'application/pdf' });
      const url   = URL.createObjectURL(blob);
      const a     = document.createElement('a');
      a.href     = url;
      a.download = `salida-${req.proyectoNombre.replace(/\s+/g, '-').slice(0, 20)}-${req.id.slice(0, 6)}.pdf`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 3000);
    } catch (err) {
      console.error('Error generando PDF de salida:', err);
    }
  }

  cargarBorrador(): void {
    if (!this.servicioId) return;
    this.cargandoBorrador = true;
    this.svc.getBorrador(this.servicioId).subscribe({
      next: (data: any) => {
        this.materialesBorrador = (data.items ?? []).map((item: any) => ({
          id:              item.id,
          material_id:     item.material_id,
          nombre:          item.nombre,
          unidad:          item.unidad,
          cantidad:        item.cantidad,
          esNuevo:         item.es_nuevo,
          agregadoPor:     item.agregado_por_nombre || '',
          agregadoPorFoto: item.agregado_por_foto   || '',
          especificacion:  item.especificacion,
        }));
        this.cargandoBorrador = false;
      },
      error: () => { this.cargandoBorrador = false; }
    });
  }

  // ==========================================================
  // COMUNICADOS (nivel proyecto) — tablero de anuncios
  // ==========================================================
  cargarComunicados(): void {
    const proyectoId = this.servicio?.proyectoId;
    if (!proyectoId) return;
    this.cargandoComunicados = true;
    this.errorComunicados    = '';
    this.svc.getComunicadosProyecto(proyectoId).subscribe({
      next: (res: any) => {
        const list = Array.isArray(res) ? res : (res?.comunicados ?? []);
        this.comunicados = list.map((c: any) => ({
          id:          c.id,
          titulo:      c.titulo ?? '(Sin título)',
          mensaje:     c.mensaje ?? '',
          autor:       c.autor ?? 'Sistema',
          fecha:       c.fecha ?? '—',
          adjunto_url: c.adjunto_url ?? null,
          leido:       !!c.leido,
        }));
        this.cargandoComunicados = false;
      },
      error: (err: any) => {
        this.errorComunicados = err?.error?.detail ?? 'No se pudieron cargar los comunicados.';
        this.cargandoComunicados = false;
      }
    });
  }

  get comunicadosNoLeidos(): number {
    return this.comunicados.filter(c => !c.leido).length;
  }

  abrirNuevoComunicado(): void {
    this.showNuevoComunicado = true;
    this.ncTitulo = '';
    this.ncMensaje = '';
  }

  cancelarNuevoComunicado(): void {
    this.showNuevoComunicado = false;
    this.ncTitulo = '';
    this.ncMensaje = '';
  }

  enviarComunicado(): void {
    const proyectoId = this.servicio?.proyectoId;
    if (!proyectoId) return;
    const titulo  = this.ncTitulo.trim();
    const mensaje = this.ncMensaje.trim();
    if (!titulo || !mensaje) {
      this.toast.mostrar('Completa título y mensaje del comunicado.', 'error');
      return;
    }
    this.guardandoComunicado = true;
    this.svc.crearComunicado(proyectoId, { titulo, mensaje }).subscribe({
      next: () => {
        this.guardandoComunicado = false;
        this.showNuevoComunicado = false;
        this.ncTitulo = '';
        this.ncMensaje = '';
        this.toast.mostrar('Comunicado publicado', 'success');
        this.cargarComunicados();
      },
      error: (err: any) => {
        this.guardandoComunicado = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo publicar el comunicado.', 'error');
      }
    });
  }

  marcarComunicadoLeido(c: ComunicadoItem): void {
    if (c.leido) return;
    c.leido = true; // optimista
    this.svc.marcarComunicadoLeido(c.id).subscribe({
      error: () => { c.leido = false; }
    });
  }

  // ==========================================================
  // NOTAS (nivel servicio) — CRUD
  // ==========================================================
  cargarNotas(): void {
    if (!this.servicioId) return;
    this.cargandoNotas = true;
    this.errorNotas    = '';
    this.svc.getNotasServicio(this.servicioId).subscribe({
      next: (res: any) => {
        const list = Array.isArray(res) ? res : (res?.notas ?? []);
        this.notas = list.map((n: any) => ({
          id:           n.id,
          descripcion:  n.descripcion ?? '',
          autor:        n.autor ?? 'Usuario',
          autor_id:     n.autor_id ?? null,
          fecha:        n.fecha ?? '—',
          puede_editar: !!n.puede_editar,
        }));
        this.cargandoNotas = false;
      },
      error: (err: any) => {
        this.errorNotas = err?.error?.detail ?? 'No se pudieron cargar las notas.';
        this.cargandoNotas = false;
      }
    });
  }

  agregarNota(): void {
    if (!this.servicioId) return;
    const texto = this.nuevaNota.trim();
    if (!texto) { return; }
    this.guardandoNota = true;
    this.svc.agregarNota(this.servicioId, { descripcion: texto }).subscribe({
      next: () => {
        this.guardandoNota = false;
        this.nuevaNota = '';
        this.toast.mostrar('Nota agregada', 'success');
        this.cargarNotas();
      },
      error: (err: any) => {
        this.guardandoNota = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo agregar la nota.', 'error');
      }
    });
  }

  iniciarEdicionNota(n: NotaItem): void {
    this.notaEditandoId = n.id;
    this.notaEditTexto  = n.descripcion;
  }

  cancelarEdicionNota(): void {
    this.notaEditandoId = null;
    this.notaEditTexto  = '';
  }

  guardarEdicionNota(n: NotaItem): void {
    const texto = this.notaEditTexto.trim();
    if (!texto) { return; }
    this.svc.actualizarNota(n.id, { descripcion: texto }).subscribe({
      next: () => {
        n.descripcion = texto;
        this.notaEditandoId = null;
        this.notaEditTexto  = '';
        this.toast.mostrar('Nota actualizada', 'success');
      },
      error: (err: any) => {
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo actualizar la nota.', 'error');
      }
    });
  }

  eliminarNota(n: NotaItem): void {
    this.notaEliminandoId = n.id;
    this.svc.eliminarNota(n.id).subscribe({
      next: () => {
        this.notas = this.notas.filter(x => x.id !== n.id);
        this.notaEliminandoId = null;
        this.toast.mostrar('Nota eliminada', 'success');
      },
      error: (err: any) => {
        this.notaEliminandoId = null;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo eliminar la nota.', 'error');
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

  private _conectarChat(servicioId: string): void {
    const token  = localStorage.getItem('ezyro_token') ?? '';
    const wsBase = environment.apiUrl.replace(/^http/, 'ws');
    this.chatSub?.unsubscribe();
    this.chatSocket$?.complete();

    this.chatSocket$ = webSocket<unknown>(
      `${wsBase}/ws/chat/servicio/${servicioId}?token=${token}`
    );

    this.chatSub = this.chatSocket$.subscribe({
      next: (msg: any) => {
        if (msg.tipo === 'historial') {
          this.chatMensajes = (msg.mensajes ?? []).map((m: any) => this._mapMensaje(m));
          this._scrollPending = true;
          return;
        }
        if (msg.tipo === 'error') return;
        if (msg.tipo === 'borrador_actualizado') {
          this.cargarBorrador();
          return;
        }
        if (msg.tipo === 'requerimiento_actualizado') {
          this.cargarReqsListos();
          return;
        }
        if (msg.tipo === 'servicio_completado_retorno') {
          // El servicio fue completado — todos deben saber que hay retorno pendiente
          if (this.servicio) this.servicio.estado = 'Completado';
          if (this.soyJefeOperaciones) {
            // El jefe ya abrió el modal al finalizar — no duplicar
          } else {
            // Técnicos: mostrar alerta prominente con botón para abrir el modal
            this.alertaRetornoPendiente = true;
            this.toast.mostrar('¡Servicio completado! Debes registrar la devolución de materiales.', 'info');
          }
          return;
        }
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

  getChatMemberFoto(remitenteId?: string): string {
    if (!remitenteId) return '';
    return this.servicio?.equipo.find(m => m.id === remitenteId)?.fotoUrl ?? '';
  }

  get _fotoUsuario(): string {
    try {
      const stored = localStorage.getItem('ezyro_user');
      return stored ? (JSON.parse(stored)?.foto_url ?? '') : '';
    } catch { return ''; }
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
        id:           p.id,
        nombre:       p.nombre,
        descripcion:  p.descripcion,
        orden:        p.orden,
        estado:       p.estado,
        responsableId: p.responsable_id ?? null,
        evidencias:  (p.evidencias ?? []).map((e: any) => ({
          id:            e.id,
          urlCloudinary: e.url_cloudinary,
          descripcion:   e.descripcion,
          fechaCaptura:  e.fecha_captura,
          etapa:         (e.etapa as 'antes' | 'durante' | 'despues') ?? 'antes'
        }))
      })),
      itemsAsignados:   this._mapItems(raw.materiales_asignados),
      itemsSolicitados: this._mapItems(raw.materiales_solicitados),
      zonaEjecucion:   raw.zona_ejecucion ?? null,
      esMantenimiento: raw.es_mantenimiento ?? false,
    };
  }

  private _mapItems(list: any[]): ItemMaterial[] {
    return (list ?? []).map((m: any) => ({
      id:              m.id,
      requerimientoId: m.requerimiento_id,
      nombre:          m.nombre,
      unidad:          m.unidad ?? 'Unidades',
      cantidad:        m.cantidad,
      estadoReq:       m.estado_req,
      clase:           (m.tipo ?? 'material') as 'material' | 'herramienta' | 'equipo',
      estadoEquipo:    m.estado_equipo ?? m.estado ?? undefined,
      equipoId:        m.equipo_id ?? null,
      numeroSerie:     m.numero_serie ?? null,
    }));
  }

  claseLabel(clase?: string): string {
    const m: Record<string, string> = { material: 'Material', herramienta: 'Herramienta', equipo: 'Equipo' };
    return m[clase ?? 'material'] ?? 'Material';
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
    if (this.soyJefeOperaciones) {
      this._pendingProcRef   = proc;
      this._pendingEstado    = nuevoEstado as 'completado' | 'pendiente';
      this._pendingEstadoPrev = proc.estado;
      this.showJustModal = true;
      return;
    }
    this._doToggleProcedimiento(proc, nuevoEstado as 'completado' | 'pendiente', proc.estado);
  }

  private _doToggleProcedimiento(proc: Procedimiento, nuevoEstado: Procedimiento['estado'], prevEstado: string, justificacion?: string): void {
    proc.estado = nuevoEstado;
    this.recalcularProgreso();
    this.svc.toggleProcedimiento(proc.id, nuevoEstado, justificacion).subscribe({
      error: () => {
        proc.estado = prevEstado as Procedimiento['estado'];
        this.recalcularProgreso();
      }
    });
  }

  onJustTareaConfirmado(justificacion: string): void {
    this.showJustModal = false;
    if (this._pendingProcRef) {
      this._doToggleProcedimiento(this._pendingProcRef, this._pendingEstado, this._pendingEstadoPrev, justificacion);
    }
    this._pendingProcRef = null;
  }

  onJustTareaCancelado(): void {
    this.showJustModal = false;
    this._pendingProcRef = null;
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
    document.body.style.overflow = 'hidden';
  }

  cerrarModalEvidencia(): void {
    this.showModalEvidencia  = false;
    this.procedimientoActivo = null;
    document.body.style.overflow = '';
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
    document.body.style.overflow = 'hidden';
  }

  cerrarModalEditarMat(): void {
    this.showModalEditarMat = false;
    this.materialActivo     = null;
    document.body.style.overflow = '';
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
    this.tabSolicitar        = 'materiales';
    this.busquedaMaterial    = '';
    this.resultadosBusqueda  = [];
    this.materialElegido     = null;
    this.cantidadSolicitar   = 1;
    this.busquedaEquipo      = '';
    this.resultadosEquipos   = [];
    this.equipoElegido       = null;
    this.cantidadEquipo      = 1;
    this.manualNombre          = '';
    this.manualCantidad        = 1;
    this.manualUnidad          = 'Unidades';
    this.manualEspecificacion  = '';
    this.manualTipoItem        = 'material';
    this.manualPrecioEstimado  = null;
    this.showModalSolicitar    = true;
    document.body.style.overflow = 'hidden';
  }

  cerrarModalSolicitar(): void { this.showModalSolicitar = false; document.body.style.overflow = ''; }

  // ── Incidencia ───────────────────────────────────────────────────────
  abrirIncidencia(): void {
    this.incEquipoId         = '';
    this.incEquipoNombre     = '';
    this.incEquipoClase      = 'equipo';
    this.incEquipoSinSerie   = false;
    this.incNumeroSerie      = '';
    this.incCantidadAfectada = 1;
    this.incTipoFalla        = 'otro';
    this.incDescripcion      = '';
    this.showModalIncidencia = true;
    document.body.style.overflow = 'hidden';
    // Usar ítems del servicio (equipos y herramientas con equipo_id)
    const todos = [
      ...(this.servicio?.itemsAsignados   ?? []),
      ...(this.servicio?.itemsSolicitados ?? []),
    ];
    this.incListaEquipos = todos
      .filter(it => it.clase === 'equipo' || it.clase === 'herramienta')
      .filter(it => !!it.equipoId)
      .map(it => ({
        id:          it.equipoId!,
        nombre:      it.nombre,
        clase:       it.clase!,
        numeroSerie: it.numeroSerie ?? null,
      }));
    // Deduplicar por equipo_id
    this.incListaEquipos = this.incListaEquipos.filter(
      (e, i, arr) => arr.findIndex(x => x.id === e.id) === i
    );
    this.incCargandoEquipos = false;
  }

  cerrarIncidencia(): void {
    this.showModalIncidencia = false;
    document.body.style.overflow = '';
  }

  onSeleccionarEquipoInc(id: string): void {
    this.incEquipoId = id;
    const eq = this.incListaEquipos.find(e => e.id === id);
    if (eq) {
      this.incEquipoNombre    = eq.nombre;
      this.incEquipoClase     = eq.clase as 'equipo' | 'herramienta';
      this.incEquipoSinSerie  = !eq.numeroSerie?.trim();
      this.incNumeroSerie     = eq.numeroSerie ?? '';
    }
  }

  enviarIncidencia(): void {
    if (!this.incEquipoId || !this.incDescripcion.trim() || this.enviandoIncidencia) return;
    this.enviandoIncidencia = true;
    this.logistica.crearIncidencia({
      equipoId:           this.incEquipoId,
      proyectoServicioId: this.servicioId,
      numeroSerie:        this.incNumeroSerie.trim() || null,
      cantidadAfectada:   this.incEquipoClase === 'herramienta' ? this.incCantidadAfectada : 1,
      tipoFalla:          this.incTipoFalla,
      descripcion:        this.incDescripcion.trim(),
    }).subscribe({
      next: () => {
        this.enviandoIncidencia  = false;
        this.toast.mostrar('Incidencia reportada. Logística recibirá el aviso.', 'success');
        this.cerrarIncidencia();
      },
      error: err => {
        this.enviandoIncidencia = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al reportar la incidencia.', 'error');
      },
    });
  }

  // ── Verificación automática de retorno al cargar servicio completado ──
  private _verificarRetornoPendiente(servicioId: string): void {
    this.logistica.checkRetornoServicio(servicioId).subscribe({
      next: res => {
        if (!res.tieneRetorno) {
          // Esperar a que reqsListos se cargue y luego abrir el modal obligatorio
          setTimeout(() => {
            this.retornoObligatorio     = true;
            this.alertaRetornoPendiente = true;
            this.abrirModalRetorno();
          }, 800);
        }
      },
      error: () => { /* silencioso — no bloquear la vista si falla */ }
    });
  }

  // ── Retorno ──────────────────────────────────────────────────────────
  abrirModalRetorno(): void {
    if (!this.servicioId || !this.servicio) return;
    this.retornoServicioId  = this.servicioId;
    this.retornoNotaTecnico = '';
    this.alertaRetornoPendiente = false;

    // Agregar TODOS los ítems aprobados de TODOS los requerimientos del servicio
    const todosLosReqs = [
      ...this.reqsListos,
      ...(this.reqsEntregados ?? []),
    ];
    const vistos = new Set<string>();
    this.retornoItems = [];
    for (const req of todosLosReqs) {
      for (const it of req.items.filter(i => i.estadoItem === 'aprobado')) {
        if (vistos.has(it.id)) continue;
        vistos.add(it.id);
        const tipo = (it as any).tipoItemCompra || 'material';
        const esOblig = ['equipo','herramienta'].includes(tipo);
        this.retornoItems.push({
          detalleId:         it.id,
          nombre:            it.nombre,
          unidad:            it.unidad,
          tipoItem:          tipo,
          esObligatorio:     esOblig,
          cantidadEntregada: it.cantidadAprobada ?? it.cantidad,
          cantidadRetornada: esOblig ? (it.cantidadAprobada ?? it.cantidad) : 0,
        });
      }
    }
    this.showModalRetorno = true;
    document.body.style.overflow = 'hidden';
  }

  intentarCerrarRetorno(): void {
    // Si es obligatorio, no se puede cerrar sin completarlo
    if (this.retornoObligatorio) return;
    this.cerrarModalRetorno();
  }

  cerrarModalRetorno(): void {
    this.showModalRetorno        = false;
    this.retornoObligatorio      = false;
    this.retornoItems            = [];
    document.body.style.overflow = '';
  }

  retornoTodosObligatorios(): void {
    this.retornoItems.forEach(it => {
      if (it.esObligatorio) it.cantidadRetornada = it.cantidadEntregada;
    });
  }

  /** Un clic: declara que nada retorna (todo fue consumible). Si hay ítems
   * obligatorios (equipos/herramientas), la validación en enviarRetorno()
   * sigue exigiendo que se complete su devolución — este botón solo agiliza
   * el caso común de servicios sin equipos/herramientas pendientes. */
  retornoNadaVuelve(): void {
    this.retornoItems.forEach(it => { it.cantidadRetornada = 0; });
  }

  enviarRetorno(): void {
    if (!this.retornoServicioId || this.enviandoRetorno) return;

    // Validar que los obligatorios tengan cantidad > 0
    const obligSinRetorno = this.retornoItems.filter(
      it => it.esObligatorio && it.cantidadRetornada <= 0
    );
    if (obligSinRetorno.length > 0) {
      this.toast.mostrar(
        `Debes indicar la cantidad a devolver de: ${obligSinRetorno.map(i => i.nombre).join(', ')}`,
        'error'
      );
      return;
    }

    this.enviandoRetorno = true;
    this.logistica.crearRetornoDesdeServicio({
      proyectoServicioId: this.retornoServicioId,
      items: this.retornoItems.map(it => ({ detalleId: it.detalleId, cantidadRetornada: it.cantidadRetornada })),
      notaTecnico: this.retornoNotaTecnico.trim() || undefined,
    }).subscribe({
      next: () => {
        this.enviandoRetorno         = false;
        this.retornoObligatorio      = false;
        this.alertaRetornoPendiente  = false;
        this.toast.mostrar('Devolución registrada correctamente. Logística recibirá los ítems.', 'success');
        this.cerrarModalRetorno();
      },
      error: err => {
        this.enviandoRetorno = false;
        if (err?.status === 409) {
          // Otro técnico ya lo registró — se cierra el modal obligatorio
          this.retornoObligatorio     = false;
          this.alertaRetornoPendiente = false;
          this.toast.mostrar('La devolución ya fue registrada por otro técnico del equipo.', 'info');
          this.cerrarModalRetorno();
        } else {
          this.toast.mostrar(err?.error?.detail ?? 'Error al registrar la devolución.', 'error');
        }
      },
    });
  }

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

  buscarEquipos(): void {
    const q = this.busquedaEquipo.trim();
    if (q.length < 2) { this.resultadosEquipos = []; return; }
    this.buscandoEquipo = true;
    this.logistica.getEquipos({ q }).subscribe({
      next: items => {
        this.resultadosEquipos = items
          .filter(e => e.estado === 'operativo')
          .map(e => ({ id: e.id, nombre: e.nombre, clase: e.clase, cantidad: e.cantidad, estado: e.estado }));
        this.buscandoEquipo = false;
      },
      error: () => { this.buscandoEquipo = false; }
    });
  }

  elegirEquipo(eq: { id: string; nombre: string; clase: string; cantidad: number; estado: string }): void {
    this.equipoElegido    = eq;
    this.busquedaEquipo   = eq.nombre;
    this.resultadosEquipos = [];
    this.cantidadEquipo   = 1;
  }

  solicitarEquipo(): void {
    if (!this.equipoElegido || !this.servicioId) return;
    this.solicitando = true;
    const eq = this.equipoElegido;
    this.svc.agregarItemBorrador(this.servicioId, {
      material_id:      null,
      nombre:           eq.nombre,
      unidad:           'Unidades',
      cantidad:         this.cantidadEquipo,
      especificacion:   `[${eq.clase === 'equipo' ? 'Equipo' : 'Herramienta'}] ${eq.nombre} del inventario`,
      tipo_item_compra: eq.clase,
    }).subscribe({
      next: (res: any) => {
        this.materialesBorrador.push({
          id:              res.detalle_id,
          material_id:     null,
          nombre:          eq.nombre,
          unidad:          'Unidades',
          cantidad:        this.cantidadEquipo,
          esNuevo:         false,
          clase:           eq.clase as 'herramienta' | 'equipo',
          agregadoPor:     this._nombreUsuario,
          agregadoPorFoto: this._usuarioFoto,
          especificacion:  `[${eq.clase}] ${eq.nombre}`,
        });
        this.equipoElegido    = null;
        this.busquedaEquipo   = '';
        this.resultadosEquipos = [];
        this.cantidadEquipo   = 1;
        this.solicitando      = false;
      },
      error: () => { this.solicitando = false; }
    });
  }

  solicitarMaterial(): void {
    if (!this.materialElegido || !this.servicioId) return;
    this.solicitando = true;
    const mat = this.materialElegido;
    this.svc.agregarItemBorrador(this.servicioId, {
      material_id: mat.id,
      nombre:      mat.nombre,
      unidad:      mat.unidad,
      cantidad:    this.cantidadSolicitar,
    }).subscribe({
      next: (res: any) => {
        this.materialesBorrador.push({
          id:              res.detalle_id,
          material_id:     mat.id,
          nombre:          mat.nombre,
          unidad:          mat.unidad,
          cantidad:        this.cantidadSolicitar,
          esNuevo:         false,
          agregadoPor:     this._nombreUsuario,
          agregadoPorFoto: this._usuarioFoto,
        });
        this.materialElegido    = null;
        this.busquedaMaterial   = '';
        this.resultadosBusqueda = [];
        this.cantidadSolicitar  = 1;
        this.solicitando        = false;
      },
      error: () => { this.solicitando = false; }
    });
  }

  solicitarMaterialManual(): void {
    if (!this.manualNombre.trim() || !this.manualEspecificacion.trim() || this.manualCantidad < 1 || !this.servicioId) return;
    this.solicitando = true;
    const nombre = this.manualNombre.trim();
    const espec  = this.manualEspecificacion.trim();
    this.svc.agregarItemBorrador(this.servicioId, {
      material_id:      null,
      nombre,
      unidad:           this.manualUnidad,
      cantidad:         this.manualCantidad,
      especificacion:   espec,
      tipo_item_compra: this.manualTipoItem,
      precio_estimado:  this.manualPrecioEstimado ?? undefined,
    }).subscribe({
      next: (res: any) => {
        this.materialesBorrador.push({
          id:              res.detalle_id,
          material_id:     null,
          nombre,
          unidad:          this.manualUnidad,
          cantidad:        this.manualCantidad,
          esNuevo:         true,
          agregadoPor:     this._nombreUsuario,
          agregadoPorFoto: this._usuarioFoto,
          especificacion:  espec,
        });
        this.manualNombre          = '';
        this.manualCantidad        = 1;
        this.manualUnidad          = 'Unidades';
        this.manualEspecificacion  = '';
        this.manualTipoItem        = 'material';
        this.manualPrecioEstimado  = null;
        this.solicitando           = false;
      },
      error: () => { this.solicitando = false; }
    });
  }

  editarItemBorrador(index: number): void {
    const item = this.materialesBorrador[index];
    this.editandoIndice     = index;
    this.editCantBorrador   = item.cantidad;
    this.editNombreBorrador = item.nombre;
    this.editEspecBorrador  = item.especificacion ?? '';
  }

  cancelarEdicionBorrador(): void {
    this.editandoIndice = null;
  }

  guardarEdicionBorrador(index: number): void {
    const item = this.materialesBorrador[index];
    if (this.editCantBorrador < 1) return;
    const body: any = { cantidad: this.editCantBorrador };
    if (item.esNuevo) {
      body.nombre         = this.editNombreBorrador.trim() || item.nombre;
      body.especificacion = this.editEspecBorrador.trim();
    }
    this.svc.actualizarRequerimientoDetalle(item.id, body).subscribe({
      next: () => {
        item.cantidad = this.editCantBorrador;
        if (item.esNuevo) {
          item.nombre         = body.nombre;
          item.especificacion = body.especificacion;
        }
        this.editandoIndice = null;
      }
    });
  }

  removerDelBorrador(index: number): void {
    const item = this.materialesBorrador[index];
    this.svc.removerItemBorrador(item.id).subscribe({
      next: () => {
        this.materialesBorrador.splice(index, 1);
        if (this.materialesBorrador.length === 0) this.consensoEquipo = false;
      }
    });
  }

  enviarSolicitudLote(): void {
    if (!this.servicio || this.materialesBorrador.length === 0) return;
    this.enviandoLote = true;
    this.svc.enviarBorrador(this.servicio.id).subscribe({
      next: () => {
        this.materialesBorrador = [];
        this.consensoEquipo     = false;
        this.enviandoLote       = false;
        this.cargarDetalle();
      },
      error: () => {
        this.enviandoLote = false;
        this.toast.mostrar('Hubo un error al enviar el borrador a Logística.', 'error');
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

      if (s.itemsAsignados.length > 0) {
        checkPage(26);
        page.drawText('Materiales y Herramientas Asignados Originalmente',
          { x: ML, y, size: 8.5, font: bold, color: INK });
        y -= 14;
        renderMatTable(s.itemsAsignados);
        y -= 8;
      }

      const matsExtra = s.itemsSolicitados.filter((m: ItemMaterial) => ['aprobado', 'entregado'].includes(m.estadoReq));
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
      this.toast.mostrar('Acceso denegado: solo el Jefe de Operaciones puede finalizar y cerrar este servicio.', 'error');
      return;
    }

    if (!this.todasCompletadas || !this.servicio) return;

    this.svc.actualizarEstado(this.servicio.id, 'Completado').subscribe({
      next: () => {
        this.servicio!.estado = 'Completado';
        // Esperar un ciclo para que reqsListos y reqsEntregados estén actualizados,
        // luego abrir el modal de retorno obligatorio
        setTimeout(() => this.abrirModalRetorno(), 400);
      }
    });
    await this.abrirModalPreInforme();
  }
}

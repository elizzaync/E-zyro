import {
  Component, Input, Output, EventEmitter,
  OnInit, OnDestroy, inject, HostListener
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, FormArray, Validators } from '@angular/forms';
import { FormsModule } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';

import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

// ─── Interfaces ─────────────────────────────────────────────────────────────

export interface TecnicoDisponible {
  id: string;
  usuarioId: string;
  nombre: string;
  apellido: string;
  cargo: string;
  fotoUrl: string;
  grupoNombre?: string | null;
  /** Nombre del grupo actual al que pertenece (HU-13 — alerta de conflicto). */
  grupoActual?: string | null;
}

export interface GrupoDisponible {
  id: string;
  nombre: string;
  jefeNombre: string;
  miembros: TecnicoDisponible[];
}

export interface TareaForm {
  id?: string;
  nombre: string;
  responsable_id: string;
  fecha_inicio: string;
  fecha_fin: string;
}

export interface ServicioResumen {
  id: string;
  nombre: string;
  descripcion: string | null;
  estado: string;
  cliente: string;
  ubicacion: string;
  fechaStr: string;
}

/** Resultado de validación de cruce para una tarea */
export interface CruceState {
  validando: boolean;
  conflicto: boolean;
  mensaje: string;
}

// ─── Componente ──────────────────────────────────────────────────────────────

@Component({
  selector: 'app-asignacion-servicio-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule, SpinnerComponent],
  templateUrl: './asignacion-servicio-modal.component.html',
  styleUrls: ['./asignacion-servicio-modal.component.css']
})
export class AsignacionServicioModalComponent implements OnInit, OnDestroy {

  // ── Inputs / Outputs ─────────────────────────────────────────────────────
  @Input() servicioId!: string;       // ID del servicio a configurar
  @Input() mode: 'crear' | 'editar' = 'crear';
  @Output() closed = new EventEmitter<{ guardado: boolean }>();

  // ── DI ───────────────────────────────────────────────────────────────────
  private fb  = inject(FormBuilder);
  private svc = inject(OperacionesService);
  private destroy$ = new Subject<void>();

  // ── Estado del usuario logueado ──────────────────────────────────────────
  usuarioActual = { id: '', nombre: 'Cargando...', rol: '', fotoUrl: '' };

  // ── Datos de la vista ────────────────────────────────────────────────────
  servicio: ServicioResumen | null = null;
  cargandoServicio = false;

  // ── Líder del servicio (el asignado al CREAR el servicio, no el usuario logueado) ──
  liderId           = '';
  liderNombre       = '';
  liderCargo        = '';
  liderFoto         = '';
  // Técnico Líder (opcional: puede venir de la creación o asignarse aquí)
  tecnicoLiderId     = '';
  tecnicoLiderNombre = '';
  tecnicoLiderCargo  = '';
  /** Candidatos a Técnico Líder (para el selector del Paso 1). */
  responsablesOpciones: { id: string; nombre: string; apellido: string; cargo: string }[] = [];

  /** empleado.id → datos básicos, para resolver nombre/foto del líder y técnico líder. */
  private _personasMap = new Map<string, { nombre: string; apellido: string; cargo: string; fotoUrl: string }>();

  // Técnicos — source of truth (never mutated after load)
  todosTecnicos: TecnicoDisponible[]     = [];
  // Renderizado en la columna izquierda (disponibles minus seleccionados, filtrado por búsqueda)
  tecnicosFiltrados: TecnicoDisponible[] = [];
  equipoSeleccionado: TecnicoDisponible[] = [];
  grupos: GrupoDisponible[] = [];
  busquedaTecnico   = '';
  cargandoTecnicos  = false;
  errorCargaTecnicos = false;   // true cuando el API de técnicos falla

  // ── Validación de cruces de horario (Paso 3) ─────────────────────────────
  /** Estado de validación de cruce por índice de tarea. */
  cruceEstados: CruceState[] = [];

  // UI
  seccionActiva: 1 | 2 | 3 = 1;
  guardando  = false;
  errorMsg   = '';
  successMsg = '';

  // ── HU-13: confirmación de añadir técnico que ya pertenece a un grupo ──
  confirmGrupoOpen = false;
  confirmGrupoTecnico: TecnicoDisponible | null = null;

  // ── Formulario ───────────────────────────────────────────────────────────
  form!: FormGroup;

  get procedimientosArray(): FormArray {
    return this.form.get('procedimientos') as FormArray;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPUTED — Auto-liderazgo
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Devuelve el empleado.id del usuario actualmente logueado.
   * Lo busca por `usuarioId` en la lista de técnicos cargados desde el API.
   * Retorna '' si el usuario no figura como empleado activo de la empresa.
   */
  get currentUserEmpleadoId(): string {
    if (!this.usuarioActual.id) return '';
    return this.todosTecnicos.find(t => t.usuarioId === this.usuarioActual.id)?.id ?? '';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this._cargarUsuario();
    this._initForm();
    this._cargarTecnicos();
    this._cargarLideresYResponsables();
    this._cargarServicio();
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
    document.body.style.overflow = '';
  }

  @HostListener('document:keydown.escape')
  onEsc(): void { this.cerrar(); }

  // ─────────────────────────────────────────────────────────────────────────
  // INICIALIZACIÓN
  // ─────────────────────────────────────────────────────────────────────────

  private _cargarUsuario(): void {
    try {
      const stored = localStorage.getItem('ezyro_user');
      if (stored) {
        const u = JSON.parse(stored);
        this.usuarioActual = {
          id:      u.id              ?? '',
          nombre:  u.nombre_completo ?? 'Jefe de Operaciones',
          rol:     u.rol             ?? '',
          fotoUrl: u.foto_url        ?? ''
        };
      }
    } catch { /* ignore */ }
  }

  private _initForm(): void {
    this.form = this.fb.group({ procedimientos: this.fb.array([]) });
    this._agregarTareaVacia(); // al menos 1
  }

  private _cargarServicio(): void {
    this.cargandoServicio = true;
    this.svc.getDetalleServicio(this.servicioId).pipe(takeUntil(this.destroy$)).subscribe({
      next: (raw: any) => {
        this.servicio = {
          id:          raw.id,
          nombre:      raw.tipo_servicio ?? raw.nombre ?? 'Servicio',
          descripcion: raw.descripcion   ?? null,
          estado:      raw.estado,
          cliente:     raw.cliente       ?? '—',
          ubicacion:   raw.ubicacion     ?? '—',
          fechaStr:    raw.fecha_str     ?? '—',
        };

        // Líder y técnico líder definidos al crear el servicio (concordancia)
        this.liderId            = String(raw.lider_id ?? '');
        this.liderNombre        = String(raw.lider_nombre ?? '');
        this.liderCargo         = String(raw.lider_cargo ?? '');
        this.liderFoto          = String(raw.lider_foto ?? raw.lider_foto_url ?? '');
        this.tecnicoLiderId     = String(raw.responsable_id ?? '');
        this.tecnicoLiderNombre = String(raw.responsable_nombre ?? '');
        this.tecnicoLiderCargo  = String(raw.responsable_cargo ?? '');
        this._resolverLider();

        // Modo editar: precarga equipo y procedimientos existentes
        if (this.mode === 'editar') {
          this._precargarEquipo(raw.equipo ?? []);
          this._precargarProcedimientos(raw.procedimientos ?? []);
        }
        this.cargandoServicio = false;
      },
      error: () => { this.cargandoServicio = false; }
    });
  }

  /**
   * Carga las listas de posibles líderes y responsables para poder resolver
   * el nombre/foto del líder asignado al servicio a partir de su `lider_id`.
   */
  private _cargarLideresYResponsables(): void {
    this.svc.getLideresServicio().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        this._indexarPersonas(Array.isArray(res) ? res : (res?.lideres ?? []));
        this._resolverLider();
      }
    });
    this.svc.getResponsablesServicio().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        const lista = Array.isArray(res) ? res : (res?.responsables ?? []);
        this._indexarPersonas(lista);
        this.responsablesOpciones = (lista ?? []).map((p: any) => ({
          id:       String(p.id ?? p.usuario_id ?? ''),
          nombre:   String(p.nombre   ?? ''),
          apellido: String(p.apellido ?? ''),
          cargo:    String(p.cargo    ?? ''),
        })).filter((p: any) => p.id);
        this._resolverLider();
      }
    });
  }

  private _indexarPersonas(list: any[]): void {
    for (const p of list ?? []) {
      const id = String(p.id ?? p.usuario_id ?? '');
      if (!id) continue;
      this._personasMap.set(id, {
        nombre:   String(p.nombre   ?? ''),
        apellido: String(p.apellido ?? ''),
        cargo:    String(p.cargo    ?? ''),
        fotoUrl:  String(p.foto_url ?? ''),
      });
    }
  }

  /** Rellena nombre/foto del líder y técnico líder desde el mapa de personas. */
  private _resolverLider(): void {
    if (this.liderId) {
      const p = this._personasMap.get(this.liderId);
      if (p) {
        this.liderNombre = `${p.nombre} ${p.apellido}`.trim() || this.liderNombre;
        this.liderCargo  = p.cargo   || this.liderCargo;
        this.liderFoto   = p.fotoUrl || this.liderFoto;
      }
    }
    if (this.tecnicoLiderId) {
      const p = this._personasMap.get(this.tecnicoLiderId);
      if (p) {
        this.tecnicoLiderNombre = `${p.nombre} ${p.apellido}`.trim() || this.tecnicoLiderNombre;
        this.tecnicoLiderCargo  = p.cargo || this.tecnicoLiderCargo;
      }
    }
  }

  /** Cambio de Técnico Líder desde el selector ('' = sin asignar). */
  onTecnicoLiderChange(): void {
    this.tecnicoLiderNombre = '';
    this.tecnicoLiderCargo  = '';
    this._resolverLider();
  }

  /** true si el servicio ya trae un líder definido desde su creación. */
  get tieneLiderAsignado(): boolean {
    return !!this.liderId;
  }

  /** Nombre a mostrar: el líder asignado, o el usuario actual (que quedará como líder). */
  get liderDisplayNombre(): string {
    if (this.tieneLiderAsignado) return this.liderNombre || 'Líder asignado';
    return this.usuarioActual.nombre || 'Tú';
  }

  get liderDisplayFoto(): string {
    return this.tieneLiderAsignado ? this.liderFoto : this.usuarioActual.fotoUrl;
  }

  get liderDisplayCargo(): string {
    if (this.tieneLiderAsignado) return this.liderCargo || 'Líder asignado al crear el servicio';
    return 'Tú serás el líder — asignado al configurar este servicio';
  }

  getInicialesLider(): string {
    const p = (this.liderDisplayNombre || '').trim().split(/\s+/).filter(Boolean);
    if (p.length >= 2) return (p[0][0] + p[p.length - 1][0]).toUpperCase();
    return (p[0]?.[0] ?? 'L').toUpperCase();
  }

  private _cargarTecnicos(): void {
    this.cargandoTecnicos   = true;
    this.errorCargaTecnicos = false;

    this.svc.getPersonalTecnicos().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        // ── Técnicos planos ──────────────────────────────────────────────────
        const rawTecnicos = Array.isArray(res) ? res : (res?.tecnicos ?? []);
        this.todosTecnicos = rawTecnicos.map((t: any) => ({
          id:          String(t.id ?? ''),
          usuarioId:   String(t.usuario_id ?? ''),
          nombre:      String(t.nombre   ?? ''),
          apellido:    String(t.apellido ?? ''),
          cargo:       String(t.cargo    ?? 'Técnico'),
          fotoUrl:     String(t.foto_url ?? ''),
          grupoNombre: t.grupo_nombre ?? null,
          grupoActual: t.grupo_actual ?? t.grupo_nombre ?? null,   // HU-13
        }));

        // ── Grupos con miembros ──────────────────────────────────────────────
        const rawGrupos = Array.isArray(res) ? [] : (res?.grupos ?? []);
        this.grupos = rawGrupos.map((g: any) => ({
          id:         String(g.id ?? ''),
          nombre:     String(g.nombre ?? ''),
          jefeNombre: String(g.jefe_nombre ?? ''),
          miembros:   (g.miembros ?? []).map((m: any) => ({
            id:          String(m.id ?? ''),
            usuarioId:   String(m.usuario_id ?? ''),
            nombre:      String(m.nombre   ?? ''),
            apellido:    String(m.apellido ?? ''),
            cargo:       String(m.cargo    ?? 'Técnico'),
            fotoUrl:     String(m.foto_url ?? ''),
            grupoNombre: String(g.nombre ?? ''),
            grupoActual: String(g.nombre ?? ''),
          })),
        }));

        this.cargandoTecnicos = false;
        // Recalcula la lista disponible (excluye los ya seleccionados en modo editar)
        this.filtrarTecnicos();
      },
      error: () => {
        this.cargandoTecnicos   = false;
        this.errorCargaTecnicos = true;
      },
    });
  }

  private _precargarEquipo(equipo: any[]): void {
    // El detalle incluye al líder y técnico líder con roles propios; aquí solo
    // se precargan los MIEMBROS del equipo técnico (los roles van aparte).
    const soloMiembros = (equipo ?? []).filter((m: any) =>
      m.rol_proyecto !== 'Líder del Servicio' && m.rol_proyecto !== 'Técnico Líder'
    );
    this.equipoSeleccionado = soloMiembros.map((m: any) => ({
      id:          String(m.id ?? ''),
      usuarioId:   String(m.usuario_id ?? ''),
      nombre:      String(m.nombre   ?? ''),
      apellido:    String(m.apellido ?? ''),
      cargo:       String(m.cargo    ?? 'Técnico'),
      fotoUrl:     String(m.foto_url ?? ''),
      grupoNombre: m.grupo_nombre ?? null,
      grupoActual: m.grupo_actual ?? m.grupo_nombre ?? null,
    }));
    // Remueve los técnicos precargados de la columna izquierda
    this.filtrarTecnicos();
  }

  private _precargarProcedimientos(procs: any[]): void {
    // Limpia el array y recarga
    while (this.procedimientosArray.length) { this.procedimientosArray.removeAt(0); }
    this.cruceEstados = [];

    if (!procs.length) { this._agregarTareaVacia(); return; }

    procs.forEach((p: any) => {
      this.procedimientosArray.push(this.fb.group({
        id:             [p.id ?? null],
        nombre:         [p.nombre       ?? '', Validators.required],
        responsable_id: [p.responsable_id ?? '', Validators.required],
        // fecha_inicio_tarea → fecha_inicio, fecha_limite → fecha_fin
        fecha_inicio:   [this._isoDate(p.fecha_inicio_tarea ?? p.fecha_inicio), Validators.required],
        fecha_fin:      [this._isoDate(p.fecha_limite ?? p.fecha_fin),           Validators.required]
      }));
      this.cruceEstados.push({ validando: false, conflicto: false, mensaje: '' });
    });
  }

  private _agregarTareaVacia(): void {
    this.procedimientosArray.push(this.fb.group({
      id:             [null],
      nombre:         ['', Validators.required],
      responsable_id: ['', Validators.required],
      fecha_inicio:   ['', Validators.required],
      fecha_fin:      ['', Validators.required]
    }));
    this.cruceEstados.push({ validando: false, conflicto: false, mensaje: '' });
  }

  private _isoDate(d: string | null | undefined): string {
    if (!d) return '';
    return d.includes('T') ? d.split('T')[0] : d.trim();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TÉCNICOS
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Recalcula la columna izquierda.
   * Fuente: todosTecnicos MENOS los ya en equipoSeleccionado, luego filtra por búsqueda.
   * Debe llamarse después de CUALQUIER cambio en equipoSeleccionado o busquedaTecnico.
   */
  filtrarTecnicos(): void {
    // Pool disponible = todos los técnicos que aún no están seleccionados
    const disponibles = this.todosTecnicos.filter(t => !this.estaSeleccionado(t.id));
    const q = this.busquedaTecnico.toLowerCase().trim();
    this.tecnicosFiltrados = q
      ? disponibles.filter(t =>
          `${t.nombre} ${t.apellido}`.toLowerCase().includes(q) ||
          t.cargo.toLowerCase().includes(q) ||
          (t.grupoNombre ?? '').toLowerCase().includes(q)
        )
      : [...disponibles];
  }

  /** Total de técnicos disponibles (sin filtro de búsqueda, sin seleccionados). */
  get totalDisponibles(): number {
    return this.todosTecnicos.filter(t => !this.estaSeleccionado(t.id)).length;
  }

  /**
   * HU-13 — Alerta de grupo de trabajo.
   * Si el técnico pertenece a un grupo activo, pide confirmación antes de añadirlo.
   * Solo si el usuario acepta, lo mueve al panel derecho.
   */
  seleccionarTecnico(t: TecnicoDisponible): void {
    if (this.estaSeleccionado(t.id)) return;

    // Alerta solo si su grupo/servicio activo es OTRO (no el que se está configurando)
    if (t.grupoActual && t.grupoActual !== this.servicio?.nombre) {
      this.confirmGrupoTecnico = t;
      this.confirmGrupoOpen = true;
      return;
    }

    this._agregarTecnicoAlEquipo(t);
  }

  /** Confirma añadir el técnico que ya pertenece a un grupo activo. */
  confirmarAgregarConGrupo(): void {
    if (this.confirmGrupoTecnico) {
      this._agregarTecnicoAlEquipo(this.confirmGrupoTecnico);
    }
    this.cancelarAgregarConGrupo();
  }

  /** Cierra el modal de confirmación sin añadir al técnico. */
  cancelarAgregarConGrupo(): void {
    this.confirmGrupoOpen = false;
    this.confirmGrupoTecnico = null;
  }

  private _agregarTecnicoAlEquipo(t: TecnicoDisponible): void {
    this.equipoSeleccionado = [...this.equipoSeleccionado, t];
    this.filtrarTecnicos();
  }

  /**
   * Alias mantenido para compatibilidad con bindings de plantilla previos.
   */
  toggleTecnico(t: TecnicoDisponible): void {
    this.seleccionarTecnico(t);
  }

  /** Agrega todos los miembros de un grupo que todavía no estén seleccionados. */
  agregarGrupo(grupo: GrupoDisponible): void {
    let cambio = false;
    grupo.miembros.forEach(m => {
      if (!this.estaSeleccionado(m.id)) {
        this.equipoSeleccionado = [...this.equipoSeleccionado, m];
        cambio = true;
      }
    });
    if (cambio) this.filtrarTecnicos();
  }

  /**
   * Devuelve un técnico a la columna izquierda y limpia su asignación en el cronograma.
   */
  removerTecnico(id: string): void {
    this.equipoSeleccionado = this.equipoSeleccionado.filter(e => e.id !== id);
    this.procedimientosArray.controls.forEach((ctrl, i) => {
      if (ctrl.get('responsable_id')?.value === id) {
        ctrl.get('responsable_id')?.setValue('');
        // Limpiar advertencia de cruce para esa tarea
        if (this.cruceEstados[i]) {
          this.cruceEstados[i] = { validando: false, conflicto: false, mensaje: '' };
        }
      }
    });
    this.filtrarTecnicos();
  }

  estaSeleccionado(id: string): boolean {
    return this.equipoSeleccionado.some(e => e.id === id);
  }

  grupoTotalmenteSeleccionado(grupo: GrupoDisponible): boolean {
    return grupo.miembros.length > 0 && grupo.miembros.every(m => this.estaSeleccionado(m.id));
  }

  /** Vacía el equipo y devuelve a todos los técnicos a la columna izquierda. */
  limpiarEquipo(): void {
    this.equipoSeleccionado = [];
    this.procedimientosArray.controls.forEach(ctrl => {
      ctrl.get('responsable_id')?.setValue('');
    });
    // Resetear todas las advertencias de cruce
    this.cruceEstados = this.cruceEstados.map(() => ({ validando: false, conflicto: false, mensaje: '' }));
    this.filtrarTecnicos();
  }

  /** Reintentar carga de técnicos tras un error de red. */
  reintentarCargaTecnicos(): void {
    this.todosTecnicos     = [];
    this.tecnicosFiltrados = [];
    this.grupos            = [];
    this._cargarTecnicos();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VALIDACIÓN DE CRUCE DE HORARIOS (HU-13 — Paso 3)
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Llama al backend para verificar si el técnico asignado a la tarea `i`
   * tiene conflicto de horario con las fechas seleccionadas.
   * Se activa con (change) en responsable_id, fecha_inicio y fecha_fin.
   */
  validarCruceHorario(i: number): void {
    const ctrl = this.procedimientosArray.at(i);
    const responsableId = ctrl.get('responsable_id')?.value as string;
    const fechaInicio   = ctrl.get('fecha_inicio')?.value   as string;
    const fechaFin      = ctrl.get('fecha_fin')?.value       as string;

    // Solo validar cuando los tres campos están completos
    if (!responsableId || !fechaInicio || !fechaFin) {
      if (this.cruceEstados[i]) {
        this.cruceEstados[i] = { validando: false, conflicto: false, mensaje: '' };
      }
      return;
    }

    // Marcar como "validando"
    this.cruceEstados[i] = { validando: true, conflicto: false, mensaje: '' };

    this.svc.validarHorario({
      empleado_id:          responsableId,
      fecha_inicio:         fechaInicio,
      fecha_fin:            fechaFin,
      excluir_servicio_id:  this.servicioId,   // no reportar conflictos del mismo servicio
    }).pipe(takeUntil(this.destroy$)).subscribe({
      next: (res) => {
        if (res.conflicto && res.detalle) {
          this.cruceEstados[i] = {
            validando: false,
            conflicto: true,
            mensaje:
              `⚠ El técnico ya tiene la tarea "${res.detalle.tarea}" en ` +
              `"${res.detalle.servicio_nombre}" (${res.detalle.fecha_inicio} → ` +
              `${res.detalle.fecha_fin}).`,
          };
        } else {
          this.cruceEstados[i] = { validando: false, conflicto: false, mensaje: '' };
        }
      },
      error: () => {
        // No bloquear al usuario si el endpoint falla
        this.cruceEstados[i] = { validando: false, conflicto: false, mensaje: '' };
      },
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAREAS (FormArray)
  // ─────────────────────────────────────────────────────────────────────────

  agregarTarea(): void { this._agregarTareaVacia(); }

  removerTarea(i: number): void {
    if (this.procedimientosArray.length > 1) {
      this.procedimientosArray.removeAt(i);
      this.cruceEstados.splice(i, 1);
    }
  }

  getTareaCtrl(i: number, campo: string) {
    return this.procedimientosArray.at(i).get(campo);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WIZARD
  // ─────────────────────────────────────────────────────────────────────────

  irSeccion(n: 1 | 2 | 3): void { this.seccionActiva = n; this.errorMsg = ''; }

  siguiente(): void {
    this.errorMsg = '';
    if (this.seccionActiva === 1 && !this.servicio) {
      this.errorMsg = 'El servicio no ha cargado aún. Espera un momento.';
      return;
    }
    if (this.seccionActiva < 3) {
      this.seccionActiva = (this.seccionActiva + 1) as 1 | 2 | 3;
    }
  }

  anterior(): void {
    if (this.seccionActiva > 1) {
      this.seccionActiva = (this.seccionActiva - 1) as 1 | 2 | 3;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GUARDAR
  // ─────────────────────────────────────────────────────────────────────────

  guardar(): void {
    this.errorMsg = '';

    if (this.equipoSeleccionado.length === 0) {
      this.errorMsg = 'Debe asignar al menos un técnico al equipo.';
      this.irSeccion(2);
      return;
    }

    this.form.markAllAsTouched();
    if (this.form.invalid) {
      this.errorMsg = 'Completa todos los campos requeridos en el cronograma.';
      this.irSeccion(3);
      return;
    }

    // Validar que las fechas de fin sean >= inicio
    let fechasValidas = true;
    this.procedimientosArray.controls.forEach((ctrl, i) => {
      const ini = ctrl.get('fecha_inicio')?.value;
      const fin = ctrl.get('fecha_fin')?.value;
      if (ini && fin && fin < ini) {
        fechasValidas = false;
        ctrl.get('fecha_fin')?.setErrors({ rangeError: true });
      }
    });
    if (!fechasValidas) {
      this.errorMsg = 'La fecha de fin no puede ser anterior a la de inicio.';
      this.irSeccion(3);
      return;
    }

    this.guardando = true;

    const payload = {
      equipo:  this.equipoSeleccionado.map(e => e.id),
      // El líder es el asignado al CREAR el servicio (no el usuario logueado).
      // Respaldo al usuario actual solo si el servicio no tiene líder definido;
      // si tampoco hay, el backend reclama al usuario del JWT automáticamente.
      lider_id: this.liderId || this.currentUserEmpleadoId || undefined,
      // Técnico Líder: opcional; '' indica explícitamente "sin técnico líder".
      responsable_id: this.tecnicoLiderId || '',
      procedimientos: this.procedimientosArray.value.map((p: TareaForm) => ({
        ...(p.id ? { id: p.id } : {}),
        nombre:         p.nombre,
        responsable_id: p.responsable_id,
        fecha_inicio:   p.fecha_inicio,
        fecha_fin:      p.fecha_fin
      }))
    };

    this.svc.configurarServicio(this.servicioId, payload)
      .pipe(takeUntil(this.destroy$))
      .subscribe({
        next: () => {
          this.guardando = false;
          this.closed.emit({ guardado: true });
        },
        error: (err: any) => {
          this.guardando = false;
          this.errorMsg = err?.error?.detail ?? 'Error al guardar. Intenta nuevamente.';
        }
      });
  }

  cerrar(): void { this.closed.emit({ guardado: false }); }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS DE VISTA
  // ─────────────────────────────────────────────────────────────────────────

  getIniciales(t: TecnicoDisponible): string {
    return (t.nombre[0] + (t.apellido[0] ?? '')).toUpperCase();
  }

  getColorAvatar(id: string): string {
    const palette = ['#91d337','#3b82f6','#8b5cf6','#f59e0b','#06b6d4','#ec4899','#ef4444','#14b8a6'];
    let h = 0;
    for (let i = 0; i < id.length; i++) h = id.charCodeAt(i) + ((h << 5) - h);
    return palette[Math.abs(h) % palette.length];
  }

  estadoBadgeClass(estado: string): string {
    const m: Record<string, string> = {
      'Pendiente':  'badge-pendiente',
      'En_Proceso': 'badge-proceso',
      'Completado': 'badge-completado',
      'Cancelado':  'badge-cancelado',
    };
    return m[estado] ?? 'badge-pendiente';
  }

  estadoLabel(estado: string): string {
    return estado === 'En_Proceso' ? 'En Proceso' : estado;
  }

  get pasoCompleto1(): boolean { return !!this.servicio; }
  get pasoCompleto2(): boolean { return this.equipoSeleccionado.length > 0; }
  get pasoCompleto3(): boolean { return this.form.valid; }
}

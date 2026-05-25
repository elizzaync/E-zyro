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
  nombre: string;
  apellido: string;
  cargo: string;
  fotoUrl: string;
  grupoNombre?: string | null;
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

  // Técnicos — source of truth (never mutated after load)
  todosTecnicos: TecnicoDisponible[]     = [];
  // Renderizado en la columna izquierda (disponibles minus seleccionados, filtrado por búsqueda)
  tecnicosFiltrados: TecnicoDisponible[] = [];
  equipoSeleccionado: TecnicoDisponible[] = [];
  grupos: GrupoDisponible[] = [];
  busquedaTecnico   = '';
  cargandoTecnicos  = false;
  errorCargaTecnicos = false;   // true cuando el API de técnicos falla

  // UI
  seccionActiva: 1 | 2 | 3 = 1;
  guardando  = false;
  errorMsg   = '';
  successMsg = '';

  // ── Formulario ───────────────────────────────────────────────────────────
  form!: FormGroup;

  get procedimientosArray(): FormArray {
    return this.form.get('procedimientos') as FormArray;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this._cargarUsuario();
    this._initForm();
    this._cargarTecnicos();
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

  private _cargarTecnicos(): void {
    this.cargandoTecnicos   = true;
    this.errorCargaTecnicos = false;

    this.svc.getPersonalTecnicos().pipe(takeUntil(this.destroy$)).subscribe({
      next: (res: any) => {
        // ── Técnicos planos ──────────────────────────────────────────────────
        const rawTecnicos = Array.isArray(res) ? res : (res?.tecnicos ?? []);
        this.todosTecnicos = rawTecnicos.map((t: any) => ({
          id:          String(t.id ?? ''),
          nombre:      String(t.nombre   ?? ''),
          apellido:    String(t.apellido ?? ''),
          cargo:       String(t.cargo    ?? 'Técnico'),
          fotoUrl:     String(t.foto_url ?? ''),
          grupoNombre: t.grupo_nombre ?? null,
        }));

        // ── Grupos con miembros ──────────────────────────────────────────────
        const rawGrupos = Array.isArray(res) ? [] : (res?.grupos ?? []);
        this.grupos = rawGrupos.map((g: any) => ({
          id:         String(g.id ?? ''),
          nombre:     String(g.nombre ?? ''),
          jefeNombre: String(g.jefe_nombre ?? ''),
          miembros:   (g.miembros ?? []).map((m: any) => ({
            id:          String(m.id ?? ''),
            nombre:      String(m.nombre   ?? ''),
            apellido:    String(m.apellido ?? ''),
            cargo:       String(m.cargo    ?? 'Técnico'),
            fotoUrl:     String(m.foto_url ?? ''),
            grupoNombre: String(g.nombre ?? ''),
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
    this.equipoSeleccionado = equipo.map((m: any) => ({
      id:          String(m.id ?? ''),
      nombre:      String(m.nombre   ?? ''),
      apellido:    String(m.apellido ?? ''),
      cargo:       String(m.cargo    ?? 'Técnico'),
      fotoUrl:     String(m.foto_url ?? ''),
      grupoNombre: m.grupo_nombre ?? null,
    }));
    // Remueve los técnicos precargados de la columna izquierda
    this.filtrarTecnicos();
  }

  private _precargarProcedimientos(procs: any[]): void {
    // Limpia el array y recarga
    while (this.procedimientosArray.length) { this.procedimientosArray.removeAt(0); }

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
   * Mueve un técnico de la columna izquierda a la derecha.
   * Si ya está seleccionado (no debería verse en izquierda), lo ignora silenciosamente.
   */
  seleccionarTecnico(t: TecnicoDisponible): void {
    if (this.estaSeleccionado(t.id)) return;
    this.equipoSeleccionado = [...this.equipoSeleccionado, t];
    this.filtrarTecnicos();
  }

  /**
   * Alias mantenido para compatibilidad con bindings de plantilla previos.
   * En el nuevo flujo la izquierda solo muestra NO-seleccionados, así que
   * un click siempre agrega (nunca quita).
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
    this.procedimientosArray.controls.forEach(ctrl => {
      if (ctrl.get('responsable_id')?.value === id) {
        ctrl.get('responsable_id')?.setValue('');
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
  // TAREAS (FormArray)
  // ─────────────────────────────────────────────────────────────────────────

  agregarTarea(): void { this._agregarTareaVacia(); }

  removerTarea(i: number): void {
    if (this.procedimientosArray.length > 1) {
      this.procedimientosArray.removeAt(i);
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
      equipo: this.equipoSeleccionado.map(e => e.id),
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

  getInicialesUser(): string {
    const p = this.usuarioActual.nombre.trim().split(/\s+/);
    if (p.length >= 2) return (p[0][0] + p[p.length - 1][0]).toUpperCase();
    return (p[0]?.[0] ?? 'J').toUpperCase();
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

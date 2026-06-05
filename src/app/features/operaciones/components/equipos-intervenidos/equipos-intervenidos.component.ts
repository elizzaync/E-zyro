import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule, Location, DOCUMENT } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { ToastService } from '../../../../core/services/toast.service';
import {
  EPPS_CONFIG, MATERIALES_CONFIG, HERRAMIENTAS_CONFIG, determinarTipoBase,
  MaterialItem, HerramientaItem, TipoBase,
} from './informe-general.config';

// Interfaces legacy requeridas por sub-componentes heredados
export interface ProcedimientoEI {
  id: string; orden: number; nombre: string;
  descripcion?: string | null; estado: 'pendiente' | 'en_proceso' | 'completado';
  fotoUrl?: string | null;
}
export interface EquipoEI {
  id: string; nombre: string; tag?: string | null;
  estado: 'pendiente' | 'en_proceso' | 'completado';
  ubicacion?: string | null; procedimientos: ProcedimientoEI[];
}
export interface TipoEquipoGrupoEI { nombre: string; equipos: EquipoEI[]; }

export interface EquipoIntervenido {
  id: string;
  nombre: string;
  codigo: string | null;
  ubicacionReferencia: string | null;
  tipoNombre: string | null;
  tipoEquipoId: string | null;
  marca: string | null;
  modelo: string | null;
  numeroSerie: string | null;
  ubicacion: string | null;
  zona: string | null;
  ultimoMantenimiento: string | null;
  proximoMantenimiento: string | null;
  estadoIntervencion: string;
  estado: string;
}

@Component({
  selector: 'app-equipos-intervenidos',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './equipos-intervenidos.component.html',
  styleUrls: ['./equipos-intervenidos.component.css'],
})
export class EquiposIntervenidosComponent implements OnInit, OnDestroy {
  private route    = inject(ActivatedRoute);
  private router   = inject(Router);
  private location = inject(Location);
  private svc      = inject(OperacionesService);
  private toast    = inject(ToastService);
  private doc      = inject(DOCUMENT);

  servicioId = '';
  cargando   = true;
  error      = false;

  equipos: EquipoIntervenido[] = [];
  filtro = '';

  // Ubicación / Zona heredadas de la sede del servicio (para el form, bloqueadas)
  sedeUbicacion = '';
  sedeZona      = '';

  // ── Selección (checkboxes) para acciones masivas ──────────────────────────
  seleccionados = new Set<string>();

  // ── Modales de acciones masivas ───────────────────────────────────────────
  showModalInforme  = false;
  showModalGarantia = false;

  // ── Modal "Generar Informe" — estado ──────────────────────────────────────
  informeCargando = false;
  informeEnviando = false;
  informeTipoBase: TipoBase = 'OTRO';
  informeServicioNombre = '';                 // bloqueado en el modal
  informeEquipos: EquipoIntervenido[] = [];
  informeEpps: string[] = [];
  informeMateriales: MaterialItem[] = [];
  informeHerramientas: HerramientaItem[] = [];
  informePersonalDisp: { id: string; nombre: string; cargo: string; rol_sugerido: string }[] = [];
  informePersonalAsignado: { id: string; nombre: string; rol: string }[] = [];

  // Catálogo de EPPs cargado desde BD
  catalogoEpps: { id: string; nombre: string }[] = [];

  // Filtro y selección para el selector de EPP
  filtroEpp    = '';
  eppSelNombre = '';
  personalSel  = '';

  // ── Edición inline de "Referencia" (vista del técnico) ────────────────────
  editandoRefId: string | null = null;
  refDraft      = '';
  guardandoRef  = false;

  // ── Modal "Agregar equipo" — formulario completo ──────────────────────────
  showFormNuevo  = false;
  guardandoNuevo = false;
  form = this.formVacio();

  estadosDisp = [
    { value: 'operativo',    label: 'Operativo' },
    { value: 'inoperativo',  label: 'Inoperativo' },
    { value: 'mantenimiento',label: 'En mantenimiento' },
    { value: 'en_revision',  label: 'En revisión' },
  ];

  // Tipos de equipo disponibles para el form
  tiposDisp: { id: string; nombre: string }[] = [];

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id') ?? '';
    this.cargar();
    this.cargarTipos();
  }

  ngOnDestroy(): void {
    // Asegura que el scroll quede liberado si el componente se destruye con un modal abierto
    this.doc.body.style.overflow = '';
  }

  /** Bloquea el scroll del fondo cuando hay algún modal abierto. */
  private syncScrollLock(): void {
    const abierto = this.showFormNuevo || this.showModalInforme || this.showModalGarantia;
    this.doc.body.style.overflow = abierto ? 'hidden' : '';
  }

  private formVacio() {
    return {
      nombre: '',
      tipo_equipo_id: '',
      ubicacion_referencia: '',
      estado: 'operativo',
      descripcion: '',
    };
  }

  /** Tipos de equipo del catálogo (tabla tipo_equipo), no derivados de la lista. */
  cargarTipos(): void {
    this.svc.getTiposEquipo().subscribe({
      next: (tipos) => {
        this.tiposDisp = (tipos ?? [])
          .filter(t => t.id && t.nombre)
          .sort((a, b) => a.nombre.localeCompare(b.nombre));
      },
      error: () => { /* el form sigue usable; queda sin opciones de tipo */ }
    });
  }

  cargar(): void {
    this.cargando = true;
    this.error    = false;
    this.seleccionados.clear();
    this.svc.getEquiposIntervenidos(this.servicioId).subscribe({
      next: (data: any[]) => {
        this.equipos = data.map(r => ({
          id:                  r.id,
          nombre:              r.nombre,
          codigo:              r.codigo       ?? null,
          ubicacionReferencia: r.ubicacion_referencia ?? null,
          tipoNombre:          r.tipo_nombre  ?? null,
          tipoEquipoId:        r.tipo_equipo_id ?? null,
          marca:               r.marca        ?? null,
          modelo:              r.modelo       ?? null,
          numeroSerie:         r.numero_serie ?? null,
          ubicacion:           r.ubicacion    ?? null,
          zona:                r.zona         ?? null,
          ultimoMantenimiento: r.ultimo_mantenimiento ?? null,
          proximoMantenimiento: r.proximo_mantenimiento ?? null,
          estadoIntervencion:  r.estado_intervencion ?? 'sin_inspeccion',
          estado:              r.estado ?? 'operativo',
        }));
        this.cargando = false;

        // Ubicación / Zona heredadas de la sede (primer registro que las tenga)
        this.sedeUbicacion = this.equipos.find(e => e.ubicacion)?.ubicacion ?? '';
        this.sedeZona      = this.equipos.find(e => e.zona)?.zona ?? '';
      },
      error: () => { this.cargando = false; this.error = true; }
    });
  }

  // ── Filtro ────────────────────────────────────────────────────────────────
  get equiposFiltrados(): EquipoIntervenido[] {
    const q = this.filtro.toLowerCase().trim();
    if (!q) return this.equipos;
    return this.equipos.filter(e =>
      e.nombre.toLowerCase().includes(q) ||
      (e.tipoNombre ?? '').toLowerCase().includes(q) ||
      (e.ubicacion  ?? '').toLowerCase().includes(q) ||
      (e.zona       ?? '').toLowerCase().includes(q) ||
      (e.ubicacionReferencia ?? '').toLowerCase().includes(q) ||
      (e.codigo     ?? '').toLowerCase().includes(q)
    );
  }

  // ── Selección ───────────────────────────────────────────────────────────
  isSel(id: string): boolean { return this.seleccionados.has(id); }

  toggleSel(id: string): void {
    if (this.seleccionados.has(id)) this.seleccionados.delete(id);
    else this.seleccionados.add(id);
  }

  get haySeleccion(): boolean { return this.seleccionados.size > 0; }
  get nSeleccionados(): number { return this.seleccionados.size; }

  get todosSeleccionados(): boolean {
    const vis = this.equiposFiltrados;
    return vis.length > 0 && vis.every(e => this.seleccionados.has(e.id));
  }

  toggleTodos(): void {
    const vis = this.equiposFiltrados;
    if (this.todosSeleccionados) {
      vis.forEach(e => this.seleccionados.delete(e.id));
    } else {
      vis.forEach(e => this.seleccionados.add(e.id));
    }
  }

  get equiposSeleccionados(): EquipoIntervenido[] {
    return this.equipos.filter(e => this.seleccionados.has(e.id));
  }

  // ── Acción: Generar Informe General ──────────────────────────────────────
  // Regla estricta: solo se puede agrupar el MISMO tipo de equipo.
  generarInforme(): void {
    const sel = this.equiposSeleccionados;
    if (sel.length === 0) {
      this.toast.mostrar('Selecciona al menos un equipo para generar el informe.', 'info');
      return;
    }
    // Agrupamos por tipo de equipo (id si existe, si no por nombre de tipo).
    const tipos = new Set(sel.map(e => e.tipoEquipoId ?? e.tipoNombre ?? '∅'));
    if (tipos.size > 1) {
      // Tipos mezclados → se bloquea la acción.
      this.toast.mostrar(
        'El informe general solo permite agrupar equipos del mismo tipo.',
        'error'
      );
      return;
    }
    // Mismo tipo → abre el modal y precarga sus datos.
    this.showModalInforme = true;
    this.syncScrollLock();
    this.prepararInforme(sel);
  }
  cerrarModalInforme(): void { this.showModalInforme = false; this.syncScrollLock(); }

  /**
   * Precarga del modal:
   *  - EPPs: defaults por tipo + catálogo BD
   *  - Materiales: defaults por tipo + requerimientos del servicio (auto)
   *  - Herramientas: defaults por tipo + préstamos del servicio (auto)
   *  - Personal: todos los miembros del proyecto (auto)
   */
  private prepararInforme(sel: EquipoIntervenido[]): void {
    this.informeEquipos     = [...sel];
    this.informeTipoBase    = determinarTipoBase(sel.map(e => e.tipoNombre));
    this.informeEpps         = [...EPPS_CONFIG[this.informeTipoBase]];
    this.informeMateriales   = MATERIALES_CONFIG[this.informeTipoBase].map(m => ({ ...m }));
    this.informeHerramientas = HERRAMIENTAS_CONFIG[this.informeTipoBase].map(h => ({ ...h }));
    this.informePersonalAsignado = [];
    this.informePersonalDisp     = [];
    this.informeServicioNombre   = '';
    this.catalogoEpps            = [];
    this.filtroEpp               = '';
    this.eppSelNombre            = '';
    this.personalSel             = '';

    this.informeCargando = true;
    forkJoin({
      precarga: this.svc.getPrecargaInforme(this.servicioId).pipe(catchError(() => of(null))),
      epps:     this.svc.getEppCatalogo().pipe(catchError(() => of([]))),
    }).subscribe({
      next: ({ precarga, epps }) => {
        // ── Precarga del servicio ────────────────────────────────────────
        const res = precarga as any;
        const srv = res?.servicio;
        this.informeServicioNombre = srv?.nombre
          ? `${srv.nombre}${srv.proyecto_nombre ? ' — ' + srv.proyecto_nombre : ''}`
          : '(servicio actual)';

        // Materiales: defaults + lo solicitado en requerimientos del servicio
        this.informeMateriales = this.mergePorNombre(
          this.informeMateriales,
          (res?.materiales_solicitados ?? []).map((m: any) => ({
            nombre: m.nombre, unidad: m.unidad || 'UND.', caracteristicas: m.caracteristicas || '-',
          })),
          (x: MaterialItem) => x.nombre,
        );

        // Herramientas: defaults + lo prestado/retirado para el servicio
        this.informeHerramientas = this.mergePorNombre(
          this.informeHerramientas,
          (res?.herramientas_solicitadas ?? []).map((h: any) => ({
            serie: h.serie || '-', nombre: h.nombre, marca: h.marca || '-',
          })),
          (x: HerramientaItem) => x.nombre,
        );

        // Personal: auto-poblar todos los miembros del proyecto
        const personal: { id: string; nombre: string; cargo: string; rol_sugerido: string }[] =
          res?.personal ?? [];
        this.informePersonalDisp     = personal;
        this.informePersonalAsignado = personal.map(p => ({
          id:     p.id,
          nombre: p.nombre,
          rol:    /supervis|jefe|lider|líder/i.test(p.rol_sugerido ?? '') ? 'Supervisor' : 'Técnico',
        }));

        // Catálogo EPP desde BD
        this.catalogoEpps = (epps as any[]).map((e: any) => ({
          id:     e.id,
          nombre: (e.nombre as string).toUpperCase(),
        }));

        this.informeCargando = false;
      },
      error: () => {
        this.informeServicioNombre = '(servicio actual)';
        this.informeCargando = false;
      }
    });
  }

  /** Une base + extra omitiendo duplicados exactos por nombre (case-insensitive). */
  private mergePorNombre<T>(base: T[], extra: T[], key: (x: T) => string): T[] {
    const vistos = new Set(base.map(x => key(x).trim().toUpperCase()));
    const out = [...base];
    for (const e of extra) {
      const k = key(e).trim().toUpperCase();
      if (!k || vistos.has(k)) continue;   // duplicado → se omite
      vistos.add(k);
      out.push(e);
    }
    return out;
  }

  // Getter: EPPs del catálogo BD filtrados (excluye los ya agregados)
  get catalogoEppsFiltrados() {
    const q      = this.filtroEpp.toLowerCase().trim();
    const usados = new Set(this.informeEpps.map(e => e.toUpperCase()));
    return this.catalogoEpps
      .filter(e => !usados.has(e.nombre))
      .filter(e => !q || e.nombre.toLowerCase().includes(q));
  }

  // EPPs: selección desde catálogo BD
  agregarEpp(): void {
    const v = this.eppSelNombre.trim().toUpperCase();
    if (!v) { this.toast.mostrar('Selecciona un EPP del catálogo.', 'info'); return; }
    if (this.informeEpps.some(e => e.toUpperCase() === v)) {
      this.toast.mostrar(`${v} ya fue agregado.`, 'error'); return;
    }
    this.informeEpps.push(v);
    this.eppSelNombre = '';
    this.filtroEpp = '';
  }
  quitarEpp(i: number): void { this.informeEpps.splice(i, 1); }

  // Materiales y herramientas: solo se eliminan (son auto-poblados)
  quitarMaterial(i: number): void { this.informeMateriales.splice(i, 1); }
  quitarHerramienta(i: number): void { this.informeHerramientas.splice(i, 1); }

  // Personal (solo del proyecto del servicio)
  get personalNoAsignado() {
    const ids = new Set(this.informePersonalAsignado.map(p => p.id));
    return this.informePersonalDisp.filter(p => !ids.has(p.id));
  }
  agregarPersonal(): void {
    if (!this.personalSel) { this.toast.mostrar('Selecciona un empleado.', 'info'); return; }
    const emp = this.informePersonalDisp.find(p => p.id === this.personalSel);
    if (!emp) return;
    if (this.informePersonalAsignado.some(p => p.id === emp.id)) {
      this.toast.mostrar('El personal ya fue agregado.', 'error'); return;
    }
    const rol = /supervis|jefe|lider|líder/i.test(emp.rol_sugerido) ? 'Supervisor' : 'Técnico';
    this.informePersonalAsignado.push({ id: emp.id, nombre: emp.nombre, rol });
    this.personalSel = '';
  }
  quitarPersonal(i: number): void { this.informePersonalAsignado.splice(i, 1); }

  /** Construye el payload y lo envía (el Word es integración futura). */
  onSubmitInforme(): void {
    const payload = {
      servicio_id: this.servicioId,
      tipo_base:   this.informeTipoBase,
      equipos: this.informeEquipos.map(e => ({
        id: e.id, tipo: e.tipoNombre, nombre: e.nombre,
        provincia: e.ubicacion, zona: e.zona,
      })),
      epps:         this.informeEpps,
      materiales:   this.informeMateriales,
      herramientas: this.informeHerramientas,
      personal:     this.informePersonalAsignado,
    };
    // TODO (futura integración): este payload alimentará la generación del Word.
    console.log('[Generar Informe] payload listo para el backend/Word:', payload);

    this.informeEnviando = true;
    this.svc.generarInformeGeneral(this.servicioId, payload).subscribe({
      next: () => {
        this.informeEnviando = false;
        this.toast.mostrar('Datos del informe enviados. (Generación del Word pendiente)', 'success');
        this.cerrarModalInforme();
      },
      error: (err: any) => {
        this.informeEnviando = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al enviar el informe.', 'error');
      }
    });
  }

  // ── Acción: Carta de Garantía ────────────────────────────────────────────
  // La garantía es individual, pero se permite procesar por lote SIN restricción
  // de tipo (se pueden seleccionar equipos de tipos distintos).
  cartaGarantia(): void {
    const sel = this.equiposSeleccionados;
    if (sel.length === 0) {
      this.toast.mostrar('Selecciona al menos un equipo para emitir la garantía.', 'info');
      return;
    }
    // Sin validación de tipo: cualquier combinación es válida.
    this.showModalGarantia = true;
    this.syncScrollLock();
    // TODO (al completar el modal): iterar `this.equiposSeleccionados` y generar
    // / devolver una Carta de Garantía POR CADA equipo seleccionado de forma
    // individual (una garantía por equipo, no una sola agrupada).
  }
  cerrarModalGarantia(): void { this.showModalGarantia = false; this.syncScrollLock(); }

  // ── Edición de "Referencia" (técnico) ────────────────────────────────────
  iniciarEdicionRef(eq: EquipoIntervenido): void {
    this.editandoRefId = eq.id;
    this.refDraft = eq.ubicacionReferencia ?? '';
  }
  cancelarEdicionRef(): void {
    this.editandoRefId = null;
    this.refDraft = '';
  }
  guardarRef(eq: EquipoIntervenido): void {
    const valor = this.refDraft.trim();
    if (valor === (eq.ubicacionReferencia ?? '')) { this.cancelarEdicionRef(); return; }
    this.guardandoRef = true;
    this.svc.actualizarReferenciaEI(this.servicioId, eq.id, valor).subscribe({
      next: (res: any) => {
        eq.ubicacionReferencia = res?.ubicacion_referencia ?? (valor || null);
        this.guardandoRef = false;
        this.editandoRefId = null;
        this.toast.mostrar('Referencia actualizada.', 'success');
      },
      error: (err: any) => {
        this.guardandoRef = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo guardar la referencia.', 'error');
      }
    });
  }

  // ── Inspeccionar ──────────────────────────────────────────────────────────
  inspeccionar(ei: EquipoIntervenido): void {
    this.router.navigate([
      '/operaciones/servicio', this.servicioId,
      'equipos-intervenidos', ei.id
    ]);
  }

  // ── Crear nuevo equipo en catálogo ────────────────────────────────────────
  abrirFormNuevo(): void {
    this.form = this.formVacio();
    this.showFormNuevo = true;
    this.syncScrollLock();
  }
  cerrarFormNuevo(): void { this.showFormNuevo = false; this.syncScrollLock(); }

  guardarNuevo(): void {
    if (!this.form.nombre.trim()) {
      this.toast.mostrar('Ingresa el nombre del equipo.', 'error');
      return;
    }
    this.guardandoNuevo = true;
    // Ubicación y Zona NO se envían: el backend las hereda de la sede del servicio.
    this.svc.crearEquipoCatalogo(this.servicioId, {
      nombre:               this.form.nombre.trim(),
      tipo_equipo_id:       this.form.tipo_equipo_id || null,
      ubicacion_referencia: this.form.ubicacion_referencia.trim() || null,
      estado:               this.form.estado || 'operativo',
      descripcion:          this.form.descripcion.trim() || null,
    }).subscribe({
      next: () => {
        this.guardandoNuevo = false;
        this.showFormNuevo  = false;
        this.syncScrollLock();
        this.toast.mostrar('Equipo agregado al catálogo.', 'success');
        this.cargar();
      },
      error: (err: any) => {
        this.guardandoNuevo = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al crear el equipo.', 'error');
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  volver(): void { this.location.back(); }

  estadoLabel(e: string): string {
    return ({
      sin_inspeccion: 'Sin inspección',
      en_proceso:     'En Proceso',
      completado:     'Completado',
    } as Record<string, string>)[e] ?? e;
  }

  estadoClass(e: string): string {
    return ({
      sin_inspeccion: 'badge--muted',
      en_proceso:     'badge--info',
      completado:     'badge--ok',
    } as Record<string, string>)[e] ?? 'badge--muted';
  }
}

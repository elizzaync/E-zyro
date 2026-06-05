import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { ToastService } from '../../../../core/services/toast.service';

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
export class EquiposIntervenidosComponent implements OnInit {
  private route    = inject(ActivatedRoute);
  private router   = inject(Router);
  private location = inject(Location);
  private svc      = inject(OperacionesService);
  private toast    = inject(ToastService);

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

  // ── Modales de acciones masivas (maquetados / en construcción) ────────────
  showModalInforme  = false;
  showModalGarantia = false;

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
    // Mismo tipo → abre el modal (en construcción).
    this.showModalInforme = true;
  }
  cerrarModalInforme(): void { this.showModalInforme = false; }

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
    // TODO (al completar el modal): iterar `this.equiposSeleccionados` y generar
    // / devolver una Carta de Garantía POR CADA equipo seleccionado de forma
    // individual (una garantía por equipo, no una sola agrupada).
  }
  cerrarModalGarantia(): void { this.showModalGarantia = false; }

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
  }
  cerrarFormNuevo(): void { this.showFormNuevo = false; }

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

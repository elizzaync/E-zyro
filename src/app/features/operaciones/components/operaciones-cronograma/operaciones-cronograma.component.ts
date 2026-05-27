import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

interface ProyectoCronograma {
  id: string;
  nombre_proyecto: string;
  cliente: string;
  estado: string;
  orden_trabajo: string;
  fecha_inicio: string | null;
  fecha_fin_estimada: string | null;   // populated from backend
  total_servicios: number;
  servicios_completados: number;
}

interface ProcedimientoCronograma {
  id: string;
  nombre: string;
  descripcion?: string;
  orden: number;
  estado: string;
  responsableId?: string | null;
  responsableNombre?: string;
  responsableFoto?: string;
  responsableCargo?: string;
}

interface ServicioCronograma {
  id: string;
  nombre: string;
  descripcion: string | null;
  estado: string;
  orden: number;
  fecha_programada: string | null;   // inicio del servicio ("dd Mon YYYY")
  fecha_fin: string | null;          // cierre real del servicio ("dd Mon YYYY")
  expandido: boolean;
  cargandoProcedimientos: boolean;
  procedimientos?: ProcedimientoCronograma[];
  ganttStart: Date | null;
  ganttEnd:   Date | null;
  barLeft:    number;
  barWidth:   number;
}

interface GanttRow {
  id:               string;
  type:             'proyecto' | 'servicio' | 'procedimiento';
  nombre:           string;
  descripcion?:     string;
  estado:           string;
  level:            0 | 1 | 2;
  barLeft:          number;
  barWidth:         number;
  isExpandable:     boolean;
  isExpanded?:      boolean;
  isLoading?:       boolean;
  isEmpty?:         boolean;
  servicioId?:      string;
  servicioEstado?:  string;
  procedimientoId?: string;
  fechaInicioLabel: string;
  fechaFinLabel:    string;
  responsableNombre?: string;
  responsableFoto?:   string;
  responsableCargo?:  string;
}

interface MonthHeader {
  label: string;
  left:  number;
  width: number;
}

@Component({
  selector: 'app-operaciones-cronograma',
  standalone: true,
  imports: [CommonModule, SpinnerComponent],
  templateUrl: './operaciones-cronograma.component.html',
  styleUrls: ['./operaciones-cronograma.component.css']
})
export class OperacionesCronogramaComponent implements OnInit {
  private route  = inject(ActivatedRoute);
  private router = inject(Router);
  private svc    = inject(OperacionesService);

  proyectoId:    string | null            = null;
  proyecto:      ProyectoCronograma | null = null;
  servicios:     ServicioCronograma[]     = [];
  isLoading      = true;
  errorMessage:  string | null            = null;
  hoveredBar:    string | null            = null;
  timelineStart: Date | null              = null;
  timelineEnd:   Date | null              = null;
  monthHeaders:  MonthHeader[]            = [];
  flatRows:      GanttRow[]               = [];
  todayLeft      = -1;

  ngOnInit(): void {
    this.proyectoId = this.route.snapshot.paramMap.get('proyectoId');
    if (this.proyectoId) this.cargarDatos();
    else { this.errorMessage = 'ID de proyecto inválido.'; this.isLoading = false; }
  }

  cargarDatos(): void {
    this.isLoading = true;
    this.svc.getProyectos().subscribe({
      next: (res: any) => {
        const lista: any[] = res.proyectos ?? res ?? [];
        const raw = lista.find((p: any) => p.id === this.proyectoId);
        if (!raw) { this.errorMessage = 'Proyecto no encontrado.'; this.isLoading = false; return; }
        this.proyecto = {
          id:                    raw.id,
          nombre_proyecto:       raw.nombre_proyecto,
          cliente:               raw.cliente,
          estado:                raw.estado,
          orden_trabajo:         raw.orden_trabajo,
          fecha_inicio:          raw.fecha_inicio        ?? null,
          fecha_fin_estimada:    raw.fecha_fin_estimada  ?? null,  // now populated by backend
          total_servicios:       raw.total_servicios        ?? 0,
          servicios_completados: raw.servicios_completados  ?? 0,
        };
        this.cargarServicios();
      },
      error: () => { this.errorMessage = 'Error al cargar el proyecto.'; this.isLoading = false; }
    });
  }

  cargarServicios(): void {
    this.svc.getServiciosPorProyecto(this.proyectoId!).subscribe({
      next: (res: any) => {
        const lista: any[] = Array.isArray(res) ? res : res.servicios ?? [];
        this.servicios = lista
          .sort((a, b) => {
            const ta = this.parseDate(a.fecha_programada)?.getTime() ?? 0;
            const tb = this.parseDate(b.fecha_programada)?.getTime() ?? 0;
            return ta - tb;
          })
          .map(s => ({
            id:                     s.id,
            nombre:                 s.nombre,
            descripcion:            s.descripcion      ?? null,
            estado:                 s.estado,
            orden:                  s.orden,
            fecha_programada:       s.fecha_programada ?? null,
            fecha_fin:              s.fecha_fin         ?? null,  // from backend
            expandido:              false,
            cargandoProcedimientos: false,
            procedimientos:         undefined,
            ganttStart:             null,
            ganttEnd:               null,
            barLeft:                0,
            barWidth:               0,
          }));
        this.buildTimeline();
        this.isLoading = false;
      },
      error: () => { this.errorMessage = 'Error al cargar los servicios.'; this.isLoading = false; }
    });
  }

  private buildTimeline(): void {
    let tStart = this.parseDate(this.proyecto?.fecha_inicio);
    let tEnd   = this.parseDate(this.proyecto?.fecha_fin_estimada);

    if (!tStart) {
      const ds = this.servicios.map(s => this.parseDate(s.fecha_programada)).filter((d): d is Date => !!d);
      if (ds.length) tStart = new Date(Math.min(...ds.map(d => d.getTime())));
    }
    if (!tEnd) {
      const de = this.servicios
        .map(s => this.parseDate(s.fecha_fin ?? s.fecha_programada))
        .filter((d): d is Date => !!d);
      if (de.length) tEnd = new Date(Math.max(...de.map(d => d.getTime())));
    }

    if (!tStart) tStart = new Date();
    if (!tEnd)   { tEnd = new Date(tStart); tEnd.setDate(tEnd.getDate() + 60); }

    // Snap to month boundaries for clean headers
    tStart = new Date(tStart.getFullYear(), tStart.getMonth(), 1);
    tEnd   = new Date(tEnd.getFullYear(),   tEnd.getMonth() + 1, 0);

    this.timelineStart = tStart;
    this.timelineEnd   = tEnd;
    const totalMs = Math.max(tEnd.getTime() - tStart.getTime(), 1);

    this.servicios.forEach((srv, i) => {
      const gs = this.parseDate(srv.fecha_programada);
      let   ge = this.parseDate(srv.fecha_fin);
      if (!ge && i < this.servicios.length - 1)
        ge = this.parseDate(this.servicios[i + 1].fecha_programada);
      if (!ge) ge = tEnd;

      srv.ganttStart = gs;
      srv.ganttEnd   = ge;

      if (gs) {
        const cs = Math.max(gs.getTime(), tStart.getTime());
        const ce = Math.min(ge.getTime(), tEnd.getTime());
        srv.barLeft  = Math.max(0, (cs - tStart.getTime()) / totalMs * 100);
        srv.barWidth = Math.max(1.5, (ce - cs) / totalMs * 100);
      }
    });

    const now = new Date();
    this.todayLeft = (now >= tStart && now <= tEnd)
      ? (now.getTime() - tStart.getTime()) / totalMs * 100
      : -1;

    this.monthHeaders = this.generateMonthHeaders(tStart, tEnd, totalMs);
    this.rebuildFlatRows();
  }

  private generateMonthHeaders(start: Date, end: Date, totalMs: number): MonthHeader[] {
    const headers: MonthHeader[] = [];
    let cur = new Date(start.getFullYear(), start.getMonth(), 1);
    while (cur <= end) {
      const mStart = new Date(Math.max(cur.getTime(), start.getTime()));
      const next   = new Date(cur.getFullYear(), cur.getMonth() + 1, 1);
      const mEnd   = new Date(Math.min(next.getTime() - 86400000, end.getTime()));
      headers.push({
        label: cur.toLocaleDateString('es-PE', { month: 'short', year: '2-digit' }),
        left:  Math.max(0, (mStart.getTime() - start.getTime()) / totalMs * 100),
        width: Math.max(0, (mEnd.getTime() - mStart.getTime() + 86400000) / totalMs * 100),
      });
      cur = next;
    }
    return headers;
  }

  rebuildFlatRows(): void {
    const rows: GanttRow[] = [];

    if (this.proyecto) {
      rows.push({
        id:               this.proyecto.id + '_proj',
        type:             'proyecto',
        nombre:           this.proyecto.nombre_proyecto,
        descripcion:      `${this.proyecto.cliente} · ${this.proyecto.orden_trabajo}`,
        estado:           this.proyecto.estado,
        level:            0,
        barLeft:          0,
        barWidth:         100,
        isExpandable:     false,
        fechaInicioLabel: this.formatDate(this.proyecto.fecha_inicio),
        fechaFinLabel:    this.formatDate(this.proyecto.fecha_fin_estimada),
      });
    }

    for (const srv of this.servicios) {
      rows.push({
        id:               srv.id,
        type:             'servicio',
        nombre:           srv.nombre,
        descripcion:      srv.descripcion ?? undefined,
        estado:           srv.estado,
        level:            1,
        barLeft:          srv.barLeft,
        barWidth:         srv.barWidth,
        isExpandable:     true,
        isExpanded:       srv.expandido,
        isLoading:        srv.cargandoProcedimientos,
        fechaInicioLabel: this.formatDate(srv.fecha_programada),
        fechaFinLabel:    this.formatDate(srv.ganttEnd?.toISOString()),
      });

      if (srv.expandido) {
        if (srv.cargandoProcedimientos) {
          rows.push({
            id: srv.id + '_loading', type: 'procedimiento', nombre: '',
            estado: '', level: 2, barLeft: srv.barLeft, barWidth: srv.barWidth,
            isExpandable: false, isLoading: true, servicioId: srv.id,
            fechaInicioLabel: '', fechaFinLabel: '',
          });
        } else if (!srv.procedimientos?.length) {
          rows.push({
            id: srv.id + '_empty', type: 'procedimiento', nombre: 'Sin tareas registradas',
            estado: '', level: 2, barLeft: 0, barWidth: 0,
            isExpandable: false, isEmpty: true, servicioId: srv.id,
            fechaInicioLabel: '', fechaFinLabel: '',
          });
        } else {
          const count = srv.procedimientos.length;
          srv.procedimientos.forEach((proc, pi) => {
            rows.push({
                id:               proc.id,
                type:             'procedimiento',
                nombre:           proc.nombre,
                descripcion:      proc.descripcion,
                estado:           proc.estado,
                level:            2,
                barLeft:          srv.barLeft + (pi / count) * srv.barWidth,
                barWidth:         Math.max(1, srv.barWidth / count),
                isExpandable:     false,
                servicioId:       srv.id,
                servicioEstado:   srv.estado,
                procedimientoId:  proc.id,
                fechaInicioLabel: this.formatDate(srv.fecha_programada),
                fechaFinLabel:    '—',
                responsableNombre: proc.responsableNombre,
                responsableFoto:   proc.responsableFoto,
                responsableCargo:  proc.responsableCargo,
              });
          });
        }
      }
    }
    this.flatRows = rows;
  }

  toggleServicio(srv: ServicioCronograma | undefined): void {
    if (!srv) return;
    if (!srv.expandido && srv.procedimientos === undefined) {
      srv.cargandoProcedimientos = true;
      srv.expandido = true;
      this.rebuildFlatRows();
      this.svc.getDetalleServicio(srv.id).subscribe({
        next: (raw: any) => {
          // Mapa empleado.id → datos del técnico (para resolver el responsable de cada tarea)
          const equipoMap = new Map<string, any>();
          for (const m of (raw.equipo ?? [])) equipoMap.set(String(m.id), m);

          srv.procedimientos = (raw.procedimientos ?? []).map((p: any) => {
            const resp = p.responsable_id ? equipoMap.get(String(p.responsable_id)) : null;
            return {
              id: p.id, nombre: p.nombre,
              descripcion: p.descripcion ?? undefined,
              orden: p.orden, estado: p.estado,
              responsableId:     p.responsable_id ?? null,
              responsableNombre: resp ? `${resp.nombre ?? ''} ${resp.apellido ?? ''}`.trim() : '',
              responsableFoto:   resp?.foto_url ?? '',
              responsableCargo:  resp?.cargo ?? '',
            };
          });
          srv.cargandoProcedimientos = false;
          this.rebuildFlatRows();
        },
        error: () => {
          srv.cargandoProcedimientos = false;
          srv.expandido = false;
          this.rebuildFlatRows();
        }
      });
    } else {
      srv.expandido = !srv.expandido;
      this.rebuildFlatRows();
    }
  }

  navegarATarea(event: Event, servicioId: string, procedimientoId: string): void {
    event.stopPropagation();
    this.router.navigate(['/operaciones/servicio', servicioId], {
      queryParams: { abrirTareaId: procedimientoId }
    });
  }

  volver(): void { this.router.navigate(['/operaciones/proyecto', this.proyectoId]); }

  getSrvById(id: string): ServicioCronograma | undefined {
    return this.servicios.find(s => s.id === id);
  }

  /** Iniciales (2 letras) de un nombre completo para el avatar de respaldo. */
  getIniciales(nombre: string | undefined): string {
    const p = (nombre ?? '').trim().split(/\s+/).filter(Boolean);
    if (p.length >= 2) return (p[0][0] + p[p.length - 1][0]).toUpperCase();
    return (p[0]?.[0] ?? '?').toUpperCase();
  }

  /** Color estable del avatar de respaldo a partir de un id. */
  getAvatarColor(id: string | undefined): string {
    const palette = ['#91d337', '#3b82f6', '#8b5cf6', '#f59e0b', '#06b6d4', '#ec4899', '#ef4444', '#14b8a6'];
    if (!id) return '#64748b';
    let h = 0;
    for (let i = 0; i < id.length; i++) h = id.charCodeAt(i) + ((h << 5) - h);
    return palette[Math.abs(h) % palette.length];
  }

  /**
   * Parsea fechas en dos formatos:
   *   • ISO:          "2025-01-15"  o  "2025-01-15T00:00:00"
   *   • dd Mon YYYY:  "15 Jan 2025" (formato que devuelve el backend con strftime %d %b %Y)
   */
  private static readonly MONTH_MAP: Record<string, number> = {
    jan:1, feb:2, mar:3, apr:4, may:5, jun:6,
    jul:7, aug:8, sep:9, oct:10, nov:11, dec:12,
    // alias español (por si el servidor usa locale es)
    ene:1, abr:4, ago:8, dic:12,
  };

  parseDate(d: string | null | undefined): Date | null {
    if (!d) return null;
    const s = d.trim();

    // ── Formato ISO: YYYY-MM-DD[THH:MM:SS[.fff][Z]] ──────────────────
    if (/^\d{4}-\d{2}-\d{2}/.test(s)) {
      const part = s.split('T')[0].split(' ')[0];
      const [y, m, day] = part.split('-').map(Number);
      if (!y || !m || !day || isNaN(y) || isNaN(m) || isNaN(day)) return null;
      const dt = new Date(y, m - 1, day, 12);
      return isNaN(dt.getTime()) ? null : dt;
    }

    // ── Formato "dd Mon YYYY": "15 Jan 2025" ─────────────────────────
    const match = /^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})$/.exec(s);
    if (match) {
      const day  = parseInt(match[1], 10);
      const mon  = OperacionesCronogramaComponent.MONTH_MAP[match[2].toLowerCase()];
      const year = parseInt(match[3], 10);
      if (!day || !mon || !year || isNaN(day) || isNaN(year)) return null;
      const dt = new Date(year, mon - 1, day, 12);
      return isNaN(dt.getTime()) ? null : dt;
    }

    return null;
  }

  formatDate(d: string | Date | null | undefined): string {
    if (!d) return 'Por definir';
    const dt = d instanceof Date ? d : this.parseDate(d as string);
    if (!dt) return 'Por definir';
    return dt.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  get progresoPorcentaje(): number {
    if (!this.proyecto?.total_servicios) return 0;
    return Math.round((this.proyecto.servicios_completados / this.proyecto.total_servicios) * 100);
  }

  getBarClass(row: GanttRow): string {
    const type  = `gantt-bar--${row.type}`;
    const state = row.type === 'procedimiento'
      ? this.procEstadoClass(row.estado)
      : this.estadoClass(row.estado);
    const click = row.type === 'procedimiento' && row.procedimientoId && row.servicioEstado !== 'Completado'
                  ? 'bar-clickable' : '';
    return ['gantt-bar', type, state, click].filter(Boolean).join(' ');
  }

  getRowClass(row: GanttRow): string {
    return [
      'gantt-row',
      `gantt-row--${row.type}`,
      `level-${row.level}`,
      row.isExpanded ? 'is-expanded' : ''
    ].filter(Boolean).join(' ');
  }

  estadoClass(estado: string): string {
    const m: Record<string, string> = {
      'Pendiente':  'est-pendiente',
      'En_Proceso': 'est-en-proceso',
      'Completado': 'est-completado',
      'Cancelado':  'est-cancelado',
    };
    return m[estado] ?? 'est-pendiente';
  }

  estadoLabel(estado: string): string {
    return estado === 'En_Proceso' ? 'En Proceso' : estado;
  }

  procEstadoClass(estado: string): string {
    const m: Record<string, string> = {
      'completado': 'proc-ok',
      'en_proceso': 'proc-active',
      'bloqueado':  'proc-blocked',
    };
    return m[estado] ?? 'proc-pending';
  }
}

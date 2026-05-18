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
  fecha_fin_estimada: string | null;
  total_servicios: number;
  servicios_completados: number;
}

interface ProcedimientoCronograma {
  id: string;
  nombre: string;
  descripcion?: string;
  orden: number;
  estado: string;
}

interface ServicioCronograma {
  id: string;
  nombre: string;
  descripcion: string | null;
  estado: string;
  orden: number;
  fecha_programada: string | null;
  expandido: boolean;
  cargandoProcedimientos: boolean;
  procedimientos?: ProcedimientoCronograma[];
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

  proyectoId: string | null = null;
  proyecto: ProyectoCronograma | null = null;
  servicios: ServicioCronograma[] = [];
  isLoading = true;
  errorMessage: string | null = null;

  ngOnInit(): void {
    this.proyectoId = this.route.snapshot.paramMap.get('proyectoId');
    if (this.proyectoId) {
      this.cargarDatos();
    } else {
      this.errorMessage = 'ID de proyecto inválido.';
      this.isLoading = false;
    }
  }

  cargarDatos(): void {
    this.isLoading = true;
    this.svc.getProyectos().subscribe({
      next: (res: any) => {
        const lista: any[] = res.proyectos ?? res ?? [];
        const raw = lista.find((p: any) => p.id === this.proyectoId);
        if (!raw) {
          this.errorMessage = 'Proyecto no encontrado.';
          this.isLoading = false;
          return;
        }
        this.proyecto = {
          id:                    raw.id,
          nombre_proyecto:       raw.nombre_proyecto,
          cliente:               raw.cliente,
          estado:                raw.estado,
          orden_trabajo:         raw.orden_trabajo,
          fecha_inicio:          raw.fecha_inicio          ?? null,
          fecha_fin_estimada:    raw.fecha_fin_estimada    ?? null,
          total_servicios:       raw.total_servicios       ?? 0,
          servicios_completados: raw.servicios_completados ?? 0
        };
        this.cargarServicios();
      },
      error: () => {
        this.errorMessage = 'Error al cargar el proyecto.';
        this.isLoading = false;
      }
    });
  }

  cargarServicios(): void {
    this.svc.getServiciosPorProyecto(this.proyectoId!).subscribe({
      next: (res: any) => {
        const lista: any[] = Array.isArray(res) ? res : res.servicios ?? [];
        this.servicios = lista
          .sort((a, b) => {
            const ta = a.fecha_programada ? this.parseDate(a.fecha_programada)?.getTime() ?? 0 : 0;
            const tb = b.fecha_programada ? this.parseDate(b.fecha_programada)?.getTime() ?? 0 : 0;
            return ta - tb;
          })
          .map(s => ({
            id:                     s.id,
            nombre:                 s.nombre,
            descripcion:            s.descripcion ?? null,
            estado:                 s.estado,
            orden:                  s.orden,
            fecha_programada:       s.fecha_programada ?? null,
            expandido:              false,
            cargandoProcedimientos: false,
            procedimientos:         undefined
          }));
        this.isLoading = false;
      },
      error: () => {
        this.errorMessage = 'Error al cargar los servicios.';
        this.isLoading = false;
      }
    });
  }

  /** Parsea un string de fecha ISO de forma segura, devuelve null si inválido. */
  parseDate(d: string | null | undefined): Date | null {
    if (!d) return null;
    const datePart = d.includes('T') ? d.split('T')[0] : d;
    const dt = new Date(datePart + 'T12:00:00');
    return isNaN(dt.getTime()) ? null : dt;
  }

  formatDate(d: string | null | undefined): string {
    const dt = this.parseDate(d);
    if (!dt) return 'Fecha por definir';
    return dt.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  get progresoPorcentaje(): number {
    if (!this.proyecto?.total_servicios) return 0;
    return Math.round((this.proyecto.servicios_completados / this.proyecto.total_servicios) * 100);
  }

  toggleServicio(srv: ServicioCronograma): void {
    if (!srv.expandido && srv.procedimientos === undefined) {
      srv.cargandoProcedimientos = true;
      this.svc.getDetalleServicio(srv.id).subscribe({
        next: (raw: any) => {
          srv.procedimientos = (raw.procedimientos ?? []).map((p: any) => ({
            id:          p.id,
            nombre:      p.nombre,
            descripcion: p.descripcion ?? undefined,
            orden:       p.orden,
            estado:      p.estado
          }));
          srv.cargandoProcedimientos = false;
          srv.expandido = true;
        },
        error: () => { srv.cargandoProcedimientos = false; }
      });
    } else {
      srv.expandido = !srv.expandido;
    }
  }

  navegarAEvidencia(event: Event, servicioId: string, procedimientoId: string): void {
    event.stopPropagation();
    this.router.navigate(['/operaciones/servicio', servicioId], {
      queryParams: { abrirTareaId: procedimientoId }
    });
  }

  volver(): void {
    this.router.navigate(['/operaciones/proyecto', this.proyectoId]);
  }

  estadoClass(estado: string): string {
    const m: Record<string, string> = {
      'Pendiente':  'est-pendiente',
      'En_Proceso': 'est-en-proceso',
      'Completado': 'est-completado',
      'Cancelado':  'est-cancelado'
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
      'bloqueado':  'proc-blocked'
    };
    return m[estado] ?? 'proc-pending';
  }
}

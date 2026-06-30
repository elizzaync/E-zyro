import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { ActivatedRoute, Router } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { ToastService } from '../../../../core/services/toast.service';
import { AuthService } from '../../../../core/services/auth.service';
import { AsignacionServicioModalComponent } from '../asignacion-servicio-modal/asignacion-servicio-modal.component';
import { CrearServicioModalComponent } from '../crear-servicio-modal/crear-servicio-modal.component';
import { FASES_SERVICIO, faseClase as faseClaseServicio } from '../../fase-servicio';

export interface ServicioProyecto {
  id: string;
  nombre: string;
  descripcion: string | null;
  estado: string;
  orden: number;
  fecha_programada: string | null;
  estado_color: 'rojo' | 'amarillo' | 'verde';
  /** Progreso 0-100 si el backend lo provee; afina la fase mostrada en la tarjeta. */
  progreso?: number;
}

interface Paginacion { total: number; page: number; page_size: number; total_pages: number; }

@Component({
  selector: 'app-operaciones-servicios-lista',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AsignacionServicioModalComponent, CrearServicioModalComponent],
  templateUrl: './operaciones-servicios-lista.component.html',
  styleUrls: ['./operaciones-servicios-lista.component.css']
})
export class OperacionesServiciosListaComponent implements OnInit {
  private route  = inject(ActivatedRoute);
  private router = inject(Router);
  private svc    = inject(OperacionesService);
  private toast  = inject(ToastService);
  private auth   = inject(AuthService);

  get isTecnico(): boolean        { return this.auth.isTecnico(); }
  get isJefeOperaciones(): boolean { return this.auth.isJefeOperaciones(); }

  proyectoId: string | null = null;
  servicios: ServicioProyecto[] = [];
  paginacion: Paginacion = { total: 0, page: 1, page_size: 20, total_pages: 1 };
  isLoading    = true;
  errorMessage: string | null = null;

  // ── Búsqueda y filtros ─────────────────────────────────────────────
  busqueda     = '';
  filtroActual = '';
  readonly FILTROS: { valor: string; label: string }[] = [
    { valor: '',            label: 'Todos'      },
    { valor: 'Pendiente',   label: 'Pendiente'  },
    { valor: 'En_Proceso',  label: 'En Proceso' },
    { valor: 'Completado',  label: 'Completado' },
    { valor: 'Cancelado',   label: 'Cancelado'  },
  ];

  // Mismas 4 fases que el detalle del servicio (fuente única de verdad)
  fasesServicio = FASES_SERVICIO;

  // ── Modal de asignación (HU-13) ──────────────────────────────────────
  showAsignacionModal = false;
  modalServicioId: string | null = null;
  modalMode: 'crear' | 'editar' = 'crear';

  // ── Modal Crear / Editar Servicio ─────────────────────────────────────
  showCrearServicioModal = false;
  csmMode: 'crear' | 'editar' = 'crear';
  csmServicioId: string | null = null;

  private debounceTimer: any;

  get pagFin(): number {
    return Math.min(this.paginacion.page * this.paginacion.page_size, this.paginacion.total);
  }

  get paginas(): number[] {
    const total = this.paginacion.total_pages;
    const cur   = this.paginacion.page;
    const all   = Array.from({ length: total }, (_, i) => i + 1);
    if (total <= 7) return all;
    const near = new Set([1, total, cur - 1, cur, cur + 1].filter(n => n >= 1 && n <= total));
    return [...near].sort((a, b) => a - b);
  }

  ngOnInit(): void {
    this.proyectoId = this.route.snapshot.paramMap.get('id');
    this.cargarServicios();
  }

  onBusquedaChange(): void {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.paginacion.page = 1;
      this.cargarServicios();
    }, 350);
  }

  setFiltro(valor: string): void {
    this.filtroActual = valor;
    this.paginacion.page = 1;
    this.cargarServicios();
  }

  irPagina(p: number): void {
    if (p < 1 || p > this.paginacion.total_pages) return;
    this.paginacion.page = p;
    this.cargarServicios();
  }

  cargarServicios(): void {
    if (!this.proyectoId) {
      this.errorMessage = 'ID de proyecto inválido.';
      this.isLoading = false;
      return;
    }
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.getServiciosPorProyecto(this.proyectoId, {
      q:         this.busqueda    || undefined,
      estado:    this.filtroActual || undefined,
      page:      this.paginacion.page,
      page_size: this.paginacion.page_size,
    }).subscribe({
      next: (res: any) => {
        this.servicios  = res.servicios  ?? [];
        this.paginacion = res.paginacion ?? this.paginacion;
        this.isLoading  = false;
      },
      error: (err: any) => {
        console.error('Error cargando servicios:', err);
        this.errorMessage = err?.error?.detail ?? 'Error al cargar los servicios del proyecto.';
        this.isLoading = false;
      }
    });
  }

  volver(): void { this.router.navigate(['/operaciones']); }

  irAlServicio(id: string): void { this.router.navigate(['/operaciones/servicio', id]); }

  irAlCronograma(): void { this.router.navigate(['/operaciones/cronograma', this.proyectoId]); }

  estadoLabel(estado: string): string {
    const map: Record<string, string> = { 'En_Proceso': 'En Proceso' };
    return map[estado] ?? estado;
  }

  /** Clase del paso `n` en el stepper de la tarjeta ('done' | 'current' | ''). */
  faseClaseCard(n: number, servicio: ServicioProyecto): string {
    const c = faseClaseServicio(n, servicio.estado, servicio.progreso ?? 0);
    return c === 'active' ? 'current' : c === 'done' ? 'done' : '';
  }

  // ── HU-13: Métodos del modal ─────────────────────────────────────────

  /**
   * Abre el modal de asignación.
   * @param servicio  El servicio al que se aplica la asignación.
   * @param event     El evento del click para detener la propagación (no abrir detalle).
   */
  abrirModalAsignacion(event: Event, servicio: ServicioProyecto): void {
    event.stopPropagation();           // Evita navegar al detalle del servicio
    this.modalServicioId = servicio.id;
    this.modalMode = servicio.estado === 'Pendiente' ? 'crear' : 'editar';
    this.showAsignacionModal = true;
  }

  onModalClosed(result: { guardado: boolean }): void {
    this.showAsignacionModal = false;
    if (result.guardado) {
      this.toast.mostrar('Servicio configurado exitosamente', 'success');
      this.cargarServicios();
    }
    this.modalServicioId = null;
  }

  /** Oculto para Técnico y en estados terminales */
  puedeAsignar(servicio: ServicioProyecto): boolean {
    if (this.isTecnico) return false;
    return servicio.estado !== 'Completado' && servicio.estado !== 'Cancelado';
  }

  // ── Acciones directas de estado ─────────────────────────────────────

  cambiarEstado(event: Event, servicio: ServicioProyecto, nuevoEstado: string): void {
    event.stopPropagation();
    if (this.isTecnico) return;
    this.svc.actualizarEstado(servicio.id, nuevoEstado).subscribe({
      next: () => {
        const labels: Record<string, string> = {
          En_Proceso: 'Servicio iniciado',
          Cancelado:  'Servicio cancelado',
          Completado: 'Servicio completado',
          Pendiente:  'Servicio reabierto',
        };
        this.toast.mostrar(labels[nuevoEstado] ?? 'Estado actualizado', 'success');
        this.cargarServicios();
      },
      error: (err: any) => {
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo cambiar el estado', 'error');
      },
    });
  }

  // ── Crear / Editar Servicio ───────────────────────────────────────────

  abrirCrearServicio(): void {
    this.csmMode = 'crear';
    this.csmServicioId = null;
    this.showCrearServicioModal = true;
  }

  abrirEditarServicio(event: Event, servicio: ServicioProyecto): void {
    event.stopPropagation();
    this.csmMode = 'editar';
    this.csmServicioId = servicio.id;
    this.showCrearServicioModal = true;
  }

  onCrearServicioClosed(result: { guardado: boolean }): void {
    this.showCrearServicioModal = false;
    this.csmServicioId = null;
    if (result.guardado) {
      const msg = this.csmMode === 'crear' ? 'Servicio creado exitosamente' : 'Servicio actualizado exitosamente';
      this.toast.mostrar(msg, 'success');
      this.cargarServicios();
    }
  }
}

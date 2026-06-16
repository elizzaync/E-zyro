import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
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

@Component({
  selector: 'app-operaciones-servicios-lista',
  standalone: true,
  imports: [CommonModule, SpinnerComponent, AsignacionServicioModalComponent, CrearServicioModalComponent],
  templateUrl: './operaciones-servicios-lista.component.html',
  styleUrls: ['./operaciones-servicios-lista.component.css']
})
export class OperacionesServiciosListaComponent implements OnInit {
  private route  = inject(ActivatedRoute);
  private router = inject(Router);
  private svc    = inject(OperacionesService);
  private toast  = inject(ToastService);
  private auth   = inject(AuthService);

  get isTecnico(): boolean {
    return (this.auth.getUsuario()?.rol || '').trim() === 'Técnico de Campo';
  }
  get isJefeOperaciones(): boolean {
    return (this.auth.getUsuario()?.rol || '').trim() === 'Jefe de Operaciones';
  }

  proyectoId: string | null = null;
  servicios: ServicioProyecto[] = [];
  isLoading    = true;
  errorMessage: string | null = null;

  filtros      = ['Todos', 'Pendiente', 'En_Proceso', 'Completado'];
  filtroActual = 'Todos';

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

  get serviciosFiltrados(): ServicioProyecto[] {
    if (this.filtroActual === 'Todos') return this.servicios;
    return this.servicios.filter(s => s.estado === this.filtroActual);
  }

  ngOnInit(): void {
    this.proyectoId = this.route.snapshot.paramMap.get('id');
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
    this.svc.getServiciosPorProyecto(this.proyectoId).subscribe({
      next: (res: any) => {
        this.servicios = res;
        this.isLoading = false;
      },
      error: (err: any) => {
        console.error('Error cargando servicios:', err);
        this.errorMessage = err?.error?.detail ?? 'Error al cargar los servicios del proyecto.';
        this.isLoading = false;
      }
    });
  }

  setFiltro(filtro: string): void { this.filtroActual = filtro; }

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

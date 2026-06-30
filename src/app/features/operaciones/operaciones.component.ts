import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { OperacionesService } from '../../core/services/operaciones.service';
import { ToastService } from '../../core/services/toast.service';
import { AuthService } from '../../core/services/auth.service';
import { AlertComponent } from '../../shared/components/login/alert.component';
import { SpinnerComponent } from '../../shared/components/spinner/spinner.component';
import { CrearProyectoModalComponent } from './components/crear-proyecto-modal/crear-proyecto-modal.component';

export interface ProyectoOperacion {
  id: string;
  orden_trabajo: string;
  nombre_proyecto: string;
  estado: string;
  fecha_inicio: string | null;
  fecha_fin_estimada: string | null;
  cliente: string;
  total_servicios: number;
  servicios_completados: number;
  jefe_nombre: string;
}

interface KpisOperaciones {
  total_proyectos: number;
  servicios_completados: number;
  servicios_pendientes: number;
  tasa_avance: number;
}

interface Paginacion { total: number; page: number; page_size: number; total_pages: number; }

@Component({
  selector: 'app-operaciones',
  standalone: true,
  imports: [CommonModule, FormsModule, AlertComponent, SpinnerComponent, CrearProyectoModalComponent],
  templateUrl: './operaciones.component.html',
  styleUrls: ['./operaciones.component.css']
})
export class OperacionesComponent implements OnInit {
  private svc    = inject(OperacionesService);
  private toast  = inject(ToastService);
  private router = inject(Router);
  private auth   = inject(AuthService);

  get isTecnico(): boolean        { return this.auth.isTecnico(); }
  get isJefeOperaciones(): boolean { return this.auth.isJefeOperaciones(); }

  proyectos: ProyectoOperacion[] = [];
  kpis: KpisOperaciones = { total_proyectos: 0, servicios_completados: 0, servicios_pendientes: 0, tasa_avance: 0 };
  paginacion: Paginacion = { total: 0, page: 1, page_size: 12, total_pages: 1 };
  isLoading    = true;
  errorMessage: string | null = null;

  // ── Búsqueda y filtros ─────────────────────────────────────────────────
  busqueda     = '';
  estadoFiltro = '';
  readonly ESTADOS = ['', 'Pendiente', 'En_Proceso', 'En_Pausa', 'Completado', 'Cancelado'];

  proyectosAbierto = true;
  toggleProyectos(): void { this.proyectosAbierto = !this.proyectosAbierto; }

  // ── Modal Crear / Editar Proyecto ─────────────────────────────────────
  showCrearProyectoModal = false;
  cpmMode: 'crear' | 'editar' = 'crear';
  cpmProyectoId: string | null = null;

  private debounceTimer: any;

  ngOnInit(): void {
    this.cargarProyectos();
  }

  onBusquedaChange(): void {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.paginacion.page = 1;
      this.cargarProyectos();
    }, 350);
  }

  onFiltroEstado(estado: string): void {
    this.estadoFiltro = estado;
    this.paginacion.page = 1;
    this.cargarProyectos();
  }

  irPagina(p: number): void {
    if (p < 1 || p > this.paginacion.total_pages) return;
    this.paginacion.page = p;
    this.cargarProyectos();
  }

  get paginas(): number[] {
    const total = this.paginacion.total_pages;
    const cur   = this.paginacion.page;
    const all   = Array.from({ length: total }, (_, i) => i + 1);
    if (total <= 7) return all;
    const near = new Set([1, total, cur - 1, cur, cur + 1].filter(n => n >= 1 && n <= total));
    return [...near].sort((a, b) => a - b);
  }

  get pagFin(): number {
    return Math.min(this.paginacion.page * this.paginacion.page_size, this.paginacion.total);
  }

  cargarProyectos(): void {
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.getProyectos({
      q:         this.busqueda   || undefined,
      estado:    this.estadoFiltro || undefined,
      page:      this.paginacion.page,
      page_size: this.paginacion.page_size,
    }).subscribe({
      next: (res: any) => {
        this.kpis       = res.kpis       ?? this.kpis;
        this.proyectos  = res.proyectos  ?? [];
        this.paginacion = res.paginacion ?? this.paginacion;
        this.isLoading  = false;
      },
      error: (err: any) => {
        console.error('Error cargando proyectos:', err);
        this.errorMessage = 'Error de conexión con el servidor. Intenta nuevamente.';
        this.toast.mostrar('Error de conexión', 'error');
        this.isLoading = false;
      }
    });
  }

  porcentaje(p: ProyectoOperacion): number {
    if (!p.total_servicios) return 0;
    return Math.round(p.servicios_completados / p.total_servicios * 100);
  }

  irAProyecto(id: string): void {
    this.router.navigate(['/operaciones/proyecto', id]);
  }

  estadoClass(estado: string): string {
    const map: Record<string, string> = {
      'Pendiente':  'estado-pendiente',
      'En_Proceso': 'estado-en-proceso',
      'En_Pausa':   'estado-en-pausa',
      'Completado': 'estado-completado',
      'Cancelado':  'estado-cancelado',
    };
    return map[estado] ?? 'estado-pendiente';
  }

  estadoLabel(estado: string): string {
    const map: Record<string, string> = {
      'En_Proceso': 'En Proceso',
      'En_Pausa':   'En Pausa',
    };
    return map[estado] ?? estado;
  }

  // ── Modal ─────────────────────────────────────────────────────────────

  abrirCrearProyecto(): void {
    this.cpmMode = 'crear';
    this.cpmProyectoId = null;
    this.showCrearProyectoModal = true;
  }

  abrirEditarProyecto(event: Event, id: string): void {
    event.stopPropagation();
    this.cpmMode = 'editar';
    this.cpmProyectoId = id;
    this.showCrearProyectoModal = true;
  }

  onCrearProyectoClosed(result: { guardado: boolean; proyectoId?: string }): void {
    this.showCrearProyectoModal = false;
    this.cpmProyectoId = null;
    if (result.guardado) {
      const msg = this.cpmMode === 'crear' ? 'Proyecto creado exitosamente' : 'Proyecto actualizado exitosamente';
      this.toast.mostrar(msg, 'success');
      this.cargarProyectos();
      if (this.cpmMode === 'crear' && result.proyectoId) {
        this.router.navigate(['/operaciones/proyecto', result.proyectoId]);
      }
    }
  }
}

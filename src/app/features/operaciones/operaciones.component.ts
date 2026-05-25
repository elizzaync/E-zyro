import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { OperacionesService } from '../../core/services/operaciones.service';
import { ToastService } from '../../core/services/toast.service';
import { AlertComponent } from '../../shared/components/login/alert.component';
import { SpinnerComponent } from '../../shared/components/spinner/spinner.component';
import { CrearProyectoModalComponent } from './components/crear-proyecto-modal/crear-proyecto-modal.component';

export interface ProyectoOperacion {
  id: string;
  orden_trabajo: string;
  nombre_proyecto: string;
  estado: string;
  fecha_inicio: string | null;
  fecha_fin_estimada: string | null;   // nuevo — para cronograma / Gantt
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

@Component({
  selector: 'app-operaciones',
  standalone: true,
  imports: [CommonModule, AlertComponent, SpinnerComponent, CrearProyectoModalComponent],
  templateUrl: './operaciones.component.html',
  styleUrls: ['./operaciones.component.css']
})
export class OperacionesComponent implements OnInit {
  private svc    = inject(OperacionesService);
  private toast  = inject(ToastService);
  private router = inject(Router);

  proyectos: ProyectoOperacion[] = [];
  kpis: KpisOperaciones = { total_proyectos: 0, servicios_completados: 0, servicios_pendientes: 0, tasa_avance: 0 };
  isLoading    = true;
  errorMessage: string | null = null;

  // ── Modal Crear / Editar Proyecto ─────────────────────────────────────
  showCrearProyectoModal = false;
  cpmMode: 'crear' | 'editar' = 'crear';
  cpmProyectoId: string | null = null;

  ngOnInit(): void { this.cargarProyectos(); }

  cargarProyectos(): void {
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.getProyectos().subscribe({
      next: (res: any) => {
        this.kpis      = res.kpis     ?? this.kpis;
        this.proyectos = res.proyectos ?? [];
        this.isLoading = false;
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

  // ── Modal Crear / Editar Proyecto ─────────────────────────────────────

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

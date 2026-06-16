import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { AuthService } from '../../../../core/services/auth.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { CrearProyectoServicioModalComponent } from '../../../operaciones/components/crear-proyecto-servicio-modal/crear-proyecto-servicio-modal.component';
import { CrearServicioModalComponent } from '../../../operaciones/components/crear-servicio-modal/crear-servicio-modal.component';
import { ToastService } from '../../../../core/services/toast.service';

@Component({
  selector: 'app-logistica-servicios',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, CrearProyectoServicioModalComponent, CrearServicioModalComponent],
  templateUrl: './logistica-servicios.component.html',
  styleUrls: ['./logistica-servicios.component.css'],
})
export class LogisticaServiciosComponent implements OnInit {
  private svc    = inject(LogisticaService);
  private router = inject(Router);
  private auth   = inject(AuthService);
  private toast  = inject(ToastService);

  servicios: any[] = [];
  isLoading = true;
  errorMessage: string | null = null;

  busqueda     = '';
  filtroEstado = '';
  filtroCliente   = '';
  filtroUbicacion = '';
  page = 1;
  readonly PER_PAGE = 10;

  showCrearProyectoModal = false;
  showCrearServicioModal = false;

  get isTecnico(): boolean {
    return (this.auth.getUsuario()?.rol || '').trim() === 'Técnico de Campo';
  }

  get isJefeOperaciones(): boolean {
    return (this.auth.getUsuario()?.rol || '').trim() === 'Jefe de Operaciones';
  }

  get puedeCrear(): boolean {
    return !this.isTecnico && !this.isJefeOperaciones;
  }

  get clientesUnicos(): string[] {
    return [...new Set(this.servicios.map(s => s.cliente).filter(Boolean))].sort();
  }

  get ubicacionesUnicas(): string[] {
    return [...new Set(this.servicios.map(s => s.ubicacion).filter(Boolean))].sort();
  }

  get hayFiltros(): boolean {
    return !!(this.busqueda || this.filtroEstado || this.filtroCliente || this.filtroUbicacion);
  }

  setEstado(e: string): void { this.filtroEstado = e; this.page = 1; }

  limpiarFiltros(): void {
    this.busqueda = '';
    this.filtroEstado = '';
    this.filtroCliente = '';
    this.filtroUbicacion = '';
    this.page = 1;
  }

  get filtrados(): any[] {
    const term = this.busqueda.toLowerCase().trim();
    return this.servicios.filter(s => {
      const matchTerm = !term ||
        s.nombre.toLowerCase().includes(term) ||
        s.nombre_proyecto.toLowerCase().includes(term) ||
        s.cliente.toLowerCase().includes(term) ||
        s.orden_trabajo.toLowerCase().includes(term) ||
        (s.tipo_servicio || '').toLowerCase().includes(term) ||
        (s.ubicacion || '').toLowerCase().includes(term);
      const matchEstado    = !this.filtroEstado    || s.estado    === this.filtroEstado;
      const matchCliente   = !this.filtroCliente   || s.cliente   === this.filtroCliente;
      const matchUbicacion = !this.filtroUbicacion || s.ubicacion === this.filtroUbicacion;
      return matchTerm && matchEstado && matchCliente && matchUbicacion;
    });
  }

  get paginados(): any[] {
    const start = (this.page - 1) * this.PER_PAGE;
    return this.filtrados.slice(start, start + this.PER_PAGE);
  }

  get totalPaginas(): number {
    return Math.max(1, Math.ceil(this.filtrados.length / this.PER_PAGE));
  }

  get botonesPage(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(1, this.page - 2); i <= Math.min(this.totalPaginas, this.page + 2); i++) pages.push(i);
    return pages;
  }

  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) this.page = p; }

  onFiltroChange(): void { this.page = 1; }

  get kpis() {
    const total = this.servicios.length;
    const completados = this.servicios.filter(s => s.estado === 'Completado').length;
    const pendientes  = this.servicios.filter(s => s.estado === 'Pendiente').length;
    const enProceso   = this.servicios.filter(s => s.estado === 'En_Proceso').length;
    return { total, completados, pendientes, enProceso };
  }

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.getServiciosGlobal().subscribe({
      next: (data) => { this.servicios = data; this.isLoading = false; },
      error: () => {
        this.errorMessage = 'Error de conexión con el servidor.';
        this.isLoading = false;
      },
    });
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
    const map: Record<string, string> = { 'En_Proceso': 'En Proceso', 'En_Pausa': 'En Pausa' };
    return map[estado] ?? estado;
  }

  irAServicio(s: any): void {
    this.router.navigate(['/operaciones/proyecto', s.proyecto_id]);
  }

  abrirCrearProyecto(): void { this.showCrearProyectoModal = true; }
  abrirCrearServicio(): void { this.showCrearServicioModal = true; }

  onCrearClosed(result: { guardado: boolean; proyectoId?: string; servicioId?: string }): void {
    this.showCrearProyectoModal = false;
    if (result.guardado) {
      this.toast.mostrar('Proyecto y servicio creados exitosamente', 'success');
      this.cargar();
    }
  }

  onCrearServicioClosed(result: { guardado: boolean }): void {
    this.showCrearServicioModal = false;
    if (result.guardado) {
      this.toast.mostrar('Servicio creado exitosamente', 'success');
      this.cargar();
    }
  }
}

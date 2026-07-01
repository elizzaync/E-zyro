import { Component, OnInit, Output, EventEmitter, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { AuthService } from '../../../../core/services/auth.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { EquipoFormModalComponent } from '../equipo-form-modal/equipo-form-modal.component';
import { EquipoMovimientosModalComponent } from '../equipo-movimientos-modal/equipo-movimientos-modal.component';
import { RellenarStockModalComponent } from '../rellenar-stock-modal/rellenar-stock-modal.component';
import { ReporteModalComponent } from '../reporte-modal/reporte-modal.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import {
  EquipoHerramienta, ClaseArticulo, EstadoEquipo, FrecuenciaMantenimiento,
  EquipoStockDesglose,
} from '../../logistica.models';

@Component({
  selector: 'app-equipos-tabla',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, EquipoFormModalComponent, EquipoMovimientosModalComponent, RellenarStockModalComponent, ReporteModalComponent, AppModalComponent],
  templateUrl: './equipos-tabla.component.html',
  styleUrls: ['./equipos-tabla.component.css']
})
export class EquiposTablaComponent implements OnInit {
  @Output() cambio = new EventEmitter<void>();

  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);
  private auth  = inject(AuthService);

  get isTecnico(): boolean { return this.auth.isTecnico(); }
  get esOperativo(): boolean { return this.auth.isTecnico() || this.auth.isJefeOperaciones(); }

  equipos: EquipoHerramienta[] = [];
  cargando = true;

  // Filtros
  busqueda = '';
  filtroClase: 'todas' | ClaseArticulo = 'todas';
  filtroEstado: 'todos' | EstadoEquipo = 'todos';

  // Paginación
  pagina = 1;
  tamanoPagina = 8;

  // Modal
  showModal = false;
  guardando = false;
  equipoEnEdicion: EquipoHerramienta | null = null;

  // Eliminación
  equipoAEliminar: EquipoHerramienta | null = null;
  eliminando = false;

  // Tooltip desglose stock
  tooltipEquipoId:   string | null   = null;
  tooltipDesglose:   EquipoStockDesglose | null = null;
  tooltipCargando    = false;

  // Historial de movimientos
  movimientosEquipoId:   string | null = null;
  movimientosEquipoNombre = '';

  // Rellenar stock
  showRellenarStock = false;

  // Modal reportes
  showReporte = false;

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getEquipos().subscribe({
      next: (data) => { this.equipos = data; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar equipos.', 'error'); }
    });
  }

  get equiposFiltrados(): EquipoHerramienta[] {
    const q = this.busqueda.toLowerCase().trim();
    return this.equipos.filter(e => {

      const matchTexto = !q
        || e.nombre.toLowerCase().includes(q)
        || e.codigo.toLowerCase().includes(q)
        || (e.marca ?? '').toLowerCase().includes(q)
        || (e.numeroSerie ?? '').toLowerCase().includes(q);
      const matchClase = this.filtroClase === 'todas' || e.clase === this.filtroClase;
      const matchEstado = this.filtroEstado === 'todos' || e.estado === this.filtroEstado;
      return matchTexto && matchClase && matchEstado;
    });
  }

  get totalPaginas(): number {
    return Math.max(1, Math.ceil(this.equiposFiltrados.length / this.tamanoPagina));
  }
  get equiposPagina(): EquipoHerramienta[] {
    const ini = (this.pagina - 1) * this.tamanoPagina;
    return this.equiposFiltrados.slice(ini, ini + this.tamanoPagina);
  }
  onFiltroCambio(): void { this.pagina = 1; }
  irPagina(p: number): void { this.pagina = Math.min(Math.max(1, p), this.totalPaginas); }

  // ── Helpers de presentación ──
  claseLabel(c: ClaseArticulo): string {
    if (c === 'equipo') return 'Equipo';
    if (c === 'equipo_tecnologico') return 'Eq. TI';
    return 'Herramienta';
  }

  estadoLabel(e: EstadoEquipo): string {
    const m: Record<EstadoEquipo, string> = {
      operativo: 'Operativo', en_mantenimiento: 'En mantenimiento',
      fuera_de_servicio: 'Fuera de servicio', baja: 'De baja',
    };
    return m[e];
  }
  estadoClase(e: EstadoEquipo): string { return 'est-' + e.replace(/_/g, '-'); }

  frecuenciaLabel(f: FrecuenciaMantenimiento): string {
    const m: Record<FrecuenciaMantenimiento, string> = {
      ninguno: 'No requiere', mensual: 'Mensual', trimestral: 'Trimestral',
      semestral: 'Semestral', anual: 'Anual',
    };
    return m[f];
  }

  /** true si el próximo mantenimiento está vencido o es hoy. */
  mantenimientoVencido(e: EquipoHerramienta): boolean {
    if (!e.requiereMantenimiento || !e.proximaFechaMantenimiento) return false;
    return new Date(e.proximaFechaMantenimiento) <= new Date();
  }

  // ── Tooltip desglose ──
  mostrarTooltip(e: EquipoHerramienta): void {
    this.tooltipEquipoId = e.id;
    this.tooltipDesglose = null;
    // Solo consulta el API si hay incidencias activas (estado indica problema)
    if (this.tieneIncidencias(e)) {
      this.tooltipCargando = true;
      this.svc.getDesgloseEquipo(e.id).subscribe({
        next:  d => { this.tooltipDesglose = d; this.tooltipCargando = false; },
        error: () => { this.tooltipCargando = false; },
      });
    }
  }

  ocultarTooltip(): void { this.tooltipEquipoId = null; this.tooltipDesglose = null; }

  tieneIncidencias(e: EquipoHerramienta): boolean {
    return e.estado === 'en_mantenimiento' || e.estado === 'fuera_de_servicio';
  }

  onRellenarStockClosed(r: { guardado: boolean }): void {
    this.showRellenarStock = false;
    if (r.guardado) { this.cargar(); this.cambio.emit(); }
  }

  // ── Historial ──
  verHistorial(e: EquipoHerramienta): void {
    this.movimientosEquipoId     = e.id;
    this.movimientosEquipoNombre = e.nombre;
  }
  cerrarHistorial(): void { this.movimientosEquipoId = null; this.movimientosEquipoNombre = ''; }

  // ── CRUD ──
  abrirCrear(): void { this.equipoEnEdicion = null; this.showModal = true; }
  abrirEditar(e: EquipoHerramienta): void { this.equipoEnEdicion = e; this.showModal = true; }
  cerrarModal(): void { this.showModal = false; this.equipoEnEdicion = null; }

  onGuardar(data: any): void {
    this.guardando = true;
    const obs = this.equipoEnEdicion
      ? this.svc.actualizarEquipo(this.equipoEnEdicion.id, data)
      : this.svc.crearEquipo(data);
    obs.subscribe({
      next: () => {
        this.guardando = false;
        this.cerrarModal();
        this.toast.mostrar(this.equipoEnEdicion ? 'Registro actualizado.' : 'Registro creado.', 'success');
        this.cargar();
        this.cambio.emit();
      },
      error: () => { this.guardando = false; this.toast.mostrar('No se pudo guardar.', 'error'); }
    });
  }

  pedirEliminar(e: EquipoHerramienta): void { this.equipoAEliminar = e; }
  cancelarEliminar(): void { this.equipoAEliminar = null; }
  confirmarEliminar(): void {
    if (!this.equipoAEliminar) return;
    this.eliminando = true;
    this.svc.eliminarEquipo(this.equipoAEliminar.id).subscribe({
      next: () => {
        this.eliminando = false;
        this.equipoAEliminar = null;
        this.toast.mostrar('Registro eliminado.', 'success');
        this.cargar();
        this.cambio.emit();
      },
      error: (err) => {
        this.eliminando = false;
        const msg = err?.error?.detail ?? 'No se pudo eliminar.';
        this.toast.mostrar(msg, 'error');
      }
    });
  }
}

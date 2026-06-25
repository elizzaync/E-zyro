import { Component, OnInit, Output, EventEmitter, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { MaterialFormModalComponent } from '../material-form-modal/material-form-modal.component';
import { RellenarStockModalComponent } from '../rellenar-stock-modal/rellenar-stock-modal.component';
import { ReporteModalComponent } from '../reporte-modal/reporte-modal.component';
import { MaterialLog } from '../../logistica.models';

@Component({
  selector: 'app-materiales-tabla',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, MaterialFormModalComponent, RellenarStockModalComponent, ReporteModalComponent],
  templateUrl: './materiales-tabla.component.html',
  styleUrls: ['./materiales-tabla.component.css']
})
export class MaterialesTablaComponent implements OnInit {
  @Output() cambio = new EventEmitter<void>();

  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  materiales: MaterialLog[] = [];
  cargando = true;

  // Filtros
  busqueda = '';
  filtroCategoria = 'Todas';
  filtroEstado: 'todos' | 'activos' | 'inactivos' | 'stock_bajo' = 'todos';

  // Paginación (alineada con HU-15: GET /materiales con filtros y paginación)
  pagina = 1;
  tamanoPagina = 8;

  // Modal crear/editar
  showModal = false;
  guardando = false;
  materialEnEdicion: MaterialLog | null = null;

  // Modal rellenar stock
  showRellenarStock = false;

  // Modal reportes
  showReporte = false;

  // Confirmación de eliminación
  materialAEliminar: MaterialLog | null = null;
  eliminando = false;

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getMateriales().subscribe({
      next: (data) => { this.materiales = data; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar materiales.', 'error'); }
    });
  }

  get categorias(): string[] {
    return ['Todas', ...new Set(this.materiales.map(m => m.categoria))];
  }

  get materialesFiltrados(): MaterialLog[] {
    const q = this.busqueda.toLowerCase().trim();
    return this.materiales.filter(m => {
      const cat = m.categoria ?? '';
      const matchTexto = !q
        || m.nombre.toLowerCase().includes(q)
        || m.codigo.toLowerCase().includes(q)
        || cat.toLowerCase().includes(q);
      const matchCat = this.filtroCategoria === 'Todas' || cat === this.filtroCategoria;
      const matchEstado =
        this.filtroEstado === 'todos' ||
        (this.filtroEstado === 'activos'    && m.activo) ||
        (this.filtroEstado === 'inactivos'  && !m.activo) ||
        (this.filtroEstado === 'stock_bajo' && m.cantidad <= m.stockMinimo);
      return matchTexto && matchCat && matchEstado;
    });
  }

  // ── Paginación ──
  get totalPaginas(): number {
    return Math.max(1, Math.ceil(this.materialesFiltrados.length / this.tamanoPagina));
  }
  get materialesPagina(): MaterialLog[] {
    const ini = (this.pagina - 1) * this.tamanoPagina;
    return this.materialesFiltrados.slice(ini, ini + this.tamanoPagina);
  }
  /** Reinicia a la primera página cuando cambian los filtros. */
  onFiltroCambio(): void { this.pagina = 1; }
  irPagina(p: number): void {
    this.pagina = Math.min(Math.max(1, p), this.totalPaginas);
  }

  stockBajo(m: MaterialLog): boolean { return m.cantidad <= m.stockMinimo; }

  onRellenarStockClosed(r: { guardado: boolean }): void {
    this.showRellenarStock = false;
    if (r.guardado) { this.cargar(); this.cambio.emit(); }
  }

  // ── CRUD ──
  abrirCrear(): void { this.materialEnEdicion = null; this.showModal = true; }
  abrirEditar(m: MaterialLog): void { this.materialEnEdicion = m; this.showModal = true; }
  cerrarModal(): void { this.showModal = false; this.materialEnEdicion = null; }

  onGuardar(data: any): void {
    this.guardando = true;
    const obs = this.materialEnEdicion
      ? this.svc.actualizarMaterial(this.materialEnEdicion.id, data)
      : this.svc.crearMaterial(data);
    obs.subscribe({
      next: () => {
        this.guardando = false;
        this.cerrarModal();
        this.toast.mostrar(this.materialEnEdicion ? 'Material actualizado.' : 'Material creado.', 'success');
        this.cargar();
        this.cambio.emit();
      },
      error: () => { this.guardando = false; this.toast.mostrar('No se pudo guardar.', 'error'); }
    });
  }

  pedirEliminar(m: MaterialLog): void { this.materialAEliminar = m; }
  cancelarEliminar(): void { this.materialAEliminar = null; }
  confirmarEliminar(): void {
    if (!this.materialAEliminar) return;
    this.eliminando = true;
    this.svc.eliminarMaterial(this.materialAEliminar.id).subscribe({
      next: () => {
        this.eliminando = false;
        this.materialAEliminar = null;
        this.toast.mostrar('Material eliminado.', 'success');
        this.cargar();
        this.cambio.emit();
      },
      error: () => { this.eliminando = false; this.toast.mostrar('No se pudo eliminar.', 'error'); }
    });
  }
}

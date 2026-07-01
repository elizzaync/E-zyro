import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, CentroCosto, ComparativoCentro } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

@Component({
  selector: 'app-controlling',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
  templateUrl: './controlling.component.html',
  styleUrls: ['./controlling.component.css']
})
export class ControllingComponent implements OnInit {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  cargando = false;
  centros: CentroCosto[] = [];
  comparativo: ComparativoCentro | null = null;
  centroSeleccionado: string | null = null;

  desde = new Date(new Date().getFullYear(), 0, 1).toISOString().slice(0, 10);
  hasta = new Date().toISOString().slice(0, 10);

  showForm = false;
  nuevo: Partial<CentroCosto> = {};
  guardando = false;

  page = 1;
  readonly PER_PAGE = 10;

  get paginados(): CentroCosto[] {
    const s = (this.page - 1) * this.PER_PAGE;
    return this.centros.slice(s, s + this.PER_PAGE);
  }
  get totalPaginas(): number { return Math.max(1, Math.ceil(this.centros.length / this.PER_PAGE)); }
  get totalItems(): number { return this.centros.length; }
  get botonesPage(): number[] {
    const pp: number[] = [];
    for (let i = Math.max(1, this.page - 2); i <= Math.min(this.totalPaginas, this.page + 2); i++) pp.push(i);
    return pp;
  }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) this.page = p; }

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.page = 1;
    this.svc.getCentrosCosto().subscribe({
      next: d => { this.centros = d; this.cargando = false; },
      error: () => { this.cargando = false; }
    });
  }

  verComparativo(c: CentroCosto): void {
    this.centroSeleccionado = c.id;
    this.comparativo = null;
    this.svc.getComparativoCentro(c.id, this.desde, this.hasta).subscribe({
      next: d => { this.comparativo = d; },
      error: () => this.toast.mostrar('Error al cargar comparativo', 'error')
    });
  }

  guardar(): void {
    this.guardando = true;
    this.svc.crearCentroCosto(this.nuevo).subscribe({
      next: () => {
        this.toast.mostrar('Centro de costo creado', 'success');
        this.showForm = false;
        this.nuevo = {};
        this.guardando = false;
        this.cargar();
      },
      error: () => { this.guardando = false; this.toast.mostrar('Error al crear', 'error'); }
    });
  }

  eliminar(c: CentroCosto): void {
    if (!confirm(`¿Eliminar el centro "${c.nombre}"?`)) return;
    this.svc.eliminarCentroCosto(c.id).subscribe({
      next: () => { this.toast.mostrar('Centro eliminado', 'success'); this.cargar(); },
      error: () => this.toast.mostrar('Error al eliminar', 'error')
    });
  }

  get porcentajeEjecutado(): number {
    if (!this.comparativo || !this.comparativo.presupuesto) return 0;
    return Math.round((this.comparativo.costo_real / this.comparativo.presupuesto) * 100);
  }
}

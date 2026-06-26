import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, CentroCosto, ComparativoCentro } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';

@Component({
  selector: 'app-controlling',
  standalone: true,
  imports: [CommonModule, FormsModule],
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

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
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

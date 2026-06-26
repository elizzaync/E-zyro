import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';

type TabRep = 'balance-general' | 'estado-resultados' | 'flujo-efectivo' | 'libro-diario';

@Component({
  selector: 'app-reportes',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './reportes.component.html',
  styleUrls: ['./reportes.component.css']
})
export class ReportesComponent {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  tab: TabRep = 'balance-general';
  cargando = false;
  datos: any = null;

  // Filtros
  fechaCorte = new Date().toISOString().slice(0, 10);
  periodoActual = new Date().toISOString().slice(0, 7); // YYYY-MM
  desdeEstado = new Date(new Date().getFullYear(), 0, 1).toISOString().slice(0, 10);
  hastaEstado = new Date().toISOString().slice(0, 10);

  setTab(t: TabRep): void { this.tab = t; this.datos = null; }

  consultar(): void {
    this.cargando = true;
    this.datos = null;
    let obs$;
    if (this.tab === 'balance-general') {
      obs$ = this.svc.getBalanceGeneral(this.fechaCorte);
    } else if (this.tab === 'estado-resultados') {
      obs$ = this.svc.getEstadoResultados(this.desdeEstado, this.hastaEstado);
    } else if (this.tab === 'flujo-efectivo') {
      obs$ = this.svc.getFlujoEfectivo(this.periodoActual);
    } else {
      obs$ = this.svc.getLibroDiario(this.periodoActual);
    }
    obs$.subscribe({
      next: d => { this.datos = d; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar reporte', 'error'); }
    });
  }

  get filas(): any[] {
    if (!this.datos) return [];
    if (Array.isArray(this.datos)) return this.datos;
    if (this.datos.filas) return this.datos.filas;
    return Object.entries(this.datos).map(([k, v]) => ({ descripcion: k, valor: v }));
  }
}

import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, PlanillaItem } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';

type TabPlan = 'planillas' | 'conceptos' | 'empleados';

@Component({
  selector: 'app-planilla',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './planilla.component.html',
  styleUrls: ['./planilla.component.css']
})
export class PlanillaComponent implements OnInit {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  tab: TabPlan = 'planillas';
  cargando = false;

  planillas: PlanillaItem[] = [];
  conceptos: any[] = [];
  empleados: any[] = [];

  periodoCalculo = new Date().toISOString().slice(0, 7);
  calculando = false;

  boletasVisible: string | null = null;
  boletas: any[] = [];
  cargandoBoletas = false;

  ngOnInit(): void { this.cargar(); }
  setTab(t: TabPlan): void { this.tab = t; this.cargar(); }

  cargar(): void {
    this.cargando = true;
    if (this.tab === 'planillas') {
      this.svc.getPlanillas().subscribe({
        next: d => { this.planillas = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    } else if (this.tab === 'conceptos') {
      this.svc.getConceptosPlanilla().subscribe({
        next: d => { this.conceptos = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    } else {
      this.svc.getEmpleadosPlanilla().subscribe({
        next: d => { this.empleados = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    }
  }

  calcular(): void {
    if (!this.periodoCalculo) return;
    this.calculando = true;
    this.svc.calcularPlanilla(this.periodoCalculo).subscribe({
      next: () => {
        this.calculando = false;
        this.toast.mostrar('Planilla calculada', 'success');
        this.cargar();
      },
      error: () => { this.calculando = false; this.toast.mostrar('Error al calcular planilla', 'error'); }
    });
  }

  aprobar(p: PlanillaItem): void {
    this.svc.aprobarPlanilla(p.id).subscribe({
      next: () => { p.estado = 'aprobada'; this.toast.mostrar('Planilla aprobada', 'success'); },
      error: () => this.toast.mostrar('Error al aprobar', 'error')
    });
  }

  marcarPagada(p: PlanillaItem): void {
    this.svc.marcarPagadaPlanilla(p.id).subscribe({
      next: () => { p.estado = 'pagada'; this.toast.mostrar('Planilla marcada como pagada', 'success'); },
      error: () => this.toast.mostrar('Error', 'error')
    });
  }

  verBoletas(p: PlanillaItem): void {
    if (this.boletasVisible === p.id) { this.boletasVisible = null; return; }
    this.boletasVisible = p.id;
    this.cargandoBoletas = true;
    this.svc.getBoletas(p.id).subscribe({
      next: d => { this.boletas = d; this.cargandoBoletas = false; },
      error: () => { this.cargandoBoletas = false; }
    });
  }

  estadoClase(e: string): string {
    if (e === 'aprobada') return 'badge-ok';
    if (e === 'pagada')   return 'badge-ok';
    if (e === 'borrador') return 'badge-warn';
    if (e === 'anulada')  return 'badge-off';
    return 'badge-off';
  }
}

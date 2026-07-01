import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, CuentaContable, PeriodoContable, Asiento } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

type TabCont = 'plan' | 'periodos' | 'asientos';

@Component({
  selector: 'app-contabilidad',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
  templateUrl: './contabilidad.component.html',
  styleUrls: ['./contabilidad.component.css']
})
export class ContabilidadComponent implements OnInit {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  tab: TabCont = 'plan';
  cargando = false;

  cuentas: CuentaContable[] = [];
  filtroCuenta = '';
  filtroTipo = '';
  filtroSoloActivas = false;

  periodos: PeriodoContable[] = [];
  showNuevoPeriodo = false;
  nuevoPeriodoAnio = new Date().getFullYear();
  nuevoPeriodoMes  = new Date().getMonth() + 1;
  guardandoPeriodo = false;

  asientos: Asiento[] = [];
  filtroAsientoPeriodo = '';
  asientoDetalle: Asiento | null = null;

  readonly meses = ['Enero','Febrero','Marzo','Abril','Mayo','Junio',
                    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];

  page = 1;
  readonly PER_PAGE = 10;

  private get listaActiva(): any[] {
    if (this.tab === 'plan') return this.cuentasFiltradas;
    if (this.tab === 'asientos') return this.asientos;
    return this.periodos;
  }
  get paginados(): any[] {
    const s = (this.page - 1) * this.PER_PAGE;
    return this.listaActiva.slice(s, s + this.PER_PAGE);
  }
  get totalPaginas(): number { return Math.max(1, Math.ceil(this.listaActiva.length / this.PER_PAGE)); }
  get totalItems(): number { return this.listaActiva.length; }
  get botonesPage(): number[] {
    const pp: number[] = [];
    for (let i = Math.max(1, this.page - 2); i <= Math.min(this.totalPaginas, this.page + 2); i++) pp.push(i);
    return pp;
  }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) this.page = p; }
  resetPage(): void { this.page = 1; }

  ngOnInit(): void { this.cargar(); }

  setTab(t: TabCont): void {
    this.tab = t;
    this.page = 1;
    this.cargar();
  }

  cargar(): void {
    this.cargando = true;
    this.page = 1;
    if (this.tab === 'plan') {
      this.svc.getPlanCuentas().subscribe({
        next: d => { this.cuentas = d; this.cargando = false; },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar plan de cuentas', 'error'); }
      });
    } else if (this.tab === 'periodos') {
      this.svc.getPeriodos().subscribe({
        next: d => { this.periodos = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    } else if (this.tab === 'asientos') {
      this.svc.getAsientos(this.filtroAsientoPeriodo ? { periodo_id: this.filtroAsientoPeriodo } : {}).subscribe({
        next: d => { this.asientos = d; this.cargando = false; },
        error: () => { this.cargando = false; }
      });
    }
  }

  get cuentasFiltradas(): CuentaContable[] {
    const q = this.filtroCuenta.toLowerCase().trim();
    return this.cuentas.filter(c =>
      (!q || c.codigo.toLowerCase().includes(q) || c.nombre.toLowerCase().includes(q)) &&
      (!this.filtroTipo || c.tipo === this.filtroTipo) &&
      (!this.filtroSoloActivas || c.activo)
    );
  }

  toggleCuenta(c: CuentaContable): void {
    this.svc.activarCuenta(c.id, !c.activo).subscribe({
      next: () => { c.activo = !c.activo; },
      error: () => this.toast.mostrar('Error al cambiar estado', 'error')
    });
  }

  crearPeriodo(): void {
    this.guardandoPeriodo = true;
    this.svc.crearPeriodo(this.nuevoPeriodoAnio, this.nuevoPeriodoMes).subscribe({
      next: () => {
        this.toast.mostrar('Periodo creado', 'success');
        this.showNuevoPeriodo = false;
        this.guardandoPeriodo = false;
        this.cargar();
      },
      error: () => { this.guardandoPeriodo = false; this.toast.mostrar('Error al crear periodo', 'error'); }
    });
  }

  cerrarPeriodo(p: PeriodoContable): void {
    this.svc.cerrarPeriodo(p.id).subscribe({
      next: () => { p.estado = 'cerrado'; this.toast.mostrar('Periodo cerrado', 'success'); },
      error: () => this.toast.mostrar('Error al cerrar periodo', 'error')
    });
  }

  reabrirPeriodo(p: PeriodoContable): void {
    this.svc.reabrirPeriodo(p.id).subscribe({
      next: () => { p.estado = 'abierto'; this.toast.mostrar('Periodo reabierto', 'success'); },
      error: () => this.toast.mostrar('Error al reabrir periodo', 'error')
    });
  }

  mesNombre(m: number): string { return this.meses[m - 1] ?? String(m); }

  verAsiento(a: Asiento): void {
    this.asientoDetalle = this.asientoDetalle?.id === a.id ? null : a;
  }
}

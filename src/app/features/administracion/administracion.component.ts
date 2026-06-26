import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, ActivatedRoute } from '@angular/router';
import { ContabilidadComponent } from './components/contabilidad/contabilidad.component';
import { CxcComponent } from './components/cxc/cxc.component';
import { CxpComponent } from './components/cxp/cxp.component';
import { ReportesComponent } from './components/reportes/reportes.component';
import { PlanillaComponent } from './components/planilla/planilla.component';
import { ControllingComponent } from './components/controlling/controlling.component';
import { TributarioComponent } from './components/tributario/tributario.component';
import { CajaChicaComponent } from './components/caja-chica/caja-chica.component';
import { ConciliacionComponent } from './components/conciliacion/conciliacion.component';
import { ActivosFijosComponent } from './components/activos-fijos/activos-fijos.component';

type TabAdm =
  | 'contabilidad' | 'cxc' | 'cxp' | 'reportes'
  | 'planilla' | 'controlling' | 'tributario'
  | 'caja-chica' | 'conciliacion' | 'activos-fijos';

const TABS: { key: TabAdm; label: string; desc: string; color: string }[] = [
  { key: 'contabilidad',  label: 'Contabilidad',         desc: 'Plan de cuentas, periodos y asientos',      color: '#6366f1' },
  { key: 'cxc',          label: 'Cuentas por Cobrar',    desc: 'Facturas de clientes, cobros y saldos',     color: '#10b981' },
  { key: 'cxp',          label: 'Cuentas por Pagar',     desc: 'Facturas de proveedores, pagos y saldos',   color: '#ef4444' },
  { key: 'reportes',     label: 'Reportes Financieros',  desc: 'Balance, resultados y flujo de efectivo',   color: '#3b82f6' },
  { key: 'planilla',     label: 'Planilla',              desc: 'Cálculo y aprobación de nómina',            color: '#8b5cf6' },
  { key: 'controlling',  label: 'Controlling',           desc: 'Centros de costo y comparativos',           color: '#14b8a6' },
  { key: 'tributario',   label: 'Tributario',            desc: 'Registros de compras y ventas',             color: '#f97316' },
  { key: 'caja-chica',   label: 'Caja Chica',            desc: 'Fondos fijos y movimientos',                color: '#f59e0b' },
  { key: 'conciliacion', label: 'Conciliación Bancaria', desc: 'Cuentas y movimientos bancarios',           color: '#06b6d4' },
  { key: 'activos-fijos',label: 'Activos Fijos',         desc: 'Inventario y depreciación de activos',      color: '#64748b' },
];

@Component({
  selector: 'app-administracion',
  standalone: true,
  imports: [
    CommonModule,
    ContabilidadComponent, CxcComponent, CxpComponent, ReportesComponent,
    PlanillaComponent, ControllingComponent, TributarioComponent,
    CajaChicaComponent, ConciliacionComponent, ActivosFijosComponent,
  ],
  templateUrl: './administracion.component.html',
  styleUrls: ['./administracion.component.css']
})
export class AdministracionComponent implements OnInit {
  private router = inject(Router);
  private route  = inject(ActivatedRoute);

  tab: TabAdm = 'contabilidad';
  readonly tabs = TABS;

  ngOnInit(): void {
    this.route.queryParams.subscribe(params => {
      const t = params['tab'] as TabAdm;
      if (t && TABS.some(x => x.key === t)) this.tab = t;
    });
  }

  setTab(t: TabAdm): void {
    this.tab = t;
    this.router.navigate([], { queryParams: { tab: t }, replaceUrl: true });
  }

  get tabActual() { return TABS.find(t => t.key === this.tab)!; }
}

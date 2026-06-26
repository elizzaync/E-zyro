import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

export const ADM_MODULES = [
  { path: 'contabilidad',  label: 'Contabilidad',         color: '#6366f1', desc: 'Plan de cuentas, periodos y asientos' },
  { path: 'cxc',          label: 'Cuentas por Cobrar',    color: '#10b981', desc: 'Facturas de clientes, cobros y saldos' },
  { path: 'cxp',          label: 'Cuentas por Pagar',     color: '#ef4444', desc: 'Facturas de proveedores, pagos y saldos' },
  { path: 'reportes',     label: 'Reportes Financieros',  color: '#3b82f6', desc: 'Balance, resultados y flujo de efectivo' },
  { path: 'planilla',     label: 'Planilla',              color: '#8b5cf6', desc: 'Cálculo y aprobación de nómina' },
  { path: 'controlling',  label: 'Controlling',           color: '#14b8a6', desc: 'Centros de costo y comparativos' },
  { path: 'tributario',   label: 'Tributario',            color: '#f97316', desc: 'Registros de compras y ventas' },
  { path: 'caja-chica',   label: 'Caja Chica',            color: '#f59e0b', desc: 'Fondos fijos y movimientos' },
  { path: 'conciliacion', label: 'Conciliación Bancaria', color: '#06b6d4', desc: 'Cuentas y movimientos bancarios' },
  { path: 'activos-fijos',label: 'Activos Fijos',         color: '#64748b', desc: 'Inventario y depreciación de activos' },
] as const;

@Component({
  selector: 'app-administracion',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, RouterOutlet],
  templateUrl: './administracion.component.html',
  styleUrls: ['./administracion.component.css']
})
export class AdministracionComponent {
  readonly modulos = ADM_MODULES;
}

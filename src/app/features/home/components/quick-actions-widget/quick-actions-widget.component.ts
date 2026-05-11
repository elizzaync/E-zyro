import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DashboardService } from '../../../../core/services/dashboard.service';
import { ToastService } from '../../../../core/services/toast.service';
import { Subscription } from 'rxjs';
import { Router } from '@angular/router';

@Component({
  selector: 'app-quick-actions-widget',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './quick-actions-widget.component.html',
  styleUrls: ['./quick-actions-widget.component.css']
})
export class QuickActionsWidgetComponent implements OnInit, OnDestroy {
  acciones = [
    { nombre: 'Asistencia',  icono: 'clock',    ruta: '/personal', params: { tab: 'asistencia' } },
    { nombre: 'Operaciones', icono: 'wrench',   ruta: null,        params: null },
    { nombre: 'Evidencia',   icono: 'camera',   ruta: null,        params: null },
    { nombre: 'Reportes',    icono: 'chart',    ruta: null,        params: null },
  ];

  totalAlertas = 0;
  proximoServicio: any = null;
  private notiSub!: Subscription;
  private refreshSub!: Subscription;

  constructor(
    private dashboardService: DashboardService,
    private toastService: ToastService,
    private router: Router
  ) {}

  ngOnInit(): void {
    this.notiSub = this.dashboardService.notificaciones$.subscribe(lista => {
      this.totalAlertas = lista.length;
    });

    this.refreshSub = this.dashboardService.refreshWidgets$.subscribe(() => {
      this.dashboardService.getProximosServicios().subscribe({
        next: (res: any) => {
          this.proximoServicio = res.status === 'success' && res.data?.length > 0 ? res.data[0] : null;
        }
      });
    });
  }

  ngOnDestroy(): void {
    this.notiSub?.unsubscribe();
    this.refreshSub?.unsubscribe();
  }

  ejecutarAccion(accion: any): void {
    if (accion.ruta) {
      setTimeout(() => this.router.navigate([accion.ruta], { queryParams: accion.params || {} }), 120);
    } else {
      this.toastService.mostrar(`${accion.nombre}: módulo en construcción`, 'info');
    }
  }

  get estadoClase(): string {
    if (!this.proximoServicio) return '';
    const e = this.proximoServicio.estado?.toLowerCase().replace(/_/g, '-') ?? '';
    return `dot-${e}`;
  }

  get estadoBadgeClase(): string {
    if (!this.proximoServicio) return '';
    const e = this.proximoServicio.estado?.toLowerCase().replace(/_/g, '-') ?? '';
    return `badge-${e}`;
  }

  get estadoLabel(): string {
    if (!this.proximoServicio) return '';
    const e = this.proximoServicio.estado?.toLowerCase().replace(/_/g, '-') ?? '';
    const labels: Record<string, string> = {
      'en-proceso': 'En proceso',
      'pendiente': 'Pendiente',
      'completado': 'Completado',
    };
    return labels[e] ?? e;
  }
}

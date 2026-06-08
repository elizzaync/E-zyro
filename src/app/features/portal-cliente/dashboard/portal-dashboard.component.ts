import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { forkJoin } from 'rxjs';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-portal-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink, FormsModule],
  templateUrl: './portal-dashboard.component.html',
  styleUrls: ['./portal-dashboard.component.css'],
})
export class PortalDashboardComponent implements OnInit {
  private svc  = inject(PortalClienteService);
  private auth = inject(AuthService);

  cargando  = true;
  error     = '';
  kpis: any = null;
  historial: any[] = [];
  filtro = '';

  get saludo() {
    const n = this.auth.getUsuario()?.nombre_completo ?? '';
    return n ? `Bienvenido(a), ${n}` : 'Bienvenido al Portal';
  }

  get hoy() {
    return new Date().toLocaleDateString('es-PE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
    });
  }

  get historialFiltrado() {
    if (!this.filtro.trim()) return this.historial;
    const q = this.filtro.toLowerCase();
    return this.historial.filter(e =>
      (e.nombre     ?? '').toLowerCase().includes(q) ||
      (e.ubicacion  ?? '').toLowerCase().includes(q) ||
      (e.proyecto   ?? '').toLowerCase().includes(q)
    );
  }

  ngOnInit(): void {
    forkJoin({
      kpis:     this.svc.getKpis(),
      historial: this.svc.getHistorial(),
    }).subscribe({
      next: ({ kpis, historial }) => {
        this.kpis      = kpis;
        this.historial = historial;
        this.cargando  = false;
      },
      error: () => {
        this.error    = 'No se pudo cargar el panel. Intente nuevamente.';
        this.cargando = false;
      },
    });
  }

  badgeIntervencion(estado: string): string {
    const m: Record<string, string> = {
      pendiente:  'badge-pend',
      en_proceso: 'badge-prog',
      completado: 'badge-ok',
      cancelado:  'badge-err',
    };
    return m[estado] ?? 'badge-pend';
  }

  labelIntervencion(estado: string): string {
    const m: Record<string, string> = {
      pendiente:  'Pendiente',
      en_proceso: 'En proceso',
      completado: 'Completado',
      cancelado:  'Cancelado',
    };
    return m[estado] ?? estado;
  }

  proximoAlerta(fecha: string | null): boolean {
    if (!fecha) return false;
    const dias = (new Date(fecha).getTime() - Date.now()) / 86400000;
    return dias >= 0 && dias <= 30;
  }
}

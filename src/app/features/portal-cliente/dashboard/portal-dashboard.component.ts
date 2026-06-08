import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-portal-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './portal-dashboard.component.html',
  styleUrls: ['./portal-dashboard.component.css'],
})
export class PortalDashboardComponent implements OnInit {
  private svc  = inject(PortalClienteService);
  private auth = inject(AuthService);

  cargando      = true;
  error         = '';
  kpis: any     = null;
  proximos: any[]= [];

  get saludo() {
    const n = this.auth.getUsuario()?.nombre_completo ?? '';
    return n ? `Bienvenido(a), ${n}` : 'Bienvenido al Portal';
  }

  get hoy() {
    return new Date().toLocaleDateString('es-PE', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
  }

  ngOnInit(): void {
    this.svc.getDashboard().subscribe({
      next: (data) => {
        this.kpis     = data;
        this.proximos = data.proximos_mantenimientos ?? [];
        this.cargando = false;
      },
      error: () => {
        this.error    = 'No se pudo cargar el dashboard.';
        this.cargando = false;
      },
    });
  }

  estadoBadge(estado: string): string {
    const m: Record<string, string> = {
      pendiente: 'badge-pend',
      en_curso:  'badge-prog',
      completado:'badge-ok',
      cancelado: 'badge-err',
    };
    return m[estado] ?? 'badge-pend';
  }
}

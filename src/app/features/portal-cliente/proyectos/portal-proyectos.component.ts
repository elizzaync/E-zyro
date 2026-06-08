import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';

@Component({
  selector: 'app-portal-proyectos',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './portal-proyectos.component.html',
  styleUrls: ['./portal-proyectos.component.css'],
})
export class PortalProyectosComponent implements OnInit {
  private svc = inject(PortalClienteService);

  cargando    = true;
  error       = '';
  proyectos: any[] = [];

  ngOnInit(): void {
    this.svc.getProyectos().subscribe({
      next: (data) => { this.proyectos = data; this.cargando = false; },
      error: () => { this.error = 'Error al cargar proyectos.'; this.cargando = false; },
    });
  }

  estadoBadge(e: string) {
    const m: Record<string, string> = { activo: 'badge-prog', completado: 'badge-ok', cancelado: 'badge-err', planificado: 'badge-pend' };
    return m[e] ?? 'badge-pend';
  }

  estadoLabel(e: string) {
    const m: Record<string, string> = { activo: 'En curso', completado: 'Completado', cancelado: 'Cancelado', planificado: 'Planificado' };
    return m[e] ?? e;
  }
}

import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';

@Component({
  selector: 'app-portal-proyecto-detalle',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './portal-proyecto-detalle.component.html',
  styleUrls: ['./portal-proyecto-detalle.component.css'],
})
export class PortalProyectoDetalleComponent implements OnInit {
  private svc    = inject(PortalClienteService);
  private route  = inject(ActivatedRoute);

  cargando    = true;
  error       = '';
  data: any   = null;

  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    this.svc.getProyectoDetalle(id).subscribe({
      next: (d) => { this.data = d; this.cargando = false; },
      error: () => { this.error = 'No se pudo cargar el detalle del proyecto.'; this.cargando = false; },
    });
  }

  estadoBadge(e: string) {
    const m: Record<string, string> = { completado: 'badge-ok', en_curso: 'badge-prog', pendiente: 'badge-pend', cancelado: 'badge-err' };
    return m[e] ?? 'badge-pend';
  }

  estadoEquipo(e: string) {
    const m: Record<string, string> = { operativo: 'badge-ok', inoperativo: 'badge-err', mantenimiento: 'badge-prog' };
    return m[e] ?? 'badge-pend';
  }

  iniciales(nombre: string) {
    return nombre.split(' ').slice(0, 2).map(w => w[0]).join('').toUpperCase();
  }
}

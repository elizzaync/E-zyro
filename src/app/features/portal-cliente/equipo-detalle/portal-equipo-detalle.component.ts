import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink, ActivatedRoute } from '@angular/router';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';

@Component({
  selector: 'app-portal-equipo-detalle',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './portal-equipo-detalle.component.html',
  styleUrls: ['./portal-equipo-detalle.component.css'],
})
export class PortalEquipoDetalleComponent implements OnInit {
  private svc   = inject(PortalClienteService);
  private route = inject(ActivatedRoute);

  cargando = true;
  error    = '';
  data: any = null;

  get equipo()     { return this.data?.equipo     ?? null; }
  get servicio()   { return this.data?.servicio   ?? null; }
  get personal()   { return this.data?.personal   ?? []; }
  get herramientas() { return this.data?.herramientas ?? []; }
  get documentos() { return this.data?.documentos ?? []; }
  get proyecto()   { return this.data?.proyecto   ?? '—'; }

  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    this.svc.getMantenimientoDetalle(id).subscribe({
      next:  (d) => { this.data = d; this.cargando = false; },
      error: () => { this.error = 'No se pudo cargar el detalle.'; this.cargando = false; },
    });
  }

  estadoPct(estado: string): number {
    const m: Record<string, number> = {
      pendiente: 0, en_proceso: 50, completado: 100, cancelado: 0,
    };
    return m[estado] ?? 0;
  }

  estadoLabel(estado: string): string {
    const m: Record<string, string> = {
      pendiente:  'Pendiente',
      en_proceso: 'En Proceso',
      completado: 'Completado',
      cancelado:  'Cancelado',
    };
    return m[estado] ?? estado;
  }

  tipoLabel(tipo: string): string {
    return tipo === 'pre' ? 'Pre-Informe' : tipo === 'final' ? 'Informe Final' : tipo;
  }

  tipoIconColor(tipo: string): string {
    const m: Record<string, string> = {
      pre:   '#3b82f6',
      final: '#8b5cf6',
    };
    return m[tipo] ?? '#6b7280';
  }

  badgeEstado(estado: string): string {
    const m: Record<string, string> = {
      pendiente:  'badge-pend',
      en_proceso: 'badge-prog',
      completado: 'badge-ok',
      cancelado:  'badge-err',
    };
    return m[estado] ?? 'badge-pend';
  }
}

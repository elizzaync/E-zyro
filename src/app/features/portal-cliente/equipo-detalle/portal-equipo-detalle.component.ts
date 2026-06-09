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

  get equipo()       { return this.data?.equipo       ?? null; }
  get proyecto()     { return this.data?.proyecto      ?? {}; }
  get servicio()     { return this.data?.servicio      ?? {}; }
  get personal()     { return this.data?.personal      ?? []; }
  get herramientas() { return this.data?.herramientas  ?? []; }
  get documentos()   { return this.data?.documentos    ?? []; }
  get historial()    { return this.data?.historial     ?? []; }

  duracionLabel(dias: number | null): string {
    if (dias === null || dias === undefined) return '—';
    if (dias === 0) return 'Mismo día';
    if (dias === 1) return '1 día';
    return `${dias} días`;
  }

  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    this.svc.getMantenimientoDetalle(id).subscribe({
      next:  (d) => { this.data = d; this.cargando = false; },
      error: (e) => {
        const status = e?.status;
        this.error = status === 404
          ? 'Equipo no encontrado o sin acceso.'
          : status === 403
            ? 'No tiene permisos para ver este registro.'
            : 'No se pudo cargar el detalle. Intente nuevamente.';
        this.cargando = false;
      },
    });
  }

  estadoPct(estado: string): number {
    return { pendiente: 0, en_proceso: 50, completado: 100, cancelado: 0 }[estado] ?? 0;
  }

  estadoLabel(estado: string): string {
    return { pendiente: 'Pendiente', en_proceso: 'En Proceso', completado: 'Completado', cancelado: 'Cancelado' }[estado] ?? estado;
  }

  badgeEstado(estado: string): string {
    return { pendiente: 'badge-pend', en_proceso: 'badge-prog', completado: 'badge-ok', cancelado: 'badge-err' }[estado] ?? 'badge-pend';
  }

  tipoDocLabel(tipo: string): string {
    return { pre: 'Pre-Informe', final: 'Informe Final', garantia: 'Carta de Garantía' }[tipo] ?? tipo;
  }

  tipoDocColor(tipo: string): string {
    return { pre: '#3b82f6', final: '#8b5cf6', garantia: '#f59e0b' }[tipo] ?? '#6b7280';
  }

  calEstado(espec: string | null): 'ok' | 'warn' | 'danger' | 'none' {
    if (!espec) return 'none';
    if (espec.startsWith('⚠')) return 'danger';
    if (espec.startsWith('⏳')) return 'warn';
    if (espec.startsWith('✓')) return 'ok';
    return 'none';
  }

  avatarIniciales(nombre: string): string {
    const parts = (nombre || '').trim().split(' ').filter(Boolean);
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return (parts[0]?.[0] ?? '?').toUpperCase();
  }
}

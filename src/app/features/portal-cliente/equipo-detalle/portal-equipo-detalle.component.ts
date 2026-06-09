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

  // ── FASE 1: estado del equipo basado en fechas ────────────────────────────
  equipoStatus(): { label: string; badge: string } {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const eq = this.equipo;

    if (eq?.ultimo_mantenimiento) {
      return { label: 'Se realizó mantenimiento', badge: 'badge-success' };
    }
    if (eq?.proximo_mantenimiento) {
      const prox  = new Date(eq.proximo_mantenimiento);
      const diffD = (prox.getTime() - today.getTime()) / 86_400_000;
      if (diffD < 0) return { label: 'No se realizó mantenimiento', badge: 'badge-danger' };
      if (diffD <= 30) return { label: 'Se aproxima próximo mantenimiento', badge: 'badge-warning' };
    }
    const fb: Record<string, { label: string; badge: string }> = {
      completado: { label: 'Se realizó mantenimiento',     badge: 'badge-success' },
      en_proceso: { label: 'En proceso',                    badge: 'badge-prog'    },
    };
    return fb[eq?.estado_intervencion] ?? { label: 'Pendiente', badge: 'badge-pend' };
  }

  // ── FASE 3: items para el Timeline ───────────────────────────────────────
  get timelineItems(): Array<{
    fecha: string | null;
    titulo: string;
    subtitulo: string;
    observaciones: string | null;
    tipo: 'completed' | 'upcoming' | 'overdue';
  }> {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const items: any[] = [];

    // Mantenimientos completados del historial
    for (const h of this.historial) {
      items.push({
        fecha:         h.fecha_fin ?? h.fecha_inicio,
        titulo:        'Se realizó mantenimiento',
        subtitulo:     [h.servicio, h.proyecto].filter(Boolean).join(' · '),
        observaciones: h.observaciones ?? null,
        tipo:          'completed',
      });
    }

    // Próximo mantenimiento (del equipo)
    const prox = this.equipo?.proximo_mantenimiento;
    if (prox) {
      const proxDate = new Date(prox);
      const diffD    = (proxDate.getTime() - today.getTime()) / 86_400_000;
      items.push({
        fecha:         prox,
        titulo:        diffD < 0 ? 'No se realizó mantenimiento' : 'Se aproxima próximo mantenimiento',
        subtitulo:     diffD < 0 ? 'Fecha vencida — sin registro de ejecución' : 'Programado',
        observaciones: null,
        tipo:          diffD < 0 ? 'overdue' : 'upcoming',
      });
    }

    // Ordenar descendente por fecha
    return items.sort((a, b) => {
      const da = a.fecha ? new Date(a.fecha).getTime() : 0;
      const db = b.fecha ? new Date(b.fecha).getTime() : 0;
      return db - da;
    });
  }
}

import { Component, HostListener, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';

export interface MiembroServicioPortal {
  id: string;
  nombre: string;
  cargo: string;
  foto_url: string | null;
  rol: string;
}

export interface ServicioPortal {
  id: string;
  nombre: string;
  descripcion: string | null;
  estado: string;
  fecha_programada: string | null;
  fecha_inicio: string | null;
  fecha_fin: string | null;
  progreso: number;
  equipo: MiembroServicioPortal[];
}

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

  private readonly MAX_AVATARES = 5;

  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    this.svc.getProyectoDetalle(id).subscribe({
      next: (d) => { this.data = d; this.cargando = false; },
      error: () => { this.error = 'No se pudo cargar el detalle del proyecto.'; this.cargando = false; },
    });
  }

  /** Normaliza el estado (la BD guarda 'Completado'/'En_Proceso'; el legacy, minúsculas). */
  private estadoKey(e: string): string {
    return (e ?? '').toLowerCase();
  }

  estadoBadge(e: string) {
    const k = this.estadoKey(e);
    if (k === 'completado') return 'badge-ok';
    if (k === 'en_proceso' || k === 'en_curso') return 'badge-prog';
    if (k === 'cancelado') return 'badge-err';
    return 'badge-pend';
  }

  estadoLabel(e: string): string {
    const k = this.estadoKey(e);
    const m: Record<string, string> = {
      'completado': 'Completado', 'en_proceso': 'En Proceso', 'en_curso': 'En Proceso',
      'pendiente': 'Pendiente', 'cancelado': 'Cancelado',
    };
    return m[k] ?? e;
  }

  esCompletado(e: string): boolean {
    return this.estadoKey(e) === 'completado';
  }

  estadoEquipo(e: string) {
    const m: Record<string, string> = { operativo: 'badge-ok', inoperativo: 'badge-err', mantenimiento: 'badge-prog' };
    return m[this.estadoKey(e)] ?? 'badge-pend';
  }

  iniciales(nombre: string) {
    return (nombre ?? '').split(' ').filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase() || '?';
  }

  // ── Avance y equipo por servicio ──────────────────────────────────────

  progresoPct(s: ServicioPortal): number {
    return Math.max(0, Math.min(100, Math.round(s.progreso ?? 0)));
  }

  /** Color de barra y % según el avance del servicio. */
  progresoClase(s: ServicioPortal): string {
    const p = this.progresoPct(s);
    if (this.esCompletado(s.estado) || p >= 100) return 'pg-verde';
    if (p >= 60) return 'pg-azul';
    if (p >= 25) return 'pg-ambar';
    return 'pg-gris';
  }

  equipoVisible(s: ServicioPortal): MiembroServicioPortal[] {
    return (s.equipo ?? []).slice(0, this.MAX_AVATARES);
  }

  equipoExtra(s: ServicioPortal): number {
    return Math.max(0, (s.equipo ?? []).length - this.MAX_AVATARES);
  }

  // ── Modal: datos del equipo del servicio ──────────────────────────────

  equipoModalServicio: ServicioPortal | null = null;

  abrirEquipoModal(s: ServicioPortal): void {
    if ((s.equipo ?? []).length === 0) return;
    this.equipoModalServicio = s;
    document.body.style.overflow = 'hidden';
  }

  cerrarEquipoModal(): void {
    this.equipoModalServicio = null;
    document.body.style.overflow = '';
  }

  @HostListener('document:keydown.escape')
  onEsc(): void { this.cerrarEquipoModal(); }

  colorAvatar(id: string): string {
    const palette = ['#8dc63f', '#3b82f6', '#8b5cf6', '#f59e0b', '#06b6d4', '#ec4899', '#14b8a6'];
    let h = 0;
    for (let i = 0; i < id.length; i++) h = id.charCodeAt(i) + ((h << 5) - h);
    return palette[Math.abs(h) % palette.length];
  }
}

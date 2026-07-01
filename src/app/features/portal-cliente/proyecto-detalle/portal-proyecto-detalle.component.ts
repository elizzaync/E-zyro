import { Component, HostListener, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { AppModalComponent } from '../../../shared/components/modal/app-modal.component';

export interface MiembroServicioPortal {
  id: string;
  nombre: string;
  apellido: string;
  cargo: string;
  foto_url: string | null;
  email: string | null;
  telefono: string | null;
  empresa: string;
  rol: string;
}

export interface ActividadCronograma {
  id: string;
  nombre: string;
  estado: string;
  fecha_inicio: string | null;
  fecha_fin: string | null;
  responsable: string | null;
}

export interface PasoServicio {
  nombre: string;
  estado: string;
  orden: number;
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
  cronograma: ActividadCronograma[];
  pasos: PasoServicio[];
}

@Component({
  selector: 'app-portal-proyecto-detalle',
  standalone: true,
  imports: [CommonModule, RouterLink, AppModalComponent],
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

  nombreCompleto(m: MiembroServicioPortal): string {
    return `${m.nombre} ${m.apellido ?? ''}`.trim();
  }

  inicialesMiembro(m: MiembroServicioPortal): string {
    return ((m.nombre?.[0] ?? '') + (m.apellido?.[0] ?? '')).toUpperCase() || '?';
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
    document.body.style.overflow = this.drawerServicio ? 'hidden' : '';
  }

  // ── Drawer lateral: detalle del servicio (cronograma, solo lectura) ───

  drawerServicio: ServicioPortal | null = null;

  abrirDrawer(s: ServicioPortal): void {
    this.drawerServicio = s;
    document.body.style.overflow = 'hidden';
  }

  cerrarDrawer(): void {
    this.drawerServicio = null;
    document.body.style.overflow = '';
  }

  estadoActividad(e: string): string {
    const k = (e ?? '').toLowerCase();
    if (k === 'completado' || k === 'completada') return 'act-done';
    if (k === 'en_proceso' || k === 'en_curso') return 'act-prog';
    return 'act-pend';
  }

  pasosCompletados(s: ServicioPortal): number {
    return (s.pasos ?? []).filter(p => (p.estado ?? '').toLowerCase() === 'completado').length;
  }

  @HostListener('document:keydown.escape')
  onEsc(): void {
    if (this.equipoModalServicio) this.cerrarEquipoModal();
    else this.cerrarDrawer();
  }

  colorAvatar(id: string): string {
    const palette = ['#8dc63f', '#3b82f6', '#8b5cf6', '#f59e0b', '#06b6d4', '#ec4899', '#14b8a6'];
    let h = 0;
    for (let i = 0; i < id.length; i++) h = id.charCodeAt(i) + ((h << 5) - h);
    return palette[Math.abs(h) % palette.length];
  }
}

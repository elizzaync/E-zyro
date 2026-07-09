import { Component, HostListener, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { AppModalComponent } from '../../../shared/components/modal/app-modal.component';
import { StatusBadgeComponent } from '../shared/status-badge.component';
import { ProgressBarComponent } from '../shared/progress-bar.component';

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
  imports: [CommonModule, RouterLink, AppModalComponent, StatusBadgeComponent, ProgressBarComponent],
  templateUrl: './portal-proyecto-detalle.component.html',
  styleUrls: ['./portal-proyecto-detalle.component.css'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PortalProyectoDetalleComponent implements OnInit {
  private svc    = inject(PortalClienteService);
  private route  = inject(ActivatedRoute);
  private cdr    = inject(ChangeDetectorRef);

  cargando    = true;
  error       = '';
  data: any   = null;

  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    this.svc.getProyectoDetalle(id).subscribe({
      next: (d) => { this.data = d; this.cargando = false; this.cdr.markForCheck(); },
      error: () => { this.error = 'No se pudo cargar el detalle del proyecto.'; this.cargando = false; this.cdr.markForCheck(); },
    });
  }

  /** Normaliza el estado (la BD guarda 'Completado'/'En_Proceso'; el legacy, minúsculas). */
  private estadoKey(e: string): string {
    return (e ?? '').toLowerCase();
  }

  estadoSt(e: string): 'ok' | 'prog' | 'warn' | 'err' | 'neutral' {
    const k = this.estadoKey(e);
    if (k === 'completado') return 'ok';
    if (k === 'en_proceso' || k === 'en_curso' || k === 'activo') return 'prog';
    if (k === 'cancelado') return 'err';
    return 'neutral';
  }

  estadoLabel(e: string): string {
    const k = this.estadoKey(e);
    const m: Record<string, string> = {
      'completado': 'Completado', 'en_proceso': 'En Proceso', 'en_curso': 'En Proceso',
      'activo': 'En curso', 'pendiente': 'Pendiente', 'cancelado': 'Cancelado',
      'planificado': 'Planificado',
    };
    return m[k] ?? e;
  }

  esCompletado(e: string): boolean {
    return this.estadoKey(e) === 'completado';
  }

  equipoSt(e: string): 'ok' | 'prog' | 'warn' | 'err' | 'neutral' {
    const m: Record<string, 'ok' | 'err' | 'prog'> =
      { operativo: 'ok', inoperativo: 'err', mantenimiento: 'prog' };
    return m[this.estadoKey(e)] ?? 'neutral';
  }

  progresoPct(s: ServicioPortal): number {
    return Math.max(0, Math.min(100, Math.round(s.progreso ?? 0)));
  }

  avancePct(): number {
    return Math.max(0, Math.min(100, Math.round(this.data?.proyecto?.avance_pct ?? 0)));
  }

  nombreCompleto(m: MiembroServicioPortal): string {
    return `${m.nombre} ${m.apellido ?? ''}`.trim();
  }

  inicialesMiembro(m: MiembroServicioPortal): string {
    return ((m.nombre?.[0] ?? '') + (m.apellido?.[0] ?? '')).toUpperCase() || '?';
  }

  colorAvatar(id: string): string {
    const palette = ['#8dc63f', '#3b82f6', '#8b5cf6', '#f59e0b', '#06b6d4', '#ec4899', '#14b8a6'];
    let h = 0;
    for (let i = 0; i < id.length; i++) h = id.charCodeAt(i) + ((h << 5) - h);
    return palette[Math.abs(h) % palette.length];
  }

  // ── Modal: detalle del servicio (cronograma + pasos) — reemplaza al drawer ──

  servicioModal: ServicioPortal | null = null;

  abrirServicio(s: ServicioPortal): void {
    this.servicioModal = s;
    this.equipoModalServicio = null;
    document.body.style.overflow = 'hidden';
  }

  cerrarServicio(): void {
    this.servicioModal = null;
    document.body.style.overflow = '';
  }

  estadoActividad(e: string): string {
    const k = this.estadoKey(e);
    if (k === 'completado' || k === 'completada') return 'act-done';
    if (k === 'en_proceso' || k === 'en_curso') return 'act-prog';
    return 'act-pend';
  }

  pasoCompletado(p: PasoServicio): boolean {
    return this.estadoKey(p.estado) === 'completado';
  }

  pasosCompletados(s: ServicioPortal): number {
    return (s.pasos ?? []).filter(p => this.pasoCompletado(p)).length;
  }

  // ── Modal: equipo del servicio ──────────────────────────────────────────

  equipoModalServicio: ServicioPortal | null = null;

  abrirEquipoModal(s: ServicioPortal, ev?: Event): void {
    ev?.stopPropagation();
    if ((s.equipo ?? []).length === 0) return;
    this.equipoModalServicio = s;
    this.servicioModal = null;
    document.body.style.overflow = 'hidden';
  }

  cerrarEquipoModal(): void {
    this.equipoModalServicio = null;
    document.body.style.overflow = '';
  }

  @HostListener('document:keydown.escape')
  onEsc(): void {
    if (this.equipoModalServicio) this.cerrarEquipoModal();
    else if (this.servicioModal) this.cerrarServicio();
    this.cdr.markForCheck();
  }
}

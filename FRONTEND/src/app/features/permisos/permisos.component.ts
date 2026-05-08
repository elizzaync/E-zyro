import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { PermisoFormComponent, PreviewData } from './components/permiso-form/permiso-form.component';
import { PermisoPdfPreviewComponent, EmpleadoInfo } from './components/permiso-pdf-preview/permiso-pdf-preview.component';
import { PermisoHistorialComponent } from './components/permiso-historial/permiso-historial.component';
import { Solicitud } from './components/permiso-tramite-card/permiso-tramite-card.component';
import { ToastService } from '../../core/services/toast.service';
import { DashboardService } from '../../core/services/dashboard.service';
import { PermisosService } from '../../core/services/permisos.service';

@Component({
  selector: 'app-permisos',
  standalone: true,
  imports: [CommonModule, PermisoFormComponent, PermisoPdfPreviewComponent, PermisoHistorialComponent],
  templateUrl: './permisos.component.html',
  styleUrls: ['./permisos.component.css']
})
export class PermisosComponent implements OnInit {
  private toastService     = inject(ToastService);
  private dashboardService = inject(DashboardService);
  private permisosService  = inject(PermisosService);

  tabActiva    = 'solicitar';
  previewData: PreviewData | null = null;
  generandoPdf = false;

  empleadoInfo: EmpleadoInfo  = { nombre: '', cargo: 'PRACTICANTE', area: 'TI' };
  firmaGuardadaUrl: string | null = null;

  misTramites:      Solicitud[] = [];
  cargandoHistorial = false;

  // ── Lifecycle ────────────────────────────────────────────────────
  ngOnInit(): void {
    this.cargarPerfil();
    this.cargarFirmaGuardada();
    this.cargarHistorial();
  }

  // ── Datos iniciales ──────────────────────────────────────────────
  private cargarPerfil(): void {
    const cached = localStorage.getItem('ezyro_user');
    if (cached) {
      try { this.aplicarPerfil(JSON.parse(cached)); } catch { /* ignore */ }
    }
    this.dashboardService.getPerfilUsuario().subscribe({
      next: (res: any) => {
        if (res.status === 'success') this.aplicarPerfil(res.data.personal);
      }
    });
  }

  private aplicarPerfil(p: any): void {
    if (!p) return;
    const apellido = (p.apellido ?? '').toUpperCase().trim();
    const nombre   = (p.nombre   ?? '').toUpperCase().trim();
    const cargo    = (p.rol ?? p.cargo ?? 'PRACTICANTE').toUpperCase();
    this.empleadoInfo = {
      nombre: apellido && nombre ? `${apellido}, ${nombre}` : (nombre || apellido),
      cargo,
      area:  (p.area ?? 'TI').toUpperCase(),
    };
  }

  private cargarFirmaGuardada(): void {
    this.permisosService.getMiFirma().subscribe({
      next: (res: any) => {
        if (res.status === 'success' && res.data?.url_firma) {
          this.firmaGuardadaUrl = res.data.url_firma;
        }
      }
    });
  }

  private cargarHistorial(): void {
    this.cargandoHistorial = true;
    this.dashboardService.getPermisos().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.misTramites = (res.data as any[]).map(s => this.mapearSolicitud(s));
        }
        this.cargandoHistorial = false;
      },
      error: () => { this.cargandoHistorial = false; }
    });
  }

  private mapearSolicitud(s: any): Solicitud {
    const estadoMap: Record<string, Solicitud['estadoActual']> = {
      'pendiente':  'enviado',
      'aprobada':   'aceptado',
      'rechazada':  'rechazado',
      'anulada':    'rechazado',
      'en_proceso': 'proceso',
    };
    const estado = (s.estado ?? '').toLowerCase();
    return {
      id:           `PRM-${String(s.id).substring(0, 6).toUpperCase()}`,
      tipo:         s.titulo ?? s.tipo,
      fechaEmision: s.fecha  ?? '',
      estadoActual: estadoMap[estado] ?? 'enviado',
      urlPdf:       s.url_pdf ?? undefined,
    };
  }

  // ── Handlers ─────────────────────────────────────────────────────
  cambiarTab(tab: string): void {
    this.tabActiva = tab;
    if (tab === 'historial') this.cargarHistorial();
  }

  onPreviewData(data: PreviewData): void {
    this.previewData = data;
  }

  // ── Envío de la solicitud (PDF generado en el backend con WeasyPrint) ────
  generarPdf(): void {
    if (!this.previewData) {
      this.toastService.mostrar('Faltan datos del formulario.', 'error');
      return;
    }
    this.generandoPdf = true;
    this.enviarAlBackend();
  }

  private enviarAlBackend(): void {
    const p = this.previewData!;

    const payload = {
      tipo:             p.tipo,
      tipo_label:       p.tipoLabel ?? p.tipo,
      fecha_inicio:     p.fechaInicio    || undefined,
      fecha_fin:        p.fechaFin       || undefined,
      hora_inicio:      p.horaInicio     || undefined,
      hora_fin:         p.horaFin        || undefined,
      motivo:           p.motivo         || undefined,
      lugar_destino:    p.lugarDestino   || undefined,
      horas_calculadas: p.horasCalculadas ?? undefined,
      total_dias:       typeof p.totalDias === 'number' ? p.totalDias : undefined,
      firma_base64:     p.firmaBase64    ?? '',
      adjunto_nombre:   p.adjuntoNombre  || undefined,
    };

    this.permisosService.enviarSolicitud(payload).subscribe({
      next: (res: any) => {
        this.generandoPdf = false;
        if (res.status === 'success') {
          this.misTramites = [
            {
              id:           res.data.id,
              tipo:         res.data.tipo,
              fechaEmision: res.data.fechaEmision,
              estadoActual: 'enviado',
              urlPdf:       res.data.url_pdf ?? undefined,
            },
            ...this.misTramites,
          ];

          // Refrescar firma guardada si se subió una nueva
          if (payload.firma_base64.startsWith('data:')) {
            this.permisosService.getMiFirma().subscribe({
              next: (r: any) => {
                if (r.status === 'success' && r.data?.url_firma) {
                  this.firmaGuardadaUrl = r.data.url_firma;
                }
              }
            });
          }

          this.toastService.mostrar('Solicitud enviada y PDF guardado exitosamente.', 'success');
          this.tabActiva = 'historial';
        } else {
          this.toastService.mostrar('El servidor respondió con un error inesperado.', 'error');
        }
      },
      error: (err: any) => {
        this.generandoPdf = false;
        const msg = err?.error?.detail ?? 'Error al enviar la solicitud al servidor.';
        this.toastService.mostrar(msg, 'error');
      }
    });
  }
}

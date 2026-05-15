import { Component, OnInit, ViewChild, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { PermisoFormComponent, PreviewData } from './components/permiso-form/permiso-form.component';
import {
  PermisoPdfPreviewComponent,
  EmpleadoInfo,
} from './components/permiso-pdf-preview/permiso-pdf-preview.component';
import { PermisoHistorialComponent } from './components/permiso-historial/permiso-historial.component';
import { Solicitud } from './components/permiso-tramite-card/permiso-tramite-card.component';
import { ToastService } from '../../core/services/toast.service';
import { DashboardService } from '../../core/services/dashboard.service';
import { PermisosService } from '../../core/services/permisos.service';

@Component({
  selector: 'app-permisos',
  standalone: true,
  imports: [
    CommonModule,
    PermisoFormComponent,
    PermisoPdfPreviewComponent,
    PermisoHistorialComponent,
  ],
  templateUrl: './permisos.component.html',
  styleUrls: ['./permisos.component.css'],
})
export class PermisosComponent implements OnInit {
  @ViewChild(PermisoPdfPreviewComponent)
  private previewRef!: PermisoPdfPreviewComponent;

  private toastService     = inject(ToastService);
  private dashboardService = inject(DashboardService);
  private permisosService  = inject(PermisosService);

  tabActiva    = 'solicitar';
  previewData: PreviewData | null = null;
  generandoPdf = false;

  empleadoInfo: EmpleadoInfo       = { nombre: '', cargo: 'PRACTICANTE', area: 'TI' };
  firmaGuardadaUrl: string | null  = null;

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
      try { this.aplicarPerfil(JSON.parse(cached)); } catch { /* ignorar */ }
    }
    this.dashboardService.getPerfilUsuario().subscribe({
      next: (res: any) => {
        if (res.status === 'success') this.aplicarPerfil(res.data.personal);
      },
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
      area: (p.area ?? 'TI').toUpperCase(),
    };
  }

  private cargarFirmaGuardada(): void {
    this.permisosService.getMiFirma().subscribe({
      next: (res: any) => {
        if (res.status === 'success' && res.data?.url_firma) {
          this.firmaGuardadaUrl = this._bustCache(res.data.url_firma);
        }
      },
    });
  }

  /** Añade un timestamp a la URL para forzar al navegador a ignorar la caché. */
  private _bustCache(url: string): string {
    const sep = url.includes('?') ? '&' : '?';
    return `${url}${sep}v=${Date.now()}`;
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
      error: () => { this.cargandoHistorial = false; },
    });
  }

  private mapearSolicitud(s: any): Solicitud {
    const estadoMap: Record<string, Solicitud['estadoActual']> = {
      pendiente:  'enviado',
      aprobada:   'aceptado',
      rechazada:  'rechazado',
      anulada:    'rechazado',
      en_proceso: 'proceso',
    };
    const estado = (s.estado ?? '').toLowerCase();
    const rawTipo = (s.titulo ?? s.tipo ?? '').trim();
    const partes  = rawTipo.split(' — ');
    const tipo    = partes.length === 2 && partes[0].toLowerCase() === partes[1].toLowerCase()
      ? partes[0]
      : rawTipo;

    return {
      id:           `PRM-${String(s.id).substring(0, 6).toUpperCase()}`,
      tipo,
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

  // ── Envío: el PDF final viene del componente de preview (pdf-lib) ─
  generarPdf(): void {
    if (!this.previewData) {
      this.toastService.mostrar('Faltan datos del formulario.', 'error');
      return;
    }

    const archivoPdf = this.previewRef?.obtenerArchivoPdf();
    if (!archivoPdf) {
      this.toastService.mostrar('El PDF aún se está generando, inténtalo de nuevo.', 'info');
      return;
    }

    this.generandoPdf = true;
    this.enviarAlBackend(archivoPdf);
  }

  private enviarAlBackend(archivoPdf: File): void {
    const p = this.previewData!;

    const fd = new FormData();
    fd.append('pdf_file',        archivoPdf, 'solicitud_permiso.pdf');
    fd.append('tipo',            p.tipo);
    fd.append('tipo_label',      p.tipoLabel ?? p.tipo);
    fd.append('firma_base64',    p.firmaBase64 ?? '');

    if (p.fechaInicio)                    fd.append('fecha_inicio',     p.fechaInicio);
    if (p.fechaFin)                       fd.append('fecha_fin',        p.fechaFin);
    if (p.horaInicio)                     fd.append('hora_inicio',      p.horaInicio);
    if (p.horaFin)                        fd.append('hora_fin',         p.horaFin);
    if (p.motivo)                         fd.append('motivo',           p.motivo);
    if (p.lugarDestino)                   fd.append('lugar_destino',    p.lugarDestino);
    if (p.adjuntoNombre)                  fd.append('adjunto_nombre',   p.adjuntoNombre);
    if (p.horasCalculadas != null)        fd.append('horas_calculadas', String(p.horasCalculadas));
    if (typeof p.totalDias === 'number')  fd.append('total_dias',       String(p.totalDias));

    this.permisosService.enviarSolicitud(fd).subscribe({
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

          // Refrescar firma si se subió una nueva
          if ((p.firmaBase64 ?? '').startsWith('data:')) {
            this.permisosService.getMiFirma().subscribe({
              next: (r: any) => {
                if (r.status === 'success' && r.data?.url_firma) {
                  this.firmaGuardadaUrl = this._bustCache(r.data.url_firma);
                }
              },
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
      },
    });
  }
}

import { Component, OnInit, ViewChild, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { PermisoFormComponent, PreviewData } from './components/permiso-form/permiso-form.component';
import { PermisoPdfPreviewComponent, EmpleadoInfo } from './components/permiso-pdf-preview/permiso-pdf-preview.component';
import { PermisoHistorialComponent } from './components/permiso-historial/permiso-historial.component';
import { Solicitud } from './components/permiso-tramite-card/permiso-tramite-card.component';
import { ToastService } from '../../core/services/toast.service';
import { DashboardService } from '../../core/services/dashboard.service';
import { PermisosService } from './permisos.service';

import * as html2pdfLib from 'html2pdf.js';

@Component({
  selector: 'app-permisos',
  standalone: true,
  imports: [CommonModule, PermisoFormComponent, PermisoPdfPreviewComponent, PermisoHistorialComponent],
  templateUrl: './permisos.component.html',
  styleUrls: ['./permisos.component.css']
})
export class PermisosComponent implements OnInit {
  @ViewChild(PermisoPdfPreviewComponent) pdfPreviewRef?: PermisoPdfPreviewComponent;

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
      area: 'TI',
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
      'Pendiente': 'enviado', 'Aprobada':  'aceptado',
      'Rechazada': 'rechazado', 'Anulada': 'rechazado',
    };
    return {
      id:           `PRM-${String(s.id).substring(0, 6).toUpperCase()}`,
      tipo:         s.titulo ?? s.tipo,
      fechaEmision: s.fecha  ?? '',
      estadoActual: estadoMap[s.estado] ?? 'enviado',
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

  // ── Generación y envío del PDF ────────────────────────────────────
  generarPdf(): void {
    const a4Element = this.pdfPreviewRef?.a4PaperRef?.nativeElement;
    if (!a4Element) {
      this.toastService.mostrar('No se pudo capturar el documento. Inténtalo de nuevo.', 'error');
      return;
    }
    if (!this.previewData) {
      this.toastService.mostrar('Faltan datos del formulario.', 'error');
      return;
    }

    this.generandoPdf = true;

    const options = {
      margin:      0,
      filename:    'Permiso_Solicitud.pdf',
      image:       { type: 'jpeg', quality: 0.98 },
      html2canvas: { scale: 2, useCORS: true, logging: false },
      jsPDF:       { unit: 'mm', format: 'a4', orientation: 'portrait' },
    };

    const html2pdf = (html2pdfLib as any).default || html2pdfLib;

    html2pdf()
      .from(a4Element)
      .set(options)
      .output('blob')
      .then((blob: Blob) => this.procesarBlob(blob))
      .catch(() => {
        this.generandoPdf = false;
        this.toastService.mostrar('Error al generar el PDF. Inténtalo de nuevo.', 'error');
      });
  }

  private procesarBlob(blob: Blob): void {
    const reader = new FileReader();
    reader.onload = () => this.enviarAlBackend(reader.result as string);
    reader.onerror = () => {
      this.generandoPdf = false;
      this.toastService.mostrar('Error al procesar el PDF generado.', 'error');
    };
    reader.readAsDataURL(blob);
  }

  private enviarAlBackend(pdfBase64: string): void {
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
      pdf_base64:       pdfBase64,
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

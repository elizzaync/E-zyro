import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  SoporteService,
  EventoSeguridadDto,
  FiltrosEventosSeguridad,
} from '../../../../core/services/soporte.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

@Component({
  selector: 'app-auditoria-eventos',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './auditoria-eventos.component.html',
  styleUrls: ['./auditoria-eventos.component.css'],
})
export class AuditoriaEventosComponent implements OnInit {
  private svc   = inject(SoporteService);
  private toast = inject(ToastService);

  eventos: EventoSeguridadDto[] = [];
  cargando = true;
  total = 0;
  page = 1;
  pageSize = 25;
  fAccion = 'todas';
  fUsuario = '';
  fIp = '';
  fDesde = '';
  fHasta = '';
  fResultado = 'todos';

  exportando = false;
  eventoSel: EventoSeguridadDto | null = null;

  readonly acciones = [
    'LOGIN', 'LOGIN_FALLIDO', 'LOGOUT', 'DOWNLOAD', 'EXPORT',
    'PERMISSION_DENIED', 'RATE_LIMITED', 'BACKUP', 'SECURITY', 'VIEW_SENSITIVE',
  ];

  ngOnInit(): void { this.cargar(); }

  private filtrosActuales(): FiltrosEventosSeguridad {
    return {
      accion: this.fAccion,
      usuarioNombre: this.fUsuario.trim() || undefined,
      ip: this.fIp.trim() || undefined,
      desde: this.fDesde || undefined,
      hasta: this.fHasta || undefined,
      resultado: this.fResultado,
      page: this.page,
      page_size: this.pageSize,
    };
  }

  cargar(): void {
    this.cargando = true;
    this.svc.getAuditLog(this.filtrosActuales()).subscribe({
      next: r => { this.eventos = r.items; this.total = r.total; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar la auditoría de eventos.', 'error'); },
    });
  }

  filtrar(): void { this.page = 1; this.cargar(); }
  get totalPaginas(): number { return Math.max(1, Math.ceil(this.total / this.pageSize)); }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) { this.page = p; this.cargar(); } }

  exportarCsv(): void {
    if (this.exportando) return;
    this.exportando = true;
    this.toast.mostrar('Generando exportación CSV…', 'info');
    this.svc.exportAuditLog(this.filtrosActuales()).subscribe({
      next: blob => {
        this.exportando = false;
        const hoy = new Date().toISOString().slice(0, 10);
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url; a.download = `auditoria_eventos_${hoy}.csv`; a.click();
        setTimeout(() => URL.revokeObjectURL(url), 5000);
      },
      error: () => {
        this.exportando = false;
        this.toast.mostrar('No se pudo exportar el CSV.', 'error');
      },
    });
  }

  abrirDetalle(e: EventoSeguridadDto): void { this.eventoSel = e; }
  cerrarDetalle(): void { this.eventoSel = null; }

  detalleJson(e: EventoSeguridadDto): string {
    if (e.detalle == null) return '—';
    try { return JSON.stringify(e.detalle, null, 2); } catch { return String(e.detalle); }
  }

  // ── Helpers presentación ──
  accionClase(a: string): string {
    if (a === 'LOGIN') return 'ok';
    if (a === 'LOGIN_FALLIDO') return 'fail';
    if (a === 'PERMISSION_DENIED') return 'warn';
    if (a === 'DOWNLOAD' || a === 'EXPORT') return 'info';
    return 'neutro';
  }

  resultadoLabel(r: string): string {
    const m: Record<string, string> = { exito: 'Éxito', fallo: 'Fallo', denegado: 'Denegado' };
    return m[r] ?? r;
  }

  fmtFecha(iso: string | null): string {
    if (!iso) return '—';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '—';
    return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short' }) + ' ' +
           d.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' });
  }
}

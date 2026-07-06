import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  SoporteService,
  MetricasSeguridadDto,
  EventoSeguridadDto,
  AlertaSeguridadDto,
  FiltrosEventosSeguridad,
} from '../../../../core/services/soporte.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

interface TarjetaMetrica {
  clave: string;
  etiqueta: string;
  valor: number;
  alerta: boolean;
  iconos: string[];
}

@Component({
  selector: 'app-seguridad-monitoreo',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './seguridad-monitoreo.component.html',
  styleUrls: ['./seguridad-monitoreo.component.css'],
})
export class SeguridadMonitoreoComponent implements OnInit {
  private svc   = inject(SoporteService);
  private toast = inject(ToastService);

  // ── Métricas ──
  metricas: MetricasSeguridadDto | null = null;
  cargandoMetricas = true;

  // ── Alertas ──
  alertas: AlertaSeguridadDto[] = [];
  cargandoAlertas = true;
  filtroAlertas: 'abierta' | 'revisada' | 'todas' = 'abierta';
  revisandoId: string | null = null;

  // ── Eventos ──
  eventos: EventoSeguridadDto[] = [];
  cargandoEventos = true;
  total = 0;
  page = 1;
  pageSize = 25;
  fAccion = 'todas';
  fUsuario = '';
  fIp = '';
  fDesde = '';
  fHasta = '';
  fResultado = 'todos';

  eventoSel: EventoSeguridadDto | null = null;

  readonly acciones = [
    'LOGIN', 'LOGIN_FALLIDO', 'LOGOUT', 'DOWNLOAD', 'EXPORT',
    'PERMISSION_DENIED', 'RATE_LIMITED', 'BACKUP', 'SECURITY', 'VIEW_SENSITIVE',
  ];

  ngOnInit(): void {
    this.cargarMetricas();
    this.cargarAlertas();
    this.cargarEventos();
  }

  refrescar(): void {
    this.cargarMetricas();
    this.cargarAlertas();
    this.cargarEventos();
  }

  // ── Métricas ──
  cargarMetricas(): void {
    this.cargandoMetricas = true;
    this.svc.getSeguridadMetricas().subscribe({
      next: m => { this.metricas = m; this.cargandoMetricas = false; },
      error: () => { this.cargandoMetricas = false; this.toast.mostrar('Error al cargar métricas de seguridad.', 'error'); },
    });
  }

  get tarjetas(): TarjetaMetrica[] {
    const m = this.metricas;
    if (!m) return [];
    return [
      {
        clave: 'loginsExitosos24h', etiqueta: 'Logins exitosos (24h)', valor: m.loginsExitosos24h, alerta: false,
        iconos: ['M22 11.08V12a10 10 0 1 1-5.93-9.14', 'M22 4L12 14.01l-3-3'],
      },
      {
        clave: 'loginsFallidos24h', etiqueta: 'Logins fallidos (24h)', valor: m.loginsFallidos24h, alerta: m.loginsFallidos24h > 0,
        iconos: ['M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z', 'M12 9v4', 'M12 17h.01'],
      },
      {
        clave: 'permisosDenegados24h', etiqueta: 'Permisos denegados (24h)', valor: m.permisosDenegados24h, alerta: m.permisosDenegados24h > 0,
        iconos: ['M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z', 'M9.5 9.5l5 5', 'M14.5 9.5l-5 5'],
      },
      {
        clave: 'sesionesActivas', etiqueta: 'Sesiones activas', valor: m.sesionesActivas, alerta: false,
        iconos: ['M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2', 'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z'],
      },
      {
        clave: 'alertasAbiertas', etiqueta: 'Alertas abiertas', valor: m.alertasAbiertas, alerta: false,
        iconos: ['M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9', 'M13.73 21a2 2 0 0 1-3.46 0'],
      },
      {
        clave: 'descargas24h', etiqueta: 'Descargas (24h)', valor: m.descargas24h, alerta: false,
        iconos: ['M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4', 'M7 10l5 5 5-5', 'M12 15V3'],
      },
    ];
  }

  // ── Alertas ──
  cargarAlertas(): void {
    this.cargandoAlertas = true;
    this.svc.getSeguridadAlertas(this.filtroAlertas).subscribe({
      next: r => { this.alertas = r.items; this.cargandoAlertas = false; },
      error: () => { this.cargandoAlertas = false; this.toast.mostrar('Error al cargar alertas de seguridad.', 'error'); },
    });
  }

  marcarRevisada(a: AlertaSeguridadDto): void {
    if (this.revisandoId) return;
    this.revisandoId = a.id;
    this.svc.revisarAlerta(a.id).subscribe({
      next: () => {
        this.revisandoId = null;
        this.toast.mostrar('Alerta marcada como revisada.', 'success');
        this.cargarAlertas();
        this.cargarMetricas();
      },
      error: err => {
        this.revisandoId = null;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo marcar la alerta.', 'error');
      },
    });
  }

  tipoAlertaLabel(t: string): string {
    const m: Record<string, string> = {
      fuerza_bruta: 'Fuerza bruta',
      denegados_repetidos: 'Denegados repetidos',
      descarga_masiva: 'Descarga masiva',
      logins_fallidos_usuario: 'Logins fallidos por usuario',
    };
    return m[t] ?? t;
  }

  // ── Eventos ──
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

  cargarEventos(): void {
    this.cargandoEventos = true;
    this.svc.getSeguridadEventos(this.filtrosActuales()).subscribe({
      next: r => { this.eventos = r.items; this.total = r.total; this.cargandoEventos = false; },
      error: () => { this.cargandoEventos = false; this.toast.mostrar('Error al cargar eventos de seguridad.', 'error'); },
    });
  }

  filtrar(): void { this.page = 1; this.cargarEventos(); }
  get totalPaginas(): number { return Math.max(1, Math.ceil(this.total / this.pageSize)); }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) { this.page = p; this.cargarEventos(); } }

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

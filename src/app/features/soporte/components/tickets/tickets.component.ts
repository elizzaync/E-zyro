import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subject } from 'rxjs';
import { takeUntil } from 'rxjs/operators';
import { SoporteService, TicketSoporteDto, ActividadDto } from '../../../../core/services/soporte.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SoporteWsService } from '../../../../core/services/soporte-ws.service';
import { AuthService } from '../../../../core/services/auth.service';

type TabEstado = 'abierto' | 'en_proceso' | 'resuelto' | 'cerrado';

@Component({
  selector: 'app-tickets-soporte',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './tickets.component.html',
  styleUrls: ['./tickets.component.css']
})
export class TicketsSoporteComponent implements OnInit, OnDestroy {
  private svc    = inject(SoporteService);
  private toast  = inject(ToastService);
  private wsSvc  = inject(SoporteWsService);
  private auth   = inject(AuthService);
  private destroy$ = new Subject<void>();

  wsConectado = false;

  tab: TabEstado = 'abierto';
  cargando = true;
  procesando = false;

  tickets: TicketSoporteDto[] = [];
  busqueda = '';

  kpiAbiertos   = 0;
  kpiEnProceso  = 0;
  kpiUrgentes   = 0;

  ticketActivo: TicketSoporteDto | null = null;
  actividades: ActividadDto[] = [];
  cargandoActividades = false;

  nuevoEstado = '';
  nuevaRespuesta = '';
  nuevoComentario = '';
  enviandoComentario = false;

  ngOnInit(): void {
    this.cargarTodos();
    // Conectar WebSocket y suscribirse a eventos de tickets.
    const token = this.auth.getToken();
    if (token) {
      this.wsSvc.connect(token);
      this.wsConectado = true;
      this.wsSvc.evento$
        .pipe(takeUntil(this.destroy$))
        .subscribe(e => {
          if (e.tipo === 'ticket_nuevo' || e.tipo === 'ticket_actualizado') {
            this.toast.mostrar('Tickets actualizados', 'info');
            this.cargarTodos();
          }
        });
    }
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
    this.setMainModal(false);
  }

  cargarTodos(): void {
    this.cargando = true;
    this.svc.getTickets({ alcance: 'todos' }).subscribe({
      next: data => {
        this.tickets = data;
        this.kpiAbiertos  = data.filter(t => t.estado === 'abierto').length;
        this.kpiEnProceso = data.filter(t => t.estado === 'en_proceso').length;
        this.kpiUrgentes  = data.filter(t => t.prioridad === 'urgente' && t.estado !== 'cerrado').length;
        this.cargando = false;
      },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar tickets.', 'error'); }
    });
  }

  setTab(t: TabEstado): void { this.tab = t; }

  get listaFiltrada(): TicketSoporteDto[] {
    const q = this.busqueda.toLowerCase().trim();
    return this.tickets
      .filter(t => t.estado === this.tab)
      .filter(t => !q || t.codigo.toLowerCase().includes(q) || t.titulo.toLowerCase().includes(q) || t.reportante_nombre.toLowerCase().includes(q));
  }

  abrirTicket(t: TicketSoporteDto): void {
    this.ticketActivo = t;
    this.nuevoEstado = t.estado;
    this.nuevaRespuesta = t.respuesta_ti ?? '';
    this.nuevoComentario = '';
    this.actividades = [];
    this.setMainModal(true);
    this.cargandoActividades = true;
    this.svc.getActividades(t.id).subscribe({
      next: a => { this.actividades = a; this.cargandoActividades = false; },
      error: () => { this.cargandoActividades = false; }
    });
  }

  cerrarTicket(): void {
    this.ticketActivo = null;
    this.actividades = [];
    this.setMainModal(false);
  }

  tomarTicket(): void {
    if (!this.ticketActivo) return;
    this.procesando = true;
    this.svc.tomarTicket(this.ticketActivo.id).subscribe({
      next: t => {
        this.procesando = false;
        this.ticketActivo = t;
        this.nuevoEstado = t.estado;
        this.toast.mostrar('Ticket tomado correctamente.', 'success');
        this.cargarTodos();
        this.recargarActividades();
      },
      error: err => { this.procesando = false; this.toast.mostrar(err?.error?.detail ?? 'Error al tomar el ticket.', 'error'); }
    });
  }

  guardarGestion(): void {
    if (!this.ticketActivo) return;
    this.procesando = true;
    const body: any = {};
    if (this.nuevoEstado && this.nuevoEstado !== this.ticketActivo.estado) body.estado = this.nuevoEstado;
    if (this.nuevaRespuesta.trim() !== (this.ticketActivo.respuesta_ti ?? '')) body.respuesta_ti = this.nuevaRespuesta.trim();
    if (!Object.keys(body).length) { this.procesando = false; return; }
    this.svc.gestionarTicket(this.ticketActivo.id, body).subscribe({
      next: t => {
        this.procesando = false;
        this.ticketActivo = t;
        this.nuevoEstado = t.estado;
        this.toast.mostrar('Ticket actualizado.', 'success');
        this.cargarTodos();
        this.recargarActividades();
      },
      error: err => { this.procesando = false; this.toast.mostrar(err?.error?.detail ?? 'Error al actualizar.', 'error'); }
    });
  }

  enviarComentario(): void {
    if (!this.ticketActivo || !this.nuevoComentario.trim()) return;
    this.enviandoComentario = true;
    this.svc.crearActividad(this.ticketActivo.id, { tipo: 'comentario', texto: this.nuevoComentario.trim() }).subscribe({
      next: a => {
        this.actividades = [...this.actividades, a];
        this.nuevoComentario = '';
        this.enviandoComentario = false;
      },
      error: err => { this.enviandoComentario = false; this.toast.mostrar(err?.error?.detail ?? 'Error al enviar comentario.', 'error'); }
    });
  }

  private recargarActividades(): void {
    if (!this.ticketActivo) return;
    this.svc.getActividades(this.ticketActivo.id).subscribe({ next: a => { this.actividades = a; } });
  }

  private setMainModal(open: boolean): void {
    const main = document.querySelector('main');
    if (!main) return;
    if (open) { main.classList.add('modal-open'); document.body.style.overflow = 'hidden'; }
    else { main.classList.remove('modal-open'); document.body.style.overflow = ''; }
  }

  prioridadClase(p: string): string {
    const m: Record<string, string> = { urgente: 'badge-urgente', alta: 'badge-alta', media: 'badge-media', baja: 'badge-baja' };
    return m[p] ?? 'badge-baja';
  }

  estadoClase(e: string): string {
    const m: Record<string, string> = { abierto: 'est-abierto', en_proceso: 'est-en-proceso', resuelto: 'est-resuelto', cerrado: 'est-cerrado' };
    return m[e] ?? '';
  }

  estadoLabel(e: string): string {
    const m: Record<string, string> = { abierto: 'Abierto', en_proceso: 'En Proceso', resuelto: 'Resuelto', cerrado: 'Cerrado' };
    return m[e] ?? e;
  }

  prioridadLabel(p: string): string {
    const m: Record<string, string> = { urgente: 'Urgente', alta: 'Alta', media: 'Media', baja: 'Baja' };
    return m[p] ?? p;
  }

  categoriaLabel(c: string): string {
    const m: Record<string, string> = { app_movil: 'App Móvil', sistema_web: 'Sistema Web', acceso: 'Acceso', datos: 'Datos', otro: 'Otro' };
    return m[c] ?? c;
  }

  actividadLabel(tipo: string): string {
    const m: Record<string, string> = { comentario: 'Comentario', avance: 'Avance', solucion: 'Solución', cambio_estado: 'Cambio de estado', tomado: 'Tomado' };
    return m[tipo] ?? tipo;
  }

  get puedeGuardar(): boolean {
    if (!this.ticketActivo) return false;
    const estadoCambio = this.nuevoEstado && this.nuevoEstado !== this.ticketActivo.estado;
    const respCambio   = this.nuevaRespuesta.trim() !== (this.ticketActivo.respuesta_ti ?? '');
    return estadoCambio || respCambio;
  }

  get puedeTomarTicket(): boolean {
    if (!this.ticketActivo) return false;
    return this.ticketActivo.estado === 'abierto' || !this.ticketActivo.atendido_por;
  }

  tabCount(estado: TabEstado): number {
    return this.tickets.filter(t => t.estado === estado).length;
  }

  trackById(_: number, item: TicketSoporteDto): string { return item.id; }
  trackActById(_: number, a: ActividadDto): string { return a.id; }
}

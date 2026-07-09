import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { ToastService } from '../../../core/services/toast.service';
import { StatusBadgeComponent } from '../shared/status-badge.component';
import { EmptyStateComponent } from '../shared/empty-state.component';

type St = 'ok' | 'prog' | 'warn' | 'err' | 'neutral';

@Component({
  selector: 'app-portal-soporte',
  standalone: true,
  imports: [CommonModule, FormsModule, StatusBadgeComponent, EmptyStateComponent],
  templateUrl: './portal-soporte.component.html',
  styleUrls: ['./portal-soporte.component.css'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PortalSoporteComponent implements OnInit {
  private svc   = inject(PortalClienteService);
  private toast = inject(ToastService);
  private cdr   = inject(ChangeDetectorRef);

  cargando = true;
  error    = '';
  tickets: any[] = [];

  // Formulario de nuevo ticket
  titulo      = '';
  descripcion = '';
  categoria   = 'sistema_web';
  prioridad   = 'media';
  enviando    = false;

  readonly categorias = [
    { key: 'sistema_web', label: 'Portal / Sistema web' },
    { key: 'acceso',      label: 'Acceso / Contraseña' },
    { key: 'datos',       label: 'Datos incorrectos' },
    { key: 'otro',        label: 'Otro' },
  ];
  readonly prioridades = [
    { key: 'baja',    label: 'Baja' },
    { key: 'media',   label: 'Media' },
    { key: 'alta',    label: 'Alta' },
    { key: 'urgente', label: 'Urgente' },
  ];

  ngOnInit(): void {
    this.cargarTickets();
  }

  private cargarTickets(): void {
    this.svc.getTickets().subscribe({
      next: (data) => { this.tickets = data; this.cargando = false; this.cdr.markForCheck(); },
      error: () => { this.error = 'No se pudieron cargar tus tickets.'; this.cargando = false; this.cdr.markForCheck(); },
    });
  }

  get puedeEnviar(): boolean {
    return !this.enviando && this.titulo.trim().length > 3 && this.descripcion.trim().length > 10;
  }

  enviar(): void {
    if (!this.puedeEnviar) return;
    this.enviando = true;
    this.svc.crearTicket({
      titulo: this.titulo.trim(),
      descripcion: this.descripcion.trim(),
      categoria: this.categoria,
      prioridad: this.prioridad,
    }).subscribe({
      next: (t) => {
        this.enviando = false;
        this.titulo = ''; this.descripcion = '';
        this.categoria = 'sistema_web'; this.prioridad = 'media';
        this.toast.mostrar(`Ticket ${t.codigo} creado. El equipo de soporte fue notificado.`, 'success');
        this.cargarTickets();
        this.cdr.markForCheck();
      },
      error: () => {
        this.enviando = false;
        this.toast.mostrar('No se pudo enviar el ticket. Intenta nuevamente.', 'error');
        this.cdr.markForCheck();
      },
    });
  }

  estadoSt(estado: string): St {
    const m: Record<string, St> = {
      abierto: 'prog', en_proceso: 'warn', resuelto: 'ok', cerrado: 'neutral',
    };
    return m[estado] ?? 'neutral';
  }

  estadoLabel(estado: string): string {
    const m: Record<string, string> = {
      abierto: 'Abierto', en_proceso: 'En proceso', resuelto: 'Resuelto', cerrado: 'Cerrado',
    };
    return m[estado] ?? estado;
  }

  categoriaLabel(c: string): string {
    return this.categorias.find(x => x.key === c)?.label
      ?? ({ app_movil: 'App móvil' } as Record<string, string>)[c]
      ?? c;
  }
}

import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { Incidencia, EstadoIncidencia } from '../../logistica.models';

@Component({
  selector: 'app-incidencias-tabla',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './incidencias-tabla.component.html',
  styleUrls: ['./incidencias-tabla.component.css'],
})
export class IncidenciasTablaComponent implements OnInit {
  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  cargando   = true;
  incidencias: Incidencia[] = [];
  total      = 0;
  page       = 1;
  pageSize   = 20;

  busqueda    = '';
  filtroClase = '';    // '' | 'equipo' | 'herramienta'
  filtroEstado = '';   // '' | 'abierta' | 'en_reparacion' | 'solucionado' | 'dado_de_baja'

  // ── Modal resolución ──
  incActiva: Incidencia | null = null;
  resolNuevoEstado: string     = '';
  resolNota                    = '';
  resolviendo                  = false;

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getIncidencias({
      q:        this.busqueda     || undefined,
      clase:    this.filtroClase  || undefined,
      estado:   this.filtroEstado || undefined,
      page:     this.page,
      pageSize: this.pageSize,
    }).subscribe({
      next:  r => { this.incidencias = r.items; this.total = r.total; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar incidencias.', 'error'); },
    });
  }

  buscar():  void { this.page = 1; this.cargar(); }
  limpiar(): void { this.busqueda = ''; this.filtroClase = ''; this.filtroEstado = ''; this.page = 1; this.cargar(); }

  get totalPaginas(): number { return Math.ceil(this.total / this.pageSize); }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) { this.page = p; this.cargar(); } }

  // ── Modal ──
  abrirResolucion(inc: Incidencia): void {
    this.incActiva        = inc;
    this.resolNuevoEstado = inc.estado === 'abierta' ? 'en_reparacion' : 'solucionado';
    this.resolNota        = '';
  }
  cerrarResolucion(): void { this.incActiva = null; }

  confirmarResolucion(): void {
    if (!this.incActiva || !this.resolNuevoEstado || this.resolviendo) return;
    this.resolviendo = true;
    this.svc.resolverIncidencia(this.incActiva.id, {
      estado:        this.resolNuevoEstado,
      resolucionNota: this.resolNota.trim() || undefined,
    }).subscribe({
      next: () => {
        this.resolviendo = false;
        const label = this.resolNuevoEstado === 'solucionado'   ? 'Marcado como solucionado.' :
                      this.resolNuevoEstado === 'en_reparacion' ? 'Enviado a reparación.' :
                                                                  'Dado de baja. Stock descontado.';
        this.toast.mostrar(label, 'success');
        this.cerrarResolucion();
        this.cargar();
      },
      error: err => { this.resolviendo = false; this.toast.mostrar(err?.error?.detail ?? 'Error.', 'error'); },
    });
  }

  // ── Helpers ──
  estadoLabel(e: string): string {
    const m: Record<string, string> = {
      abierta: 'Abierta', en_reparacion: 'En reparación',
      solucionado: 'Solucionado', dado_de_baja: 'Dado de baja',
    };
    return m[e] ?? e;
  }

  tipoFallaLabel(t: string): string {
    const m: Record<string, string> = {
      no_enciende: 'No enciende', dano_fisico: 'Daño físico',
      desgaste: 'Desgaste', perdida: 'Pérdida', otro: 'Otro',
    };
    return m[t] ?? t;
  }

  esCerrada(e: string): boolean { return e === 'solucionado' || e === 'dado_de_baja'; }

  fechaCorta(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }
}

import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { Requerimiento, RequerimientoItem, AprobarItemDecision } from '../../logistica.models';

type TabReq = 'pendientes' | 'historial';

@Component({
  selector: 'app-requerimientos',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './requerimientos.component.html',
  styleUrls: ['./requerimientos.component.css']
})
export class RequerimientosComponent implements OnInit {
  private svc    = inject(LogisticaService);
  private toast  = inject(ToastService);
  private router = inject(Router);

  tab: TabReq = 'pendientes';
  cargando = true;

  pendientes: Requerimiento[] = [];
  historial: Requerimiento[]  = [];

  busqueda = '';
  filtroProyecto = '';

  // ── Modal de revisión / aprobación ──
  reqActivo: Requerimiento | null = null;
  decisiones: Record<string, 'aprobar' | 'compra' | 'rechazar'> = {};
  procesando = false;

  // ── Modal de rechazo ──
  reqRechazar: Requerimiento | null = null;
  motivoRechazo = '';

  ngOnInit(): void { this.cargar(); }

  setTab(t: TabReq): void {
    this.tab = t;
    this.cargar();
  }

  cargar(): void {
    this.cargando = true;
    if (this.tab === 'pendientes') {
      this.svc.getRequerimientos({ estado: 'pendiente' }).subscribe({
        next: (d) => { this.pendientes = d; this.cargando = false; },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar requerimientos.', 'error'); }
      });
    } else {
      this.svc.getHistorialRequerimientos().subscribe({
        next: (d) => { this.historial = d; this.cargando = false; },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar el historial.', 'error'); }
      });
    }
  }

  get lista(): Requerimiento[] {
    const base = this.tab === 'pendientes' ? this.pendientes : this.historial;
    const q = this.busqueda.toLowerCase().trim();
    if (!q) return base;
    return base.filter(r =>
      r.proyectoNombre.toLowerCase().includes(q) ||
      (r.servicioNombre ?? '').toLowerCase().includes(q) ||
      r.solicitanteNombre.toLowerCase().includes(q) ||
      r.items.some(i => i.nombre.toLowerCase().includes(q))
    );
  }

  // ── Helpers de presentación ──
  estadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente: 'Pendiente', aprobado: 'Aprobado', listo: 'Listo para entrega',
      entregado: 'Entregado', rechazado: 'Rechazado',
    };
    return m[e] ?? e;
  }
  estadoClase(e: string): string { return 'est-' + e; }

  itemEstadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente: 'Pendiente', aprobado: 'De stock', para_compra: 'Compra', rechazado: 'Rechazado',
    };
    return m[e] ?? e;
  }

  // ── Modal de revisión ──
  abrirRevision(r: Requerimiento): void {
    this.reqActivo = r;
    this.decisiones = {};
    // Sugerencia automática: en stock → aprobar; sin stock/compra externa → compra
    for (const it of r.items) {
      this.decisiones[it.id] = it.esCompraExterna || !it.enStock ? 'compra' : 'aprobar';
    }
  }
  cerrarRevision(): void { this.reqActivo = null; this.decisiones = {}; }

  setDecision(itemId: string, d: 'aprobar' | 'compra' | 'rechazar'): void {
    this.decisiones[itemId] = d;
  }

  confirmarAprobacion(): void {
    if (!this.reqActivo) return;
    this.procesando = true;
    const decisiones: AprobarItemDecision[] = this.reqActivo.items.map(it => ({
      detalleId: it.id,
      decision: this.decisiones[it.id] ?? 'aprobar',
    }));
    this.svc.aprobarRequerimiento(this.reqActivo.id, { decisiones }).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Requerimiento procesado. Stock actualizado.', 'success');
        this.cerrarRevision();
        this.cargar();
      },
      error: (err) => {
        this.procesando = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo procesar.', 'error');
      }
    });
  }

  // ── Modal de rechazo ──
  abrirRechazo(r: Requerimiento): void { this.reqRechazar = r; this.motivoRechazo = ''; }
  cerrarRechazo(): void { this.reqRechazar = null; this.motivoRechazo = ''; }
  confirmarRechazo(): void {
    if (!this.reqRechazar || !this.motivoRechazo.trim()) return;
    this.procesando = true;
    this.svc.rechazarRequerimiento(this.reqRechazar.id, this.motivoRechazo.trim()).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Requerimiento rechazado.', 'success');
        this.cerrarRechazo();
        this.cargar();
      },
      error: () => { this.procesando = false; this.toast.mostrar('No se pudo rechazar.', 'error'); }
    });
  }

  // ── Entregar (cuando está aprobado/listo) ──
  entregar(r: Requerimiento): void {
    this.procesando = true;
    this.svc.entregarRequerimiento(r.id, {}).subscribe({
      next: () => {
        this.procesando = false;
        this.toast.mostrar('Entrega registrada.', 'success');
        this.cargar();
      },
      error: (err) => {
        this.procesando = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo registrar la entrega.', 'error');
      }
    });
  }

  // Resumen de proyección de stock para el modal
  proyeccion(it: RequerimientoItem): number {
    return Math.max(0, it.stockDisponible - it.cantidad);
  }

  volverInventario(): void { this.router.navigate(['/logistica']); }
}

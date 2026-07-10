import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { EquipoIntervenidoService } from '../../../../../core/services/equipo-intervenido.service';
import { SpinnerComponent } from '../../../../../shared/components/spinner/spinner.component';

type Anticipacion = '1sem' | '2sem' | '1mes';

interface EventoHistorial {
  fecha: string;
  titulo: string;
  descripcion?: string | null;
  realizadoPor?: string | null;
  icono: 'correctivo' | 'inspeccion' | 'otro' | 'registro';
}

@Component({
  selector: 'app-detalle-equipo-intervenido',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './detalle-equipo.component.html',
  styleUrls: ['./detalle-equipo.component.css'],
})
export class DetalleEquipoComponent implements OnInit {
  private svc = inject(EquipoIntervenidoService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);

  equipoId = '';
  equipo: any = null;
  mantenimientos: any[] = [];
  isLoading = true;
  errorMessage: string | null = null;

  // Recordatorio: 100% local (localStorage), no se persiste en backend.
  recordatorioActivo = false;
  recordatorioAnticipacion: Anticipacion = '1sem';

  ngOnInit(): void {
    this.equipoId = this.route.snapshot.paramMap.get('id') || '';
    this.cargarRecordatorio();
    this.cargar();
  }

  cargar(): void {
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.obtener(this.equipoId).subscribe({
      next: (e) => {
        this.equipo = e;
        this.svc.listarMantenimientos(this.equipoId).subscribe({
          next: (m) => { this.mantenimientos = m || []; this.isLoading = false; },
          error: () => { this.mantenimientos = []; this.isLoading = false; },
        });
      },
      error: () => {
        this.errorMessage = 'No se pudo cargar el equipo.';
        this.isLoading = false;
      },
    });
  }

  volver(): void { this.router.navigate(['/operaciones/mantenimiento']); }

  irAlServicio(): void {
    if (!this.equipo?.proyecto_servicio_id) return;
    this.router.navigate(['/operaciones/servicio', this.equipo.proyecto_servicio_id]);
  }

  get tieneObservaciones(): boolean {
    return !!(this.equipo?.observaciones && String(this.equipo.observaciones).trim().length > 0);
  }

  // ── Identidad / semáforo ────────────────────────────────────────────────
  estadoClass(estado: string): string {
    const map: Record<string, string> = {
      operativo: 'estado-operativo', mantenimiento: 'estado-mtto',
      inoperativo: 'estado-inoperativo', en_revision: 'estado-revision',
    };
    return map[estado] ?? 'estado-operativo';
  }

  estadoLabel(estado: string): string {
    const map: Record<string, string> = {
      operativo: 'Operativo', mantenimiento: 'Mantenimiento',
      inoperativo: 'Inoperativo', en_revision: 'En Revisión',
    };
    return map[estado] ?? estado;
  }

  ubicacionCompleta(): string {
    if (!this.equipo) return '—';
    return [this.equipo.cliente_nombre, this.equipo.ubicacion_nombre, this.equipo.zona_nombre,
            this.equipo.area_nombre || this.equipo.area_descripcion]
      .filter(Boolean).join(' › ') || '—';
  }

  // ── Gauge circular de próximo mantenimiento ──────────────────────────────
  get diasParaMantenimiento(): number | null {
    if (!this.equipo?.proximo_mantenimiento) return null;
    const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
    const prox = new Date(this.equipo.proximo_mantenimiento + 'T00:00:00');
    return Math.round((prox.getTime() - hoy.getTime()) / 86400000);
  }

  get gaugeSemaforo(): 'vencido' | 'proximo' | 'ok' | 'sin_plan' {
    const d = this.diasParaMantenimiento;
    if (d === null) return 'sin_plan';
    if (d < 0) return 'vencido';
    if (d <= 30) return 'proximo';
    return 'ok';
  }

  get gaugeTexto(): string {
    const d = this.diasParaMantenimiento;
    if (d === null) return 'Sin plan';
    if (d < 0) return `Vencido ${Math.abs(d)} d`;
    if (d === 0) return 'Hoy';
    if (d < 60) return `${d} d`;
    return `${Math.round(d / 30)} meses`;
  }

  /** Fracción 0..1 del ciclo transcurrido desde el último mantenimiento (o su
   * estimación) hasta el próximo. */
  get gaugeFraccion(): number {
    if (!this.equipo?.proximo_mantenimiento) return 0;
    const proximo = new Date(this.equipo.proximo_mantenimiento + 'T00:00:00');
    let inicio: Date;
    if (this.equipo.ultimo_mantenimiento) {
      inicio = new Date(this.equipo.ultimo_mantenimiento + 'T00:00:00');
    } else {
      inicio = new Date(proximo);
      inicio.setMonth(inicio.getMonth() - (this.equipo.frecuencia_meses || 6));
    }
    const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
    const total = proximo.getTime() - inicio.getTime();
    if (total <= 0) return 1;
    const transcurrido = hoy.getTime() - inicio.getTime();
    return Math.min(1, Math.max(0, transcurrido / total));
  }

  readonly gaugeRadio = 60;
  get gaugeCircunferencia(): number { return 2 * Math.PI * this.gaugeRadio; }
  get gaugeOffset(): number { return this.gaugeCircunferencia * (1 - this.gaugeFraccion); }

  // ── Recordatorio (local) ─────────────────────────────────────────────────
  private get recordatorioKey(): string { return `ezyro_recordatorio_${this.equipoId}`; }

  private cargarRecordatorio(): void {
    try {
      const raw = localStorage.getItem(this.recordatorioKey);
      if (!raw) return;
      const data = JSON.parse(raw);
      this.recordatorioActivo = !!data.activo;
      this.recordatorioAnticipacion = data.anticipacion || '1sem';
    } catch { /* noop */ }
  }

  guardarRecordatorio(): void {
    localStorage.setItem(this.recordatorioKey, JSON.stringify({
      activo: this.recordatorioActivo, anticipacion: this.recordatorioAnticipacion,
    }));
  }

  // ── Historial (mantenimientos + registro del equipo) ─────────────────────
  get historial(): EventoHistorial[] {
    const eventos: EventoHistorial[] = this.mantenimientos.map(m => ({
      fecha: m.fecha,
      titulo: this.tipoMantenimientoLabel(m.tipo),
      descripcion: m.descripcion,
      realizadoPor: m.realizado_por,
      icono: (m.tipo === 'correctivo' || m.tipo === 'inspeccion') ? m.tipo : 'otro',
    }));
    if (this.equipo?.created_at) {
      eventos.push({
        fecha: this.equipo.created_at,
        titulo: 'Registro del equipo',
        icono: 'registro',
      });
    }
    return eventos.sort((a, b) => new Date(b.fecha).getTime() - new Date(a.fecha).getTime());
  }

  private tipoMantenimientoLabel(tipo: string): string {
    const map: Record<string, string> = {
      preventivo: 'Mantenimiento preventivo', correctivo: 'Mantenimiento correctivo',
      inspeccion: 'Inspección', otro: 'Mantenimiento',
    };
    return map[tipo] ?? 'Mantenimiento';
  }

  formatFecha(iso: string | null | undefined): string {
    if (!iso) return '—';
    try {
      return new Date(iso.length === 10 ? iso + 'T00:00:00' : iso)
        .toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
    } catch { return iso; }
  }

  // ── Ficha técnica ────────────────────────────────────────────────────────
  get fichaTecnicaDinamica(): { clave: string; valor: string }[] {
    const ft = this.equipo?.ficha_tecnica;
    if (!ft || typeof ft !== 'object') return [];
    return Object.entries(ft).map(([clave, valor]) => ({
      clave: this.humanizarClave(clave),
      valor: valor === null || valor === undefined ? '—' : String(valor),
    }));
  }

  private humanizarClave(clave: string): string {
    return clave
      .replace(/_/g, ' ')
      .replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

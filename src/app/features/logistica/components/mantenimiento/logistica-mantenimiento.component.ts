import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

@Component({
  selector: 'app-logistica-mantenimiento',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './logistica-mantenimiento.component.html',
  styleUrls: ['./logistica-mantenimiento.component.css'],
})
export class LogisticaMantenimientoComponent implements OnInit {
  private svc = inject(LogisticaService);

  equipos: any[] = [];
  isLoading = true;
  errorMessage: string | null = null;

  busqueda     = '';
  filtroEstado    = '';
  filtroTipo      = '';
  filtroUbicacion = '';
  page = 1;
  readonly PER_PAGE = 10;

  get tiposUnicos(): string[] {
    return [...new Set(this.equipos.map(e => e.tipo_nombre).filter(Boolean))].sort();
  }

  get ubicacionesUnicas(): string[] {
    return [...new Set(this.equipos.map(e => e.ubicacion).filter(Boolean))].sort();
  }

  get hayFiltros(): boolean {
    return !!(this.busqueda || this.filtroEstado || this.filtroTipo || this.filtroUbicacion);
  }

  get chipsFiltros(): { label: string; campo: string }[] {
    const chips: { label: string; campo: string }[] = [];
    if (this.filtroEstado)    chips.push({ label: this.estadoLabel(this.filtroEstado), campo: 'filtroEstado' });
    if (this.filtroTipo)      chips.push({ label: this.filtroTipo,      campo: 'filtroTipo' });
    if (this.filtroUbicacion) chips.push({ label: this.filtroUbicacion, campo: 'filtroUbicacion' });
    if (this.busqueda)        chips.push({ label: `"${this.busqueda}"`, campo: 'busqueda' });
    return chips;
  }

  quitarChip(campo: string): void {
    (this as any)[campo] = '';
    this.page = 1;
  }

  limpiarFiltros(): void {
    this.busqueda = '';
    this.filtroEstado = '';
    this.filtroTipo = '';
    this.filtroUbicacion = '';
    this.page = 1;
  }

  get filtrados(): any[] {
    const term = this.busqueda.toLowerCase().trim();
    return this.equipos.filter(e => {
      const matchTerm = !term ||
        (e.nombre || '').toLowerCase().includes(term) ||
        (e.codigo || '').toLowerCase().includes(term) ||
        (e.tipo_nombre || '').toLowerCase().includes(term) ||
        (e.ubicacion || '').toLowerCase().includes(term) ||
        (e.marca || '').toLowerCase().includes(term);
      const matchEstado    = !this.filtroEstado    || e.estado     === this.filtroEstado;
      const matchTipo      = !this.filtroTipo      || e.tipo_nombre === this.filtroTipo;
      const matchUbicacion = !this.filtroUbicacion || e.ubicacion  === this.filtroUbicacion;
      return matchTerm && matchEstado && matchTipo && matchUbicacion;
    });
  }

  get paginados(): any[] {
    const start = (this.page - 1) * this.PER_PAGE;
    return this.filtrados.slice(start, start + this.PER_PAGE);
  }

  get totalPaginas(): number {
    return Math.max(1, Math.ceil(this.filtrados.length / this.PER_PAGE));
  }

  get botonesPage(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(1, this.page - 2); i <= Math.min(this.totalPaginas, this.page + 2); i++) pages.push(i);
    return pages;
  }

  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) this.page = p; }

  onFiltroChange(): void { this.page = 1; }

  get kpis() {
    const total     = this.equipos.length;
    const operativo = this.equipos.filter(e => e.estado === 'operativo').length;
    const mtto      = this.equipos.filter(e => e.estado === 'mantenimiento').length;
    const inoperativo = this.equipos.filter(e => e.estado === 'inoperativo').length;
    return { total, operativo, mtto, inoperativo };
  }

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.getMantenimientoGlobal().subscribe({
      next: (data) => { this.equipos = data; this.isLoading = false; },
      error: () => {
        this.errorMessage = 'Error de conexión con el servidor.';
        this.isLoading = false;
      },
    });
  }

  estadoClass(estado: string): string {
    const map: Record<string, string> = {
      'operativo':     'estado-operativo',
      'mantenimiento': 'estado-mtto',
      'inoperativo':   'estado-inoperativo',
      'en_revision':   'estado-revision',
    };
    return map[estado] ?? 'estado-operativo';
  }

  estadoLabel(estado: string): string {
    const map: Record<string, string> = {
      'operativo': 'Operativo', 'mantenimiento': 'Mantenimiento',
      'inoperativo': 'Inoperativo', 'en_revision': 'En Revisión',
    };
    return map[estado] ?? estado;
  }

  intervencionClass(e: string): string {
    const map: Record<string, string> = {
      'aprobado': 'interv-ok', 'observado': 'interv-obs',
      'rechazado': 'interv-bad', 'sin_inspeccion': 'interv-none',
    };
    return map[e] ?? 'interv-none';
  }

  intervencionLabel(e: string): string {
    const map: Record<string, string> = {
      'aprobado': 'OK', 'observado': 'Observado',
      'rechazado': 'Rechazado', 'sin_inspeccion': 'Sin insp.',
    };
    return map[e] ?? e;
  }

  formatFecha(iso: string | null): string {
    if (!iso) return '—';
    try {
      return new Date(iso + 'T00:00:00').toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
    } catch { return iso; }
  }

  isProximoVencido(iso: string | null): boolean {
    if (!iso) return false;
    return new Date(iso) < new Date();
  }
}

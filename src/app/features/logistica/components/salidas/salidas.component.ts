import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { Salida, SalidasKpis } from '../../logistica.models';

@Component({
  selector: 'app-salidas',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './salidas.component.html',
  styleUrls: ['./salidas.component.css'],
})
export class SalidasComponent implements OnInit {
  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  cargando = true;
  salidas: Salida[] = [];
  total    = 0;
  page     = 1;
  pageSize = 30;

  busqueda    = '';
  filtroDesde = '';
  filtroHasta = '';

  kpis: SalidasKpis = {
    totalSalidas: 0, totalUnidadesEntregadas: 0,
    salidasEsteMes: 0, proyectosAtendidos: 0,
  };

  expandidas    = new Set<string>();
  salidaReporte: Salida | null = null;

  ngOnInit(): void { this.cargar(); this.cargarKpis(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getSalidas({
      q:          this.busqueda    || undefined,
      desde:      this.filtroDesde || undefined,
      hasta:      this.filtroHasta || undefined,
      page:       this.page,
      pageSize:   this.pageSize,
    }).subscribe({
      next:  r => { this.salidas = r.items; this.total = r.total; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar salidas.', 'error'); },
    });
  }

  cargarKpis(): void {
    this.svc.getSalidasKpis().subscribe({ next: k => (this.kpis = k), error: () => {} });
  }

  buscar():        void { this.page = 1; this.cargar(); }
  limpiarFiltros(): void {
    this.busqueda = ''; this.filtroDesde = ''; this.filtroHasta = '';
    this.page = 1; this.cargar();
  }

  toggleExpandir(id: string): void {
    if (this.expandidas.has(id)) this.expandidas.delete(id);
    else this.expandidas.add(id);
  }

  get totalPaginas(): number { return Math.ceil(this.total / this.pageSize); }
  irPagina(p: number): void {
    if (p >= 1 && p <= this.totalPaginas) { this.page = p; this.cargar(); }
  }

  // ── Reporte ──
  abrirReporte(s: Salida): void  { this.salidaReporte = s; }
  cerrarReporte(): void          { this.salidaReporte = null; }
  imprimirReporte(): void        { window.print(); }

  // ── Helpers ──
  fechaCorta(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('es-PE', {
      day: '2-digit', month: 'short', year: 'numeric',
    });
  }

  fechaHora(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleString('es-PE', {
      day: '2-digit', month: 'short', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });
  }

  fechaImpresion(): string {
    return new Date().toLocaleDateString('es-PE', {
      day: '2-digit', month: 'long', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });
  }

  sumCantSolicitada(items: import('../../logistica.models').SalidaItem[]): number {
    return items.reduce((s, i) => s + i.cantidadSolicitada, 0);
  }
}

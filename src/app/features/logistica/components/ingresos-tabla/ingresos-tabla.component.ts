import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { Ingreso, IngresoItemLog } from '../../logistica.models';

@Component({
  selector: 'app-ingresos-tabla',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './ingresos-tabla.component.html',
  styleUrls: ['./ingresos-tabla.component.css'],
})
export class IngresosTablaComponent implements OnInit {
  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  cargando = true;
  ingresos: Ingreso[] = [];
  total    = 0;
  page     = 1;
  pageSize = 30;

  busqueda    = '';
  filtroDesde = this._primerDiaMes();
  filtroHasta = '';

  expandidos = new Set<string>();

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getIngresos({
      q:        this.busqueda    || undefined,
      desde:    this.filtroDesde || undefined,
      hasta:    this.filtroHasta || undefined,
      page:     this.page,
      pageSize: this.pageSize,
    }).subscribe({
      next:  r => { this.ingresos = r.items; this.total = r.total; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar ingresos.', 'error'); },
    });
  }

  buscar(): void { this.page = 1; this.cargar(); }

  limpiarFiltros(): void {
    this.busqueda    = '';
    this.filtroDesde = this._primerDiaMes();
    this.filtroHasta = '';
    this.page        = 1;
    this.cargar();
  }

  toggleExpandir(id: string): void {
    if (this.expandidos.has(id)) this.expandidos.delete(id);
    else this.expandidos.add(id);
  }

  get totalPaginas(): number { return Math.ceil(this.total / this.pageSize); }

  irPagina(p: number): void {
    if (p >= 1 && p <= this.totalPaginas) { this.page = p; this.cargar(); }
  }

  totalIngreso(ing: Ingreso): number {
    return ing.totalReal ?? ing.totalEstimado ?? 0;
  }

  resumenItems(items: IngresoItemLog[]): string {
    if (!items.length) return '—';
    const primeros = items.slice(0, 2).map(i => i.nombre).join(', ');
    return items.length > 2 ? `${primeros} +${items.length - 2} más` : primeros;
  }

  tiposBadges(items: IngresoItemLog[]): { tipo: string; count: number }[] {
    const mapa: Record<string, number> = {};
    for (const it of items) {
      const t = it.tipoItem || 'material';
      mapa[t] = (mapa[t] || 0) + 1;
    }
    return Object.entries(mapa).map(([tipo, count]) => ({ tipo, count }));
  }

  tipoLabel(tipo: string): string {
    return tipo === 'material' ? 'Mat.' : tipo === 'equipo' ? 'Eqp.' : 'Herr.';
  }

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

  private _primerDiaMes(): string {
    const hoy = new Date();
    return `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-01`;
  }
}

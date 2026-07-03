import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { HistoricoLegacyItem } from '../../logistica.models';

type FiltroTipo = '' | 'material' | 'equipo';

@Component({
  selector: 'app-historico-legacy',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './historico-legacy.component.html',
  styleUrls: ['./historico-legacy.component.css'],
})
export class HistoricoLegacyComponent implements OnInit {
  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  cargando = true;
  items: HistoricoLegacyItem[] = [];
  total    = 0;
  page     = 1;
  pageSize = 30;

  busqueda   = '';
  filtroTipo: FiltroTipo = '';

  get totalPaginas(): number {
    return Math.max(1, Math.ceil(this.total / this.pageSize));
  }

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getHistoricoLegacy({
      tipoItem: this.filtroTipo || undefined,
      q:        this.busqueda   || undefined,
      page:     this.page,
      pageSize: this.pageSize,
    }).subscribe({
      next:  r => { this.items = r.items; this.total = r.total; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar el histórico.', 'error'); },
    });
  }

  buscar(): void { this.page = 1; this.cargar(); }

  setFiltroTipo(t: FiltroTipo): void {
    this.filtroTipo = t;
    this.page = 1;
    this.cargar();
  }

  irPagina(p: number): void {
    if (p < 1 || p > this.totalPaginas) return;
    this.page = p;
    this.cargar();
  }

  fechaCorta(iso: string): string {
    if (!iso) return '—';
    return new Date(iso + 'T00:00:00').toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }
}

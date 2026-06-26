import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, ConfiguracionTributaria, RegistroFila } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';

type TabTrib = 'configuracion' | 'registro-compras' | 'registro-ventas';

@Component({
  selector: 'app-tributario',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './tributario.component.html',
  styleUrls: ['./tributario.component.css']
})
export class TributarioComponent implements OnInit {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  tab: TabTrib = 'configuracion';
  cargando = false;
  guardando = false;

  config: ConfiguracionTributaria | null = null;
  registros: RegistroFila[] = [];
  periodo = new Date().toISOString().slice(0, 7);

  page = 1;
  readonly PER_PAGE = 15;

  get paginados(): RegistroFila[] {
    const s = (this.page - 1) * this.PER_PAGE;
    return this.registros.slice(s, s + this.PER_PAGE);
  }
  get totalPaginas(): number { return Math.max(1, Math.ceil(this.registros.length / this.PER_PAGE)); }
  get totalItems(): number { return this.registros.length; }
  get botonesPage(): number[] {
    const pp: number[] = [];
    for (let i = Math.max(1, this.page - 2); i <= Math.min(this.totalPaginas, this.page + 2); i++) pp.push(i);
    return pp;
  }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) this.page = p; }

  ngOnInit(): void { this.cargarConfig(); }

  setTab(t: TabTrib): void {
    this.tab = t;
    this.page = 1;
    if (t === 'configuracion') this.cargarConfig();
    else this.cargarRegistro();
  }

  cargarConfig(): void {
    this.cargando = true;
    this.svc.getConfiguracionTributaria().subscribe({
      next: d => { this.config = d; this.cargando = false; },
      error: () => { this.cargando = false; }
    });
  }

  cargarRegistro(): void {
    this.cargando = true;
    this.page = 1;
    const obs$ = this.tab === 'registro-compras'
      ? this.svc.getRegistroCompras(this.periodo)
      : this.svc.getRegistroVentas(this.periodo);
    obs$.subscribe({
      next: d => { this.registros = d; this.cargando = false; },
      error: () => { this.cargando = false; }
    });
  }

  guardarConfig(): void {
    if (!this.config) return;
    this.guardando = true;
    this.svc.actualizarConfiguracionTributaria({ regimen_id: this.config.regimen_id }).subscribe({
      next: () => { this.guardando = false; this.toast.mostrar('Configuración guardada', 'success'); },
      error: () => { this.guardando = false; this.toast.mostrar('Error al guardar', 'error'); }
    });
  }

  get totalBaseImponible(): number {
    return this.registros.reduce((acc, r) => acc + r.base_imponible, 0);
  }
  get totalIgv(): number {
    return this.registros.reduce((acc, r) => acc + r.igv, 0);
  }
}

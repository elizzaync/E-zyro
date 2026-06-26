import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionService, ActivoFijo } from '../../../../core/services/administracion.service';
import { ToastService } from '../../../../core/services/toast.service';

type TabAF = 'activos' | 'depreciacion';

@Component({
  selector: 'app-activos-fijos',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './activos-fijos.component.html',
  styleUrls: ['./activos-fijos.component.css']
})
export class ActivosFijosComponent implements OnInit {
  private svc   = inject(AdministracionService);
  private toast = inject(ToastService);

  tab: TabAF = 'activos';
  cargando = false;
  activos: ActivoFijo[] = [];
  filtroEstado = '';
  busqueda = '';

  // Depreciación
  periodoDepreciacion = new Date().toISOString().slice(0, 7);
  procesando = false;
  activoDepreciacion: ActivoFijo | null = null;
  historialDep: any[] = [];
  cargandoHist = false;

  showForm = false;
  nuevo: Partial<ActivoFijo> = {};
  guardando = false;

  ngOnInit(): void { this.cargar(); }

  setTab(t: TabAF): void { this.tab = t; if (t === 'activos') this.cargar(); }

  cargar(): void {
    this.cargando = true;
    const f: any = {};
    if (this.filtroEstado) f.estado = this.filtroEstado;
    this.svc.getActivosFijos(f).subscribe({
      next: d => { this.activos = d; this.cargando = false; },
      error: () => { this.cargando = false; }
    });
  }

  get activosFiltrados(): ActivoFijo[] {
    const q = this.busqueda.toLowerCase().trim();
    return this.activos.filter(a => !q || a.nombre.toLowerCase().includes(q));
  }

  darDeBaja(a: ActivoFijo): void {
    if (!confirm(`¿Dar de baja el activo "${a.nombre}"?`)) return;
    this.svc.darDeBajaActivo(a.id).subscribe({
      next: () => { a.estado = 'dado_de_baja'; this.toast.mostrar('Activo dado de baja', 'success'); },
      error: () => this.toast.mostrar('Error', 'error')
    });
  }

  verDepreciacion(a: ActivoFijo): void {
    this.activoDepreciacion = this.activoDepreciacion?.id === a.id ? null : a;
    if (this.activoDepreciacion) {
      this.cargandoHist = true;
      this.svc.getDepreciacionActivo(a.id).subscribe({
        next: d => { this.historialDep = d; this.cargandoHist = false; },
        error: () => { this.cargandoHist = false; }
      });
    }
  }

  procesarDepreciacion(): void {
    this.procesando = true;
    this.svc.procesarDepreciacion(this.periodoDepreciacion).subscribe({
      next: (r: any) => {
        this.procesando = false;
        this.toast.mostrar(`Depreciación procesada: ${r.activos_procesados ?? 0} activos`, 'success');
        this.cargar();
      },
      error: () => { this.procesando = false; this.toast.mostrar('Error al procesar depreciación', 'error'); }
    });
  }

  guardar(): void {
    this.guardando = true;
    this.svc.crearActivoFijo(this.nuevo).subscribe({
      next: () => {
        this.toast.mostrar('Activo creado', 'success');
        this.showForm = false;
        this.nuevo = {};
        this.guardando = false;
        this.cargar();
      },
      error: () => { this.guardando = false; this.toast.mostrar('Error al crear activo', 'error'); }
    });
  }
}

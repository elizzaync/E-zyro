import { Component, Input, Output, EventEmitter, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';

interface FilaStock {
  id: string;
  nombre: string;
  codigo: string;
  cantidadActual: number;
  delta: number;
}

@Component({
  selector: 'app-rellenar-stock-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './rellenar-stock-modal.component.html',
  styleUrls: ['./rellenar-stock-modal.component.css'],
})
export class RellenarStockModalComponent implements OnInit {
  @Input() tipo: 'material' | 'equipo' = 'material';
  @Output() closed = new EventEmitter<{ guardado: boolean }>();

  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  filas: FilaStock[] = [];
  cargando  = true;
  guardando = false;
  busqueda  = '';
  motivo    = 'Reposición de stock';
  errorMsg  = '';

  get titulo(): string {
    return this.tipo === 'material' ? 'Rellenar Stock de Materiales' : 'Rellenar Stock de Equipos y Herramientas';
  }
  get subtitulo(): string {
    return this.tipo === 'material'
      ? 'Ingresa la cantidad a agregar por cada material'
      : 'Ingresa la cantidad a agregar por cada equipo o herramienta';
  }

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    if (this.tipo === 'material') {
      this.svc.getMateriales().subscribe({
        next: (items: any[]) => {
          this.filas = items.map(m => ({ id: m.id, nombre: m.nombre, codigo: m.codigo, cantidadActual: m.cantidad, delta: 0 }));
          this.cargando = false;
        },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar materiales.', 'error'); },
      });
    } else {
      this.svc.getEquipos().subscribe({
        next: (items: any[]) => {
          this.filas = items.map(e => ({ id: e.id, nombre: e.nombre, codigo: e.codigo, cantidadActual: e.cantidad, delta: 0 }));
          this.cargando = false;
        },
        error: () => { this.cargando = false; this.toast.mostrar('Error al cargar equipos.', 'error'); },
      });
    }
  }

  get filasFiltradas(): FilaStock[] {
    const q = this.busqueda.toLowerCase().trim();
    if (!q) return this.filas;
    return this.filas.filter(f => f.nombre.toLowerCase().includes(q) || f.codigo.toLowerCase().includes(q));
  }

  get totalConDelta(): number { return this.filas.filter(f => f.delta > 0).length; }

  guardar(): void {
    const conDelta = this.filas.filter(f => f.delta > 0);
    if (!conDelta.length) { this.errorMsg = 'Ingresa al menos una cantidad para agregar.'; return; }
    if (!this.motivo.trim()) { this.errorMsg = 'Ingresa un motivo para el ajuste.'; return; }
    this.errorMsg  = '';
    this.guardando = true;

    if (this.tipo === 'material') {
      const obs = conDelta.map(f =>
        this.svc.ajustarStockMaterial(f.id, f.delta, this.motivo.trim()).pipe(catchError(() => of(null)))
      );
      forkJoin(obs).subscribe({
        next: (results: any[]) => {
          this.guardando = false;
          const ok = results.filter(r => r !== null).length;
          const fail = results.length - ok;
          if (ok > 0) this.toast.mostrar(`Stock actualizado en ${ok} material${ok > 1 ? 'es' : ''}.${fail > 0 ? ` ${fail} fallo(s).` : ''}`, 'success');
          else this.toast.mostrar('No se pudo actualizar el stock.', 'error');
          this.closed.emit({ guardado: ok > 0 });
        },
      });
    } else {
      const obs = conDelta.map(f =>
        this.svc.actualizarEquipo(f.id, { cantidad: f.cantidadActual + f.delta }).pipe(catchError(() => of(null)))
      );
      forkJoin(obs).subscribe({
        next: (results: any[]) => {
          this.guardando = false;
          const ok = results.filter(r => r !== null).length;
          const fail = results.length - ok;
          if (ok > 0) this.toast.mostrar(`Stock actualizado en ${ok} equipo${ok > 1 ? 's' : ''}.${fail > 0 ? ` ${fail} fallo(s).` : ''}`, 'success');
          else this.toast.mostrar('No se pudo actualizar el stock.', 'error');
          this.closed.emit({ guardado: ok > 0 });
        },
      });
    }
  }

  limpiar(): void { this.filas.forEach(f => (f.delta = 0)); }

  cerrar(): void { this.closed.emit({ guardado: false }); }
}

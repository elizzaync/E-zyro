import { Component, Output, EventEmitter, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

interface ItemIngreso {
  clase: 'material' | 'equipo' | 'herramienta';
  nombre: string;
  cantidad: number;
  precioCompra: number | null;
  codigo: string;
}

@Component({
  selector: 'app-ingreso-directo-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './ingreso-directo-modal.component.html',
  styleUrls: ['./ingreso-directo-modal.component.css'],
})
export class IngresoDirectoModalComponent implements OnInit {
  @Output() closed = new EventEmitter<{ guardado: boolean }>();

  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  proveedor = '';
  notas     = '';
  guardando = false;
  errorMsg  = '';

  // búsqueda por código
  codigoBusqueda = '';
  buscando       = false;
  busquedaError  = '';

  items: ItemIngreso[] = [];

  ngOnInit(): void { this.agregarItem(); }

  agregarItem(): void {
    this.items.push({ clase: 'material', nombre: '', cantidad: 1, precioCompra: null, codigo: '' });
  }

  quitarItem(i: number): void { this.items.splice(i, 1); }

  buscarPorCodigo(): void {
    const cod = this.codigoBusqueda.trim();
    if (!cod) return;
    this.buscando = true;
    this.busquedaError = '';
    this.svc.getArticuloPorCodigo(cod).subscribe({
      next: (art: any) => {
        this.buscando = false;
        const clase: 'material' | 'equipo' | 'herramienta' =
          art.tipo === 'material' ? 'material' : art.clase === 'herramienta' ? 'herramienta' : 'equipo';
        this.items.push({
          clase, nombre: art.nombre || '', cantidad: 1,
          precioCompra: art.precioCompra ?? null, codigo: cod,
        });
        this.codigoBusqueda = '';
      },
      error: (err: any) => {
        this.buscando = false;
        this.busquedaError = err?.error?.detail ?? 'Artículo no encontrado.';
      },
    });
  }

  guardar(): void {
    if (this.items.length === 0) { this.errorMsg = 'Agrega al menos un ítem.'; return; }
    const itemsInvalidos = this.items.filter(i => !i.nombre.trim() || i.cantidad < 1);
    if (itemsInvalidos.length) { this.errorMsg = 'Completa nombre y cantidad de todos los ítems.'; return; }

    this.errorMsg  = '';
    this.guardando = true;

    const body = {
      proveedor: this.proveedor || null,
      notas:     this.notas     || null,
      destino:   { tipo: 'stock' },
      items:     this.items.map(i => ({
        clase:        i.clase,
        modo:         'nuevo',
        nombre:       i.nombre.trim(),
        cantidad:     i.cantidad,
        precioCompra: i.precioCompra ?? null,
        codigo:       i.codigo || null,
      })),
    };

    this.svc.ingresarDirecto(body).subscribe({
      next: (res: any) => {
        this.guardando = false;
        this.toast.mostrar(`Ingreso registrado: ${res.totalItems} ítem(s) al inventario`, 'success');
        this.closed.emit({ guardado: true });
      },
      error: (err: any) => {
        this.guardando = false;
        this.errorMsg = err?.error?.detail ?? 'Error al registrar el ingreso.';
      },
    });
  }

  cerrar(): void { this.closed.emit({ guardado: false }); }

  claseLabel(c: string): string {
    return { material: 'Material', equipo: 'Equipo', herramienta: 'Herramienta' }[c] ?? c;
  }
}

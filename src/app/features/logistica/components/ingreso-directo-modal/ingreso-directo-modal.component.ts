import { Component, Output, EventEmitter, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { CatalogoItem, UnidadItem, Proveedor } from '../../logistica.models';

type ClaseCompraDirecta = 'material' | 'equipo' | 'herramienta' | 'epp';

interface ItemIngreso {
  clase: ClaseCompraDirecta;
  nombre: string;
  cantidad: number;
  precioCompra: number | null;
  codigo: string;
  existenteId: string | null;  // set cuando el ítem viene de "buscar por código" (reingreso a stock)
  // material
  categoriaId: string;
  unidadId: string;
  // epp
  marcaId: string;
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

  notas     = '';
  guardando = false;
  errorMsg  = '';

  // búsqueda por código
  codigoBusqueda = '';
  buscando       = false;
  busquedaError  = '';

  categorias: CatalogoItem[] = [];
  unidades:   UnidadItem[]   = [];
  marcas:     CatalogoItem[] = [];

  // ── Proveedor: elegir de la lista, escribir un canal libre, o dar de alta uno nuevo ──
  proveedores: Proveedor[] = [];
  proveedorId       : string | null = null;
  proveedorNombre   : string | null = null;
  canalCustom       = false;
  canalTexto        = '';
  mostrarNuevoProveedor = false;
  nuevoProveedorNombre  = '';
  creandoProveedor      = false;

  items: ItemIngreso[] = [];

  ngOnInit(): void {
    this.agregarItem();
    this.svc.getCategorias().subscribe({ next: r => (this.categorias = r) });
    this.svc.getUnidades().subscribe({ next: r => (this.unidades = r) });
    this.svc.getMarcas().subscribe({ next: r => (this.marcas = r) });
    this.svc.getProveedores().subscribe({ next: r => (this.proveedores = r) });
  }

  get totalEstimado(): number {
    return this.items.reduce((s, i) => s + (i.cantidad * (i.precioCompra ?? 0)), 0);
  }

  starsText(n: number): string { return '★'.repeat(n) + '☆'.repeat(5 - n); }

  selProveedor(p: Proveedor): void {
    if (this.proveedorId === p.id) { this.proveedorId = null; this.proveedorNombre = null; return; }
    this.proveedorId = p.id; this.proveedorNombre = p.nombre;
    this.canalCustom = false; this.canalTexto = '';
    this.mostrarNuevoProveedor = false;
  }

  toggleCanalCustom(): void {
    this.canalCustom = !this.canalCustom;
    if (this.canalCustom) { this.proveedorId = null; this.proveedorNombre = null; this.mostrarNuevoProveedor = false; }
    else { this.canalTexto = ''; }
  }

  toggleNuevoProveedor(): void {
    this.mostrarNuevoProveedor = !this.mostrarNuevoProveedor;
    this.nuevoProveedorNombre = '';
    if (this.mostrarNuevoProveedor) { this.canalCustom = false; this.canalTexto = ''; }
  }

  confirmarNuevoProveedor(): void {
    const nombre = this.nuevoProveedorNombre.trim();
    if (!nombre) return;
    this.creandoProveedor = true;
    this.svc.crearProveedor({ nombre }).subscribe({
      next: p => {
        this.creandoProveedor = false;
        this.proveedores = [p, ...this.proveedores];
        this.selProveedor(p);
        this.mostrarNuevoProveedor = false;
      },
      error: err => {
        this.creandoProveedor = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo registrar el proveedor.', 'error');
      },
    });
  }

  private _nuevoItem(): ItemIngreso {
    return {
      clase: 'material', nombre: '', cantidad: 1, precioCompra: null, codigo: '',
      existenteId: null, categoriaId: '', unidadId: '', marcaId: '',
    };
  }

  agregarItem(): void { this.items.push(this._nuevoItem()); }

  quitarItem(i: number): void { this.items.splice(i, 1); }

  // Al cambiar de clase, limpiamos los campos que no aplican a la nueva clase.
  onClaseChange(item: ItemIngreso): void {
    if (item.clase !== 'material') item.categoriaId = '';
    if (item.clase !== 'material' && item.clase !== 'epp') item.unidadId = '';
    if (item.clase !== 'epp') item.marcaId = '';
  }

  buscarPorCodigo(): void {
    const cod = this.codigoBusqueda.trim();
    if (!cod) return;
    this.buscando = true;
    this.busquedaError = '';
    this.svc.getArticuloPorCodigo(cod).subscribe({
      next: (art: any) => {
        this.buscando = false;
        const clase: ClaseCompraDirecta =
          art.tipo === 'material' ? 'material' : art.clase === 'herramienta' ? 'herramienta' : 'equipo';
        const item = this._nuevoItem();
        item.clase = clase;
        item.nombre = art.nombre || '';
        item.precioCompra = art.precioCompra ?? null;
        item.codigo = cod;
        item.existenteId = art.id;
        this.items.push(item);
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
    const materialesSinCatalogo = this.items.filter(i =>
      i.clase === 'material' && !i.existenteId && (!i.categoriaId || !i.unidadId));
    if (materialesSinCatalogo.length) {
      this.errorMsg = 'Selecciona categoría y unidad para los materiales nuevos.';
      return;
    }

    this.errorMsg  = '';
    this.guardando = true;

    const body = {
      proveedor: this.canalCustom ? (this.canalTexto.trim() || null) : this.proveedorNombre,
      notas:     this.notas     || null,
      destino:   { tipo: 'stock' },
      items:     this.items.map(i => ({
        clase:        i.clase,
        modo:         i.existenteId ? 'existente' : 'nuevo',
        existenteId:  i.existenteId ?? undefined,
        nombre:       i.nombre.trim(),
        cantidad:     i.cantidad,
        precioCompra: i.precioCompra ?? null,
        categoriaId:  i.clase === 'material' ? (i.categoriaId || null) : null,
        unidadId:     (i.clase === 'material' || i.clase === 'epp') ? (i.unidadId || null) : null,
        marcaId:      i.clase === 'epp' ? (i.marcaId || null) : null,
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
    return { material: 'Material', equipo: 'Equipo', herramienta: 'Herramienta', epp: 'EPP' }[c] ?? c;
  }
}

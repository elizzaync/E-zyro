import { Component, Output, EventEmitter, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import {
  CatalogoItem, UnidadItem, AlmacenItem, CategoriaEquipoItem, ModeloItem, Proveedor,
} from '../../logistica.models';

type ClaseCompraDirecta = 'material' | 'equipo' | 'herramienta' | 'epp';

const ESTADOS_EQUIPO: { value: string; label: string }[] = [
  { value: 'operativo', label: 'Operativo' },
  { value: 'en_mantenimiento', label: 'En mantenimiento' },
  { value: 'fuera_de_servicio', label: 'Fuera de servicio' },
];

interface ItemIngreso {
  clase: ClaseCompraDirecta;
  nombre: string;
  cantidad: number;
  precioCompra: number | null;
  codigo: string;
  existenteId: string | null;  // set cuando el ítem viene de "buscar por código" (reingreso a stock)
  descripcion: string;
  // material
  categoriaId: string;
  unidadId: string;
  // equipo / herramienta
  categoriaEquipoId: string;
  marcaId: string;
  modeloId: string;
  numeroSerie: string;
  estado: string;
  requiereMantenimiento: boolean;
  frecuenciaMantenimiento: string;
  // epp (unidadId se reusa)
  // comunes opcionales
  almacenId: string;
  stockMinimo: number;
  // estado de UI (no se envía al backend)
  mostrarDetalles: boolean;
  modelosDisponibles: ModeloItem[];
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

  estadosEquipo = ESTADOS_EQUIPO;
  clasesDisponibles: ClaseCompraDirecta[] = ['material', 'equipo', 'herramienta', 'epp'];

  // búsqueda por código
  codigoBusqueda = '';
  buscando       = false;
  busquedaError  = '';

  // catálogos compartidos
  categorias:       CatalogoItem[]        = [];
  unidades:         UnidadItem[]          = [];
  marcas:           CatalogoItem[]        = [];
  categoriasEquipo: CategoriaEquipoItem[] = [];
  almacenes:        AlmacenItem[]         = [];

  // "+ Nueva …" inline (aplican al ítem expandido)
  showAddCategoria = false; nuevaCategoria = ''; creandoCategoria = false;
  showAddCategoriaEq = false; nuevaCategoriaEq = ''; creandoCategoriaEq = false;
  showAddMarca = false; nuevaMarca = ''; creandoMarca = false;

  // ── Proveedor: elegir de la lista, escribir un canal libre, o dar de alta uno nuevo ──
  proveedores: Proveedor[] = [];
  proveedorId       : string | null = null;
  proveedorNombre   : string | null = null;
  canalCustom       = false;
  canalTexto        = '';
  mostrarNuevoProveedor = false;
  nuevoProveedorNombre  = '';
  nuevoProveedorRuc     = '';
  creandoProveedor      = false;

  items: ItemIngreso[] = [];
  expandedIndex = 0;

  ngOnInit(): void {
    this.agregarItem();
    this.svc.getCategorias().subscribe({ next: r => (this.categorias = r) });
    this.svc.getUnidades().subscribe({ next: r => (this.unidades = r) });
    this.svc.getMarcas().subscribe({ next: r => (this.marcas = r) });
    this.svc.getCategoriasEquipo().subscribe({ next: r => (this.categoriasEquipo = r) });
    this.svc.getAlmacenes().subscribe({ next: r => (this.almacenes = r) });
    this.svc.getProveedores().subscribe({ next: r => (this.proveedores = r) });
  }

  private _nuevoItem(): ItemIngreso {
    return {
      clase: 'material', nombre: '', cantidad: 1, precioCompra: null, codigo: '',
      existenteId: null, descripcion: '',
      categoriaId: '', unidadId: '',
      categoriaEquipoId: '', marcaId: '', modeloId: '', numeroSerie: '', estado: 'operativo',
      requiereMantenimiento: false, frecuenciaMantenimiento: 'mensual',
      almacenId: '', stockMinimo: 0,
      mostrarDetalles: false, modelosDisponibles: [],
    };
  }

  categoriasEquipoDe(item: ItemIngreso): CategoriaEquipoItem[] {
    return this.categoriasEquipo.filter(c => !c.clase || c.clase === item.clase);
  }

  agregarItem(): void {
    this.items.push(this._nuevoItem());
    this.expandedIndex = this.items.length - 1;
  }

  quitarItem(i: number): void {
    this.items.splice(i, 1);
    if (this.expandedIndex >= this.items.length) this.expandedIndex = this.items.length - 1;
  }

  toggleExpandir(i: number): void { this.expandedIndex = this.expandedIndex === i ? -1 : i; }
  toggleDetalles(item: ItemIngreso): void { item.mostrarDetalles = !item.mostrarDetalles; }

  resumenItem(item: ItemIngreso): string {
    const nombre = item.nombre.trim() || 'Sin nombre';
    const precio = item.precioCompra ? ` · S/ ${(item.cantidad * item.precioCompra).toFixed(2)}` : '';
    return `${nombre} · ${item.cantidad} un.${precio}`;
  }

  // Al cambiar de clase, limpiamos los campos que no aplican a la nueva clase.
  onClaseChange(item: ItemIngreso): void {
    item.categoriaId = ''; item.categoriaEquipoId = ''; item.marcaId = '';
    item.modeloId = ''; item.numeroSerie = ''; item.modelosDisponibles = [];
    item.requiereMantenimiento = false;
  }

  onMarcaChange(item: ItemIngreso): void {
    item.modeloId = '';
    if (!item.marcaId) { item.modelosDisponibles = []; return; }
    this.svc.getModelos(item.marcaId).subscribe({ next: r => (item.modelosDisponibles = r) });
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
        this.expandedIndex = this.items.length - 1;
        this.codigoBusqueda = '';
      },
      error: (err: any) => {
        this.buscando = false;
        this.busquedaError = err?.error?.detail ?? 'Artículo no encontrado.';
      },
    });
  }

  // ── Proveedor ──
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
    this.nuevoProveedorNombre = ''; this.nuevoProveedorRuc = '';
    if (this.mostrarNuevoProveedor) { this.canalCustom = false; this.canalTexto = ''; }
  }

  confirmarNuevoProveedor(): void {
    const nombre = this.nuevoProveedorNombre.trim();
    if (!nombre) return;
    this.creandoProveedor = true;
    this.svc.crearProveedor({ nombre, ruc: this.nuevoProveedorRuc.trim() || undefined }).subscribe({
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

  // ── "+ Nueva …" inline: aplican al ítem que está expandido ──
  private get itemActivo(): ItemIngreso | null { return this.items[this.expandedIndex] ?? null; }

  toggleAddCategoria(): void { this.showAddCategoria = !this.showAddCategoria; this.nuevaCategoria = ''; }
  confirmarNuevaCategoria(): void {
    const n = this.nuevaCategoria.trim(); if (!n) return;
    this.creandoCategoria = true;
    this.svc.crearCategoria(n).subscribe({
      next: c => {
        this.categorias = [...this.categorias.filter(x => x.id !== c.id), c].sort((a, b) => a.nombre.localeCompare(b.nombre));
        if (this.itemActivo) this.itemActivo.categoriaId = c.id;
        this.showAddCategoria = false; this.nuevaCategoria = ''; this.creandoCategoria = false;
      },
      error: () => (this.creandoCategoria = false),
    });
  }

  toggleAddCategoriaEq(): void { this.showAddCategoriaEq = !this.showAddCategoriaEq; this.nuevaCategoriaEq = ''; }
  confirmarNuevaCategoriaEq(): void {
    const n = this.nuevaCategoriaEq.trim(); if (!n) return;
    this.creandoCategoriaEq = true;
    this.svc.crearCategoriaEquipo(n).subscribe({
      next: c => {
        this.categoriasEquipo = [...this.categoriasEquipo.filter(x => x.id !== c.id), c as CategoriaEquipoItem]
          .sort((a, b) => a.nombre.localeCompare(b.nombre));
        if (this.itemActivo) this.itemActivo.categoriaEquipoId = c.id;
        this.showAddCategoriaEq = false; this.nuevaCategoriaEq = ''; this.creandoCategoriaEq = false;
      },
      error: () => (this.creandoCategoriaEq = false),
    });
  }

  toggleAddMarca(): void { this.showAddMarca = !this.showAddMarca; this.nuevaMarca = ''; }
  confirmarNuevaMarca(): void {
    const n = this.nuevaMarca.trim(); if (!n) return;
    this.creandoMarca = true;
    this.svc.crearMarca(n).subscribe({
      next: m => {
        this.marcas = [...this.marcas.filter(x => x.id !== m.id), m].sort((a, b) => a.nombre.localeCompare(b.nombre));
        if (this.itemActivo) { this.itemActivo.marcaId = m.id; this.onMarcaChange(this.itemActivo); }
        this.showAddMarca = false; this.nuevaMarca = ''; this.creandoMarca = false;
      },
      error: () => (this.creandoMarca = false),
    });
  }

  get totalEstimado(): number {
    return this.items.reduce((s, i) => s + (i.cantidad * (i.precioCompra ?? 0)), 0);
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
        almacenId:    i.almacenId || null,
        stockMinimo:  i.stockMinimo || null,
        descripcion:  i.clase === 'material' ? (i.descripcion.trim() || null) : null,
        observaciones: (i.clase === 'equipo' || i.clase === 'herramienta') ? (i.descripcion.trim() || null) : null,
        categoriaId:  i.clase === 'material' ? (i.categoriaId || null) : null,
        unidadId:     (i.clase === 'material' || i.clase === 'epp') ? (i.unidadId || null) : null,
        marcaId:      (i.clase === 'epp' || i.clase === 'equipo' || i.clase === 'herramienta') ? (i.marcaId || null) : null,
        categoriaEquipoId: (i.clase === 'equipo' || i.clase === 'herramienta') ? (i.categoriaEquipoId || null) : null,
        modeloId:     (i.clase === 'equipo' || i.clase === 'herramienta') ? (i.modeloId || null) : null,
        numeroSerie:  (i.clase === 'equipo' || i.clase === 'herramienta') ? (i.numeroSerie.trim() || null) : null,
        estado:       (i.clase === 'equipo' || i.clase === 'herramienta') ? i.estado : null,
        requiereMantenimiento:   (i.clase === 'equipo' || i.clase === 'herramienta') ? i.requiereMantenimiento : null,
        frecuenciaMantenimiento: (i.clase === 'equipo' || i.clase === 'herramienta') && i.requiereMantenimiento ? i.frecuenciaMantenimiento : null,
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

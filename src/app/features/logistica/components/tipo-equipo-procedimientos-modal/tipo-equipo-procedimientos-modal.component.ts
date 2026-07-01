import { Component, Input, Output, EventEmitter, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { CatalogoItem } from '../../logistica.models';

interface FilaProcedimiento {
  orden: number;
  nombre: string;
  descripcion: string;
  editando: boolean;
}

@Component({
  selector: 'app-tipo-equipo-procedimientos-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './tipo-equipo-procedimientos-modal.component.html',
  styleUrls: ['./tipo-equipo-procedimientos-modal.component.css'],
})
export class TipoEquipoProcedimientosModalComponent implements OnInit {
  @Input() tipoIdInicial: string | null = null;
  @Output() closed = new EventEmitter<void>();

  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  tipos: CatalogoItem[] = [];
  tipoIdSeleccionado: string | null = null;
  nombreTipoSeleccionado = '';

  cargandoTipos  = true;
  cargandoProcs  = false;
  guardando      = false;

  procedimientos: FilaProcedimiento[] = [];

  nuevoNombre      = '';
  nuevoDescripcion = '';
  agregando        = false;

  // ── Crear nuevo tipo desde el sidebar ──
  showNuevoTipo   = false;
  nuevoTipoNombre = '';
  creandoTipo     = false;
  // procedimientos del nuevo tipo (obligatorio)
  ntProcs: { nombre: string; descripcion: string }[] = [];
  ntNombre = ''; ntDesc = '';

  abrirNuevoTipo(): void {
    this.showNuevoTipo = true;
    this.nuevoTipoNombre = ''; this.ntProcs = []; this.ntNombre = ''; this.ntDesc = '';
  }
  cancelarNuevoTipo(): void { this.showNuevoTipo = false; }

  agregarProcNuevoTipo(): void {
    const n = this.ntNombre.trim(); if (!n) return;
    this.ntProcs.push({ nombre: n, descripcion: this.ntDesc.trim() });
    this.ntNombre = ''; this.ntDesc = '';
  }
  quitarProcNuevoTipo(i: number): void { this.ntProcs.splice(i, 1); }

  confirmarNuevoTipo(): void {
    const n = this.nuevoTipoNombre.trim();
    if (!n || this.ntProcs.length === 0 || this.creandoTipo) return;
    this.creandoTipo = true;
    this.svc.crearTipoEquipo(n).subscribe({
      next: (t) => {
        const procs = this.ntProcs.map((p, i) => ({ orden: i + 1, nombre: p.nombre, descripcion: p.descripcion || undefined }));
        this.svc.actualizarProcedimientosTipoEquipo(t.id, procs).subscribe({
          complete: () => {
            this.tipos = [...this.tipos.filter(x => x.id !== t.id), t].sort((a, b) => a.nombre.localeCompare(b.nombre));
            this.creandoTipo = false;
            this.showNuevoTipo = false;
            this.toast.mostrar(`Tipo "${t.nombre}" creado con ${procs.length} procedimiento(s).`, 'success');
            this.seleccionarTipo(t.id);
          },
          error: () => { this.creandoTipo = false; this.toast.mostrar('Error al guardar procedimientos.', 'error'); },
        });
      },
      error: () => { this.creandoTipo = false; this.toast.mostrar('Error al crear el tipo.', 'error'); },
    });
  }

  ngOnInit(): void {
    this.svc.getTiposEquipo().subscribe({
      next: (r) => {
        this.tipos = r;
        this.cargandoTipos = false;
        const ini = this.tipoIdInicial ?? (r.length > 0 ? r[0].id : null);
        if (ini) this.seleccionarTipo(ini);
      },
      error: () => { this.cargandoTipos = false; },
    });
  }

  seleccionarTipo(id: string): void {
    const t = this.tipos.find(x => x.id === id);
    if (!t) return;
    this.tipoIdSeleccionado    = id;
    this.nombreTipoSeleccionado = t.nombre;
    this.cargandoProcs  = true;
    this.procedimientos = [];
    this.cancelarAgregado();
    this.svc.getProcedimientosTipoEquipo(id).subscribe({
      next: (r) => {
        this.procedimientos = (r.procedimientos || []).map((p: any) => ({
          orden:       p.orden,
          nombre:      p.nombre,
          descripcion: p.descripcion ?? '',
          editando:    false,
        }));
        this.cargandoProcs = false;
      },
      error: () => { this.cargandoProcs = false; },
    });
  }

  moverArriba(i: number): void {
    if (i === 0) return;
    [this.procedimientos[i], this.procedimientos[i - 1]] =
      [this.procedimientos[i - 1], this.procedimientos[i]];
    this.reordenar();
  }

  moverAbajo(i: number): void {
    if (i === this.procedimientos.length - 1) return;
    [this.procedimientos[i], this.procedimientos[i + 1]] =
      [this.procedimientos[i + 1], this.procedimientos[i]];
    this.reordenar();
  }

  private reordenar(): void {
    this.procedimientos.forEach((p, idx) => (p.orden = idx + 1));
  }

  eliminar(i: number): void {
    this.procedimientos.splice(i, 1);
    this.reordenar();
  }

  toggleEditar(p: FilaProcedimiento): void {
    p.editando = !p.editando;
  }

  agregarProcedimiento(): void {
    const n = this.nuevoNombre.trim();
    if (!n) return;
    this.procedimientos.push({
      orden:       this.procedimientos.length + 1,
      nombre:      n,
      descripcion: this.nuevoDescripcion.trim(),
      editando:    false,
    });
    this.nuevoNombre      = '';
    this.nuevoDescripcion = '';
    this.agregando        = false;
  }

  cancelarAgregado(): void {
    this.agregando        = false;
    this.nuevoNombre      = '';
    this.nuevoDescripcion = '';
  }

  guardar(): void {
    if (!this.tipoIdSeleccionado) return;
    this.guardando = true;
    const payload = this.procedimientos.map((p, i) => ({
      orden:       i + 1,
      nombre:      p.nombre.trim(),
      descripcion: p.descripcion.trim() || undefined,
    }));
    this.svc.actualizarProcedimientosTipoEquipo(this.tipoIdSeleccionado, payload).subscribe({
      next: () => {
        this.guardando = false;
        this.toast.mostrar(`Procedimientos de "${this.nombreTipoSeleccionado}" guardados.`, 'success');
        this.reordenar();
      },
      error: () => { this.guardando = false; this.toast.mostrar('Error al guardar procedimientos.', 'error'); },
    });
  }

  cerrar(): void { this.closed.emit(); }
}

import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { DocumentosSstService, DocumentoSst, TipoDocSst } from '../../../core/services/documentos-sst.service';
import { OperacionesService } from '../../../core/services/operaciones.service';
import { ToastService } from '../../../core/services/toast.service';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

type Tab = 'homologacion' | 'ats' | 'petar';

interface FormDoc {
  titulo: string;
  clienteId: string;
  entidadEmisora: string;
  codigo: string;
  fechaEmision: string;
  fechaVencimiento: string;
  observaciones: string;
  archivoBase64: string | null;
  archivoNombre: string | null;
}

@Component({
  selector: 'app-documentos-sst',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './documentos-sst.component.html',
  styleUrls: ['./documentos-sst.component.css'],
})
export class DocumentosSstComponent implements OnInit {
  private svc   = inject(DocumentosSstService);
  private opsSvc = inject(OperacionesService);
  private toast = inject(ToastService);

  tab: Tab = 'homologacion';
  docs: DocumentoSst[] = [];
  cargando = true;
  busqueda = '';

  clientes: { id: string; nombre: string }[] = [];

  // Modal subir / editar
  showForm   = false;
  editandoId: string | null = null;
  guardando  = false;
  archivoError = '';

  form: FormDoc = this.formVacio();

  // Confirmación eliminar
  docAEliminar: DocumentoSst | null = null;
  eliminando = false;

  ngOnInit(): void {
    this.cargar();
    this.opsSvc.getClientes().subscribe({
      next: (r: any) => {
        const lista = Array.isArray(r) ? r : (r.items ?? []);
        this.clientes = lista.map((c: any) => ({ id: c.id, nombre: c.razon_social || c.nombre || c.id }));
      },
    });
  }

  setTab(t: Tab): void { this.tab = t; this.busqueda = ''; this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.svc.listar({ tipo: this.tab }).subscribe({
      next: (r) => { this.docs = r; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar documentos.', 'error'); },
    });
  }

  get docsFiltrados(): DocumentoSst[] {
    const q = this.busqueda.toLowerCase().trim();
    if (!q) return this.docs;
    return this.docs.filter(d =>
      d.titulo.toLowerCase().includes(q) ||
      (d.cliente_nombre ?? '').toLowerCase().includes(q) ||
      (d.entidad_emisora ?? '').toLowerCase().includes(q) ||
      (d.codigo ?? '').toLowerCase().includes(q)
    );
  }

  get tabLabel(): string {
    return this.tab === 'homologacion' ? 'Homologación' : this.tab === 'petar' ? 'PETAR' : 'ATS';
  }

  // ── Form ──────────────────────────────────────────────────────────────────
  private formVacio(): FormDoc {
    return { titulo: '', clienteId: '', entidadEmisora: '', codigo: '',
             fechaEmision: '', fechaVencimiento: '', observaciones: '',
             archivoBase64: null, archivoNombre: null };
  }

  abrirNuevo(): void {
    this.editandoId  = null;
    this.form        = this.formVacio();
    this.archivoError = '';
    this.showForm    = true;
  }

  abrirEditar(d: DocumentoSst): void {
    this.editandoId = d.id;
    this.form = {
      titulo:          d.titulo,
      clienteId:       d.cliente_id ?? '',
      entidadEmisora:  d.entidad_emisora ?? '',
      codigo:          d.codigo ?? '',
      fechaEmision:    d.fecha_emision ?? '',
      fechaVencimiento:d.fecha_vencimiento ?? '',
      observaciones:   d.observaciones ?? '',
      archivoBase64:   null,
      archivoNombre:   null,
    };
    this.archivoError = '';
    this.showForm = true;
  }

  cerrarForm(): void { this.showForm = false; this.editandoId = null; }

  onArchivo(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file  = input.files?.[0];
    this.archivoError = '';
    if (!file) return;

    const allowed = ['application/pdf', 'image/png', 'image/jpeg'];
    if (!allowed.includes(file.type)) {
      this.archivoError = 'Solo se permiten archivos PDF, PNG o JPG.';
      input.value = '';
      return;
    }
    if (file.size > 15 * 1024 * 1024) {
      this.archivoError = 'El archivo no debe superar 15 MB.';
      input.value = '';
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      this.form.archivoBase64 = (reader.result as string);
      this.form.archivoNombre = file.name;
    };
    reader.readAsDataURL(file);
  }

  guardar(): void {
    if (!this.form.titulo.trim()) {
      this.toast.mostrar('El título es obligatorio.', 'error'); return;
    }
    this.guardando = true;
    const payload = {
      titulo:            this.form.titulo.trim(),
      tipo:              this.tab as TipoDocSst,
      cliente_id:        this.form.clienteId || null,
      entidad_emisora:   this.form.entidadEmisora || null,
      codigo:            this.form.codigo || null,
      fecha_emision:     this.form.fechaEmision || null,
      fecha_vencimiento: this.form.fechaVencimiento || null,
      observaciones:     this.form.observaciones || null,
      archivo_base64:    this.form.archivoBase64,
      archivo_nombre:    this.form.archivoNombre,
    };

    const obs = this.editandoId
      ? this.svc.editar(this.editandoId, payload)
      : this.svc.crear(payload);

    obs.subscribe({
      next: () => {
        this.guardando = false;
        this.toast.mostrar(this.editandoId ? 'Documento actualizado.' : 'Documento subido.', 'success');
        this.cerrarForm();
        this.cargar();
      },
      error: () => { this.guardando = false; this.toast.mostrar('No se pudo guardar.', 'error'); },
    });
  }

  // ── Eliminar ──────────────────────────────────────────────────────────────
  pedirEliminar(d: DocumentoSst): void { this.docAEliminar = d; }
  cancelarEliminar(): void { this.docAEliminar = null; }
  confirmarEliminar(): void {
    if (!this.docAEliminar) return;
    this.eliminando = true;
    this.svc.eliminar(this.docAEliminar.id).subscribe({
      next: () => {
        this.eliminando = false; this.docAEliminar = null;
        this.toast.mostrar('Documento eliminado.', 'success');
        this.cargar();
      },
      error: () => { this.eliminando = false; this.toast.mostrar('No se pudo eliminar.', 'error'); },
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  estadoLabel(e: string): string {
    return { vigente: 'Vigente', por_vencer: 'Por vencer', vencida: 'Vencida', sin_fecha: 'Sin fecha' }[e] ?? e;
  }

  abrirArchivo(url: string | null): void {
    if (url) window.open(url, '_blank');
  }

  esImagen(d: DocumentoSst): boolean {
    return ['png', 'jpg', 'jpeg'].includes((d.formato ?? '').toLowerCase());
  }
}

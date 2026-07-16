import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FormatosService, Formato, FormatoVersion } from '../../core/services/formatos.service';
import { ToastService } from '../../core/services/toast.service';
import { SpinnerComponent } from '../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../shared/components/modal/app-modal.component';

interface FormForm {
  nombre: string;
  tipo_formato: string;
  nota: string;
  archivoBase64: string | null;
  archivoNombre: string | null;
}

@Component({
  selector: 'app-documentos-formatos',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './documentos-formatos.component.html',
  styleUrls: ['./documentos-formatos.component.css'],
})
export class DocumentosFormatosComponent implements OnInit {
  private svc   = inject(FormatosService);
  private toast = inject(ToastService);

  formatos: Formato[] = [];
  cargando = true;
  busqueda = '';
  filtroTipo = '';

  // Los formatos nunca se eliminan: solo se publican nuevas versiones.
  // Gestionar (crear/actualizar) queda oculto para roles operativos; el
  // backend igual lo exige vía RBAC 'formatos:gestionar'.
  puedeGestionar = false;

  // Modal nuevo / actualizar
  showForm = false;
  formatoEnEdicion: Formato | null = null;   // null = nuevo
  guardando = false;
  archivoError = '';
  form: FormForm = this.formVacio();

  // Modal historial
  showHistorial = false;
  historialDe: Formato | null = null;
  versiones: FormatoVersion[] = [];
  cargandoVersiones = false;

  ngOnInit(): void {
    const u = localStorage.getItem('ezyro_user');
    if (u) {
      const rol = (JSON.parse(u).rol || '').trim().toLowerCase().replace(/\s+/g, '');
      this.puedeGestionar = !['técnico', 'tecnico', 'jefedeoperaciones', 'clienteexterno'].includes(rol);
    }
    this.cargar();
  }

  cargar(): void {
    this.cargando = true;
    this.svc.listar().subscribe({
      next: (rows) => { this.formatos = rows; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('No se pudieron cargar los formatos', 'error'); },
    });
  }

  get tipos(): string[] {
    return [...new Set(this.formatos.map(f => f.tipo_formato || '').filter(Boolean))].sort();
  }

  get formatosFiltrados(): Formato[] {
    const q = this.busqueda.trim().toLowerCase();
    return this.formatos.filter(f => {
      if (this.filtroTipo && (f.tipo_formato || '') !== this.filtroTipo) return false;
      if (!q) return true;
      return f.nombre.toLowerCase().includes(q) || (f.tipo_formato || '').toLowerCase().includes(q);
    });
  }

  // ── Ver / descargar (pasa por /enlace → queda auditado) ────────────────────
  ver(f: Formato, version?: number): void {
    this.svc.enlace(f.id, version).subscribe({
      next: (r) => { if (r.url) window.open(r.url, '_blank'); },
      error: () => this.toast.mostrar('No se pudo abrir el documento', 'error'),
    });
  }

  // ── Historial ───────────────────────────────────────────────────────────────
  abrirHistorial(f: Formato): void {
    this.historialDe = f;
    this.showHistorial = true;
    this.cargandoVersiones = true;
    this.versiones = [];
    this.svc.versiones(f.id).subscribe({
      next: (v) => { this.versiones = v; this.cargandoVersiones = false; },
      error: () => { this.cargandoVersiones = false; this.toast.mostrar('No se pudo cargar el historial', 'error'); },
    });
  }

  cerrarHistorial(): void {
    this.showHistorial = false;
    this.historialDe = null;
  }

  verVersion(v: FormatoVersion): void {
    if (this.historialDe) this.ver(this.historialDe, v.numero_version);
  }

  // ── Nuevo / actualizar ──────────────────────────────────────────────────────
  abrirNuevo(): void {
    this.formatoEnEdicion = null;
    this.form = this.formVacio();
    this.archivoError = '';
    this.showForm = true;
  }

  abrirActualizar(f: Formato): void {
    this.formatoEnEdicion = f;
    this.form = { nombre: f.nombre, tipo_formato: f.tipo_formato || '', nota: '', archivoBase64: null, archivoNombre: null };
    this.archivoError = '';
    this.showForm = true;
  }

  cerrarForm(): void {
    if (this.guardando) return;
    this.showForm = false;
  }

  onArchivo(ev: Event): void {
    this.archivoError = '';
    const input = ev.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    if (file.type !== 'application/pdf' && !file.name.toLowerCase().endsWith('.pdf')) {
      this.archivoError = 'Solo se aceptan archivos PDF.';
      input.value = '';
      return;
    }
    if (file.size > 20 * 1024 * 1024) {
      this.archivoError = 'El archivo supera los 20 MB.';
      input.value = '';
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      this.form.archivoBase64 = reader.result as string;
      this.form.archivoNombre = file.name;
    };
    reader.readAsDataURL(file);
  }

  guardar(): void {
    const nombre = this.form.nombre.trim();
    if (!nombre) { this.toast.mostrar('El nombre es obligatorio', 'error'); return; }

    if (!this.formatoEnEdicion) {
      if (!this.form.archivoBase64) { this.archivoError = 'Selecciona el PDF del formato.'; return; }
      this.guardando = true;
      this.svc.crear({
        nombre,
        tipo_formato: this.form.tipo_formato.trim() || null,
        nota: this.form.nota.trim() || null,
        archivo_base64: this.form.archivoBase64,
        archivo_nombre: this.form.archivoNombre,
      }).subscribe({
        next: () => {
          this.guardando = false; this.showForm = false;
          this.toast.mostrar('Formato registrado (v1)', 'success');
          this.cargar();
        },
        error: (e) => {
          this.guardando = false;
          this.toast.mostrar(e?.error?.detail || 'No se pudo registrar el formato', 'error');
        },
      });
      return;
    }

    // Actualización: si hay PDF se publica nueva versión; el historial se conserva.
    const f = this.formatoEnEdicion;
    const cambioNombre = nombre !== f.nombre;
    const cambioTipo = (this.form.tipo_formato.trim() || null) !== (f.tipo_formato || null);
    if (!this.form.archivoBase64 && !cambioNombre && !cambioTipo) {
      this.toast.mostrar('No hay cambios que guardar', 'error');
      return;
    }
    this.guardando = true;
    this.svc.actualizar(f.id, {
      nombre: cambioNombre ? nombre : null,
      tipo_formato: this.form.tipo_formato.trim() || null,
      nota: this.form.nota.trim() || null,
      archivo_base64: this.form.archivoBase64,
      archivo_nombre: this.form.archivoNombre,
    }).subscribe({
      next: (res) => {
        this.guardando = false; this.showForm = false;
        this.toast.mostrar(
          this.form.archivoBase64 ? `Nueva versión publicada (v${res.version_actual})` : 'Formato actualizado',
          'success');
        this.cargar();
      },
      error: (e) => {
        this.guardando = false;
        this.toast.mostrar(e?.error?.detail || 'No se pudo actualizar el formato', 'error');
      },
    });
  }

  // ── Utilidades de presentación ──────────────────────────────────────────────
  fechaCorta(iso: string | null): string {
    if (!iso) return '—';
    const d = new Date(iso);
    return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  pesoLegible(bytes: number | null): string {
    if (!bytes) return '—';
    if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  private formVacio(): FormForm {
    return { nombre: '', tipo_formato: '', nota: '', archivoBase64: null, archivoNombre: null };
  }
}

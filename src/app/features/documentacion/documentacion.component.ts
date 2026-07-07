import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subject, debounceTime, distinctUntilChanged, takeUntil } from 'rxjs';
import { PlanosService, CarpetaOut, PlanoOut, PlanoDetalleOut } from '../../core/services/planos.service';
import { ToastService } from '../../core/services/toast.service';
import { AppModalComponent } from '../../shared/components/modal/app-modal.component';

interface BreadcrumbItem { id: string; nombre: string; }

@Component({
  selector: 'app-documentacion',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
  templateUrl: './documentacion.component.html',
  styleUrls: ['./documentacion.component.css']
})
export class DocumentacionComponent implements OnInit, OnDestroy {
  private destroy$ = new Subject<void>();
  private searchSubject = new Subject<string>();

  carpetas: CarpetaOut[] = [];
  planos: PlanoOut[] = [];
  breadcrumb: BreadcrumbItem[] = [];
  carpetaActualId = '';

  loading = false;
  uploading = false;
  vistaLista = false;

  searchTerm = '';

  // ── Modales ──
  showModalSubir = false;
  showModalCarpeta = false;
  showModalVersion = false;
  showModalDetalle = false;
  showModalRenombrar = false;

  // ── Forms ──
  uploadForm = { nombre: '', disciplina: '', descripcion: '', filename: '', archivo_base64: '' };
  carpetaForm = { nombre: '' };
  versionForm = { filename: '', archivo_base64: '', version: '' };
  renombrarForm = { carpetaId: '', nombre: '' };

  planoDetalle: PlanoDetalleOut | null = null;
  planoParaVersion: PlanoOut | null = null;
  planoParaEliminar: PlanoOut | null = null;
  carpetaParaEliminar: CarpetaOut | null = null;
  showConfirmEliminar = false;
  confirmandoCarpeta = false;

  readonly DISCIPLINAS = ['Eléctrico', 'Mecánico', 'Civil', 'Sanitario', 'Estructural', 'Arquitectónico', 'Instrumentación', 'Otro'];

  constructor(private planosSvc: PlanosService, private toastSvc: ToastService) {}

  ngOnInit(): void {
    this.searchSubject.pipe(
      debounceTime(400),
      distinctUntilChanged(),
      takeUntil(this.destroy$)
    ).subscribe(() => this.cargar());
    this.cargar();
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  get esGestor(): boolean {
    try {
      const u = JSON.parse(localStorage.getItem('ezyro_user') || '{}');
      const r = (u.rol || '').toLowerCase().trim();
      return ['superadmin', 'admin', 'administrador', 'jefe de operaciones',
              'jefe_operaciones', 'supervisor', 'supervisor de campo',
              'logística', 'logistica', 'logístico', 'logistico'].some(x => r.includes(x));
    } catch { return false; }
  }

  cargar(): void {
    this.loading = true;
    this.planosSvc.listarCarpetas(this.carpetaActualId).subscribe({
      next: (c) => { this.carpetas = c; this.cargarPlanos(); },
      error: () => { this.toastSvc.mostrar('Error al cargar carpetas', 'error'); this.loading = false; }
    });
  }

  private cargarPlanos(): void {
    this.planosSvc.listarPlanos(this.carpetaActualId, this.searchTerm).subscribe({
      next: (p) => { this.planos = p; this.loading = false; },
      error: () => { this.toastSvc.mostrar('Error al cargar planos', 'error'); this.loading = false; }
    });
  }

  onSearch(): void { this.searchSubject.next(this.searchTerm); }

  // El breadcrumb es la RUTA real de carpetas: cada entrada es una carpeta
  // {id, nombre}, desde el primer nivel hasta la carpeta actual (la última
  // entrada es donde estás parado). Antes guardaba el id del PADRE con
  // nombres vacíos, por eso los botones para retroceder salían sin texto y
  // no se podían clickear.
  abrirCarpeta(c: CarpetaOut): void {
    this.breadcrumb.push({ id: c.id, nombre: c.nombre });
    this.carpetaActualId = c.id;
    this.searchTerm = '';
    this.cargar();
  }

  // Salta a una carpeta ancestro tocándola en el breadcrumb: deja la ruta
  // recortada hasta esa carpeta (inclusive).
  navegar(idx: number): void {
    this.breadcrumb = this.breadcrumb.slice(0, idx + 1);
    this.carpetaActualId = this.breadcrumb[idx].id;
    this.searchTerm = '';
    this.cargar();
  }

  // Retrocede un nivel (carpeta padre); desde el primer nivel vuelve a la raíz.
  volver(): void {
    if (this.breadcrumb.length === 0) return;
    this.breadcrumb.pop();
    this.carpetaActualId = this.breadcrumb.length
      ? this.breadcrumb[this.breadcrumb.length - 1].id
      : '';
    this.searchTerm = '';
    this.cargar();
  }

  irRaiz(): void {
    this.breadcrumb = [];
    this.carpetaActualId = '';
    this.searchTerm = '';
    this.cargar();
  }

  // ── Nueva carpeta ──
  abrirModalCarpeta(): void { this.carpetaForm.nombre = ''; this.showModalCarpeta = true; }
  cerrarModalCarpeta(): void { this.showModalCarpeta = false; }

  crearCarpeta(): void {
    const nombre = this.carpetaForm.nombre.trim();
    if (!nombre) { this.toastSvc.mostrar('El nombre es obligatorio', 'error'); return; }
    this.planosSvc.crearCarpeta(nombre, this.carpetaActualId || undefined).subscribe({
      next: () => { this.cerrarModalCarpeta(); this.cargar(); this.toastSvc.mostrar('Carpeta creada', 'success'); },
      error: (e) => this.toastSvc.mostrar(e?.error?.detail || 'Error al crear carpeta', 'error')
    });
  }

  abrirModalRenombrar(c: CarpetaOut, ev: Event): void {
    ev.stopPropagation();
    this.renombrarForm = { carpetaId: c.id, nombre: c.nombre };
    this.showModalRenombrar = true;
  }
  cerrarModalRenombrar(): void { this.showModalRenombrar = false; }

  renombrarCarpeta(): void {
    const nombre = this.renombrarForm.nombre.trim();
    if (!nombre) { this.toastSvc.mostrar('El nombre es obligatorio', 'error'); return; }
    this.planosSvc.renombrarCarpeta(this.renombrarForm.carpetaId, nombre).subscribe({
      next: () => { this.cerrarModalRenombrar(); this.cargar(); this.toastSvc.mostrar('Carpeta renombrada', 'success'); },
      error: (e) => this.toastSvc.mostrar(e?.error?.detail || 'Error al renombrar', 'error')
    });
  }

  confirmarEliminarCarpeta(c: CarpetaOut, ev: Event): void {
    ev.stopPropagation();
    this.carpetaParaEliminar = c;
    this.confirmandoCarpeta = true;
    this.showConfirmEliminar = true;
  }

  // ── Subir plano ──
  abrirModalSubir(): void {
    this.uploadForm = { nombre: '', disciplina: '', descripcion: '', filename: '', archivo_base64: '' };
    this.showModalSubir = true;
  }
  cerrarModalSubir(): void { this.showModalSubir = false; }

  onFileSelected(ev: Event): void {
    const file = (ev.target as HTMLInputElement).files?.[0];
    if (file) this.procesarArchivoPdf(file);
  }

  // Valida y carga un PDF en el formulario de subida. Reusado por el input de
  // archivo y por el arrastre de archivos desde el PC (drag & drop).
  private procesarArchivoPdf(file: File): boolean {
    if (file.type !== 'application/pdf') { this.toastSvc.mostrar('Solo se permiten archivos PDF', 'error'); return false; }
    if (file.size > 30 * 1024 * 1024) { this.toastSvc.mostrar('El archivo supera los 30 MB', 'error'); return false; }
    this.uploadForm.filename = file.name;
    if (!this.uploadForm.nombre.trim()) {
      this.uploadForm.nombre = file.name.replace(/\.pdf$/i, '');
    }
    const reader = new FileReader();
    reader.onload = (e: any) => { this.uploadForm.archivo_base64 = e.target.result; };
    reader.readAsDataURL(file);
    return true;
  }

  subirPlano(): void {
    if (!this.uploadForm.nombre.trim()) { this.toastSvc.mostrar('El nombre es obligatorio', 'error'); return; }
    if (!this.uploadForm.archivo_base64) { this.toastSvc.mostrar('Selecciona un archivo PDF', 'error'); return; }
    this.uploading = true;
    this.planosSvc.crearPlano({
      nombre: this.uploadForm.nombre.trim(),
      archivo_base64: this.uploadForm.archivo_base64,
      filename: this.uploadForm.filename,
      disciplina: this.uploadForm.disciplina || undefined,
      descripcion: this.uploadForm.descripcion || undefined,
      carpeta_id: this.carpetaActualId || undefined,
    }).subscribe({
      next: () => { this.uploading = false; this.cerrarModalSubir(); this.cargar(); this.toastSvc.mostrar('Plano subido correctamente', 'success'); },
      error: (e) => { this.uploading = false; this.toastSvc.mostrar(e?.error?.detail || 'Error al subir plano', 'error'); }
    });
  }

  // ── Nueva versión ──
  abrirModalVersion(p: PlanoOut, ev: Event): void {
    ev.stopPropagation();
    this.planoParaVersion = p;
    this.versionForm = { filename: '', archivo_base64: '', version: '' };
    this.showModalVersion = true;
  }
  cerrarModalVersion(): void { this.showModalVersion = false; this.planoParaVersion = null; }

  onVersionFileSelected(ev: Event): void {
    const file = (ev.target as HTMLInputElement).files?.[0];
    if (!file) return;
    if (file.type !== 'application/pdf') { this.toastSvc.mostrar('Solo se permiten archivos PDF', 'error'); return; }
    if (file.size > 30 * 1024 * 1024) { this.toastSvc.mostrar('El archivo supera los 30 MB', 'error'); return; }
    this.versionForm.filename = file.name;
    const reader = new FileReader();
    reader.onload = (e: any) => { this.versionForm.archivo_base64 = e.target.result; };
    reader.readAsDataURL(file);
  }

  subirVersion(): void {
    if (!this.versionForm.archivo_base64) { this.toastSvc.mostrar('Selecciona un archivo PDF', 'error'); return; }
    this.uploading = true;
    this.planosSvc.subirVersion(this.planoParaVersion!.id, {
      archivo_base64: this.versionForm.archivo_base64,
      filename: this.versionForm.filename,
      version: this.versionForm.version || undefined,
    }).subscribe({
      next: () => { this.uploading = false; this.cerrarModalVersion(); this.cargar(); this.toastSvc.mostrar('Nueva versión subida', 'success'); },
      error: (e) => { this.uploading = false; this.toastSvc.mostrar(e?.error?.detail || 'Error al subir versión', 'error'); }
    });
  }

  // ── Detalle / versiones ──
  verDetalle(p: PlanoOut, ev: Event): void {
    ev.stopPropagation();
    this.planosSvc.detallePlano(p.id).subscribe({
      next: (d) => { this.planoDetalle = d; this.showModalDetalle = true; },
      error: () => this.toastSvc.mostrar('Error al cargar detalle', 'error')
    });
  }
  cerrarModalDetalle(): void { this.showModalDetalle = false; this.planoDetalle = null; }

  abrirPdf(url: string | null): void {
    if (url) window.open(url, '_blank');
  }

  // ── Drag & Drop tipo Drive ─────────────────────────────────────────────────
  planoArrastrado: PlanoOut | null = null;   // plano que se está arrastrando
  dropZoneActiva = false;                     // resalta la página al arrastrar un archivo del PC
  carpetaDropId: string | null = null;        // destino resaltado (id carpeta | '__back__' | '__root__')
  moviendoPlano = false;

  private tieneArchivosOS(ev: DragEvent): boolean {
    // El arrastre trae archivos del sistema (no un plano interno) si el
    // dataTransfer declara el tipo 'Files'.
    return Array.from(ev.dataTransfer?.types || []).includes('Files');
  }

  // Subir: arrastrar un PDF desde el PC sobre la página abre el modal ya cargado.
  onZonaDragOver(ev: DragEvent): void {
    if (this.planoArrastrado || !this.tieneArchivosOS(ev) || !this.esGestor) return;
    ev.preventDefault();
    this.dropZoneActiva = true;
  }
  onZonaDragLeave(ev: DragEvent): void {
    if (ev.currentTarget === ev.target) this.dropZoneActiva = false;
  }
  onZonaDrop(ev: DragEvent): void {
    this.dropZoneActiva = false;
    if (this.planoArrastrado || !this.tieneArchivosOS(ev)) return;
    ev.preventDefault();
    if (!this.esGestor) { this.toastSvc.mostrar('No tienes permiso para subir planos', 'error'); return; }
    const file = ev.dataTransfer?.files?.[0];
    if (!file) return;
    this.abrirModalSubir();            // resetea el formulario y abre el modal
    this.procesarArchivoPdf(file);     // deja el archivo ya cargado
  }

  // Mover: arrastrar un plano y soltarlo sobre una carpeta / atrás / Inicio.
  onPlanoDragStart(p: PlanoOut, ev: DragEvent): void {
    if (!this.esGestor) return;
    this.planoArrastrado = p;
    ev.dataTransfer?.setData('text/plain', p.id);
    if (ev.dataTransfer) ev.dataTransfer.effectAllowed = 'move';
  }
  onPlanoDragEnd(): void {
    this.planoArrastrado = null;
    this.carpetaDropId = null;
  }
  onDestinoDragOver(ev: DragEvent, key: string): void {
    if (!this.planoArrastrado) return;   // solo destinos válidos para mover un plano
    ev.preventDefault();
    ev.stopPropagation();
    if (ev.dataTransfer) ev.dataTransfer.dropEffect = 'move';
    this.carpetaDropId = key;
  }
  onDestinoDragLeave(key: string): void {
    if (this.carpetaDropId === key) this.carpetaDropId = null;
  }
  soltarEn(ev: DragEvent, carpetaId: string | null): void {
    if (!this.planoArrastrado) return;
    ev.preventDefault();
    ev.stopPropagation();
    const plano = this.planoArrastrado;
    this.carpetaDropId = null;
    this.planoArrastrado = null;
    if ((carpetaId || null) === (plano.carpeta_id || null)) return;   // ya está ahí
    this.moviendoPlano = true;
    this.planosSvc.moverPlano(plano.id, carpetaId).subscribe({
      next: () => { this.moviendoPlano = false; this.cargar(); this.toastSvc.mostrar('Plano movido', 'success'); },
      error: (e) => { this.moviendoPlano = false; this.toastSvc.mostrar(e?.error?.detail || 'Error al mover el plano', 'error'); },
    });
  }

  // Carpeta padre de la actual (destino del botón "atrás" al soltar un plano).
  get carpetaPadreId(): string | null {
    return this.breadcrumb.length <= 1 ? null : this.breadcrumb[this.breadcrumb.length - 2].id;
  }

  // ── Eliminar plano ──
  confirmarEliminarPlano(p: PlanoOut, ev: Event): void {
    ev.stopPropagation();
    this.planoParaEliminar = p;
    this.confirmandoCarpeta = false;
    this.showConfirmEliminar = true;
  }

  cerrarConfirm(): void {
    this.showConfirmEliminar = false;
    this.planoParaEliminar = null;
    this.carpetaParaEliminar = null;
  }

  ejecutarEliminar(): void {
    if (this.confirmandoCarpeta && this.carpetaParaEliminar) {
      this.planosSvc.eliminarCarpeta(this.carpetaParaEliminar.id).subscribe({
        next: () => { this.cerrarConfirm(); this.cargar(); this.toastSvc.mostrar('Carpeta eliminada', 'success'); },
        error: (e) => { this.cerrarConfirm(); this.toastSvc.mostrar(e?.error?.detail || 'Error al eliminar carpeta', 'error'); }
      });
    } else if (this.planoParaEliminar) {
      this.planosSvc.eliminarPlano(this.planoParaEliminar.id).subscribe({
        next: () => { this.cerrarConfirm(); this.cargar(); this.toastSvc.mostrar('Plano eliminado', 'success'); },
        error: (e) => { this.cerrarConfirm(); this.toastSvc.mostrar(e?.error?.detail || 'Error al eliminar plano', 'error'); }
      });
    }
  }

  // ── Helpers ──
  formatBytes(b: number | null): string { return this.planosSvc.formatBytes(b); }

  formatFecha(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  disciplinaColor(d: string | null): string {
    const map: Record<string, string> = {
      'Eléctrico': 'disc-elec', 'Mecánico': 'disc-mec', 'Civil': 'disc-civil',
      'Sanitario': 'disc-san', 'Estructural': 'disc-est', 'Arquitectónico': 'disc-arq',
      'Instrumentación': 'disc-inst',
    };
    return d ? (map[d] || 'disc-otro') : 'disc-otro';
  }
}

import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { RrhhService, DocumentoDto, EmpleadoInfoDto } from '../../../core/services/rrhh.service';
import { AuthService } from '../../../core/services/auth.service';

const TIPOS_DOCUMENTO = [
  'Contrato',
  'Memorándum',
  'Certificado',
  'Constancia',
  'Acta de compromiso',
  'Política interna',
  'Otro',
];

@Component({
  selector: 'app-legajo-detalle',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './legajo-detalle.component.html',
  styleUrls: ['./legajo-detalle.component.css']
})
export class LegajoDetalleComponent implements OnInit {
  empleadoId = '';
  empleado: EmpleadoInfoDto | null = null;
  documentos: DocumentoDto[] = [];
  cargando = true;
  error = '';

  tiposDocumento = TIPOS_DOCUMENTO;

  // Upload modal
  showUploadModal = false;
  uploadCargando = false;
  uploadError = '';
  uploadForm = {
    tipo: '',
    nombre: '',
    fechaEmision: '',
    requiereFirma: false,
  };
  archivoSeleccionado: File | null = null;

  // Firma modal
  showFirmarModal = false;
  firmarCargando = false;
  firmarError = '';
  docParaFirmar: DocumentoDto | null = null;
  firmaUrl: string | null = null;

  // Confirm delete
  showConfirmEliminar = false;
  docParaEliminar: DocumentoDto | null = null;
  eliminandoCargando = false;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private rrhhService: RrhhService,
    private authService: AuthService,
  ) {}

  ngOnInit(): void {
    this.empleadoId = this.route.snapshot.paramMap.get('id') ?? '';
    this.cargarDetalle();
  }

  get isAdmin(): boolean {
    const u = this.authService.getUsuario();
    const rol = (u?.rol || '').trim();
    return rol === 'Administrador' || rol === 'administrador';
  }

  get esSelf(): boolean {
    if (!this.empleado) return false;
    const u = this.authService.getUsuario();
    return !!u && u.id === this.empleado.usuarioId;
  }

  private cargarDetalle(): void {
    this.cargando = true;
    this.rrhhService.getEmpleadoDetalle(this.empleadoId).subscribe({
      next: (res) => {
        this.empleado = res.empleado;
        this.documentos = res.documentos;
        this.cargando = false;
      },
      error: () => {
        this.error = 'No se pudo cargar el expediente del empleado.';
        this.cargando = false;
      }
    });
  }

  volver(): void {
    this.router.navigate(['/rrhh/legajo']);
  }

  // ── Upload modal ──────────────────────────────────────────────────────────

  abrirUploadModal(): void {
    this.uploadForm = { tipo: '', nombre: '', fechaEmision: '', requiereFirma: false };
    this.archivoSeleccionado = null;
    this.uploadError = '';
    this.showUploadModal = true;
  }

  cerrarUploadModal(): void {
    this.showUploadModal = false;
  }

  onArchivoSeleccionado(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0] ?? null;
    if (file && file.type !== 'application/pdf') {
      this.uploadError = 'Solo se permiten archivos PDF.';
      this.archivoSeleccionado = null;
      return;
    }
    if (file && file.size > 20 * 1024 * 1024) {
      this.uploadError = 'El archivo supera los 20 MB.';
      this.archivoSeleccionado = null;
      return;
    }
    this.uploadError = '';
    this.archivoSeleccionado = file;
  }

  subirDocumento(): void {
    if (!this.uploadForm.tipo || !this.uploadForm.nombre || !this.uploadForm.fechaEmision) {
      this.uploadError = 'Completa todos los campos obligatorios.';
      return;
    }
    if (!this.archivoSeleccionado) {
      this.uploadError = 'Selecciona un archivo PDF.';
      return;
    }
    this.uploadCargando = true;
    this.uploadError = '';

    const form = new FormData();
    form.append('tipo', this.uploadForm.tipo);
    form.append('nombre', this.uploadForm.nombre);
    form.append('fecha_emision', this.uploadForm.fechaEmision);
    form.append('requiere_firma', String(this.uploadForm.requiereFirma));
    form.append('archivo', this.archivoSeleccionado);

    this.rrhhService.subirDocumento(this.empleadoId, form).subscribe({
      next: () => {
        this.uploadCargando = false;
        this.showUploadModal = false;
        this.cargarDetalle();
      },
      error: (err) => {
        this.uploadCargando = false;
        this.uploadError = err?.error?.detail ?? 'Error al subir el documento.';
      }
    });
  }

  // ── Firma modal ───────────────────────────────────────────────────────────

  abrirFirmarModal(doc: DocumentoDto): void {
    this.docParaFirmar = doc;
    this.firmarError = '';
    this.firmaUrl = null;
    this.showFirmarModal = true;

    this.rrhhService.getMiFirma().subscribe({
      next: (res) => {
        this.firmaUrl = res.firma?.url_cloudinary ?? null;
      },
      error: () => {
        this.firmarError = 'No se pudo cargar tu firma digital.';
      }
    });
  }

  cerrarFirmarModal(): void {
    this.showFirmarModal = false;
    this.docParaFirmar = null;
  }

  confirmarFirma(): void {
    if (!this.docParaFirmar) return;
    if (!this.firmaUrl) {
      this.firmarError = 'No tienes una firma digital registrada.';
      return;
    }
    this.firmarCargando = true;
    this.firmarError = '';

    this.rrhhService.firmarDocumento(this.docParaFirmar.id).subscribe({
      next: () => {
        this.firmarCargando = false;
        this.showFirmarModal = false;
        this.cargarDetalle();
      },
      error: (err) => {
        this.firmarCargando = false;
        this.firmarError = err?.error?.detail ?? 'Error al firmar el documento.';
      }
    });
  }

  // ── Eliminar ──────────────────────────────────────────────────────────────

  pedirConfirmEliminar(doc: DocumentoDto): void {
    this.docParaEliminar = doc;
    this.showConfirmEliminar = true;
  }

  cancelarEliminar(): void {
    this.showConfirmEliminar = false;
    this.docParaEliminar = null;
  }

  confirmarEliminar(): void {
    if (!this.docParaEliminar) return;
    this.eliminandoCargando = true;

    this.rrhhService.eliminarDocumento(this.docParaEliminar.id).subscribe({
      next: () => {
        this.eliminandoCargando = false;
        this.showConfirmEliminar = false;
        this.cargarDetalle();
      },
      error: () => {
        this.eliminandoCargando = false;
        this.showConfirmEliminar = false;
      }
    });
  }

  // ── Utilidades ────────────────────────────────────────────────────────────

  get firmadosCount(): number {
    return this.documentos.filter(d => d.firmado).length;
  }

  formatearFecha(iso: string | null): string {
    if (!iso) return '—';
    try {
      return new Date(iso).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
    } catch {
      return iso;
    }
  }
}

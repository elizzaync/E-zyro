import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { RrhhService, DocumentoDto, EmpleadoInfoDto, LegajoStatsDto } from '../../../../../core/services/rrhh.service';
import { AuthService } from '../../../../../core/services/auth.service';
import { AppModalComponent } from '../../../../../shared/components/modal/app-modal.component';

const TIPOS_DOCUMENTO = [
  'Boleta Mensual',
  'Contrato',
  'Memorándum',
  'Certificado',
  'Constancia',
  'Acta de compromiso',
  'Política interna',
  'Otro',
];

const MESES_ES = [
  { value: 1,  label: 'Enero' },   { value: 2,  label: 'Febrero' },
  { value: 3,  label: 'Marzo' },   { value: 4,  label: 'Abril' },
  { value: 5,  label: 'Mayo' },    { value: 6,  label: 'Junio' },
  { value: 7,  label: 'Julio' },   { value: 8,  label: 'Agosto' },
  { value: 9,  label: 'Septiembre' }, { value: 10, label: 'Octubre' },
  { value: 11, label: 'Noviembre' }, { value: 12, label: 'Diciembre' },
];

type CatFiltro = 'todos' | 'contratos' | 'certificaciones' | 'otros';

@Component({
  selector: 'app-legajo-detalle',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
  templateUrl: './legajo-detalle.component.html',
  styleUrls: ['./legajo-detalle.component.css']
})
export class LegajoDetalleComponent implements OnInit {

  empleadoId = '';
  empleado: EmpleadoInfoDto | null = null;
  documentos: DocumentoDto[]       = [];
  stats: LegajoStatsDto            = { total: 0, contratos: 0, firmados: 0, pendientes_firma: 0 };
  cargando = true;
  error    = '';

  tiposDocumento = TIPOS_DOCUMENTO;
  mesesEs        = MESES_ES;

  // ── Filtro de categoría ────────────────────────────────────────────────
  categoriaFiltro: CatFiltro = 'todos';

  // ── Paginación ────────────────────────────────────────────────────────
  currentPage  = 1;
  itemsPerPage = 10;

  get documentosFiltrados(): DocumentoDto[] {
    switch (this.categoriaFiltro) {
      case 'contratos':
        return this.documentos.filter(d => d.tipo.toLowerCase() === 'contrato');
      case 'certificaciones':
        return this.documentos.filter(d =>
          ['certificado', 'constancia'].includes(d.tipo.toLowerCase()));
      case 'otros':
        return this.documentos.filter(d =>
          !['contrato', 'certificado', 'constancia'].includes(d.tipo.toLowerCase()));
      default:
        return this.documentos;
    }
  }

  get paginatedDocumentos(): DocumentoDto[] {
    const start = (this.currentPage - 1) * this.itemsPerPage;
    return this.documentosFiltrados.slice(start, start + this.itemsPerPage);
  }

  get totalPaginas(): number {
    return Math.max(1, Math.ceil(this.documentosFiltrados.length / this.itemsPerPage));
  }

  get rangoMostrando(): { desde: number; hasta: number; total: number } {
    const total = this.documentosFiltrados.length;
    if (total === 0) return { desde: 0, hasta: 0, total: 0 };
    const desde = (this.currentPage - 1) * this.itemsPerPage + 1;
    const hasta = Math.min(this.currentPage * this.itemsPerPage, total);
    return { desde, hasta, total };
  }

  get paginasBotones(): number[] {
    const total = this.totalPaginas;
    const cur   = this.currentPage;
    const pages: number[] = [];
    for (let i = Math.max(1, cur - 2); i <= Math.min(total, cur + 2); i++) pages.push(i);
    return pages;
  }

  setCategoriaFiltro(cat: CatFiltro): void {
    this.categoriaFiltro = cat;
    this.currentPage = 1;
  }

  paginaSiguiente(): void { if (this.currentPage < this.totalPaginas) this.currentPage++; }
  paginaAnterior(): void  { if (this.currentPage > 1) this.currentPage--; }
  irPagina(p: number): void {
    if (p >= 1 && p <= this.totalPaginas) this.currentPage = p;
  }

  // ── Upload modal ──────────────────────────────────────────────────────
  showUploadModal = false;
  uploadCargando  = false;
  uploadError     = '';
  uploadForm = {
    tipo:         '',
    nombre:       '',
    fechaEmision: '',
    requiereFirma: false,
    mes:          0,
    anio:         new Date().getFullYear(),
  };
  archivoSeleccionado: File | null = null;

  get esBoletaSeleccionada(): boolean {
    return this.uploadForm.tipo === 'Boleta Mensual';
  }

  get esContratoSeleccionado(): boolean {
    return this.uploadForm.tipo === 'Contrato';
  }

  get aniosDisponibles(): number[] {
    const anio = new Date().getFullYear();
    return Array.from({ length: 6 }, (_, i) => anio - 4 + i).reverse();
  }

  get nombreBoleta(): string {
    if (!this.uploadForm.mes || !this.uploadForm.anio) return '';
    const mes = MESES_ES.find(m => m.value === this.uploadForm.mes);
    return mes ? `Boleta de Pago - ${mes.label} ${this.uploadForm.anio}` : '';
  }

  // ── Firma modal ───────────────────────────────────────────────────────
  showFirmarModal = false;
  firmarCargando  = false;
  firmarError     = '';
  docParaFirmar: DocumentoDto | null = null;
  firmaUrl: string | null = null;

  // ── Confirm delete ────────────────────────────────────────────────────
  showConfirmEliminar = false;
  docParaEliminar: DocumentoDto | null = null;
  eliminandoCargando  = false;

  constructor(
    private route:        ActivatedRoute,
    private router:       Router,
    private rrhhService:  RrhhService,
    private authService:  AuthService,
  ) {}

  ngOnInit(): void {
    this.empleadoId = this.route.snapshot.paramMap.get('id') ?? '';
    this.cargarDetalle();
  }

  get isAdmin(): boolean {
    const rol = (this.authService.getUsuario()?.rol || '').trim();
    return rol === 'Administrador' || rol === 'administrador';
  }

  get esSelf(): boolean {
    if (!this.empleado) return false;
    const u = this.authService.getUsuario();
    return !!u && u.id === this.empleado.usuarioId;
  }

  get firmadosCount(): number  { return this.stats.firmados; }
  get pendientesCount(): number { return this.stats.pendientes_firma; }

  // ── Carga ─────────────────────────────────────────────────────────────

  private cargarDetalle(): void {
    this.cargando = true;
    this.rrhhService.getEmpleadoDetalle(this.empleadoId).subscribe({
      next: (res) => {
        this.empleado   = res.empleado;
        this.documentos = res.documentos;
        this.stats      = res.stats;
        this.cargando   = false;
      },
      error: () => {
        this.error   = 'No se pudo cargar el expediente del empleado.';
        this.cargando = false;
      },
    });
  }

  private recargarDocumentos(): void {
    this.rrhhService.getDocumentosEmpleado(this.empleadoId).subscribe({
      next: (res) => {
        this.documentos  = res.documentos;
        this.stats = {
          total: res.total,
          contratos: res.documentos.filter(d => d.tipo.toLowerCase() === 'contrato').length,
          firmados: res.documentos.filter(d => d.firmado).length,
          pendientes_firma: res.documentos.filter(d => d.firma_estado === 'pendiente').length,
        };
        this.currentPage = 1;
      },
      error: () => {},
    });
  }

  volver(): void {
    this.router.navigate(['/rrhh/legajo']);
  }

  // ── Upload ────────────────────────────────────────────────────────────

  abrirUploadModal(): void {
    this.uploadForm = {
      tipo: '', nombre: '', fechaEmision: '',
      requiereFirma: false, mes: 0, anio: new Date().getFullYear(),
    };
    this.archivoSeleccionado = null;
    this.uploadError = '';
    this.showUploadModal = true;
  }

  onTipoChange(): void {
    // Contratos siempre requieren firma
    if (this.esContratoSeleccionado) {
      this.uploadForm.requiereFirma = true;
    }
  }

  cerrarUploadModal(): void { this.showUploadModal = false; }

  onArchivoSeleccionado(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file  = input.files?.[0] ?? null;
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
    if (!this.uploadForm.tipo) {
      this.uploadError = 'Selecciona el tipo de documento.';
      return;
    }

    let nombreFinal  = this.uploadForm.nombre;
    let fechaFinal   = this.uploadForm.fechaEmision;

    if (this.esBoletaSeleccionada) {
      if (!this.uploadForm.mes || !this.uploadForm.anio) {
        this.uploadError = 'Selecciona el mes y el año de la boleta.';
        return;
      }
      const mes = MESES_ES.find(m => m.value === this.uploadForm.mes)!;
      nombreFinal = `Boleta de Pago - ${mes.label} ${this.uploadForm.anio}`;
      fechaFinal  = `${this.uploadForm.anio}-${String(this.uploadForm.mes).padStart(2, '0')}-01`;
    } else {
      if (!nombreFinal.trim()) {
        this.uploadError = 'Completa el nombre del documento.';
        return;
      }
      if (!fechaFinal) {
        this.uploadError = 'Selecciona la fecha de emisión.';
        return;
      }
    }

    if (!this.archivoSeleccionado) {
      this.uploadError = 'Selecciona un archivo PDF.';
      return;
    }

    this.uploadCargando = true;
    this.uploadError    = '';

    const form = new FormData();
    form.append('tipo',          this.uploadForm.tipo);
    form.append('nombre',        nombreFinal);
    form.append('fecha_emision', fechaFinal);
    form.append('requiere_firma', String(this.uploadForm.requiereFirma || this.esContratoSeleccionado));
    form.append('archivo',       this.archivoSeleccionado);
    if (this.esBoletaSeleccionada) {
      form.append('mes',  String(this.uploadForm.mes));
      form.append('anio', String(this.uploadForm.anio));
    }

    this.rrhhService.subirDocumento(this.empleadoId, form).subscribe({
      next: () => {
        this.uploadCargando  = false;
        this.showUploadModal = false;
        this.recargarDocumentos();
      },
      error: (err) => {
        this.uploadCargando = false;
        this.uploadError    = err?.error?.detail ?? 'Error al subir el documento.';
      },
    });
  }

  // ── Firma ─────────────────────────────────────────────────────────────

  abrirFirmarModal(doc: DocumentoDto): void {
    this.docParaFirmar = doc;
    this.firmarError   = '';
    this.firmaUrl      = null;
    this.showFirmarModal = true;
    this.rrhhService.getMiFirma().subscribe({
      next:  (res) => { this.firmaUrl = res.firma?.url_cloudinary ?? null; },
      error: ()    => { this.firmarError = 'No se pudo cargar tu firma digital.'; },
    });
  }

  cerrarFirmarModal(): void {
    this.showFirmarModal = false;
    this.docParaFirmar   = null;
  }

  confirmarFirma(): void {
    if (!this.docParaFirmar) return;
    if (!this.firmaUrl) { this.firmarError = 'No tienes una firma digital registrada.'; return; }
    this.firmarCargando = true;
    this.firmarError    = '';
    this.rrhhService.firmarDocumento(this.docParaFirmar.id).subscribe({
      next: () => {
        this.firmarCargando  = false;
        this.showFirmarModal = false;
        this.recargarDocumentos();
      },
      error: (err) => {
        this.firmarCargando = false;
        this.firmarError    = err?.error?.detail ?? 'Error al firmar el documento.';
      },
    });
  }

  // ── Eliminar ──────────────────────────────────────────────────────────

  pedirConfirmEliminar(doc: DocumentoDto): void {
    this.docParaEliminar     = doc;
    this.showConfirmEliminar = true;
  }

  cancelarEliminar(): void {
    this.showConfirmEliminar = false;
    this.docParaEliminar     = null;
  }

  confirmarEliminar(): void {
    if (!this.docParaEliminar) return;
    this.eliminandoCargando = true;
    this.rrhhService.eliminarDocumento(this.docParaEliminar.id).subscribe({
      next: () => {
        this.eliminandoCargando  = false;
        this.showConfirmEliminar = false;
        this.recargarDocumentos();
      },
      error: () => {
        this.eliminandoCargando  = false;
        this.showConfirmEliminar = false;
      },
    });
  }

  // ── Utilidades ────────────────────────────────────────────────────────

  /** Convierte URLs raw de Cloudinary para que el navegador las abra inline en lugar de descargarlas. */
  pdfUrl(url: string): string {
    if (!url) return url;
    if (url.includes('/raw/upload/') && !url.includes('fl_attachment')) {
      return url.replace('/raw/upload/', '/raw/upload/fl_attachment:false/');
    }
    return url;
  }

  tipoClase(tipo: string): string {
    const map: Record<string, string> = {
      'boleta mensual':    'tipo-boleta',
      'contrato':          'tipo-contrato',
      'memorándum':        'tipo-memo',
      'memorandum':        'tipo-memo',
      'certificado':       'tipo-cert',
      'constancia':        'tipo-const',
      'acta de compromiso':'tipo-acta',
      'política interna':  'tipo-politica',
    };
    return map[tipo.toLowerCase()] ?? 'tipo-otro';
  }

  formatearFecha(iso: string | null): string {
    if (!iso) return '—';
    try {
      return new Date(iso + (iso.length === 10 ? 'T00:00:00' : '')).toLocaleDateString(
        'es-PE', { day: '2-digit', month: 'short', year: 'numeric' }
      );
    } catch { return iso; }
  }
}

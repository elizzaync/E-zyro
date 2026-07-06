import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  SoporteService,
  DocumentoArchivoDto,
  FiltrosDocumentos,
} from '../../../../core/services/soporte.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

@Component({
  selector: 'app-documentos',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './documentos.component.html',
  styleUrls: ['./documentos.component.css'],
})
export class DocumentosComponent implements OnInit, OnDestroy {
  private svc   = inject(SoporteService);
  private toast = inject(ToastService);

  documentos: DocumentoArchivoDto[] = [];
  cargando = true;
  total = 0;
  page = 1;
  pageSize = 25;

  fQ = '';
  fTipo = 'todos';
  fModulo = '';

  private qTimer: ReturnType<typeof setTimeout> | null = null;

  readonly tipos = ['pdf', 'excel', 'csv', 'export', 'otro'];

  ngOnInit(): void { this.cargar(); }

  ngOnDestroy(): void {
    if (this.qTimer) { clearTimeout(this.qTimer); this.qTimer = null; }
  }

  private filtrosActuales(): FiltrosDocumentos {
    return {
      q: this.fQ.trim() || undefined,
      tipo: this.fTipo,
      modulo: this.fModulo.trim() || undefined,
      page: this.page,
      page_size: this.pageSize,
    };
  }

  cargar(): void {
    this.cargando = true;
    this.svc.getDocumentos(this.filtrosActuales()).subscribe({
      next: r => { this.documentos = r.items; this.total = r.total; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar documentos.', 'error'); },
    });
  }

  filtrar(): void { this.page = 1; this.cargar(); }

  // Debounce simple para el buscador
  onBuscarChange(): void {
    if (this.qTimer) clearTimeout(this.qTimer);
    this.qTimer = setTimeout(() => { this.page = 1; this.cargar(); }, 350);
  }

  get totalPaginas(): number { return Math.max(1, Math.ceil(this.total / this.pageSize)); }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) { this.page = p; this.cargar(); } }

  abrir(d: DocumentoArchivoDto): void {
    if (!d.cloudinaryUrl) return;
    window.open(d.cloudinaryUrl, '_blank');
  }

  copiarHash(d: DocumentoArchivoDto): void {
    if (!d.hashSha256) return;
    navigator.clipboard.writeText(d.hashSha256).then(
      () => this.toast.mostrar('Hash SHA-256 copiado.', 'success'),
      () => this.toast.mostrar('No se pudo copiar.', 'error'));
  }

  // ── Helpers presentación ──
  tipoLabel(t: string): string {
    const m: Record<string, string> = {
      pdf: 'PDF', excel: 'Excel', csv: 'CSV', export: 'Export', otro: 'Otro',
    };
    return m[t] ?? t;
  }

  fmtBytes(n: number | null): string {
    if (!n) return '—';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0; let v = n;
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return `${v.toFixed(i === 0 ? 0 : 1)} ${u[i]}`;
  }

  fmtFecha(iso: string | null): string {
    if (!iso) return '—';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '—';
    return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short' }) + ' ' +
           d.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' });
  }
}

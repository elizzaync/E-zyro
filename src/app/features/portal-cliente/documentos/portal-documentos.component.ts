import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { EmptyStateComponent } from '../shared/empty-state.component';

@Component({
  selector: 'app-portal-documentos',
  standalone: true,
  imports: [CommonModule, FormsModule, EmptyStateComponent],
  templateUrl: './portal-documentos.component.html',
  styleUrls: ['./portal-documentos.component.css'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PortalDocumentosComponent implements OnInit {
  private svc = inject(PortalClienteService);
  private cdr = inject(ChangeDetectorRef);

  cargando     = true;
  error        = '';
  documentos: any[] = [];

  busqueda   = '';
  filtroTipo = '';

  // Precalculados (OnPush)
  filtrados: any[] = [];
  tipos: string[] = [];

  ngOnInit(): void {
    this.svc.getDocumentos().subscribe({
      next: (data) => {
        this.documentos = data;
        this.cargando = false;
        this.tipos = [...new Set(this.documentos.map(d => d.tipo).filter(Boolean))] as string[];
        this.aplicarFiltros();
        this.cdr.markForCheck();
      },
      error: () => { this.error = 'No se pudo cargar la galería documental.'; this.cargando = false; this.cdr.markForCheck(); },
    });
  }

  onFiltroChange(): void { this.aplicarFiltros(); this.cdr.markForCheck(); }
  setTipo(t: string): void { this.filtroTipo = t; this.aplicarFiltros(); this.cdr.markForCheck(); }

  private aplicarFiltros(): void {
    const q = this.busqueda.trim().toLowerCase();
    this.filtrados = this.documentos.filter(d =>
      (!this.filtroTipo || d.tipo === this.filtroTipo) &&
      (!q ||
        (d.titulo ?? '').toLowerCase().includes(q) ||
        (d.proyecto ?? '').toLowerCase().includes(q) ||
        (d.servicio ?? '').toLowerCase().includes(q))
    );
  }

  tipoLabel(t: string): string {
    const m: Record<string, string> = {
      carta_garantia:   'Carta de Garantía',
      informe_general:  'Informe General',
      informe_pozos:    'Informe Pozos',
      protocolo_prueba: 'Protocolo de Prueba',
      certificado:      'Certificado',
    };
    return m[t] ?? t;
  }

  /** Clase de acento por familia de documento (borde superior + ícono). */
  tipoClase(t: string): string {
    if (t?.includes('garantia')) return 'tp-garantia';
    if (t?.includes('informe'))  return 'tp-informe';
    return 'tp-otro';
  }

  descargar(url: string, titulo: string): void {
    const a = document.createElement('a');
    a.href     = url;
    a.download = titulo + '.pdf';
    a.target   = '_blank';
    a.rel      = 'noopener';
    a.click();
  }
}

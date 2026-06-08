import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';

@Component({
  selector: 'app-portal-documentos',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './portal-documentos.component.html',
  styleUrls: ['./portal-documentos.component.css'],
})
export class PortalDocumentosComponent implements OnInit {
  private svc = inject(PortalClienteService);

  cargando     = true;
  error        = '';
  documentos: any[] = [];

  // Filtro activo
  filtroTipo = '';

  ngOnInit(): void {
    this.svc.getDocumentos().subscribe({
      next: (data) => { this.documentos = data; this.cargando = false; },
      error: () => { this.error = 'No se pudo cargar la galería documental.'; this.cargando = false; },
    });
  }

  get tipos(): string[] {
    return [...new Set(this.documentos.map(d => d.tipo).filter(Boolean))];
  }

  get documentosFiltrados(): any[] {
    return this.filtroTipo ? this.documentos.filter(d => d.tipo === this.filtroTipo) : this.documentos;
  }

  tipoLabel(t: string): string {
    const m: Record<string, string> = {
      carta_garantia:     'Carta de Garantía',
      informe_general:    'Informe General',
      informe_pozos:      'Informe Pozos',
      protocolo_prueba:   'Protocolo de Prueba',
      certificado:        'Certificado',
    };
    return m[t] ?? t;
  }

  tipoIcon(t: string): string {
    if (t?.includes('garantia')) return 'icon-garantia';
    if (t?.includes('informe'))  return 'icon-informe';
    return 'icon-doc';
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

import { Component, Input, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DomSanitizer, SafeHtml } from '@angular/platform-browser';

export interface Solicitud {
  id:           string;
  tipo:         string;
  fechaEmision: string;
  estadoActual: 'enviado' | 'visto' | 'proceso' | 'aceptado' | 'rechazado';
  urlPdf?:      string;
}

const A = `xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"`;

const TIPO_SVGS: Record<string, string> = {
  personal: `<svg ${A}><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`,
  comision: `<svg ${A}><rect x="2" y="7" width="20" height="14" rx="2" ry="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/></svg>`,
  essalud:  `<svg ${A}><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>`,
  capacita: `<svg ${A}><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 1-4 4v14a3 3 0 0 0 3-3h7z"/></svg>`,
  extra:    `<svg ${A}><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>`,
  recupera: `<svg ${A}><path d="M23 4v6h-6"/><path d="M1 20v-6h6"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M20.49 15a9 9 0 0 1-14.85 3.36L1 14"/></svg>`,
  vacaci:   `<svg ${A}><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>`,
  libre:    `<svg ${A}><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>`,
  transfer: `<svg ${A}><polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/></svg>`,
  default:  `<svg ${A}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>`,
};

@Component({
  selector: 'app-permiso-tramite-card',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './permiso-tramite-card.component.html',
  styleUrls: ['./permiso-tramite-card.component.css']
})
export class PermisoTramiteCardComponent {
  @Input() tramite!: Solicitud;

  private sanitizer = inject(DomSanitizer);

  verPdf(): void {
    if (this.tramite.urlPdf) window.open(this.tramite.urlPdf, '_blank');
  }

  getTipoKey(): string {
    const t = this.tramite.tipo.toLowerCase();
    if (t.includes('personal')  || t === 'permiso_personal')                    return 'personal';
    if (t.includes('comisi'))                                                    return 'comision';
    if (t.includes('essalud')   || t.includes('clínica') || t.includes('cita')) return 'essalud';
    if (t.includes('capacita'))                                                  return 'capacita';
    if (t.includes('extra'))                                                     return 'extra';
    if (t.includes('recupera'))                                                  return 'recupera';
    if (t.includes('vacaci'))                                                    return 'vacaci';
    if (t.includes('libre')     || t === 'dias_libres')                          return 'libre';
    if (t.includes('transfer'))                                                  return 'transfer';
    return 'default';
  }

  getTipoIcono(): SafeHtml {
    return this.sanitizer.bypassSecurityTrustHtml(
      TIPO_SVGS[this.getTipoKey()] ?? TIPO_SVGS['default']
    );
  }

  getEstadoLabel(): string {
    const map: Record<string, string> = {
      enviado:   'Pendiente',
      visto:     'En revisión',
      proceso:   'En proceso',
      aceptado:  'Aprobado',
      rechazado: 'Rechazado',
    };
    return map[this.tramite.estadoActual] ?? 'Desconocido';
  }
}

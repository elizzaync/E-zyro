/**
 * PermisoPdfPreviewComponent
 *
 * Carga la plantilla PDF desde /assets, estampa los datos del formulario
 * en tiempo real usando pdf-lib y muestra el resultado en un <iframe>.
 *
 * Flujo de datos:
 *   previewData (Input) → debounce 400ms → PDFDocument.load(template)
 *   → page.drawText / drawImage → pdfDoc.save() → Blob → ObjectURL → iframe
 *
 * COORDENADAS (x, y en puntos PDF, origen inferior-izquierdo, A4 = 595×842 pt):
 *   Todos los valores calibrables viven en COORDS y TIPO_COORDS dentro de estampar().
 *   ▲ Aumentar Y → sube el texto.   ▶ Aumentar X → mueve a la derecha.
 */
import {
  Component, Input, OnChanges, OnDestroy,
  SimpleChanges, inject
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';
import { Subject } from 'rxjs';
import { debounceTime, takeUntil } from 'rxjs/operators';
import { PreviewData } from '../permiso-form/permiso-form.component';

export interface EmpleadoInfo {
  nombre: string;
  cargo:  string;
  area:   string;
}

const TEMPLATE_PATH = '/assets/plantilla_permiso.pdf';

@Component({
  selector: 'app-permiso-pdf-preview',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="preview-shell">
      <p class="preview-label">Vista previa en tiempo real</p>

      @if (pdfUrl) {
        <iframe
          [src]="pdfUrl"
          width="100%"
          height="620"
          type="application/pdf"
          class="preview-iframe">
        </iframe>
      } @else {
        <div class="preview-placeholder">
          <div class="mini-spinner"></div>
          <span>Cargando plantilla…</span>
        </div>
      }
    </div>
  `,
  styles: [`
    .preview-shell {
      display: flex;
      flex-direction: column;
      gap: 10px;
      height: 100%;
    }
    .preview-label {
      margin: 0;
      font-size: 12px;
      font-weight: 600;
      color: #64748b;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .preview-iframe {
      border: 1px solid #e2e8f0;
      border-radius: 10px;
      min-height: 620px;
      background: #f1f5f9;
    }
    .preview-placeholder {
      height: 620px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 14px;
      border: 1px dashed #cbd5e1;
      border-radius: 10px;
      color: #94a3b8;
      font-size: 14px;
      font-weight: 500;
    }
    .mini-spinner {
      width: 32px; height: 32px;
      border: 3px solid #e2e8f0;
      border-top-color: #91d337;
      border-radius: 50%;
      animation: giro 0.8s linear infinite;
    }
    @keyframes giro { to { transform: rotate(360deg); } }
  `],
})
export class PermisoPdfPreviewComponent implements OnChanges, OnDestroy {
  @Input() previewData:  PreviewData | null = null;
  @Input() empleadoInfo: EmpleadoInfo       = { nombre: '', cargo: '', area: '' };

  private sanitizer = inject(DomSanitizer);
  private destroy$  = new Subject<void>();
  private stamp$    = new Subject<void>();

  pdfUrl: SafeResourceUrl | null = null;

  private templateCache:  ArrayBuffer | null = null;
  private currentBlobUrl: string | null      = null;
  private currentBlob:    Blob   | null      = null;

  constructor() {
    this.stamp$.pipe(
      debounceTime(400),
      takeUntil(this.destroy$),
    ).subscribe(() => this.estampar());
  }

  ngOnChanges(_: SimpleChanges): void {
    this.stamp$.next();
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
    this.revocar();
  }

  /** El componente padre llama a este método en el submit para obtener el File final. */
  obtenerArchivoPdf(): File | null {
    if (!this.currentBlob) return null;
    return new File([this.currentBlob], 'solicitud_permiso.pdf', { type: 'application/pdf' });
  }

  // ── Estampado ────────────────────────────────────────────────────
  private async estampar(): Promise<void> {
    try {
      const templateBytes = await this.obtenerTemplate();
      const pdfDoc = await PDFDocument.load(templateBytes, { ignoreEncryption: true });
      const font   = await pdfDoc.embedFont(StandardFonts.Helvetica);
      const fontB  = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
      const page   = pdfDoc.getPages()[0];

      // ── COORDENADAS CALIBRABLES ──────────────────────────────────────────────
      // Origen (0,0) = esquina inferior-izquierda. A4 = 595 × 842 pt.
      // ▲ Aumentar Y → sube el texto.   ▶ Aumentar X → mueve a la derecha.
      const COORDS = {
        // Fila superior (perfecta)
        fecha:         { x: 105, y: 746 },
        area:          { x: 255, y: 746 },
        puesto:        { x: 445, y: 746 },
        nombre:        { x: 185, y: 716 },

        horaInicio:    { x: 300, y: 603 }, // Línea de "Inicio:"
        horaFin:       { x: 460, y: 603 }, // Línea de "Fin:"

        totalDias:     { x: 330, y: 579 }, // Línea de "Total Días:"

        periodoInicio: { x: 290, y: 554 }, // Línea de "Fecha Inicio:"
        periodoFin:    { x: 420, y: 554 }, // Línea de "Fecha Fin:"

        // Sustento (Lo subimos un poco para que empiece arriba de la caja)
        motivo:        { x:  60, y: 515 },
      };

      // ── CHECKBOXES (Matriz corregida) ────────────────────────────────────────
      // Columna 1 = x: 191 | Columna 2 = x: 340 | Columna 3 = x: 510
      // Fila 1 = y: 690 | Fila 2 = y: 672 | Fila 3 = y: 654 | Fila 4 = y: 636
      const TIPO_COORDS: Record<string, { x: number; y: number }> = {
        // Fila 1 (y: 690)
        permiso_personal:         { x: 191, y: 690 },
        comision_trabajo:         { x: 363, y: 690 },
        cita_essalud:             { x: 533, y: 690 },

        // Fila 2 (y: 672)
        permanencia_capacitacion: { x: 191, y: 672 },
        permanencia_extra:        { x: 363, y: 672 },
        recuperacion:             { x: 533, y: 672 },

        // Fila 3 (y: 654)
        vacaciones:               { x: 191, y: 654 },
        dias_libres:              { x: 363, y: 654 },
        transferencia:            { x: 533, y: 654 },

        // Fila 4 (y: 636)
        otros:                    { x: 191, y: 636 },
      };

      const texto = (
        txt: string, x: number, y: number,
        { bold = false, size = 10 }: { bold?: boolean; size?: number } = {}
      ) => {
        if (!txt) return;
        page.drawText(txt, { x, y, size, font: bold ? fontB : font, color: rgb(0, 0, 0) });
      };

      // ── Fila: Fecha | Área | Puesto ──────────────────────────────
      texto(this.previewData?.fechaInicio ?? '',            COORDS.fecha.x,  COORDS.fecha.y);
      texto((this.empleadoInfo.area  ?? '').toUpperCase(),  COORDS.area.x,   COORDS.area.y);
      texto((this.empleadoInfo.cargo ?? '').toUpperCase(),  COORDS.puesto.x, COORDS.puesto.y);

      // ── Nombre del colaborador ────────────────────────────────────
      texto(
        (this.empleadoInfo.nombre ?? '').toUpperCase(),
        COORDS.nombre.x, COORDS.nombre.y,
        { bold: true, size: 11 },
      );

      // ── Checkbox: tipo de permiso ─────────────────────────────────
      const tipoCoord = TIPO_COORDS[this.previewData?.tipo ?? ''];
      if (tipoCoord) {
        texto('X', tipoCoord.x, tipoCoord.y, { bold: true, size: 12 });
      }

      // ── Horario ───────────────────────────────────────────────────
      texto(this.previewData?.horaInicio ?? '', COORDS.horaInicio.x, COORDS.horaInicio.y);
      texto(this.previewData?.horaFin    ?? '', COORDS.horaFin.x,    COORDS.horaFin.y);

      // ── Período: Total Días / Fecha Inicio / Fecha Fin ────────────
      if (this.previewData?.totalDias != null) {
        texto(String(this.previewData.totalDias), COORDS.totalDias.x, COORDS.totalDias.y);
      }
      texto(this.previewData?.fechaInicio ?? '', COORDS.periodoInicio.x, COORDS.periodoInicio.y);
      texto(this.previewData?.fechaFin    ?? '', COORDS.periodoFin.x,    COORDS.periodoFin.y);

      // ── Sustento / Motivo (truncado a 120 chars) ──────────────────
      const motivo = (this.previewData?.motivo ?? '').substring(0, 120);
      texto(motivo, COORDS.motivo.x, COORDS.motivo.y, { size: 9 });

      // ── Imagen de firma ───────────────────────────────────────────
      const firma = this.previewData?.firmaBase64 ?? '';
      if (firma) {
        await this.estamparFirma(pdfDoc, page, firma);
      }

      const finalBytes = await pdfDoc.save();
      this.actualizarIframe(finalBytes);
    } catch (err) {
      console.error('[PermisoPdfPreview] Error estampando:', err);
    }
  }

  private async estamparFirma(
    pdfDoc: PDFDocument,
    page: ReturnType<PDFDocument['getPages']>[0],
    firma: string,
  ): Promise<void> {
    try {
      let imgBytes: Uint8Array;
      let isPng: boolean;

      if (firma.startsWith('data:')) {
        // Firma dibujada/subida en sesión: viene como data URL base64
        isPng    = firma.startsWith('data:image/png');
        imgBytes = Uint8Array.from(atob(firma.split(',')[1]), c => c.charCodeAt(0));
      } else {
        // Firma guardada en servidor: viene como URL remota (http/https)
        const res = await fetch(firma);
        if (!res.ok) return;
        isPng    = (res.headers.get('content-type') ?? '').includes('png');
        imgBytes = new Uint8Array(await res.arrayBuffer());
      }

      const img = isPng
        ? await pdfDoc.embedPng(imgBytes)
        : await pdfDoc.embedJpg(imgBytes);
      page.drawImage(img, { x: 80, y: 339, width: 110, height: 50 });
    } catch {
      // Firma inválida o formato no soportado — se omite sin romper el PDF
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────
  private async obtenerTemplate(): Promise<ArrayBuffer> {
    if (this.templateCache) return this.templateCache;
    const res = await fetch(TEMPLATE_PATH);
    if (!res.ok) throw new Error(`No se pudo cargar la plantilla: ${res.status}`);
    this.templateCache = await res.arrayBuffer();
    return this.templateCache;
  }

  private actualizarIframe(bytes: Uint8Array): void {
    this.revocar();
    this.currentBlob = new Blob([bytes as any], { type: 'application/pdf' });
    this.currentBlobUrl = URL.createObjectURL(this.currentBlob);
    this.pdfUrl = this.sanitizer.bypassSecurityTrustResourceUrl(this.currentBlobUrl);
  }

  private revocar(): void {
    if (this.currentBlobUrl) {
      URL.revokeObjectURL(this.currentBlobUrl);
      this.currentBlobUrl = null;
    }
  }
}

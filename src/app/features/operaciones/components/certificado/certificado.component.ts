import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

type TipoCert = 'pozo' | 'operatividad';

@Component({
  selector: 'app-certificado',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './certificado.component.html',
  styleUrls: ['./certificado.component.css'],
})
export class CertificadoComponent implements OnInit {
  private route     = inject(ActivatedRoute);
  private location  = inject(Location);
  private svc       = inject(OperacionesService);
  private toast     = inject(ToastService);
  private sanitizer = inject(DomSanitizer);

  servicioId = '';
  eiId       = '';
  tipo: TipoCert = 'pozo';

  generando    = false;
  pdfUrl: SafeResourceUrl | null = null;

  // ── Datos del equipo (auto-completados) ───────────────────────────
  ubicacionReferencia = '';
  fechaHoy            = '';

  // ── Personal disponible para el dropdown ──────────────────────────
  personal: { id: string; nombre: string; cargo: string }[] = [];

  // ── Fotos de procedimientos 1, 4 y 7 (solo Pozo) ──────────────────
  fotoProc1: string | null = null;
  fotoProc4: string | null = null;
  fotoProc7: string | null = null;

  // ── Firmas (solo Pozo a Tierra) ───────────────────────────────────
  firmaTecB64: string | null = null;

  // ── Campos del formulario ─────────────────────────────────────────
  form = {
    ubicacion:          '',
    // Pozo
    nombre_pozo:        '',   // auto desde BD → va en "CERTIFICADO N°"
    numero_pozo:        '',   // auto desde BD → columna N° DE POZO de tabla
    fecha_ejecucion:    '',   // type="date"  → YYYY-MM-DD
    fecha_hora_medicion:'',   // type="datetime-local" → YYYY-MM-DDTHH:MM
    resultado_medicion: '',
    hora_inicio:        '',   // type="time" → HH:MM
    hora_termino:       '',   // type="time" → HH:MM
    nombre_tecnico:     '',
    // Operatividad (todos auto-completados)
    nombre_tablero:     '',
    fecha:              '',
    razon_social:       '',
  };

  get esPozo(): boolean         { return this.tipo === 'pozo'; }
  get esOperatividad(): boolean { return this.tipo === 'operatividad'; }
  get titulo(): string {
    return this.esPozo ? 'Protocolo de Pozo a Tierra' : 'Certificado de Operatividad';
  }

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id')    ?? '';
    this.eiId       = this.route.snapshot.paramMap.get('eiId')  ?? '';
    this.tipo       = (this.route.snapshot.paramMap.get('tipo') ?? 'pozo') as TipoCert;

    const hoy = new Date();
    this.fechaHoy = hoy.toLocaleDateString('es-PE', { day: '2-digit', month: '2-digit', year: 'numeric' });
    this.form.fecha = `${String(hoy.getDate()).padStart(2,'0')}/${String(hoy.getMonth()+1).padStart(2,'0')}/${hoy.getFullYear()}`;

    this.cargarDatos();
  }

  private cargarDatos(): void {
    // Carga datos del equipo + personal del servicio
    this.svc.getInspeccionActiva(this.servicioId, this.eiId).subscribe({
      next: (data: any) => {
        const eq = data?.equipo;
        if (eq) {
          this.ubicacionReferencia = eq.ubicacion_referencia ?? '';
          this.form.ubicacion = this.ubicacionReferencia;
          this.form.nombre_tablero = eq.nombre ?? '';
          this.form.nombre_pozo    = eq.nombre ?? '';
          this.form.numero_pozo    = eq.nombre ?? '';
        }
        // Fotos de los procedimientos (si ya fueron subidas)
        const procs: any[] = data?.resultado ?? [];
        this.fotoProc1 = procs.find((p: any) => p.orden === 1)?.foto_url ?? null;
        this.fotoProc4 = procs.find((p: any) => p.orden === 4)?.foto_url ?? null;
        this.fotoProc7 = procs.find((p: any) => p.orden === 7)?.foto_url ?? null;
      },
      error: () => { /* continúa sin precarga */ }
    });

    this.svc.getPrecargaInforme(this.servicioId).subscribe({
      next: (res: any) => {
        this.personal = (res?.personal ?? []).map((p: any) => ({
          id:     p.id,
          nombre: p.nombre,
          cargo:  p.cargo ?? '',
        }));
        const cliente = res?.servicio?.cliente_nombre;
        if (cliente) this.form.razon_social = cliente;
      },
      error: () => {}
    });
  }

  // ── Firma desde archivo (solo Pozo) ──────────────────────────────
  async onFirmaFile(event: Event, _tipo: 'tecnico'): Promise<void> {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    this.firmaTecB64 = await this._fileToB64(file);
  }

  private _fileToB64(file: File): Promise<string> {
    return new Promise((res, rej) => {
      const r = new FileReader();
      r.onload = () => res(r.result as string);
      r.onerror = rej;
      r.readAsDataURL(file);
    });
  }

  // ── Generar / Actualizar vista previa ─────────────────────────────
  generar(): void {
    if (this.generando) return;
    this.generando = true;

    const payload = this.esPozo ? this._payloadPozo() : this._payloadOperatividad();
    console.log('[Certificado] Payload enviado:', payload);

    const obs = this.esPozo
      ? this.svc.generarCertificadoPozo(this.servicioId, this.eiId, payload)
      : this.svc.generarCertificadoOperatividad(this.servicioId, this.eiId, payload);

    obs.subscribe({
      next: (blob: Blob) => {
        this.generando = false;
        const objUrl = URL.createObjectURL(blob);
        this.pdfUrl  = this.sanitizer.bypassSecurityTrustResourceUrl(objUrl);
      },
      error: (err: any) => {
        this.generando = false;
        // Cuando responseType='blob', los errores también llegan como Blob.
        // Hay que leerlo como texto para obtener el detail del backend.
        if (err?.error instanceof Blob) {
          err.error.text().then((text: string) => {
            let detail = 'Error al generar el certificado.';
            try {
              const json = JSON.parse(text);
              detail = json?.detail ?? text;
            } catch { detail = text || detail; }
            console.error('[Certificado] Error del backend:', detail);
            this.toast.mostrar(detail, 'error');
          });
        } else {
          const detail = err?.error?.detail ?? 'Error al generar el certificado.';
          console.error('[Certificado] Error:', detail);
          this.toast.mostrar(detail, 'error');
        }
      },
    });
  }

  descargar(): void {
    if (!this.pdfUrl) { this.toast.mostrar('Primero genera la vista previa.', 'info'); return; }
    const a = document.createElement('a');
    // Extraemos la URL cruda del SafeResourceUrl para forzar descarga
    const raw = (this.pdfUrl as any).changingThisBreaksApplicationSecurity as string;
    a.href     = raw;
    a.download = `${this.esPozo ? 'PROTOCOLO_POZO' : 'CERT_OPERATIVIDAD'}_${this.form.numero_pozo || this.form.nombre_tablero || 'doc'}.pdf`;
    a.click();
  }

  private _fmtDate(val: string): string {
    if (!val) return '';
    const [y, m, d] = val.split('-');
    return `${d}/${m}/${y}`;
  }

  private _fmtDatetime(val: string): string {
    if (!val) return '';
    const [date, time] = val.split('T');
    const [y, m, d] = date.split('-');
    return `${d}/${m}/${y}  ${time ?? ''}`;
  }

  private _payloadPozo(): object {
    return {
      nombre_pozo:          this.form.nombre_pozo,
      ubicacion:            this.form.ubicacion,
      numero_pozo:          this.form.numero_pozo,
      // fecha_actualizacion se auto-genera en backend (fecha de hoy)
      fecha_ejecucion:      this._fmtDate(this.form.fecha_ejecucion),
      fecha_hora_medicion:  this._fmtDatetime(this.form.fecha_hora_medicion),
      resultado_medicion:   this.form.resultado_medicion,
      hora_inicio:          this.form.hora_inicio,
      hora_termino:         this.form.hora_termino,
      nombre_tecnico:       this.form.nombre_tecnico,
      firma_tecnico:        this.firmaTecB64,
      fotos_procedimientos: [this.fotoProc1, this.fotoProc4, this.fotoProc7],
    };
  }

  private _payloadOperatividad(): object {
    return {
      nombre_tablero: this.form.nombre_tablero,
      fecha:          this.form.fecha,
      razon_social:   this.form.razon_social,
      ubicacion:      this.form.ubicacion,
    };
  }

  volver(): void { this.location.back(); }
}

import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { Salida, SalidaItem, SalidasKpis } from '../../logistica.models';

@Component({
  selector: 'app-salidas',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './salidas.component.html',
  styleUrls: ['./salidas.component.css'],
})
export class SalidasComponent implements OnInit, OnDestroy {
  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  cargando = true;
  salidas: Salida[] = [];
  total    = 0;
  page     = 1;
  pageSize = 30;

  busqueda    = '';
  filtroDesde = '';
  filtroHasta = '';

  kpis: SalidasKpis = {
    totalSalidas: 0, totalUnidadesEntregadas: 0,
    salidasEsteMes: 0, proyectosAtendidos: 0,
  };

  salidaDetalle: Salida | null = null;

  ngOnInit(): void { this.cargar(); this.cargarKpis(); }

  ngOnDestroy(): void { document.body.style.overflow = ''; }

  cargar(): void {
    this.cargando = true;
    this.svc.getSalidas({
      q:        this.busqueda    || undefined,
      desde:    this.filtroDesde || undefined,
      hasta:    this.filtroHasta || undefined,
      page:     this.page,
      pageSize: this.pageSize,
    }).subscribe({
      next:  r => { this.salidas = r.items; this.total = r.total; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar salidas.', 'error'); },
    });
  }

  cargarKpis(): void {
    this.svc.getSalidasKpis().subscribe({ next: k => (this.kpis = k), error: () => {} });
  }

  buscar():         void { this.page = 1; this.cargar(); }
  limpiarFiltros(): void {
    this.busqueda = ''; this.filtroDesde = ''; this.filtroHasta = '';
    this.page = 1; this.cargar();
  }

  abrirDetalle(s: Salida): void  { this.salidaDetalle = s; document.body.style.overflow = 'hidden'; }
  cerrarDetalle(): void          { this.salidaDetalle = null; document.body.style.overflow = ''; }

  abrirReporte(s: Salida): void {
    const ref = s.id.slice(-8).toUpperCase();
    const win = window.open('', '_blank');
    if (!win) {
      this.toast.mostrar('Permite ventanas emergentes en el navegador para generar el reporte.', 'error');
      return;
    }
    const body = this.generarHtmlReporte(s);
    win.document.write(`<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Salida-${ref}</title>
  <style>
    @media print {
      body { margin: 0; padding: 20pt; }
      @page { margin: 20pt; }
    }
    body { font-family: Arial, sans-serif; }
  </style>
</head>
<body style="padding:24px">${body}<script>window.onload=function(){window.print();}<\/script></body>
</html>`);
    win.document.close();
  }

  get totalPaginas(): number { return Math.ceil(this.total / this.pageSize); }
  irPagina(p: number): void {
    if (p >= 1 && p <= this.totalPaginas) { this.page = p; this.cargar(); }
  }

  sumCantSolicitada(items: SalidaItem[]): number {
    return items.reduce((acc, i) => acc + i.cantidadSolicitada, 0);
  }

  fechaCorta(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  fechaHora(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleString('es-PE', {
      day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
    });
  }

  private esc(v: string | null | undefined): string {
    if (v == null) return '—';
    return String(v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  private generarHtmlReporte(s: Salida): string {
    const ref   = this.esc(s.id.slice(-8).toUpperCase());
    const ahora = new Date().toLocaleString('es-PE', {
      day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
    });

    const itemsHtml = s.items.map((it, i) => `
      <tr>
        <td style="width:28px;color:#9ca3af;padding:5px 7px;border-bottom:1px solid #e5e7eb">${i + 1}</td>
        <td style="padding:5px 7px;border-bottom:1px solid #e5e7eb">${this.esc(it.nombre)}</td>
        <td style="width:70px;color:#6b7280;padding:5px 7px;border-bottom:1px solid #e5e7eb">${this.esc(it.unidad) || '—'}</td>
        <td style="width:110px;text-align:right;padding:5px 7px;border-bottom:1px solid #e5e7eb">${it.cantidadSolicitada}</td>
        <td style="width:110px;text-align:right;color:#16a34a;font-weight:600;padding:5px 7px;border-bottom:1px solid #e5e7eb">${it.cantidadEntregada}</td>
      </tr>`).join('');

    const obsHtml = s.observacion ? `
      <div style="margin-bottom:14px">
        <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;color:#6b7280;padding-bottom:4px;margin-bottom:8px;border-bottom:1px solid #e5e7eb">Observaciones</div>
        <p style="font-size:12px;color:#374151;border-left:3px solid #ca8a04;padding:6px 10px;background:rgba(234,179,8,.06)">${this.esc(s.observacion)}</p>
      </div>` : '';

    const firmaHtml = s.firmaUrl
      ? `<img src="${this.esc(s.firmaUrl)}" alt="Firma" style="max-height:60px;max-width:160px;border:1px solid #e5e7eb">`
      : '<div style="width:100%;height:1px;background:#111;margin-bottom:4px"></div>';

    return `
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: Arial, sans-serif; font-size: 13px; color: #111; background: #fff; padding: 24px; }
</style>

<div style="border-bottom:2px solid #111;padding-bottom:12px;margin-bottom:16px">
  <table style="width:100%;border-collapse:collapse">
    <tr>
      <td style="width:50px;vertical-align:middle">
        <div style="width:42px;height:42px;background:#111;border-radius:6px;text-align:center;line-height:42px;color:#fff;font-weight:900;font-size:14px">EZ</div>
      </td>
      <td style="text-align:center;vertical-align:middle">
        <div style="font-size:14px;font-weight:800;text-transform:uppercase;letter-spacing:.04em">Comprobante de Salida de Materiales</div>
        <div style="font-size:11px;color:#6b7280;margin-top:3px">Registro de entrega a campo — E-zyro</div>
      </td>
      <td style="text-align:right;vertical-align:middle;font-size:11px;color:#374151;line-height:1.7;width:160px">
        <strong>Ref:</strong> ${ref}<br>
        <strong>Fecha:</strong> ${this.esc(ahora)}
      </td>
    </tr>
  </table>
</div>

<div style="margin-bottom:14px">
  <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;color:#6b7280;padding-bottom:4px;margin-bottom:8px;border-bottom:1px solid #e5e7eb">Información del Requerimiento</div>
  <table style="width:100%;border-collapse:collapse">
    <tr>
      <td style="padding:3px 0;width:50%">
        <div style="font-size:9px;text-transform:uppercase;letter-spacing:.05em;color:#9ca3af">Proyecto</div>
        <div style="font-size:12px;font-weight:500">${this.esc(s.proyectoNombre)}</div>
      </td>
      <td style="padding:3px 0;width:50%">
        <div style="font-size:9px;text-transform:uppercase;letter-spacing:.05em;color:#9ca3af">Servicio</div>
        <div style="font-size:12px;font-weight:500">${this.esc(s.servicioNombre)}</div>
      </td>
    </tr>
    <tr>
      <td style="padding:3px 0">
        <div style="font-size:9px;text-transform:uppercase;letter-spacing:.05em;color:#9ca3af">Fecha solicitud</div>
        <div style="font-size:12px;font-weight:500">${this.esc(this.fechaHora(s.fechaSolicitud))}</div>
      </td>
      <td style="padding:3px 0">
        <div style="font-size:9px;text-transform:uppercase;letter-spacing:.05em;color:#9ca3af">Fecha salida</div>
        <div style="font-size:12px;font-weight:700;color:#16a34a">${this.esc(this.fechaHora(s.fechaSalida))}</div>
      </td>
    </tr>
  </table>
</div>

<div style="margin-bottom:14px">
  <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;color:#6b7280;padding-bottom:4px;margin-bottom:8px;border-bottom:1px solid #e5e7eb">Personal Involucrado</div>
  <table style="width:100%;border-collapse:collapse">
    <tr>
      <td style="padding:5px 8px;border:1px solid #e5e7eb;background:#f9fafb;width:33%">
        <div style="font-size:9px;text-transform:uppercase;letter-spacing:.07em;color:#9ca3af">Solicitado por</div>
        <div style="font-size:12px;font-weight:700">${this.esc(s.solicitanteNombre)}</div>
        <div style="font-size:10px;color:#9ca3af">Jefe de proyecto</div>
      </td>
      <td style="padding:5px 8px;border:1px solid #e5e7eb;background:#f9fafb;width:33%">
        <div style="font-size:9px;text-transform:uppercase;letter-spacing:.07em;color:#9ca3af">Entregado por</div>
        <div style="font-size:12px;font-weight:700">${this.esc(s.entregadoPorNombre)}</div>
        <div style="font-size:10px;color:#9ca3af">Responsable de logística</div>
      </td>
      <td style="padding:5px 8px;border:1px solid #22c55e;background:rgba(34,197,94,.04);width:34%">
        <div style="font-size:9px;text-transform:uppercase;letter-spacing:.07em;color:#9ca3af">Recibido por</div>
        <div style="font-size:12px;font-weight:700">${this.esc(s.recibidoPorNombre)}</div>
        <div style="font-size:10px;color:#9ca3af">Técnico en campo</div>
      </td>
    </tr>
  </table>
</div>

<div style="margin-bottom:14px">
  <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;color:#6b7280;padding-bottom:4px;margin-bottom:8px;border-bottom:1px solid #e5e7eb">Materiales Entregados</div>
  <table style="width:100%;border-collapse:collapse;font-size:12px">
    <thead>
      <tr style="background:#f9fafb">
        <th style="padding:6px 7px;text-align:left;border-bottom:2px solid #111;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:#374151;width:28px">#</th>
        <th style="padding:6px 7px;text-align:left;border-bottom:2px solid #111;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:#374151">Material / Ítem</th>
        <th style="padding:6px 7px;text-align:left;border-bottom:2px solid #111;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:#374151;width:70px">Unidad</th>
        <th style="padding:6px 7px;text-align:right;border-bottom:2px solid #111;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:#374151;width:110px">Cant. solicitada</th>
        <th style="padding:6px 7px;text-align:right;border-bottom:2px solid #111;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:#16a34a;width:110px">Cant. entregada</th>
      </tr>
    </thead>
    <tbody>${itemsHtml}</tbody>
    <tfoot>
      <tr style="background:#f9fafb">
        <td colspan="3" style="padding:6px 7px;font-weight:700;border-top:2px solid #111">TOTAL DE ÍTEMS: ${s.totalItems}</td>
        <td style="padding:6px 7px;font-weight:700;border-top:2px solid #111;text-align:right">—</td>
        <td style="padding:6px 7px;font-weight:700;border-top:2px solid #111;text-align:right;color:#16a34a">${s.totalUnidades}</td>
      </tr>
    </tfoot>
  </table>
</div>

${obsHtml}

<table style="width:100%;border-collapse:collapse;margin-top:24px">
  <tr>
    <td style="text-align:center;padding:0 24px;width:50%">
      <div style="width:100%;height:1px;background:#111;margin-bottom:6px"></div>
      <div style="font-size:12px;font-weight:600">${this.esc(s.entregadoPorNombre) || 'Responsable de logística'}</div>
      <div style="font-size:10px;color:#9ca3af">Entregado por</div>
    </td>
    <td style="text-align:center;padding:0 24px;width:50%">
      ${firmaHtml}
      <div style="font-size:12px;font-weight:600">${this.esc(s.recibidoPorNombre) || 'Técnico en campo'}</div>
      <div style="font-size:10px;color:#9ca3af">Recibido por (firma)</div>
    </td>
  </tr>
</table>

<div style="margin-top:16px;padding-top:8px;border-top:1px solid #e5e7eb;text-align:center;font-size:10px;color:#9ca3af">
  Documento generado por el sistema de logística E-zyro · ${this.esc(ahora)}
</div>`;
  }
}

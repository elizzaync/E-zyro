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
    const win = window.open('', '_blank');
    if (!win) { this.toast.mostrar('El navegador bloqueó la ventana emergente.', 'error'); return; }
    win.document.write(this.generarHtmlComprobante(s));
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

  private generarHtmlComprobante(s: Salida): string {
    const ref   = this.esc(s.id.slice(-8).toUpperCase());
    const ahora = new Date().toLocaleString('es-PE', {
      day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
    });
    const itemsHtml = s.items.map((it, i) => `
      <tr>
        <td class="n">${i + 1}</td>
        <td>${this.esc(it.nombre)}</td>
        <td class="u">${this.esc(it.unidad) || '—'}</td>
        <td class="r">${it.cantidadSolicitada}</td>
        <td class="r g">${it.cantidadEntregada}</td>
      </tr>`).join('');
    const totSol = this.sumCantSolicitada(s.items);
    const obsHtml = s.observacion ? `
      <div class="sec">
        <h2 class="sec-h">Observaciones</h2>
        <p class="obs">${this.esc(s.observacion)}</p>
      </div>` : '';
    const firmaHtml = s.firmaUrl
      ? `<img src="${this.esc(s.firmaUrl)}" alt="Firma" class="firma-img">`
      : '<div class="firma-linea"></div>';

    return `<!DOCTYPE html><html lang="es"><head>
<meta charset="UTF-8">
<title>Comprobante Salida — ${ref}</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Arial,sans-serif;font-size:13px;color:#111;background:#fff;padding:1.5cm}
h1{font-size:13px;font-weight:800;text-transform:uppercase;letter-spacing:.04em;margin:0}
.hdr{display:flex;justify-content:space-between;align-items:center;gap:1rem;margin-bottom:1.2rem;padding-bottom:.8rem;border-bottom:2px solid #111}
.logo{width:46px;height:46px;border-radius:8px;background:#111;color:#fff;display:flex;align-items:center;justify-content:center}
.logo svg{width:22px;height:22px}
.hdr-mid{text-align:center;flex:1}
.sub{font-size:11px;color:#6b7280;margin-top:3px}
.hdr-r{text-align:right;font-size:11px;color:#374151;line-height:1.6}
.sec{margin-bottom:1rem}
.sec-h{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;color:#6b7280;padding-bottom:4px;margin-bottom:8px;border-bottom:1px solid #e5e7eb}
.g2{display:grid;grid-template-columns:1fr 1fr;gap:4px 12px}
.g3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px}
.campo{display:flex;flex-direction:column;gap:1px}
.campo-l{font-size:9px;text-transform:uppercase;letter-spacing:.05em;color:#9ca3af}
.campo-v{font-size:12px;color:#111;font-weight:500}
.campo-v.hl{color:#16a34a;font-weight:700}
.card{border:1px solid #e5e7eb;border-radius:6px;padding:7px 9px;background:#f9fafb}
.card.hl{border-color:#22c55e;background:rgba(34,197,94,.05)}
.card-rol{font-size:9px;text-transform:uppercase;letter-spacing:.07em;color:#9ca3af;display:block}
.card-nm{font-size:12px;font-weight:700;color:#111;display:block}
.card-desc{font-size:10px;color:#9ca3af;display:block}
table{width:100%;border-collapse:collapse;font-size:12px}
thead th{padding:6px 7px;text-align:left;border-bottom:2px solid #111;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:#374151}
tbody td{padding:5px 7px;border-bottom:1px solid #e5e7eb}
tfoot td{padding:6px 7px;font-weight:700;border-top:2px solid #111;background:#f9fafb}
.n{width:28px;color:#9ca3af}
.u{width:70px;color:#6b7280}
.r{width:100px;text-align:right}
.g{color:#16a34a}
.obs{font-size:12px;color:#374151;border-left:3px solid #ca8a04;padding:6px 10px;background:rgba(234,179,8,.06);border-radius:0 6px 6px 0}
.firmas{display:grid;grid-template-columns:1fr 1fr;gap:2rem;margin-top:1.5rem}
.firma-blq{display:flex;flex-direction:column;align-items:center;gap:5px}
.firma-linea{width:100%;height:1px;background:#111;margin-bottom:4px}
.firma-img{max-height:70px;max-width:180px;border:1px solid #e5e7eb;border-radius:5px}
.firma-nm{font-size:12px;font-weight:600;color:#111}
.firma-cargo{font-size:10px;color:#9ca3af}
.footer{margin-top:1rem;padding-top:.6rem;border-top:1px solid #e5e7eb;text-align:center;font-size:10px;color:#9ca3af}
@media print{body{padding:0}@page{margin:1.5cm}}
</style></head><body>

<div class="hdr">
  <div class="logo">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/>
    </svg>
  </div>
  <div class="hdr-mid">
    <h1>Comprobante de Salida de Materiales</h1>
    <p class="sub">Registro de entrega a campo</p>
  </div>
  <div class="hdr-r">
    <strong>Impresión:</strong><br>${this.esc(ahora)}<br>
    <strong>Ref:</strong> ${ref}
  </div>
</div>

<div class="sec">
  <h2 class="sec-h">Información del Requerimiento</h2>
  <div class="g2">
    <div class="campo"><span class="campo-l">Proyecto</span><span class="campo-v">${this.esc(s.proyectoNombre)}</span></div>
    <div class="campo"><span class="campo-l">Servicio</span><span class="campo-v">${this.esc(s.servicioNombre)}</span></div>
    <div class="campo"><span class="campo-l">Fecha solicitud</span><span class="campo-v">${this.esc(this.fechaHora(s.fechaSolicitud))}</span></div>
    <div class="campo"><span class="campo-l">Fecha salida</span><span class="campo-v hl">${this.esc(this.fechaHora(s.fechaSalida))}</span></div>
  </div>
</div>

<div class="sec">
  <h2 class="sec-h">Personal Involucrado</h2>
  <div class="g3">
    <div class="card">
      <span class="card-rol">Solicitado por</span>
      <span class="card-nm">${this.esc(s.solicitanteNombre)}</span>
      <span class="card-desc">Jefe de proyecto / Coordinador</span>
    </div>
    <div class="card">
      <span class="card-rol">Entregado por</span>
      <span class="card-nm">${this.esc(s.entregadoPorNombre)}</span>
      <span class="card-desc">Responsable de logística</span>
    </div>
    <div class="card hl">
      <span class="card-rol">Recibido por</span>
      <span class="card-nm">${this.esc(s.recibidoPorNombre)}</span>
      <span class="card-desc">Técnico en campo</span>
    </div>
  </div>
</div>

<div class="sec">
  <h2 class="sec-h">Materiales Entregados</h2>
  <table>
    <thead><tr>
      <th class="n">#</th><th>Material / Ítem</th><th class="u">Unidad</th>
      <th class="r">Cant. solicitada</th><th class="r g">Cant. entregada</th>
    </tr></thead>
    <tbody>${itemsHtml}</tbody>
    <tfoot><tr>
      <td colspan="3">TOTAL DE ÍTEMS: ${s.totalItems}</td>
      <td class="r">—</td><td class="r g">${s.totalUnidades}</td>
    </tr></tfoot>
  </table>
</div>

${obsHtml}

<div class="firmas">
  <div class="firma-blq">
    <div class="firma-linea"></div>
    <span class="firma-nm">${this.esc(s.entregadoPorNombre) || 'Responsable de logística'}</span>
    <span class="firma-cargo">Entregado por</span>
  </div>
  <div class="firma-blq">
    ${firmaHtml}
    <span class="firma-nm">${this.esc(s.recibidoPorNombre) || 'Técnico en campo'}</span>
    <span class="firma-cargo">Recibido por (firma)</span>
  </div>
</div>

<div class="footer">
  Documento generado por el sistema de logística E-zyro · ${this.esc(ahora)}
</div>

<script>window.onload=function(){window.focus();window.print();};<\/script>
</body></html>`;
  }
}

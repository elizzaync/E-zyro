import { Component, Input, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import * as XLSX from 'xlsx';
import { MaterialLog, EquipoHerramienta } from '../../logistica.models';

@Component({
  selector: 'app-reporte-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './reporte-modal.component.html',
  styleUrls: ['./reporte-modal.component.css'],
})
export class ReporteModalComponent {
  @Input() tipo: 'materiales' | 'equipos' = 'materiales';
  @Input() datos: MaterialLog[] | EquipoHerramienta[] = [];
  @Output() cerrar = new EventEmitter<void>();

  formato: 'excel' | 'pdf' = 'excel';
  filtro = 'todos';

  get opcionesFiltro(): { valor: string; label: string }[] {
    if (this.tipo === 'materiales') return [
      { valor: 'todos',      label: 'Todos los materiales'   },
      { valor: 'activos',    label: 'Solo activos'           },
      { valor: 'inactivos',  label: 'Solo inactivos'         },
      { valor: 'stock_bajo', label: 'Solo con stock bajo'    },
    ];
    return [
      { valor: 'todos',            label: 'Equipos y herramientas'  },
      { valor: 'equipo',           label: 'Solo equipos'             },
      { valor: 'herramienta',      label: 'Solo herramientas'        },
      { valor: 'operativo',        label: 'Solo operativos'          },
      { valor: 'en_mantenimiento', label: 'Solo en mantenimiento'    },
    ];
  }

  get datosFiltrados(): any[] {
    if (this.tipo === 'materiales') {
      const m = this.datos as MaterialLog[];
      if (this.filtro === 'activos')    return m.filter(x => x.activo);
      if (this.filtro === 'inactivos')  return m.filter(x => !x.activo);
      if (this.filtro === 'stock_bajo') return m.filter(x => x.cantidad <= x.stockMinimo && x.stockMinimo > 0);
      return m;
    }
    const e = this.datos as EquipoHerramienta[];
    if (this.filtro === 'equipo')           return e.filter(x => x.clase !== 'herramienta');
    if (this.filtro === 'herramienta')      return e.filter(x => x.clase === 'herramienta');
    if (this.filtro === 'operativo')        return e.filter(x => x.estado === 'operativo');
    if (this.filtro === 'en_mantenimiento') return e.filter(x => x.estado === 'en_mantenimiento');
    return e;
  }

  get totalRegistros(): number { return this.datosFiltrados.length; }

  generarReporte(): void {
    if (this.tipo === 'materiales') {
      this.formato === 'excel' ? this.excelMateriales() : this.pdfMateriales();
    } else {
      this.formato === 'excel' ? this.excelEquipos() : this.pdfEquipos();
    }
    this.cerrar.emit();
  }

  // ── Excel Materiales ──────────────────────────────────────────────────────
  private excelMateriales(): void {
    const mats = this.datosFiltrados as MaterialLog[];
    const wb   = XLSX.utils.book_new();

    // Hoja 1: Inventario completo
    const filasCabecera = [['Código','Nombre','Categoría','Unidad','Cantidad','Stk. Mínimo','Marca','N° Serie','Almacén / Zona','Costo Unit. (S/)','Estado']];
    const filasDetalle  = mats.map(m => [
      m.codigo, m.nombre, m.categoria, m.unidad ?? '',
      m.cantidad, m.stockMinimo, m.marca ?? '', m.serie ?? '',
      m.almacen, m.precioCompra ?? '', m.activo ? 'Activo' : 'Inactivo',
    ]);
    const ws1 = XLSX.utils.aoa_to_sheet([...filasCabecera, ...filasDetalle]);
    ws1['!cols'] = [9,38,22,10,10,10,18,14,20,14,10].map(w => ({ wch: w }));
    XLSX.utils.book_append_sheet(wb, ws1, 'Inventario Materiales');

    // Hoja 2: Resumen de costos
    const conPrecio = mats.filter(m => m.precioCompra != null);
    const totalUnidades   = conPrecio.reduce((s, m) => s + m.cantidad, 0);
    const totalInversion  = conPrecio.reduce((s, m) => s + (m.precioCompra! * m.cantidad), 0);
    const sinPrecio       = mats.length - conPrecio.length;

    const s2: any[][] = [
      ['RESUMEN DE COSTOS DE INVENTARIO'],
      [`Generado: ${new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' })}`],
      [],
      ['Material', 'Categoría', 'Cantidad', 'Precio Unit. (S/)', 'Total (S/)'],
      ...conPrecio.map(m => [
        m.nombre, m.categoria, m.cantidad,
        m.precioCompra,
        +((m.precioCompra! * m.cantidad).toFixed(2)),
      ]),
      [],
      ['TOTAL GENERAL', '', totalUnidades, '', +totalInversion.toFixed(2)],
      [],
      [`* ${sinPrecio} material(es) sin precio registrado no están incluidos en el cálculo.`],
    ];
    const ws2 = XLSX.utils.aoa_to_sheet(s2);
    ws2['!cols'] = [38, 22, 10, 18, 18].map(w => ({ wch: w }));
    XLSX.utils.book_append_sheet(wb, ws2, 'Resumen Costos');

    XLSX.writeFile(wb, `Materiales_${this.fechaHoy()}.xlsx`);
  }

  // ── PDF Materiales ────────────────────────────────────────────────────────
  private pdfMateriales(): void {
    const mats  = this.datosFiltrados as MaterialLog[];
    const fecha = new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' });

    const rows = mats.map(m => {
      const alerta = m.stockMinimo > 0 && m.cantidad <= m.stockMinimo;
      const rowBg  = alerta ? 'background:#fef2f2' : '';
      const numSty = alerta ? 'color:#dc2626;font-weight:700' : '';
      return `<tr style="${rowBg}">
        <td>${this.esc(m.nombre)}</td>
        <td>${this.esc(m.marca ?? '—')}</td>
        <td>${this.esc(m.categoria)}</td>
        <td>${this.esc(m.unidad ?? '')}</td>
        <td style="text-align:center;${numSty}">${m.cantidad}</td>
        <td style="text-align:center">${m.stockMinimo || '—'}</td>
        <td>${this.esc(m.serie ?? '—')}</td>
        <td>${this.esc(m.almacen)}</td>
      </tr>`;
    }).join('');

    this.imprimirHtml(`
      <h2>Reporte de Inventario · Materiales</h2>
      <div class="sub">${fecha} &nbsp;·&nbsp; ${mats.length} registros
        <span class="leyenda-rojo">■ Stock por debajo del mínimo</span>
      </div>
      <table>
        <thead><tr>
          <th>Nombre</th><th>Marca</th><th>Categoría</th><th>Unidad</th>
          <th>Cant.</th><th>Mín.</th><th>N° Serie</th><th>Zona / Almacén</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    `);
  }

  // ── Excel Equipos ─────────────────────────────────────────────────────────
  private excelEquipos(): void {
    const eq = this.datosFiltrados as EquipoHerramienta[];
    const wb = XLSX.utils.book_new();
    const cl = (c: string) => c === 'equipo_tecnologico' ? 'Eq. TI' : c === 'herramienta' ? 'Herramienta' : 'Equipo';
    const el = (s: string) => ({ operativo:'Operativo', en_mantenimiento:'En mantenimiento', fuera_de_servicio:'Fuera de servicio', baja:'De baja' }[s] ?? s);

    const ws1 = XLSX.utils.aoa_to_sheet([
      ['Código','Nombre','Clase','Categoría','Marca','Modelo','N° Serie','Cantidad','Stk. Mín.','Costo (S/)','Estado','Ubicación','Observaciones','Próx. Mantenimiento'],
      ...eq.map(e => [
        e.codigo, e.nombre, cl(e.clase), e.categoria,
        e.marca ?? '', e.modelo ?? '', e.numeroSerie ?? '',
        e.cantidad, e.stockMinimo, e.precioCompra ?? '',
        el(e.estado), e.ubicacion ?? '', e.observaciones ?? '',
        e.proximaFechaMantenimiento ?? '',
      ]),
    ]);
    ws1['!cols'] = [10,36,12,22,16,16,18,10,10,12,18,18,30,18].map(w => ({ wch: w }));
    XLSX.utils.book_append_sheet(wb, ws1, 'Inventario Equipos');

    // Resumen por estado
    const byEstado: Record<string, number> = {};
    eq.forEach(e => { const k = el(e.estado); byEstado[k] = (byEstado[k] || 0) + e.cantidad; });
    const ws2 = XLSX.utils.aoa_to_sheet([
      ['Estado', 'Cantidad Total'],
      ...Object.entries(byEstado),
      [],
      ['TOTAL', eq.reduce((s, e) => s + e.cantidad, 0)],
    ]);
    ws2['!cols'] = [22, 16].map(w => ({ wch: w }));
    XLSX.utils.book_append_sheet(wb, ws2, 'Resumen por Estado');

    XLSX.writeFile(wb, `Equipos_${this.fechaHoy()}.xlsx`);
  }

  // ── PDF Equipos ───────────────────────────────────────────────────────────
  private pdfEquipos(): void {
    const eq    = this.datosFiltrados as EquipoHerramienta[];
    const fecha = new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' });
    const cl = (c: string) => c === 'equipo_tecnologico' ? 'Eq. TI' : c === 'herramienta' ? 'Herramienta' : 'Equipo';
    const el = (s: string) => ({ operativo:'Operativo', en_mantenimiento:'En mantenimiento', fuera_de_servicio:'Fuera de servicio', baja:'De baja' }[s] ?? s);
    const ec = (s: string) => ({ operativo:'#16a34a', en_mantenimiento:'#d97706', fuera_de_servicio:'#dc2626', baja:'#94a3b8' }[s] ?? '');

    const rows = eq.map(e => {
      const bajo = e.stockMinimo > 0 && e.cantidad <= e.stockMinimo;
      return `<tr style="${bajo ? 'background:#fef2f2' : ''}">
        <td>${this.esc(e.codigo)}</td>
        <td>${this.esc(e.nombre)}</td>
        <td>${cl(e.clase)}</td>
        <td>${this.esc(e.marca ?? '—')}${e.modelo ? '<br><small style="color:#94a3b8">' + this.esc(e.modelo) + '</small>' : ''}</td>
        <td>${this.esc(e.numeroSerie ?? '—')}</td>
        <td style="text-align:center;${bajo ? 'color:#dc2626;font-weight:700' : ''}">${e.cantidad}</td>
        <td style="color:${ec(e.estado)};font-weight:600">${el(e.estado)}</td>
      </tr>`;
    }).join('');

    this.imprimirHtml(`
      <h2>Reporte de Inventario · Equipos y Herramientas</h2>
      <div class="sub">${fecha} &nbsp;·&nbsp; ${eq.length} registros</div>
      <table>
        <thead><tr>
          <th>Código</th><th>Nombre</th><th>Clase</th><th>Marca / Modelo</th>
          <th>N° Serie</th><th>Cant.</th><th>Estado</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    `);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  private fechaHoy(): string {
    return new Date().toISOString().slice(0, 10);
  }

  private esc(s: string): string {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }

  private imprimirHtml(contenido: string): void {
    const html = `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Reporte E-zyro</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: Arial, sans-serif; font-size: 10px; color: #1e293b; padding: 16px 20px; }
  h2 { font-size: 14px; font-weight: 800; color: #0f172a; margin-bottom: 3px; }
  .sub { font-size: 9.5px; color: #64748b; margin-bottom: 14px; }
  .leyenda-rojo { margin-left: 14px; background: #fef2f2; color: #dc2626; padding: 2px 8px; border-radius: 4px; }
  table { width: 100%; border-collapse: collapse; }
  thead th {
    background: #1e3a5f; color: #fff; padding: 6px 8px;
    text-align: left; font-size: 9px; text-transform: uppercase; letter-spacing: .04em;
    white-space: nowrap;
  }
  tbody td { padding: 5px 8px; border-bottom: 1px solid #e2e8f0; font-size: 9.5px; vertical-align: middle; }
  tbody tr:nth-child(even):not([style*="background"]) { background: #f8fafc; }
  @page { size: A4 landscape; margin: 12mm 14mm; }
  @media print { body { padding: 0; } }
</style>
</head>
<body>
  ${contenido}
  <script>window.onload = function(){ setTimeout(function(){ window.print(); }, 250); };</script>
</body>
</html>`;

    const win = window.open('', '_blank', 'width=1000,height=720');
    if (win) { win.document.write(html); win.document.close(); }
  }
}

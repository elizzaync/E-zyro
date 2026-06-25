import { Component, Input, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MaterialLog, EquipoHerramienta } from '../../logistica.models';

// ── ARGB color palette ─────────────────────────────────────────────────────
const C = {
  NAV:    'FF1E3A5F',  // dark navy   — main headers
  NAV2:   'FF2D5B8E',  // medium navy — subheaders
  BLU:    'FF2563EB',  // blue accent
  BLIGHT: 'FFDBEAFE',  // light blue  — total rows
  GRN:    'FF16A34A',  // green
  GLIGHT: 'FFD1FAE5',  // light green
  AMB:    'FFD97706',  // amber
  ALIGHT: 'FFFEF3C7',  // light amber
  RED:    'FFDC2626',  // red
  RLIGHT: 'FFFEF2F2',  // light red   — alert rows
  PUR:    'FF7C3AED',  // purple
  PLIGHT: 'FFEDE9FE',  // light purple
  WHITE:  'FFFFFFFF',
  DARK:   'FF0F172A',  // main text
  GRAY:   'FF64748B',  // muted text
  LGRAY:  'FFF8FAFC',  // light gray bg
  ALT:    'FFF1F5F9',  // alternating row bg
  BRD:    'FFE2E8F0',  // border color
  BRD2:   'FFCBD5E1',  // darker border
} as const;

type Workbook   = import('exceljs').Workbook;
type Worksheet  = import('exceljs').Worksheet;
type Row        = import('exceljs').Row;
type Cell       = import('exceljs').Cell;
type BorderStyle = import('exceljs').BorderStyle;

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
  filtro   = 'todos';
  generando = false;

  get opcionesFiltro(): { valor: string; label: string }[] {
    if (this.tipo === 'materiales') return [
      { valor: 'todos',      label: 'Todos los materiales'  },
      { valor: 'activos',    label: 'Solo activos'          },
      { valor: 'inactivos',  label: 'Solo inactivos'        },
      { valor: 'stock_bajo', label: 'Solo con stock bajo'   },
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

  async generarReporte(): Promise<void> {
    this.generando = true;
    try {
      if (this.formato === 'excel') {
        if (this.tipo === 'materiales') await this.excelMateriales();
        else await this.excelEquipos();
      } else {
        if (this.tipo === 'materiales') this.pdfMateriales();
        else this.pdfEquipos();
      }
      this.cerrar.emit();
    } finally {
      this.generando = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXCEL MATERIALES — 5 hojas
  // ══════════════════════════════════════════════════════════════════════════
  private async excelMateriales(): Promise<void> {
    const { Workbook } = await import('exceljs');
    const mats = this.datosFiltrados as MaterialLog[];
    const wb   = new Workbook() as Workbook;
    wb.creator  = 'E-zyro';
    wb.created  = new Date();
    wb.modified = new Date();

    // ── Pre-cálculos ──────────────────────────────────────────────────────
    const activos      = mats.filter(m => m.activo);
    const inactivos    = mats.filter(m => !m.activo);
    const alerta       = mats.filter(m => m.stockMinimo > 0 && m.cantidad <= m.stockMinimo);
    const conPrecio    = mats.filter(m => m.precioCompra != null && m.precioCompra > 0);
    const sinStock     = mats.filter(m => m.activo && m.cantidad === 0);
    const totalUnid    = mats.reduce((s, m) => s + m.cantidad, 0);
    const valorTotal   = conPrecio.reduce((s, m) => s + (m.precioCompra! * m.cantidad), 0);
    const valorRepos   = alerta.filter(m => m.precioCompra != null)
                               .reduce((s, m) => s + (m.precioCompra! * (m.stockMinimo - m.cantidad)), 0);
    const categorias   = [...new Set(mats.map(m => m.categoria))].filter(Boolean);
    const marcas       = [...new Set(mats.filter(m => m.marca).map(m => m.marca!))];

    // ──────────────────────────────────────────────────────────────────────
    // HOJA 1 — PORTADA
    // ──────────────────────────────────────────────────────────────────────
    const wsP = wb.addWorksheet('Portada');
    wsP.views = [{ showGridLines: false }];
    wsP.getColumn('A').width = 4;
    wsP.getColumn('B').width = 28;
    wsP.getColumn('C').width = 20;
    wsP.getColumn('D').width = 5;
    wsP.getColumn('E').width = 28;
    wsP.getColumn('F').width = 20;
    wsP.getColumn('G').width = 5;
    wsP.getColumn('H').width = 28;
    wsP.getColumn('I').width = 20;

    // Título principal
    wsP.mergeCells('A1:I1'); wsP.getRow(1).height = 52;
    this.cell(wsP, 'A1', 'REPORTE DE INVENTARIO · MATERIALES', { sz:22, bold:true, color:C.WHITE }, C.NAV, 'center', 'middle');
    wsP.mergeCells('A2:I2'); wsP.getRow(2).height = 22;
    const fecha = new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' });
    this.cell(wsP, 'A2', `E-zyro — Sistema de Gestión de Inventarios  ·  Generado: ${fecha}`, { sz:11, color:C.WHITE }, C.NAV2, 'center', 'middle');
    wsP.getRow(3).height = 14;

    // ── Sección: Resumen General ──
    wsP.mergeCells('A4:I4'); wsP.getRow(4).height = 26;
    this.cell(wsP, 'A4', '  RESUMEN GENERAL', { sz:12, bold:true, color:C.WHITE }, C.NAV, 'left', 'middle');
    wsP.getRow(5).height = 12;

    const kpis = [
      ['Total de materiales', mats.length,          'Materiales activos',    activos.length,    'Materiales inactivos', inactivos.length],
      ['Con stock disponible', activos.filter(m => m.cantidad > 0).length, 'Sin stock (activos)', sinStock.length, 'Con stock bajo', alerta.length],
      ['Categorías',          categorias.length,    'Marcas registradas',    marcas.length,     'Total unidades',       totalUnid],
    ] as [string, number, string, number, string, number][];

    const alertaCols = new Set(['Con stock bajo', 'Sin stock (activos)']);
    for (const [r, kpiRow] of kpis.entries()) {
      const rn = 6 + r; wsP.getRow(rn).height = 22;
      wsP.mergeCells(`B${rn}:C${rn}`);
      wsP.mergeCells(`E${rn}:F${rn}`);
      wsP.mergeCells(`H${rn}:I${rn}`);
      this.cell(wsP, `B${rn}`, kpiRow[0], { sz:10, color:C.GRAY });
      this.kpiValue(wsP, `C${rn}`, kpiRow[1], alertaCols.has(kpiRow[0]) ? C.RED : C.DARK);
      this.cell(wsP, `E${rn}`, kpiRow[2], { sz:10, color:C.GRAY });
      this.kpiValue(wsP, `F${rn}`, kpiRow[3], alertaCols.has(kpiRow[2]) ? C.RED : C.DARK);
      this.cell(wsP, `H${rn}`, kpiRow[4], { sz:10, color:C.GRAY });
      this.kpiValue(wsP, `I${rn}`, kpiRow[5], alertaCols.has(kpiRow[4]) ? C.RED : C.DARK);
    }
    wsP.getRow(9).height = 14;

    // ── Sección: Indicadores Financieros ──
    wsP.mergeCells('A10:I10'); wsP.getRow(10).height = 26;
    this.cell(wsP, 'A10', '  INDICADORES FINANCIEROS', { sz:12, bold:true, color:C.WHITE }, C.NAV, 'left', 'middle');

    const financieros: [string, string | number, string][] = [
      ['Total de unidades en inventario',         totalUnid,                   'numeric'],
      ['Materiales con precio registrado',         conPrecio.length,            'numeric'],
      ['Valor total estimado del inventario',      valorTotal,                  'currency'],
      ['Costo estimado de reposición (stock bajo)',valorRepos,                  'currency'],
      ['Costo promedio por material',             conPrecio.length ? valorTotal / conPrecio.length : 0, 'currency'],
    ];
    for (const [i, [label, val, fmt]] of financieros.entries()) {
      const rn = 11 + i; wsP.getRow(rn).height = 22;
      wsP.mergeCells(`B${rn}:G${rn}`);
      wsP.mergeCells(`H${rn}:I${rn}`);
      this.cell(wsP, `B${rn}`, label, { sz:10.5, color:C.DARK, bold: i === 2 || i === 3 });
      const vc = wsP.getCell(`H${rn}`);
      vc.value  = typeof val === 'number' ? val : val;
      vc.font   = { name:'Calibri', size:12, bold:true, color:{ argb: i === 2 ? C.GRN : i === 3 ? C.AMB : C.DARK } };
      vc.alignment = { horizontal:'right', vertical:'middle' };
      if (fmt === 'currency') vc.numFmt = '"S/"#,##0.00';
      else vc.numFmt = '#,##0';
      wsP.getRow(rn).getCell('B').fill = { type:'pattern', pattern:'solid', fgColor:{ argb: i % 2 === 0 ? C.LGRAY : C.WHITE } };
      wsP.getRow(rn).getCell('H').fill = { type:'pattern', pattern:'solid', fgColor:{ argb: i % 2 === 0 ? C.LGRAY : C.WHITE } };
    }
    wsP.getRow(16).height = 14;

    // ── Sección: Estado del Inventario ──
    wsP.mergeCells('A17:I17'); wsP.getRow(17).height = 26;
    this.cell(wsP, 'A17', '  ESTADO DEL INVENTARIO', { sz:12, bold:true, color:C.WHITE }, C.NAV, 'left', 'middle');
    const estHdrs = ['', 'Estado', '', '', 'Materiales', '', '', 'Unidades', ''];
    ['B','C','D','E','F','G','H','I'].forEach((col,i) => {
      if (estHdrs[i+1]) this.cell(wsP, `${col}18`, estHdrs[i+1], { sz:9, bold:true, color:C.WHITE }, C.NAV2, 'center', 'middle');
    });
    wsP.getRow(18).height = 18;
    const estados: [string, number, number, string][] = [
      ['Con stock OK',   activos.filter(m => m.cantidad > m.stockMinimo || m.stockMinimo === 0).length, activos.filter(m => m.cantidad > m.stockMinimo || m.stockMinimo === 0).reduce((s,m)=>s+m.cantidad,0), C.GRN ],
      ['Con stock bajo', alerta.length, alerta.reduce((s,m)=>s+m.cantidad,0), C.RED ],
      ['Sin stock',      sinStock.length, 0, C.AMB ],
      ['Inactivos',      inactivos.length, inactivos.reduce((s,m)=>s+m.cantidad,0), C.GRAY],
    ];
    for (const [i, [label, cnt, unid, color]] of estados.entries()) {
      const rn = 19 + i; wsP.getRow(rn).height = 20;
      wsP.mergeCells(`B${rn}:D${rn}`); wsP.mergeCells(`E${rn}:G${rn}`); wsP.mergeCells(`H${rn}:I${rn}`);
      const bg = i % 2 === 0 ? C.LGRAY : C.WHITE;
      this.cell(wsP, `B${rn}`, label, { sz:10.5, bold:true, color }, bg);
      const nc = wsP.getCell(`E${rn}`);
      nc.value = cnt; nc.font = { name:'Calibri', size:11, bold:true, color:{ argb:color } };
      nc.alignment = { horizontal:'center', vertical:'middle' }; nc.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      nc.numFmt = '#,##0';
      const uc = wsP.getCell(`H${rn}`);
      uc.value = unid; uc.font = { name:'Calibri', size:11, color:{ argb:C.DARK } };
      uc.alignment = { horizontal:'right', vertical:'middle' }; uc.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      uc.numFmt = '#,##0';
    }

    // ── Footer ──
    wsP.getRow(24).height = 10;
    wsP.mergeCells('A25:I25'); wsP.getRow(25).height = 16;
    this.cell(wsP, 'A25', `Este reporte fue generado automáticamente por E-zyro el ${fecha}. Los valores de inventario son estimados basados en los precios de compra registrados.`, { sz:8.5, italic:true, color:C.GRAY }, C.WHITE, 'center', 'middle');

    // ──────────────────────────────────────────────────────────────────────
    // HOJA 2 — INVENTARIO COMPLETO
    // ──────────────────────────────────────────────────────────────────────
    const wsI = wb.addWorksheet('Inventario Completo');
    wsI.views = [{ state:'frozen', xSplit:0, ySplit:3 }];
    const colsI = [
      { key:'cod',   width:12  }, { key:'nom',   width:40  }, { key:'cat',   width:22  },
      { key:'unid',  width:10  }, { key:'cant',  width:11  }, { key:'min',   width:11  },
      { key:'dif',   width:11  }, { key:'cob',   width:11  }, { key:'est',   width:14  },
      { key:'marca', width:18  }, { key:'serie', width:17  }, { key:'alm',   width:22  },
      { key:'costo', width:15  }, { key:'valor', width:15  }, { key:'activo',width:11  },
    ];
    wsI.columns = colsI;

    // Título
    wsI.mergeCells('A1:O1'); wsI.getRow(1).height = 34;
    this.cell(wsI, 'A1', 'INVENTARIO COMPLETO DE MATERIALES', { sz:15, bold:true, color:C.WHITE }, C.NAV, 'center', 'middle');

    // Cabecera
    wsI.getRow(2).height = 12;
    wsI.mergeCells('A2:O2');
    this.cell(wsI, 'A2', `Reporte generado: ${fecha}  ·  Total: ${mats.length} materiales  ·  Filtro: ${this.filtroLabel()}`, { sz:9, italic:true, color:C.GRAY }, C.LGRAY, 'center', 'middle');

    const hdrs = ['Código','Nombre','Categoría','Unidad','Cantidad','Stk. Mín.','Diferencia','Cobertura','Estado Stock','Marca','N° Serie','Almacén / Zona','Costo Unit. (S/)','Valor Stock (S/)','Estado'];
    wsI.getRow(3).height = 28;
    const hr = wsI.getRow(3);
    hdrs.forEach((h, i) => {
      const cell = hr.getCell(i + 1);
      cell.value = h;
      cell.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
      cell.font  = { name:'Calibri', size:10, bold:true, color:{ argb:C.WHITE } };
      cell.alignment = { vertical:'middle', horizontal: i >= 4 && i <= 8 || i === 12 || i === 13 ? 'center' : 'left', wrapText:true };
      this.thinBorder(cell);
    });
    wsI.autoFilter = 'A3:O3';

    // Filas de datos
    for (const [idx, m] of mats.entries()) {
      const isAlt  = idx % 2 === 1;
      const isAlert = m.stockMinimo > 0 && m.cantidad <= m.stockMinimo;
      const bg = isAlert ? C.RLIGHT : isAlt ? C.ALT : C.WHITE;
      const dif = m.stockMinimo > 0 ? m.cantidad - m.stockMinimo : null;
      const cob = m.stockMinimo > 0 ? m.cantidad / m.stockMinimo : null;
      const estStock = m.stockMinimo === 0 ? '— Sin mínimo' : m.cantidad === 0 ? '⛔ Sin stock' : isAlert ? '⚠ Stock bajo' : '✓ OK';
      const estColor = m.stockMinimo === 0 ? C.GRAY : m.cantidad === 0 ? C.RED : isAlert ? C.AMB : C.GRN;
      const vals = [m.codigo, m.nombre, m.categoria, m.unidad ?? '', m.cantidad, m.stockMinimo || null, dif, cob, estStock, m.marca ?? '', m.serie ?? '', m.almacen, m.precioCompra ?? null, m.precioCompra != null ? +(m.precioCompra * m.cantidad) : null, m.activo ? 'Activo' : 'Inactivo'];

      const row = wsI.addRow(vals); row.height = 18;
      row.eachCell({ includeEmpty:true }, (cell, cn) => {
        cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
        cell.font = { name:'Calibri', size:9.5, color:{ argb: cn === 9 ? estColor : isAlert && (cn === 5 || cn === 6) ? C.RED : C.DARK } };
        if (cn === 9) cell.font.bold = true;
        cell.alignment = { vertical:'middle', horizontal: cn >= 5 && cn <= 9 || cn === 13 || cn === 14 ? 'center' : 'left' };
        this.thinBorder(cell);
        if (cn === 7 && dif !== null) cell.font.color = { argb: dif < 0 ? C.RED : dif === 0 ? C.AMB : C.GRN };
        if (cn === 8 && cob !== null) { cell.numFmt = '0%'; cell.font.color = { argb: cob < 0.5 ? C.RED : cob < 1 ? C.AMB : C.GRN }; }
        if (cn === 13) cell.numFmt = '"S/"#,##0.00';
        if (cn === 14 && cell.value != null) cell.numFmt = '"S/"#,##0.00';
        if (cn === 5 || cn === 6 || cn === 7) cell.numFmt = '#,##0';
      });
    }

    // Fila de totales
    const totRow = wsI.addRow(['', 'TOTALES', '', '', totalUnid, '', '', '', '', '', '', '', '', valorTotal > 0 ? +valorTotal.toFixed(2) : null, '']);
    totRow.height = 22;
    totRow.eachCell({ includeEmpty:true }, (cell, cn) => {
      cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.BLIGHT } };
      cell.font = { name:'Calibri', size:10, bold:true, color:{ argb:C.NAV } };
      cell.alignment = { vertical:'middle', horizontal: cn >= 5 && cn <= 9 || cn === 14 ? 'center' : 'left' };
      this.thinBorder(cell);
      if (cn === 5) cell.numFmt = '#,##0';
      if (cn === 14 && cell.value) cell.numFmt = '"S/"#,##0.00';
    });

    // ──────────────────────────────────────────────────────────────────────
    // HOJA 3 — RESUMEN POR CATEGORÍA
    // ──────────────────────────────────────────────────────────────────────
    const wsC = wb.addWorksheet('Por Categoría');
    wsC.views = [{ state:'frozen', xSplit:0, ySplit:3 }];
    wsC.columns = [
      {width:28},{width:14},{width:13},{width:14},{width:13},{width:18},{width:13},{width:13},{width:15},
    ];

    wsC.mergeCells('A1:I1'); wsC.getRow(1).height = 34;
    this.cell(wsC, 'A1', 'RESUMEN POR CATEGORÍA', { sz:15, bold:true, color:C.WHITE }, C.NAV, 'center', 'middle');
    wsC.mergeCells('A2:I2'); wsC.getRow(2).height = 14;
    this.cell(wsC, 'A2', `Distribución del inventario agrupada por categoría  ·  ${categorias.length} categorías`, { sz:9, italic:true, color:C.GRAY }, C.LGRAY, 'center', 'middle');

    const catHdrs = ['Categoría','N° Materiales','% Materiales','Unidades','Con Precio','Valor Est. (S/)','% del Valor','Stock Bajo','Sin Stock'];
    wsC.getRow(3).height = 26;
    catHdrs.forEach((h, i) => {
      const cell = wsC.getRow(3).getCell(i + 1);
      cell.value = h;
      cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
      cell.font = { name:'Calibri', size:9.5, bold:true, color:{ argb:C.WHITE } };
      cell.alignment = { vertical:'middle', horizontal: i === 0 ? 'left' : 'center', wrapText:true };
      this.thinBorder(cell);
    });
    wsC.autoFilter = 'A3:I3';

    // Datos por categoría
    const catMap = new Map<string, MaterialLog[]>();
    for (const m of mats) {
      const k = m.categoria || 'Sin categoría';
      if (!catMap.has(k)) catMap.set(k, []);
      catMap.get(k)!.push(m);
    }
    const catRows = [...catMap.entries()].map(([cat, items]) => ({
      cat,
      n:     items.length,
      unid:  items.reduce((s,m)=>s+m.cantidad,0),
      cp:    items.filter(m=>m.precioCompra != null).length,
      val:   items.reduce((s,m)=>s+(m.precioCompra??0)*m.cantidad,0),
      bajo:  items.filter(m=>m.stockMinimo>0&&m.cantidad<=m.stockMinimo).length,
      sinst: items.filter(m=>m.cantidad===0&&m.activo).length,
    })).sort((a,b)=>b.val-a.val);

    for (const [idx, cr] of catRows.entries()) {
      const bg = idx % 2 === 1 ? C.ALT : C.WHITE;
      const row = wsC.addRow([cr.cat, cr.n, cr.n / mats.length, cr.unid, cr.cp, cr.val || null, cr.val / valorTotal || null, cr.bajo || null, cr.sinst || null]);
      row.height = 18;
      row.eachCell({ includeEmpty:true }, (cell, cn) => {
        cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
        cell.font = { name:'Calibri', size:9.5, color:{ argb: cn===8&&cr.bajo>0 ? C.RED : cn===9&&cr.sinst>0 ? C.AMB : C.DARK } };
        if (cn===8&&cr.bajo>0) cell.font.bold = true;
        cell.alignment = { vertical:'middle', horizontal: cn===1 ? 'left' : 'center' };
        this.thinBorder(cell);
        if (cn===3||cn===7||cn===8||cn===9) cell.numFmt = '#,##0';
        if (cn===2||cn===6) cell.numFmt = '0.0%';
        if (cn===5) cell.numFmt = '"S/"#,##0.00';
      });
    }

    // Totales
    const ctot = wsC.addRow(['TOTAL GENERAL', mats.length, 1, totalUnid, conPrecio.length, valorTotal > 0 ? +valorTotal.toFixed(2) : null, 1, alerta.length, sinStock.length]);
    ctot.height = 22;
    ctot.eachCell({ includeEmpty:true }, (cell, cn) => {
      cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.BLIGHT } };
      cell.font = { name:'Calibri', size:10, bold:true, color:{ argb:C.NAV } };
      cell.alignment = { vertical:'middle', horizontal: cn===1 ? 'left' : 'center' };
      this.thinBorder(cell);
      if (cn===3||cn===7||cn===8||cn===9) cell.numFmt = '#,##0';
      if (cn===2||cn===6) cell.numFmt = '0.0%';
      if (cn===5) cell.numFmt = '"S/"#,##0.00';
    });

    // ──────────────────────────────────────────────────────────────────────
    // HOJA 4 — VALORIZACIÓN
    // ──────────────────────────────────────────────────────────────────────
    const wsV = wb.addWorksheet('Valorización');
    wsV.getColumn('A').width = 4; wsV.getColumn('B').width = 38; wsV.getColumn('C').width = 18;
    wsV.getColumn('D').width = 5; wsV.getColumn('E').width = 14; wsV.getColumn('F').width = 14; wsV.getColumn('G').width = 14;

    wsV.mergeCells('A1:G1'); wsV.getRow(1).height = 34;
    this.cell(wsV, 'A1', 'VALORIZACIÓN DEL INVENTARIO', { sz:15, bold:true, color:C.WHITE }, C.NAV, 'center', 'middle');
    wsV.getRow(2).height = 12;

    // Resumen ejecutivo
    wsV.mergeCells('A3:G3'); wsV.getRow(3).height = 24;
    this.cell(wsV, 'A3', '  RESUMEN FINANCIERO', { sz:11, bold:true, color:C.WHITE }, C.NAV2, 'left', 'middle');

    const finItems: [string, number, string][] = [
      ['Materiales con precio registrado',          conPrecio.length,                              '#,##0'],
      ['Total unidades en inventario',              totalUnid,                                     '#,##0'],
      ['Valor total del inventario (estimado)',     +valorTotal.toFixed(2),                        '"S/"#,##0.00'],
      ['Costo promedio por material',               conPrecio.length ? +(valorTotal/conPrecio.length).toFixed(2) : 0, '"S/"#,##0.00'],
      ['Costo estimado de reposición stock bajo',   +valorRepos.toFixed(2),                        '"S/"#,##0.00'],
      ['Materiales sin precio registrado',          mats.length - conPrecio.length,               '#,##0'],
    ];
    for (const [i, [lbl, val, fmt]] of finItems.entries()) {
      const rn = 4 + i; wsV.getRow(rn).height = 20;
      wsV.mergeCells(`B${rn}:E${rn}`);
      const bg = i % 2 === 0 ? C.LGRAY : C.WHITE;
      this.cell(wsV, `B${rn}`, lbl, { sz:10, color:C.DARK, bold: i===2||i===4 }, bg, 'left', 'middle');
      const vc = wsV.getCell(`F${rn}`);
      vc.value = val; vc.numFmt = fmt;
      vc.font  = { name:'Calibri', size:11, bold:true, color:{ argb: i===2 ? C.GRN : i===4 ? C.AMB : C.DARK } };
      vc.alignment = { horizontal:'right', vertical:'middle' };
      vc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      this.thinBorder(vc);
    }

    // Top 20 por valor de inventario
    wsV.getRow(11).height = 14;
    wsV.mergeCells('A12:G12'); wsV.getRow(12).height = 24;
    this.cell(wsV, 'A12', '  TOP 20 — MATERIALES POR VALOR DE INVENTARIO', { sz:11, bold:true, color:C.WHITE }, C.NAV2, 'left', 'middle');

    const tHdrs = ['N°','Nombre del Material','Categoría','Cant.','Costo Unit. (S/)','Valor Total (S/)','% del Inv.'];
    wsV.getRow(13).height = 24;
    tHdrs.forEach((h, i) => {
      const cell = wsV.getRow(13).getCell(['A','B','C','D','E','F','G'][i]);
      cell.value = h;
      cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
      cell.font = { name:'Calibri', size:9.5, bold:true, color:{ argb:C.WHITE } };
      cell.alignment = { vertical:'middle', horizontal: i === 1 || i === 2 ? 'left' : 'center' };
      this.thinBorder(cell);
    });

    const top20 = [...conPrecio].sort((a,b) => (b.precioCompra!*b.cantidad) - (a.precioCompra!*a.cantidad)).slice(0, 20);
    for (const [i, m] of top20.entries()) {
      const val = +(m.precioCompra! * m.cantidad).toFixed(2);
      const pct = valorTotal > 0 ? val / valorTotal : 0;
      const bg  = i % 2 === 1 ? C.ALT : C.WHITE;
      const row = wsV.addRow([i+1, m.nombre, m.categoria, m.cantidad, m.precioCompra, val, pct]);
      row.height = 18;
      row.eachCell((cell, cn) => {
        cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
        cell.font = { name:'Calibri', size:9.5, color:{ argb:C.DARK } };
        cell.alignment = { vertical:'middle', horizontal: cn===2||cn===3 ? 'left' : 'center' };
        this.thinBorder(cell);
        if (cn===5||cn===6) cell.numFmt = '"S/"#,##0.00';
        if (cn===4) cell.numFmt = '#,##0';
        if (cn===7) cell.numFmt = '0.0%';
      });
    }

    // Proyección reposición stock bajo
    const repItems = alerta.filter(m => m.precioCompra != null).sort((a,b) => (b.stockMinimo-b.cantidad) - (a.stockMinimo-a.cantidad));
    if (repItems.length > 0) {
      const rStart = 14 + top20.length + 2;
      wsV.getRow(rStart - 1).height = 14;
      wsV.mergeCells(`A${rStart}:G${rStart}`); wsV.getRow(rStart).height = 24;
      this.cell(wsV, `A${rStart}`, '  PROYECCIÓN DE REPOSICIÓN — MATERIALES CON STOCK BAJO', { sz:11, bold:true, color:C.WHITE }, C.NAV2, 'left', 'middle');
      const rpHdrs = ['N°','Nombre del Material','Categoría','Stock Actual','Stock Mínimo','Unid. a Reponer','Costo Rep. (S/)'];
      wsV.getRow(rStart + 1).height = 24;
      rpHdrs.forEach((h, i) => {
        const cell = wsV.getRow(rStart + 1).getCell(['A','B','C','D','E','F','G'][i]);
        cell.value = h;
        cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.AMB } };
        cell.font = { name:'Calibri', size:9.5, bold:true, color:{ argb:C.WHITE } };
        cell.alignment = { vertical:'middle', horizontal: i===1||i===2 ? 'left' : 'center' };
        this.thinBorder(cell);
      });
      for (const [i, m] of repItems.slice(0, 30).entries()) {
        const unidRep = m.stockMinimo - m.cantidad;
        const costoRep = +(unidRep * m.precioCompra!).toFixed(2);
        const bg = i % 2 === 1 ? C.ALT : C.WHITE;
        const row = wsV.addRow([i+1, m.nombre, m.categoria, m.cantidad, m.stockMinimo, unidRep, costoRep]);
        row.height = 18;
        row.eachCell((cell, cn) => {
          cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
          cell.font = { name:'Calibri', size:9.5, color:{ argb: cn===4&&m.cantidad===0 ? C.RED : C.DARK } };
          cell.alignment = { vertical:'middle', horizontal: cn===2||cn===3 ? 'left' : 'center' };
          this.thinBorder(cell);
          if (cn===4||cn===5||cn===6) cell.numFmt = '#,##0';
          if (cn===7) cell.numFmt = '"S/"#,##0.00';
        });
      }
    }

    // ──────────────────────────────────────────────────────────────────────
    // HOJA 5 — ALERTAS DE STOCK (solo si hay alertas)
    // ──────────────────────────────────────────────────────────────────────
    if (alerta.length > 0) {
      const wsA = wb.addWorksheet('⚠ Alertas Stock');
      wsA.views = [{ state:'frozen', xSplit:0, ySplit:3 }];
      wsA.columns = [{width:12},{width:12},{width:40},{width:22},{width:13},{width:13},{width:11},{width:13},{width:15},{width:16}];

      wsA.mergeCells('A1:J1'); wsA.getRow(1).height = 34;
      this.cell(wsA, 'A1', `⚠  ALERTAS DE STOCK — ${alerta.length} MATERIAL(ES) POR DEBAJO DEL MÍNIMO`, { sz:14, bold:true, color:C.WHITE }, 'FFBE123C', 'center', 'middle');
      wsA.mergeCells('A2:J2'); wsA.getRow(2).height = 14;
      this.cell(wsA, 'A2', 'Materiales que requieren reposición urgente. Ordenados por severidad del déficit.', { sz:9, italic:true, color:C.GRAY }, C.LGRAY, 'center', 'middle');

      const aHdrs = ['Prioridad','Código','Nombre','Categoría','Actual','Mínimo','Déficit','Cobertura','Costo Unit.','Costo Repos.'];
      wsA.getRow(3).height = 26;
      aHdrs.forEach((h,i) => {
        const cell = wsA.getRow(3).getCell(i+1);
        cell.value = h;
        cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:'FFBE123C' } };
        cell.font = { name:'Calibri', size:10, bold:true, color:{ argb:C.WHITE } };
        cell.alignment = { vertical:'middle', horizontal: i<=1||i===3 ? 'center' : i===2 ? 'left' : 'center', wrapText:true };
        this.thinBorder(cell);
      });
      wsA.autoFilter = 'A3:J3';

      const sortedAlerta = [...alerta].sort((a,b) => {
        const da = a.stockMinimo > 0 ? (a.stockMinimo - a.cantidad) / a.stockMinimo : 0;
        const db = b.stockMinimo > 0 ? (b.stockMinimo - b.cantidad) / b.stockMinimo : 0;
        return db - da;
      });

      for (const [idx, m] of sortedAlerta.entries()) {
        const cob = m.stockMinimo > 0 ? m.cantidad / m.stockMinimo : 0;
        const def = m.stockMinimo - m.cantidad;
        const prio = m.cantidad === 0 ? '🔴 CRÍTICO' : cob < 0.5 ? '🟠 ALTO' : '🟡 MEDIO';
        const prioColor = m.cantidad === 0 ? C.RED : cob < 0.5 ? C.AMB : 'FFD97706';
        const bg = idx % 2 === 1 ? C.RLIGHT : C.WHITE;
        const costoRep = m.precioCompra != null ? +(m.precioCompra * def).toFixed(2) : null;
        const row = wsA.addRow([prio, m.codigo, m.nombre, m.categoria, m.cantidad, m.stockMinimo, def, cob, m.precioCompra ?? null, costoRep]);
        row.height = 20;
        row.eachCell({ includeEmpty:true }, (cell, cn) => {
          cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
          cell.font = { name:'Calibri', size:9.5, color:{ argb: cn===1 ? prioColor : cn===5 ? (m.cantidad===0?C.RED:C.AMB) : C.DARK } };
          if (cn===1) cell.font.bold = true;
          cell.alignment = { vertical:'middle', horizontal: cn===3 ? 'left' : 'center' };
          this.thinBorder(cell);
          if (cn===5||cn===6||cn===7) cell.numFmt = '#,##0';
          if (cn===8) cell.numFmt = '0%';
          if (cn===9||cn===10) cell.numFmt = '"S/"#,##0.00';
        });
      }

      // Resumen alertas
      const totRep = sortedAlerta.filter(m=>m.precioCompra!=null).reduce((s,m)=>s+(m.precioCompra!*(m.stockMinimo-m.cantidad)),0);
      wsA.addRow([]);
      const aResRow = wsA.addRow(['', 'TOTALES', '', '', alerta.reduce((s,m)=>s+m.cantidad,0), alerta.reduce((s,m)=>s+m.stockMinimo,0), alerta.reduce((s,m)=>s+(m.stockMinimo-m.cantidad),0), '', '', totRep > 0 ? +totRep.toFixed(2) : null]);
      aResRow.height = 22;
      aResRow.eachCell({ includeEmpty:true }, (cell, cn) => {
        cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.BLIGHT } };
        cell.font = { name:'Calibri', size:10, bold:true, color:{ argb:C.NAV } };
        cell.alignment = { vertical:'middle', horizontal: cn===2 ? 'left' : 'center' };
        this.thinBorder(cell);
        if (cn===5||cn===6||cn===7) cell.numFmt = '#,##0';
        if (cn===10&&cell.value) cell.numFmt = '"S/"#,##0.00';
      });
    }

    this.descargar(await wb.xlsx.writeBuffer(), `Materiales_${this.fechaHoy()}.xlsx`);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXCEL EQUIPOS — 4 hojas
  // ══════════════════════════════════════════════════════════════════════════
  private async excelEquipos(): Promise<void> {
    const { Workbook } = await import('exceljs');
    const eq  = this.datosFiltrados as EquipoHerramienta[];
    const wb  = new Workbook() as Workbook;
    wb.creator = 'E-zyro'; wb.created = new Date();
    const fecha = new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' });
    const cl = (c: string) => c === 'equipo_tecnologico' ? 'Eq. TI' : c === 'herramienta' ? 'Herramienta' : 'Equipo';
    const el = (s: string) => ({ operativo:'Operativo', en_mantenimiento:'En mantenimiento', fuera_de_servicio:'Fuera de servicio', baja:'De baja' }[s] ?? s);
    const ec = (s: string) => ({ operativo:C.GRN, en_mantenimiento:C.AMB, fuera_de_servicio:C.RED, baja:C.GRAY }[s] ?? C.DARK);

    const operativos = eq.filter(e => e.estado === 'operativo');
    const mantenimiento = eq.filter(e => e.requiereMantenimiento);
    const conPrecio = eq.filter(e => e.precioCompra != null);
    const valorTotal = conPrecio.reduce((s,e) => s + (e.precioCompra! * e.cantidad), 0);
    const totalUnid  = eq.reduce((s,e) => s + e.cantidad, 0);

    // ── PORTADA ──────────────────────────────────────────────────────────
    const wsP = wb.addWorksheet('Portada');
    wsP.views = [{ showGridLines:false }];
    ['A','B','C','D','E','F','G','H','I'].forEach((c,i) => { wsP.getColumn(c).width = [4,28,20,5,28,20,5,28,20][i]; });

    wsP.mergeCells('A1:I1'); wsP.getRow(1).height = 52;
    this.cell(wsP, 'A1', 'REPORTE DE INVENTARIO · EQUIPOS Y HERRAMIENTAS', { sz:20, bold:true, color:C.WHITE }, C.NAV, 'center', 'middle');
    wsP.mergeCells('A2:I2'); wsP.getRow(2).height = 22;
    this.cell(wsP, 'A2', `E-zyro — Sistema de Gestión de Inventarios  ·  Generado: ${fecha}`, { sz:11, color:C.WHITE }, C.NAV2, 'center', 'middle');
    wsP.getRow(3).height = 14;

    wsP.mergeCells('A4:I4'); wsP.getRow(4).height = 26;
    this.cell(wsP, 'A4', '  RESUMEN GENERAL', { sz:12, bold:true, color:C.WHITE }, C.NAV, 'left', 'middle');
    const eqs2 = eq.filter(e => e.clase !== 'herramienta');
    const herr = eq.filter(e => e.clase === 'herramienta');
    const eKpis: [string, number, string, number, string, number][] = [
      ['Total registros', eq.length, 'Equipos', eqs2.length, 'Herramientas', herr.length],
      ['Operativos', operativos.length, 'En mantenimiento', eq.filter(e=>e.estado==='en_mantenimiento').length, 'Fuera de servicio', eq.filter(e=>e.estado==='fuera_de_servicio').length],
      ['Con mantenimiento prog.', mantenimiento.length, 'Total unidades', totalUnid, 'Con precio registrado', conPrecio.length],
    ];
    for (const [r, row] of eKpis.entries()) {
      const rn = 5 + r; wsP.getRow(rn).height = 22;
      wsP.mergeCells(`B${rn}:C${rn}`); wsP.mergeCells(`E${rn}:F${rn}`); wsP.mergeCells(`H${rn}:I${rn}`);
      const alertSet = new Set(['En mantenimiento','Fuera de servicio']);
      this.cell(wsP, `B${rn}`, row[0], { sz:10, color:C.GRAY });
      this.kpiValue(wsP, `C${rn}`, row[1], C.DARK);
      this.cell(wsP, `E${rn}`, row[2], { sz:10, color:C.GRAY });
      this.kpiValue(wsP, `F${rn}`, row[3], alertSet.has(row[2]) ? C.AMB : C.DARK);
      this.cell(wsP, `H${rn}`, row[4], { sz:10, color:C.GRAY });
      this.kpiValue(wsP, `I${rn}`, row[5], alertSet.has(row[4]) ? C.RED : C.DARK);
    }
    wsP.getRow(8).height = 14;

    wsP.mergeCells('A9:I9'); wsP.getRow(9).height = 26;
    this.cell(wsP, 'A9', '  INDICADORES FINANCIEROS', { sz:12, bold:true, color:C.WHITE }, C.NAV, 'left', 'middle');
    const eFin: [string, number, string][] = [
      ['Total de unidades en inventario',      totalUnid,                                              '#,##0'],
      ['Equipos con precio registrado',        conPrecio.length,                                       '#,##0'],
      ['Valor total estimado del inventario',  +valorTotal.toFixed(2),                                 '"S/"#,##0.00'],
      ['Costo promedio por equipo/herramienta',conPrecio.length ? +(valorTotal/conPrecio.length).toFixed(2) : 0, '"S/"#,##0.00'],
    ];
    for (const [i, [lbl,val,fmt]] of eFin.entries()) {
      const rn = 10 + i; wsP.getRow(rn).height = 22;
      wsP.mergeCells(`B${rn}:G${rn}`); wsP.mergeCells(`H${rn}:I${rn}`);
      const bg = i%2===0 ? C.LGRAY : C.WHITE;
      this.cell(wsP, `B${rn}`, lbl, { sz:10, color:C.DARK, bold:i===2 }, bg, 'left', 'middle');
      const vc = wsP.getCell(`H${rn}`);
      vc.value = val; vc.numFmt = fmt;
      vc.font = { name:'Calibri', size:12, bold:true, color:{ argb:i===2?C.GRN:C.DARK } };
      vc.alignment = { horizontal:'right', vertical:'middle' };
      vc.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
    }

    // ── INVENTARIO COMPLETO ───────────────────────────────────────────────
    const wsI = wb.addWorksheet('Inventario Completo');
    wsI.views = [{ state:'frozen', xSplit:0, ySplit:3 }];
    wsI.columns = [{width:11},{width:38},{width:13},{width:22},{width:17},{width:17},{width:17},{width:11},{width:11},{width:14},{width:18},{width:20},{width:22},{width:19}];

    wsI.mergeCells('A1:N1'); wsI.getRow(1).height = 34;
    this.cell(wsI, 'A1', 'INVENTARIO COMPLETO — EQUIPOS Y HERRAMIENTAS', { sz:15, bold:true, color:C.WHITE }, C.NAV, 'center', 'middle');
    wsI.mergeCells('A2:N2'); wsI.getRow(2).height = 14;
    this.cell(wsI, 'A2', `${fecha}  ·  Total: ${eq.length} registros  ·  Filtro: ${this.filtroLabel()}`, { sz:9, italic:true, color:C.GRAY }, C.LGRAY, 'center', 'middle');

    const iHdrs = ['Código','Nombre','Clase','Categoría','Marca','Modelo','N° Serie','Cantidad','Stk. Mín.','Costo (S/)','Estado','Ubicación','Observaciones','Próx. Mantenimiento'];
    wsI.getRow(3).height = 26;
    iHdrs.forEach((h,i) => {
      const cell = wsI.getRow(3).getCell(i+1);
      cell.value = h; cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
      cell.font = { name:'Calibri', size:9.5, bold:true, color:{ argb:C.WHITE } };
      cell.alignment = { vertical:'middle', horizontal: i<=1||i===3||i===4||i===5||i===6||i===11||i===12||i===13 ? 'left' : 'center', wrapText:true };
      this.thinBorder(cell);
    });
    wsI.autoFilter = 'A3:N3';

    for (const [idx, e] of eq.entries()) {
      const bg = idx%2===1 ? C.ALT : C.WHITE;
      const ecol = ec(e.estado);
      const row = wsI.addRow([e.codigo, e.nombre, cl(e.clase), e.categoria, e.marca??'', e.modelo??'', e.numeroSerie??'', e.cantidad, e.stockMinimo||null, e.precioCompra??null, el(e.estado), e.ubicacion??'', e.observaciones??'', e.proximaFechaMantenimiento??'']);
      row.height = 18;
      row.eachCell({ includeEmpty:true }, (cell, cn) => {
        cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
        cell.font = { name:'Calibri', size:9.5, color:{ argb: cn===11 ? ecol : C.DARK } };
        if (cn===11) cell.font.bold = true;
        cell.alignment = { vertical:'middle', horizontal: cn===2||cn===4||cn===5||cn===6||cn===7||cn===12||cn===13||cn===14 ? 'left' : 'center' };
        this.thinBorder(cell);
        if (cn===10) cell.numFmt = '"S/"#,##0.00';
        if (cn===8||cn===9) cell.numFmt = '#,##0';
      });
    }

    // ── POR ESTADO ────────────────────────────────────────────────────────
    const wsE = wb.addWorksheet('Por Estado');
    wsE.columns = [{width:22},{width:14},{width:14},{width:14},{width:16},{width:14}];
    wsE.mergeCells('A1:F1'); wsE.getRow(1).height = 34;
    this.cell(wsE, 'A1', 'RESUMEN POR ESTADO', { sz:15, bold:true, color:C.WHITE }, C.NAV, 'center', 'middle');

    const stHdrs = ['Estado','N° Registros','% Total','Total Unidades','Valor Est. (S/)','% Valor'];
    wsE.getRow(2).height = 26;
    stHdrs.forEach((h,i) => {
      const cell = wsE.getRow(2).getCell(i+1);
      cell.value = h; cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
      cell.font = { name:'Calibri', size:10, bold:true, color:{ argb:C.WHITE } };
      cell.alignment = { vertical:'middle', horizontal: i===0 ? 'left' : 'center' };
      this.thinBorder(cell);
    });

    const estados: [string, string][] = [['operativo','Operativo'],['en_mantenimiento','En mantenimiento'],['fuera_de_servicio','Fuera de servicio'],['baja','De baja']];
    for (const [i, [key, label]] of estados.entries()) {
      const items = eq.filter(e => e.estado === key);
      const val = items.filter(e=>e.precioCompra!=null).reduce((s,e)=>s+e.precioCompra!*e.cantidad,0);
      const bg = i%2===1 ? C.ALT : C.WHITE;
      const row = wsE.addRow([label, items.length, items.length/eq.length, items.reduce((s,e)=>s+e.cantidad,0), val||null, valorTotal>0?val/valorTotal:null]);
      row.height = 22;
      row.eachCell({ includeEmpty:true }, (cell, cn) => {
        cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
        cell.font = { name:'Calibri', size:10, bold:cn===1, color:{ argb: ec(key) } };
        if (cn>1) cell.font.color = { argb:C.DARK };
        cell.alignment = { vertical:'middle', horizontal: cn===1 ? 'left' : 'center' };
        this.thinBorder(cell);
        if (cn===2||cn===4) cell.numFmt = '#,##0';
        if (cn===3||cn===6) cell.numFmt = '0.0%';
        if (cn===5&&cell.value) cell.numFmt = '"S/"#,##0.00';
      });
    }

    // ── MANTENIMIENTO ─────────────────────────────────────────────────────
    if (mantenimiento.length > 0) {
      const wsM = wb.addWorksheet('Mantenimiento');
      wsM.views = [{ state:'frozen', xSplit:0, ySplit:3 }];
      wsM.columns = [{width:11},{width:36},{width:13},{width:17},{width:13},{width:13},{width:18},{width:18}];
      wsM.mergeCells('A1:H1'); wsM.getRow(1).height = 32;
      this.cell(wsM, 'A1', `PLAN DE MANTENIMIENTO — ${mantenimiento.length} EQUIPOS/HERRAMIENTAS`, { sz:14, bold:true, color:C.WHITE }, C.NAV2, 'center', 'middle');
      const mHdrs = ['Código','Nombre','Clase','Marca','N° Serie','Frecuencia','Próx. Mantenimiento','Estado Mtto.'];
      wsM.getRow(2).height = 26;
      mHdrs.forEach((h,i) => {
        const cell = wsM.getRow(2).getCell(i+1);
        cell.value = h; cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
        cell.font = { name:'Calibri', size:9.5, bold:true, color:{ argb:C.WHITE } };
        cell.alignment = { vertical:'middle', horizontal: i===1||i===3 ? 'left' : 'center' };
        this.thinBorder(cell);
      });

      const vencidos = mantenimiento.filter(e => e.proximaFechaMantenimiento && new Date(e.proximaFechaMantenimiento) <= new Date()).sort((a,b) => new Date(a.proximaFechaMantenimiento!).getTime() - new Date(b.proximaFechaMantenimiento!).getTime());
      const pendientes = mantenimiento.filter(e => !e.proximaFechaMantenimiento || new Date(e.proximaFechaMantenimiento) > new Date()).sort((a,b) => {
        if (!a.proximaFechaMantenimiento) return 1;
        if (!b.proximaFechaMantenimiento) return -1;
        return new Date(a.proximaFechaMantenimiento).getTime() - new Date(b.proximaFechaMantenimiento).getTime();
      });
      const fLabel = (f: string) => ({ ninguno:'No req.', mensual:'Mensual', trimestral:'Trimestral', semestral:'Semestral', anual:'Anual' }[f] ?? f);

      for (const [idx, e] of [...vencidos, ...pendientes].entries()) {
        const isVenc = vencidos.includes(e);
        const bg = isVenc ? C.RLIGHT : idx%2===1 ? C.ALT : C.WHITE;
        const estadoMtto = isVenc ? '🔴 VENCIDO' : '✓ Al día';
        const row = wsM.addRow([e.codigo, e.nombre, cl(e.clase), e.marca??'', e.numeroSerie??'', fLabel(e.frecuenciaMantenimiento), e.proximaFechaMantenimiento ? new Date(e.proximaFechaMantenimiento).toLocaleDateString('es-PE') : '—', estadoMtto]);
        row.height = 18;
        row.eachCell({ includeEmpty:true }, (cell, cn) => {
          cell.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
          cell.font = { name:'Calibri', size:9.5, bold:cn===8&&isVenc, color:{ argb:cn===8 ? (isVenc?C.RED:C.GRN) : C.DARK } };
          cell.alignment = { vertical:'middle', horizontal: cn===2||cn===4 ? 'left' : 'center' };
          this.thinBorder(cell);
        });
      }
    }

    this.descargar(await wb.xlsx.writeBuffer(), `Equipos_Herramientas_${this.fechaHoy()}.xlsx`);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS ExcelJS
  // ══════════════════════════════════════════════════════════════════════════
  private cell(ws: Worksheet, ref: string, value: any, font: { sz?:number; bold?:boolean; color?:string; italic?:boolean } = {}, bg?: string, halign: 'left'|'center'|'right' = 'left', valign: 'middle'|'top'|'bottom' = 'middle'): void {
    const c = ws.getCell(ref);
    c.value = value;
    c.font  = { name:'Calibri', size:font.sz ?? 10, bold:font.bold ?? false, italic:font.italic ?? false, color:{ argb:font.color ?? C.DARK } };
    c.alignment = { horizontal:halign, vertical:valign, wrapText:false };
    if (bg) c.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
  }

  private kpiValue(ws: Worksheet, ref: string, value: number, color: string): void {
    const c = ws.getCell(ref);
    c.value = value; c.numFmt = '#,##0';
    c.font  = { name:'Calibri', size:16, bold:true, color:{ argb:color } };
    c.alignment = { horizontal:'right', vertical:'middle' };
  }

  private thinBorder(cell: Cell): void {
    const s: any = { style:'thin', color:{ argb:C.BRD } };
    cell.border = { top:s, left:s, bottom:s, right:s };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PDF MATERIALES
  // ══════════════════════════════════════════════════════════════════════════
  private pdfMateriales(): void {
    const mats  = this.datosFiltrados as MaterialLog[];
    const fecha = new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' });
    const rows = mats.map(m => {
      const alerta = m.stockMinimo > 0 && m.cantidad <= m.stockMinimo;
      return `<tr style="${alerta ? 'background:#fef2f2' : ''}">
        <td>${this.esc(m.nombre)}</td><td>${this.esc(m.marca??'—')}</td>
        <td>${this.esc(m.categoria)}</td><td>${this.esc(m.unidad??'')}</td>
        <td style="text-align:center;${alerta?'color:#dc2626;font-weight:700':''}">${m.cantidad}</td>
        <td style="text-align:center">${m.stockMinimo||'—'}</td>
        <td>${this.esc(m.serie??'—')}</td><td>${this.esc(m.almacen)}</td>
      </tr>`;
    }).join('');
    this.imprimirHtml(`
      <h2>Reporte de Inventario · Materiales</h2>
      <div class="sub">${fecha} &nbsp;·&nbsp; ${mats.length} registros &nbsp;·&nbsp; Filtro: ${this.filtroLabel()}
        <span class="leg-red">■ Stock bajo el mínimo</span>
      </div>
      <table><thead><tr>
        <th>Nombre</th><th>Marca</th><th>Categoría</th><th>Unidad</th>
        <th>Cant.</th><th>Mín.</th><th>N° Serie</th><th>Zona / Almacén</th>
      </tr></thead><tbody>${rows}</tbody></table>
    `);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PDF EQUIPOS
  // ══════════════════════════════════════════════════════════════════════════
  private pdfEquipos(): void {
    const eq    = this.datosFiltrados as EquipoHerramienta[];
    const fecha = new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' });
    const cl = (c: string) => c==='equipo_tecnologico'?'Eq. TI':c==='herramienta'?'Herramienta':'Equipo';
    const el = (s: string) => ({ operativo:'Operativo', en_mantenimiento:'En mantenimiento', fuera_de_servicio:'Fuera de servicio', baja:'De baja' }[s]??s);
    const ec = (s: string) => ({ operativo:'#16a34a', en_mantenimiento:'#d97706', fuera_de_servicio:'#dc2626', baja:'#94a3b8' }[s]??'');
    const rows = eq.map(e => {
      const bajo = e.stockMinimo>0&&e.cantidad<=e.stockMinimo;
      return `<tr style="${bajo?'background:#fef2f2':''}">
        <td>${this.esc(e.codigo)}</td><td>${this.esc(e.nombre)}</td><td>${cl(e.clase)}</td>
        <td>${this.esc(e.marca??'—')}${e.modelo?'<br><small style="color:#94a3b8">'+this.esc(e.modelo)+'</small>':''}</td>
        <td>${this.esc(e.numeroSerie??'—')}</td>
        <td style="text-align:center;${bajo?'color:#dc2626;font-weight:700':''}">${e.cantidad}</td>
        <td style="color:${ec(e.estado)};font-weight:600">${el(e.estado)}</td>
      </tr>`;
    }).join('');
    this.imprimirHtml(`
      <h2>Reporte de Inventario · Equipos y Herramientas</h2>
      <div class="sub">${fecha} &nbsp;·&nbsp; ${eq.length} registros &nbsp;·&nbsp; Filtro: ${this.filtroLabel()}</div>
      <table><thead><tr>
        <th>Código</th><th>Nombre</th><th>Clase</th><th>Marca/Modelo</th>
        <th>N° Serie</th><th>Cant.</th><th>Estado</th>
      </tr></thead><tbody>${rows}</tbody></table>
    `);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS generales
  // ══════════════════════════════════════════════════════════════════════════
  private filtroLabel(): string {
    return this.opcionesFiltro.find(o => o.valor === this.filtro)?.label ?? 'Todos';
  }

  private fechaHoy(): string { return new Date().toISOString().slice(0,10); }

  private esc(s: string): string {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }

  private descargar(buffer: any, nombre: string): void {
    const blob = new Blob([buffer as ArrayBuffer], { type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href = url; a.download = nombre;
    document.body.appendChild(a); a.click();
    document.body.removeChild(a); URL.revokeObjectURL(url);
  }

  private imprimirHtml(contenido: string): void {
    const html = `<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Reporte E-zyro</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:Arial,sans-serif;font-size:10px;color:#1e293b;padding:16px 20px}
  h2{font-size:14px;font-weight:800;color:#0f172a;margin-bottom:3px}
  .sub{font-size:9.5px;color:#64748b;margin-bottom:14px}
  .leg-red{margin-left:14px;background:#fef2f2;color:#dc2626;padding:2px 8px;border-radius:4px}
  table{width:100%;border-collapse:collapse}
  thead th{background:#1e3a5f;color:#fff;padding:6px 8px;text-align:left;font-size:9px;text-transform:uppercase;letter-spacing:.04em;white-space:nowrap}
  tbody td{padding:5px 8px;border-bottom:1px solid #e2e8f0;font-size:9.5px;vertical-align:middle}
  tbody tr:nth-child(even):not([style*="background"]){background:#f8fafc}
  @page{size:A4 landscape;margin:12mm 14mm}
  @media print{body{padding:0}}
</style></head><body>${contenido}
<script>window.onload=function(){setTimeout(function(){window.print();},250);}</script>
</body></html>`;
    const win = window.open('','_blank','width=1000,height=720');
    if (win) { win.document.write(html); win.document.close(); }
  }
}

import { Component, Input, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MaterialLog, EquipoHerramienta } from '../../logistica.models';
import * as ExcelJSLib from 'exceljs';

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
  filtro          = 'todos';
  filtroCategoria = 'todas';
  generando       = false;

  get opcionesFiltro(): { valor: string; label: string }[] {
    if (this.tipo === 'materiales') return [
      { valor: 'todos',      label: 'Todos los materiales'  },
      { valor: 'activos',    label: 'Solo activos'          },
      { valor: 'inactivos',  label: 'Solo inactivos'        },
      { valor: 'stock_bajo', label: 'Solo con stock bajo'   },
    ];
    return [
      { valor: 'todos',            label: 'Todos'                   },
      { valor: 'equipo',           label: 'Solo equipos'             },
      { valor: 'herramienta',      label: 'Solo herramientas'        },
      { valor: 'operativo',        label: 'Solo operativos'          },
      { valor: 'en_mantenimiento', label: 'Solo en mantenimiento'    },
      { valor: 'fuera_de_servicio',label: 'Fuera de servicio'        },
      { valor: 'baja',             label: 'De baja'                  },
    ];
  }

  get categorias(): string[] {
    const items = this.datos as any[];
    return ['todas', ...new Set(items.map(x => x.categoria).filter(Boolean))].sort((a, b) =>
      a === 'todas' ? -1 : b === 'todas' ? 1 : a.localeCompare(b, 'es')
    );
  }

  get datosFiltrados(): any[] {
    let result: any[];

    if (this.tipo === 'materiales') {
      const m = this.datos as MaterialLog[];
      if (this.filtro === 'activos')    result = m.filter(x => x.activo);
      else if (this.filtro === 'inactivos')  result = m.filter(x => !x.activo);
      else if (this.filtro === 'stock_bajo') result = m.filter(x => x.cantidad <= x.stockMinimo && x.stockMinimo > 0);
      else result = [...m];
    } else {
      const e = this.datos as EquipoHerramienta[];
      if (this.filtro === 'equipo')            result = e.filter(x => x.clase !== 'herramienta');
      else if (this.filtro === 'herramienta')  result = e.filter(x => x.clase === 'herramienta');
      else if (this.filtro === 'operativo')    result = e.filter(x => x.estado === 'operativo');
      else if (this.filtro === 'en_mantenimiento') result = e.filter(x => x.estado === 'en_mantenimiento');
      else if (this.filtro === 'fuera_de_servicio') result = e.filter(x => x.estado === 'fuera_de_servicio');
      else if (this.filtro === 'baja')         result = e.filter(x => x.estado === 'baja');
      else result = [...e];
    }

    if (this.filtroCategoria !== 'todas') {
      result = result.filter(x => x.categoria === this.filtroCategoria);
    }
    return result;
  }

  get totalRegistros(): number { return this.datosFiltrados.length; }

  async generarReporte(): Promise<void> {
    this.generando = true;
    try {
      if (this.formato === 'excel') {
        if (this.tipo === 'materiales') await this.excelMateriales();
        else await this.excelEquipos();
      } else {
        if (this.tipo === 'materiales') await this.pdfMateriales();
        else await this.pdfEquipos();
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
    const WB = ((ExcelJSLib as any).default?.Workbook ?? (ExcelJSLib as any).Workbook) as typeof ExcelJSLib.Workbook;
    const mats = this.datosFiltrados as MaterialLog[];
    const wb   = new WB() as Workbook;
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
    // HOJA 1 — PORTADA (diseño ejecutivo)
    // ──────────────────────────────────────────────────────────────────────
    const wsP = wb.addWorksheet('Portada');
    wsP.views = [{ showGridLines: false }];

    // Columnas: A(margen) B-D(col1) E(sep) F-H(col2) I(sep) J-L(col3) M(margen)
    ['A','M'].forEach(c => { wsP.getColumn(c).width = 2; });
    ['B','C','D'].forEach(c => { wsP.getColumn(c).width = c==='B' ? 5 : c==='C' ? 17 : 10; });
    wsP.getColumn('E').width = 3;
    ['F','G','H'].forEach(c => { wsP.getColumn(c).width = c==='F' ? 5 : c==='G' ? 17 : 10; });
    wsP.getColumn('I').width = 3;
    ['J','K','L'].forEach(c => { wsP.getColumn(c).width = c==='J' ? 5 : c==='K' ? 17 : 10; });

    const fecha = new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' });
    const now   = new Date();

    // ── BANNER PRINCIPAL (filas 1-5) ──────────────────────────────────────
    // Franja izquierda oscura (A:E)
    for (let r = 1; r <= 5; r++) {
      wsP.getRow(r).height = r === 1 ? 8 : r === 2 ? 50 : r === 3 ? 32 : r === 4 ? 22 : 8;
      wsP.mergeCells(`A${r}:E${r}`);
      wsP.getCell(`A${r}`).fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
      wsP.mergeCells(`F${r}:M${r}`);
      wsP.getCell(`F${r}`).fill = { type:'pattern', pattern:'solid', fgColor:{ argb: r <= 3 ? C.NAV2 : 'FF243F6E' } };
    }

    // Logo-texto "E-zyro" en franja izquierda
    wsP.getRow(2).height = 50;
    wsP.getCell('A2').value = 'E-ZYRO';
    wsP.getCell('A2').font  = { name:'Calibri', size:28, bold:true, color:{ argb:C.WHITE } };
    wsP.getCell('A2').alignment = { horizontal:'center', vertical:'middle' };

    wsP.getRow(3).height = 28;
    wsP.getCell('A3').value = 'Sistema de Gestión de Inventarios';
    wsP.getCell('A3').font  = { name:'Calibri', size:10, color:{ argb:'FFAAC4E8' } };
    wsP.getCell('A3').alignment = { horizontal:'center', vertical:'middle' };

    // Título del reporte en franja derecha
    const titleCell = wsP.getCell('F2');
    titleCell.value = 'REPORTE DE INVENTARIO';
    titleCell.font  = { name:'Calibri', size:20, bold:true, color:{ argb:C.WHITE } };
    titleCell.alignment = { horizontal:'center', vertical:'bottom' };

    const subtitleCell = wsP.getCell('F3');
    subtitleCell.value = 'MATERIALES & CONSUMIBLES';
    subtitleCell.font  = { name:'Calibri', size:13, color:{ argb:'FFAAC4E8' }, italic:true };
    subtitleCell.alignment = { horizontal:'center', vertical:'top' };

    const dateCell = wsP.getCell('F4');
    dateCell.value = fecha;
    dateCell.font  = { name:'Calibri', size:10, color:{ argb:'FF7FB3E8' } };
    dateCell.alignment = { horizontal:'center', vertical:'middle' };

    // ── LÍNEA ACENTO ─────────────────────────────────────────────────────
    wsP.getRow(6).height = 4;
    wsP.mergeCells('A6:M6');
    wsP.getCell('A6').fill = { type:'pattern', pattern:'solid', fgColor:{ argb:'FF3B82F6' } };

    // ── ESPACIO ───────────────────────────────────────────────────────────
    wsP.getRow(7).height = 10;

    // ── SECCIÓN: TARJETAS KPI (filas 8-12) ───────────────────────────────
    // Títulos de sección
    wsP.mergeCells('A8:M8'); wsP.getRow(8).height = 18;
    const secLabel1 = wsP.getCell('A8');
    secLabel1.value = 'INDICADORES CLAVE DE INVENTARIO';
    secLabel1.font  = { name:'Calibri', size:8, bold:true, color:{ argb:C.GRAY } };
    secLabel1.alignment = { horizontal:'left', vertical:'middle' };

    // 6 tarjetas en 2 filas × 3 columnas
    const kpiCards: { label:string; value:number; fmt:string; color:string; bg:string; icon:string }[] = [
      { label:'Total Materiales',   value:mats.length,         fmt:'#,##0',        color:C.NAV,   bg:'FFE8F0FB', icon:'📦' },
      { label:'Activos',            value:activos.length,      fmt:'#,##0',        color:C.GRN,   bg:C.GLIGHT,   icon:'✅' },
      { label:'Inactivos',          value:inactivos.length,    fmt:'#,##0',        color:C.GRAY,  bg:C.ALT,      icon:'⏸' },
      { label:'Stock Bajo / Alerta',value:alerta.length,       fmt:'#,##0',        color:C.RED,   bg:C.RLIGHT,   icon:'⚠' },
      { label:'Sin Stock (activos)',value:sinStock.length,      fmt:'#,##0',        color:C.AMB,   bg:C.ALIGHT,   icon:'🔴' },
      { label:'Total Unidades',     value:totalUnid,           fmt:'#,##0',        color:C.BLU,   bg:C.BLIGHT,   icon:'🔢' },
    ];

    const cardCols: [string, string, string][] = [['B','C','D'],['F','G','H'],['J','K','L']];
    for (let i = 0; i < 6; i++) {
      const row  = i < 3 ? 9 : 11;
      const cols = cardCols[i % 3];
      const k    = kpiCards[i];
      if (i === 0 || i === 3) wsP.getRow(row).height = 36;

      // Icono
      const ic = wsP.getCell(`${cols[0]}${row}`);
      ic.value = k.icon; ic.font = { name:'Calibri', size:14 };
      ic.alignment = { horizontal:'center', vertical:'middle' };
      ic.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:k.bg } };
      this.thinBorder(ic);

      // Label + valor en merge
      wsP.mergeCells(`${cols[1]}${row}:${cols[2]}${row}`);
      const vc = wsP.getCell(`${cols[1]}${row}`);
      vc.value = k.value; vc.numFmt = k.fmt;
      vc.font  = { name:'Calibri', size:18, bold:true, color:{ argb:k.color } };
      vc.alignment = { horizontal:'right', vertical:'middle' };
      vc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:k.bg } };
      this.thinBorder(vc);

      // Label (fila siguiente)
      const lr  = row + 1;
      wsP.getRow(lr).height = 16;
      wsP.mergeCells(`${cols[0]}${lr}:${cols[2]}${lr}`);
      const lc = wsP.getCell(`${cols[0]}${lr}`);
      lc.value = k.label;
      lc.font  = { name:'Calibri', size:8.5, bold:true, color:{ argb:k.color } };
      lc.alignment = { horizontal:'center', vertical:'middle' };
      lc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:k.bg } };
      this.thinBorder(lc);
    }

    // ── ESPACIO ───────────────────────────────────────────────────────────
    wsP.getRow(13).height = 10;
    wsP.mergeCells('A13:M13');
    wsP.getCell('A13').fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.WHITE } };

    // ── SECCIÓN: FINANCIERO + ESTADO (lado a lado, filas 14-23) ──────────
    wsP.mergeCells('A14:M14'); wsP.getRow(14).height = 18;
    const secLabel2 = wsP.getCell('A14');
    secLabel2.value = 'ANÁLISIS FINANCIERO';
    secLabel2.font  = { name:'Calibri', size:8, bold:true, color:{ argb:C.GRAY } };
    secLabel2.alignment = { horizontal:'left', vertical:'middle' };

    // Cabecera bloque financiero
    wsP.mergeCells('B15:H15'); wsP.getRow(15).height = 20;
    const fh = wsP.getCell('B15');
    fh.value = 'VALORIZACIÓN DEL INVENTARIO';
    fh.font  = { name:'Calibri', size:9, bold:true, color:{ argb:C.WHITE } };
    fh.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
    fh.alignment = { horizontal:'center', vertical:'middle' };

    // Cabecera bloque estado
    wsP.mergeCells('J15:M15');
    const sh = wsP.getCell('J15');
    sh.value = 'ESTADO DEL INVENTARIO';
    sh.font  = { name:'Calibri', size:9, bold:true, color:{ argb:C.WHITE } };
    sh.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
    sh.alignment = { horizontal:'center', vertical:'middle' };

    // Filas financieras
    const finRows: [string, number, string, string][] = [
      ['Valor total estimado',           valorTotal,                                              '"S/"#,##0.00', C.GRN  ],
      ['Costo de reposición stock bajo', valorRepos,                                              '"S/"#,##0.00', C.AMB  ],
      ['Costo promedio por material',    conPrecio.length ? valorTotal/conPrecio.length : 0,     '"S/"#,##0.00', C.BLU  ],
      ['Materiales con precio',          conPrecio.length,                                        '#,##0',        C.DARK ],
      ['Total unidades en inventario',   totalUnid,                                               '#,##0',        C.DARK ],
    ];
    for (const [i, [lbl, val, fmt, clr]] of finRows.entries()) {
      const rn = 16 + i; wsP.getRow(rn).height = 20;
      wsP.mergeCells(`B${rn}:F${rn}`);
      const bg = i % 2 === 0 ? C.LGRAY : C.WHITE;
      const lc = wsP.getCell(`B${rn}`);
      lc.value = lbl; lc.font = { name:'Calibri', size:9.5, color:{ argb:C.DARK }, bold: i < 2 };
      lc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      lc.alignment = { horizontal:'left', vertical:'middle' };
      this.thinBorder(lc);
      wsP.mergeCells(`G${rn}:H${rn}`);
      const vc = wsP.getCell(`G${rn}`);
      vc.value = val; vc.numFmt = fmt;
      vc.font  = { name:'Calibri', size:11, bold:true, color:{ argb:clr } };
      vc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      vc.alignment = { horizontal:'right', vertical:'middle' };
      this.thinBorder(vc);
    }

    // Filas de estado
    const estRows: [string, number, number, string, string][] = [
      ['✅  Stock OK',   activos.filter(m=>m.cantidad>m.stockMinimo||m.stockMinimo===0).length, Math.round(activos.filter(m=>m.cantidad>m.stockMinimo||m.stockMinimo===0).length/Math.max(mats.length,1)*100), C.GRN,  C.GLIGHT],
      ['⚠  Stock bajo', alerta.length,   Math.round(alerta.length/Math.max(mats.length,1)*100),   C.AMB,  C.ALIGHT],
      ['🔴  Sin stock',  sinStock.length, Math.round(sinStock.length/Math.max(mats.length,1)*100), C.RED,  C.RLIGHT],
      ['⏸  Inactivos',  inactivos.length,Math.round(inactivos.length/Math.max(mats.length,1)*100),C.GRAY, C.ALT   ],
    ];
    // Cabeceras mini
    wsP.getRow(15).height = 20;
    wsP.mergeCells('J16:K16'); wsP.getCell('J16').value = 'Estado';
    wsP.mergeCells('L16:M16'); wsP.getCell('L16').value = 'Cant.  / %';
    ['J16','L16'].forEach(ref => {
      const c = wsP.getCell(ref);
      c.font = { name:'Calibri', size:8.5, bold:true, color:{ argb:C.GRAY } };
      c.alignment = { horizontal:'center', vertical:'middle' };
    });
    wsP.getRow(16).height = 16;

    for (const [i, [lbl, cnt, pct, clr, bg]] of estRows.entries()) {
      const rn = 17 + i; wsP.getRow(rn).height = 22;
      wsP.mergeCells(`J${rn}:K${rn}`);
      const lc = wsP.getCell(`J${rn}`);
      lc.value = lbl; lc.font = { name:'Calibri', size:9.5, bold:true, color:{ argb:clr } };
      lc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      lc.alignment = { horizontal:'left', vertical:'middle' };
      this.thinBorder(lc);
      wsP.mergeCells(`L${rn}:M${rn}`);
      const vc = wsP.getCell(`L${rn}`);
      vc.value = `${cnt.toLocaleString('es-PE')}  (${pct}%)`;
      vc.font  = { name:'Calibri', size:10, bold:true, color:{ argb:clr } };
      vc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      vc.alignment = { horizontal:'center', vertical:'middle' };
      this.thinBorder(vc);
    }

    // ── ESPACIO ───────────────────────────────────────────────────────────
    wsP.getRow(21).height = 10;

    // ── SECCIÓN: TOP 5 CATEGORÍAS ─────────────────────────────────────────
    const topCats = [...new Map(mats.reduce((acc, m) => {
      const k = m.categoria || 'Sin categoría';
      acc.set(k, (acc.get(k) || 0) + 1); return acc;
    }, new Map<string,number>())).entries()].sort((a,b)=>b[1]-a[1]).slice(0,5);

    wsP.mergeCells('A22:M22'); wsP.getRow(22).height = 18;
    const secLabel3 = wsP.getCell('A22');
    secLabel3.value = 'TOP 5 CATEGORÍAS POR NÚMERO DE MATERIALES';
    secLabel3.font  = { name:'Calibri', size:8, bold:true, color:{ argb:C.GRAY } };
    secLabel3.alignment = { horizontal:'left', vertical:'middle' };

    const barColors = [C.NAV, C.BLU, C.NAV2, 'FF3B82F6', 'FF60A5FA'];
    const maxCat = topCats[0]?.[1] ?? 1;
    for (const [i, [cat, cnt]] of topCats.entries()) {
      const rn = 23 + i; wsP.getRow(rn).height = 18;
      // Nombre
      wsP.mergeCells(`B${rn}:D${rn}`);
      const nc = wsP.getCell(`B${rn}`);
      nc.value = cat; nc.font = { name:'Calibri', size:9, color:{ argb:C.DARK } };
      nc.alignment = { horizontal:'left', vertical:'middle' };

      // Barra visual proporcional (columnas E-L)
      const barLen = Math.round((cnt / maxCat) * 8);
      const allCols = ['E','F','G','H','I','J','K','L'];
      for (let b = 0; b < 8; b++) {
        const bc = wsP.getCell(`${allCols[b]}${rn}`);
        bc.fill = { type:'pattern', pattern:'solid', fgColor:{ argb: b < barLen ? barColors[i] : 'FFEEEEEE' } };
      }

      // Número
      const vc = wsP.getCell(`M${rn}`);
      vc.value = cnt; vc.numFmt = '#,##0';
      vc.font  = { name:'Calibri', size:9, bold:true, color:{ argb:barColors[i] } };
      vc.alignment = { horizontal:'right', vertical:'middle' };
    }

    // ── FOOTER ────────────────────────────────────────────────────────────
    wsP.getRow(28).height = 8;
    wsP.mergeCells('A29:M29'); wsP.getRow(29).height = 4;
    wsP.getCell('A29').fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };

    wsP.mergeCells('A30:M30'); wsP.getRow(30).height = 18;
    const fc = wsP.getCell('A30');
    fc.value = `Generado por E-zyro el ${fecha} a las ${now.getHours().toString().padStart(2,'0')}:${now.getMinutes().toString().padStart(2,'0')}  ·  Documento confidencial — uso interno`;
    fc.font  = { name:'Calibri', size:8, italic:true, color:{ argb:C.GRAY } };
    fc.alignment = { horizontal:'center', vertical:'middle' };

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
    const WB = ((ExcelJSLib as any).default?.Workbook ?? (ExcelJSLib as any).Workbook) as typeof ExcelJSLib.Workbook;
    const eq  = this.datosFiltrados as EquipoHerramienta[];
    const wb  = new WB() as Workbook;
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

    // ── PORTADA (diseño ejecutivo) ────────────────────────────────────────
    const wsP = wb.addWorksheet('Portada');
    wsP.views = [{ showGridLines:false }];
    ['A','M'].forEach(c => { wsP.getColumn(c).width = 2; });
    ['B','C','D'].forEach(c => { wsP.getColumn(c).width = c==='B'?5:c==='C'?17:10; });
    wsP.getColumn('E').width = 3;
    ['F','G','H'].forEach(c => { wsP.getColumn(c).width = c==='F'?5:c==='G'?17:10; });
    wsP.getColumn('I').width = 3;
    ['J','K','L'].forEach(c => { wsP.getColumn(c).width = c==='J'?5:c==='K'?17:10; });

    const now2 = new Date();

    // Banner
    for (let r = 1; r <= 5; r++) {
      wsP.getRow(r).height = r===1?8:r===2?50:r===3?32:r===4?22:8;
      wsP.mergeCells(`A${r}:E${r}`);
      wsP.getCell(`A${r}`).fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
      wsP.mergeCells(`F${r}:M${r}`);
      wsP.getCell(`F${r}`).fill = { type:'pattern', pattern:'solid', fgColor:{ argb: r<=3?C.NAV2:'FF243F6E' } };
    }
    wsP.getCell('A2').value = 'E-ZYRO';
    wsP.getCell('A2').font  = { name:'Calibri', size:28, bold:true, color:{ argb:C.WHITE } };
    wsP.getCell('A2').alignment = { horizontal:'center', vertical:'middle' };
    wsP.getCell('A3').value = 'Sistema de Gestión de Inventarios';
    wsP.getCell('A3').font  = { name:'Calibri', size:10, color:{ argb:'FFAAC4E8' } };
    wsP.getCell('A3').alignment = { horizontal:'center', vertical:'middle' };
    wsP.getCell('F2').value = 'REPORTE DE INVENTARIO';
    wsP.getCell('F2').font  = { name:'Calibri', size:20, bold:true, color:{ argb:C.WHITE } };
    wsP.getCell('F2').alignment = { horizontal:'center', vertical:'bottom' };
    wsP.getCell('F3').value = 'EQUIPOS Y HERRAMIENTAS';
    wsP.getCell('F3').font  = { name:'Calibri', size:13, color:{ argb:'FFAAC4E8' }, italic:true };
    wsP.getCell('F3').alignment = { horizontal:'center', vertical:'top' };
    wsP.getCell('F4').value = fecha;
    wsP.getCell('F4').font  = { name:'Calibri', size:10, color:{ argb:'FF7FB3E8' } };
    wsP.getCell('F4').alignment = { horizontal:'center', vertical:'middle' };

    // Línea acento
    wsP.getRow(6).height = 4;
    wsP.mergeCells('A6:M6');
    wsP.getCell('A6').fill = { type:'pattern', pattern:'solid', fgColor:{ argb:'FF3B82F6' } };
    wsP.getRow(7).height = 10;

    // Tarjetas KPI equipos
    wsP.mergeCells('A8:M8'); wsP.getRow(8).height = 18;
    const eqSec1 = wsP.getCell('A8');
    eqSec1.value = 'INDICADORES CLAVE DE INVENTARIO';
    eqSec1.font  = { name:'Calibri', size:8, bold:true, color:{ argb:C.GRAY } };
    eqSec1.alignment = { horizontal:'left', vertical:'middle' };

    const eqs2 = eq.filter(e => e.clase !== 'herramienta');
    const herr  = eq.filter(e => e.clase === 'herramienta');
    const eqKpiCards: { label:string; value:number; fmt:string; color:string; bg:string; icon:string }[] = [
      { label:'Total Registros',       value:eq.length,                                    fmt:'#,##0', color:C.NAV,  bg:'FFE8F0FB', icon:'🗂' },
      { label:'Equipos',               value:eqs2.length,                                  fmt:'#,##0', color:C.BLU,  bg:C.BLIGHT,   icon:'⚙' },
      { label:'Herramientas',          value:herr.length,                                  fmt:'#,##0', color:C.GRN,  bg:C.GLIGHT,   icon:'🔧' },
      { label:'Operativos',            value:operativos.length,                            fmt:'#,##0', color:C.GRN,  bg:C.GLIGHT,   icon:'✅' },
      { label:'En Mantenimiento',      value:eq.filter(e=>e.estado==='en_mantenimiento').length, fmt:'#,##0', color:C.AMB, bg:C.ALIGHT, icon:'🔨' },
      { label:'Fuera de Servicio',     value:eq.filter(e=>e.estado==='fuera_de_servicio').length, fmt:'#,##0', color:C.RED, bg:C.RLIGHT, icon:'⛔' },
    ];
    const eqCardCols: [string,string,string][] = [['B','C','D'],['F','G','H'],['J','K','L']];
    for (let i = 0; i < 6; i++) {
      const row  = i < 3 ? 9 : 11;
      const cols = eqCardCols[i % 3];
      const k    = eqKpiCards[i];
      if (i===0||i===3) wsP.getRow(row).height = 36;
      const ic = wsP.getCell(`${cols[0]}${row}`);
      ic.value = k.icon; ic.font = { name:'Calibri', size:14 };
      ic.alignment = { horizontal:'center', vertical:'middle' };
      ic.fill = { type:'pattern', pattern:'solid', fgColor:{ argb:k.bg } };
      this.thinBorder(ic);
      wsP.mergeCells(`${cols[1]}${row}:${cols[2]}${row}`);
      const vc = wsP.getCell(`${cols[1]}${row}`);
      vc.value = k.value; vc.numFmt = k.fmt;
      vc.font  = { name:'Calibri', size:18, bold:true, color:{ argb:k.color } };
      vc.alignment = { horizontal:'right', vertical:'middle' };
      vc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:k.bg } };
      this.thinBorder(vc);
      const lr = row + 1; wsP.getRow(lr).height = 16;
      wsP.mergeCells(`${cols[0]}${lr}:${cols[2]}${lr}`);
      const lc = wsP.getCell(`${cols[0]}${lr}`);
      lc.value = k.label; lc.font = { name:'Calibri', size:8.5, bold:true, color:{ argb:k.color } };
      lc.alignment = { horizontal:'center', vertical:'middle' };
      lc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:k.bg } };
      this.thinBorder(lc);
    }

    wsP.getRow(13).height = 10;
    wsP.mergeCells('A13:M13');
    wsP.getCell('A13').fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.WHITE } };

    // Financiero
    wsP.mergeCells('A14:M14'); wsP.getRow(14).height = 18;
    const eqSec2 = wsP.getCell('A14');
    eqSec2.value = 'ANÁLISIS FINANCIERO';
    eqSec2.font  = { name:'Calibri', size:8, bold:true, color:{ argb:C.GRAY } };
    eqSec2.alignment = { horizontal:'left', vertical:'middle' };

    wsP.mergeCells('B15:H15'); wsP.getRow(15).height = 20;
    const efh = wsP.getCell('B15');
    efh.value = 'VALORIZACIÓN DEL INVENTARIO';
    efh.font  = { name:'Calibri', size:9, bold:true, color:{ argb:C.WHITE } };
    efh.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
    efh.alignment = { horizontal:'center', vertical:'middle' };

    wsP.mergeCells('J15:M15');
    const esh = wsP.getCell('J15');
    esh.value = 'DISTRIBUCIÓN POR ESTADO';
    esh.font  = { name:'Calibri', size:9, bold:true, color:{ argb:C.WHITE } };
    esh.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
    esh.alignment = { horizontal:'center', vertical:'middle' };

    const eFin2: [string, number, string, string][] = [
      ['Valor total estimado del inventario', +valorTotal.toFixed(2), '"S/"#,##0.00', C.GRN ],
      ['Costo prom. por equipo/herramienta',  conPrecio.length ? +(valorTotal/conPrecio.length).toFixed(2) : 0, '"S/"#,##0.00', C.BLU ],
      ['Con precio de compra registrado',     conPrecio.length,  '#,##0',         C.DARK],
      ['Total unidades en inventario',        totalUnid,         '#,##0',         C.DARK],
      ['Con plan de mantenimiento',           mantenimiento.length, '#,##0',      C.NAV2],
    ];
    for (const [i, [lbl,val,fmt,clr]] of eFin2.entries()) {
      const rn = 16+i; wsP.getRow(rn).height = 20;
      wsP.mergeCells(`B${rn}:F${rn}`);
      const bg = i%2===0 ? C.LGRAY : C.WHITE;
      const lc = wsP.getCell(`B${rn}`);
      lc.value = lbl; lc.font = { name:'Calibri', size:9.5, color:{ argb:C.DARK }, bold:i===0 };
      lc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      lc.alignment = { horizontal:'left', vertical:'middle' };
      this.thinBorder(lc);
      wsP.mergeCells(`G${rn}:H${rn}`);
      const vc = wsP.getCell(`G${rn}`);
      vc.value = val; vc.numFmt = fmt;
      vc.font  = { name:'Calibri', size:11, bold:true, color:{ argb:clr } };
      vc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      vc.alignment = { horizontal:'right', vertical:'middle' };
      this.thinBorder(vc);
    }

    // Estado col derecha
    wsP.getRow(16).height = 16;
    const estEqs: [string, number, string, string][] = [
      ['✅  Operativo',         operativos.length,                                  C.GRN,  C.GLIGHT],
      ['🔨  En mantenimiento',  eq.filter(e=>e.estado==='en_mantenimiento').length,  C.AMB,  C.ALIGHT],
      ['⛔  Fuera de servicio', eq.filter(e=>e.estado==='fuera_de_servicio').length, C.RED,  C.RLIGHT],
      ['⏸  De baja',           eq.filter(e=>e.estado==='baja').length,              C.GRAY, C.ALT   ],
    ];
    for (const [i, [lbl,cnt,clr,bg]] of estEqs.entries()) {
      const rn = 17+i; wsP.getRow(rn).height = 22;
      const pct = Math.round(cnt/Math.max(eq.length,1)*100);
      wsP.mergeCells(`J${rn}:K${rn}`);
      const lc = wsP.getCell(`J${rn}`);
      lc.value = lbl; lc.font = { name:'Calibri', size:9.5, bold:true, color:{ argb:clr } };
      lc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      lc.alignment = { horizontal:'left', vertical:'middle' };
      this.thinBorder(lc);
      wsP.mergeCells(`L${rn}:M${rn}`);
      const vc = wsP.getCell(`L${rn}`);
      vc.value = `${cnt.toLocaleString('es-PE')}  (${pct}%)`;
      vc.font  = { name:'Calibri', size:10, bold:true, color:{ argb:clr } };
      vc.fill  = { type:'pattern', pattern:'solid', fgColor:{ argb:bg } };
      vc.alignment = { horizontal:'center', vertical:'middle' };
      this.thinBorder(vc);
    }

    // Top 5 categorías
    const topEqCats = [...new Map(eq.reduce((acc, e) => {
      const k = e.categoria || 'Sin categoría';
      acc.set(k, (acc.get(k)||0)+1); return acc;
    }, new Map<string,number>())).entries()].sort((a,b)=>b[1]-a[1]).slice(0,5);

    wsP.getRow(22).height = 10;
    wsP.mergeCells('A23:M23'); wsP.getRow(23).height = 18;
    const eqSec3 = wsP.getCell('A23');
    eqSec3.value = 'TOP 5 CATEGORÍAS POR NÚMERO DE REGISTROS';
    eqSec3.font  = { name:'Calibri', size:8, bold:true, color:{ argb:C.GRAY } };
    eqSec3.alignment = { horizontal:'left', vertical:'middle' };

    const barColors2 = [C.NAV, C.BLU, C.NAV2, 'FF3B82F6', 'FF60A5FA'];
    const maxEqCat = topEqCats[0]?.[1] ?? 1;
    for (const [i, [cat, cnt]] of topEqCats.entries()) {
      const rn = 24+i; wsP.getRow(rn).height = 18;
      wsP.mergeCells(`B${rn}:D${rn}`);
      const nc = wsP.getCell(`B${rn}`);
      nc.value = cat; nc.font = { name:'Calibri', size:9, color:{ argb:C.DARK } };
      nc.alignment = { horizontal:'left', vertical:'middle' };
      const barLen = Math.round((cnt/maxEqCat)*8);
      ['E','F','G','H','I','J','K','L'].forEach((col,b) => {
        wsP.getCell(`${col}${rn}`).fill = { type:'pattern', pattern:'solid', fgColor:{ argb: b < barLen ? barColors2[i] : 'FFEEEEEE' } };
      });
      const vc = wsP.getCell(`M${rn}`);
      vc.value = cnt; vc.numFmt = '#,##0';
      vc.font  = { name:'Calibri', size:9, bold:true, color:{ argb:barColors2[i] } };
      vc.alignment = { horizontal:'right', vertical:'middle' };
    }

    // Footer
    wsP.getRow(29).height = 8;
    wsP.mergeCells('A30:M30'); wsP.getRow(30).height = 4;
    wsP.getCell('A30').fill = { type:'pattern', pattern:'solid', fgColor:{ argb:C.NAV } };
    wsP.mergeCells('A31:M31'); wsP.getRow(31).height = 18;
    const eqfc = wsP.getCell('A31');
    eqfc.value = `Generado por E-zyro el ${fecha} a las ${now2.getHours().toString().padStart(2,'0')}:${now2.getMinutes().toString().padStart(2,'0')}  ·  Documento confidencial — uso interno`;
    eqfc.font  = { name:'Calibri', size:8, italic:true, color:{ argb:C.GRAY } };
    eqfc.alignment = { horizontal:'center', vertical:'middle' };

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
  // PDF MATERIALES — descarga directa
  // ══════════════════════════════════════════════════════════════════════════
  private async pdfMateriales(): Promise<void> {
    const mats  = this.datosFiltrados as MaterialLog[];
    const fecha = new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' });
    const catLabel = this.filtroCategoria !== 'todas' ? ` · Categoría: ${this.filtroCategoria}` : '';

    const alertas  = mats.filter(m => m.stockMinimo > 0 && m.cantidad <= m.stockMinimo).length;
    const valorTotal = mats.filter(m => m.precioCompra != null).reduce((s,m)=>s+(m.precioCompra!*m.cantidad),0);

    const rows = mats.map((m, i) => {
      const alerta = m.stockMinimo > 0 && m.cantidad <= m.stockMinimo;
      const bg = alerta ? '#fff1f2' : i % 2 === 1 ? '#f8fafc' : '#ffffff';
      return `<tr style="background:${bg}">
        <td class="td-name">${this.esc(m.nombre)}</td>
        <td>${this.esc(m.marca ?? '—')}</td>
        <td><span class="chip">${this.esc(m.categoria)}</span></td>
        <td class="center">${this.esc(m.unidad ?? '')}</td>
        <td class="center ${alerta ? 'red bold' : ''}">${m.cantidad}</td>
        <td class="center muted">${m.stockMinimo || '—'}</td>
        <td class="muted">${this.esc(m.serie ?? '—')}</td>
        <td class="muted">${this.esc(m.almacen)}</td>
        <td class="right ${alerta ? 'red' : ''}">${alerta ? '⚠ BAJO' : m.stockMinimo === 0 ? '—' : '✓ OK'}</td>
      </tr>`;
    }).join('');

    const html = `<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Segoe UI',Arial,sans-serif;font-size:9.5px;color:#1e293b;background:#fff}
  .cover{background:linear-gradient(135deg,#1e3a5f 0%,#2d5b8e 100%);color:#fff;padding:22px 28px 18px;margin-bottom:0}
  .cover h1{font-size:18px;font-weight:800;letter-spacing:.02em;margin-bottom:4px}
  .cover .sub{font-size:9px;opacity:.75;margin-bottom:14px}
  .kpis{display:flex;gap:14px;margin-top:4px}
  .kpi{background:rgba(255,255,255,.12);border-radius:8px;padding:8px 14px;min-width:90px}
  .kpi .val{font-size:20px;font-weight:800;line-height:1}
  .kpi .lbl{font-size:8px;opacity:.8;margin-top:2px;text-transform:uppercase;letter-spacing:.05em}
  .kpi.red .val{color:#fca5a5}
  .kpi.grn .val{color:#86efac}
  .accent{height:3px;background:#3b82f6;margin-bottom:0}
  .content{padding:14px 18px}
  .filtros{display:flex;gap:8px;margin-bottom:10px;flex-wrap:wrap;align-items:center}
  .ftag{background:#e8f0fb;color:#1e3a5f;border-radius:4px;padding:2px 8px;font-size:8.5px;font-weight:700}
  .ftag.cat{background:#ede9fe;color:#6d28d9}
  .leg{display:inline-flex;align-items:center;gap:4px;background:#fff1f2;color:#dc2626;border-radius:4px;padding:2px 8px;font-size:8px;font-weight:700}
  table{width:100%;border-collapse:collapse}
  thead tr{background:#1e3a5f}
  thead th{color:#fff;padding:6px 8px;text-align:left;font-size:8px;font-weight:700;text-transform:uppercase;letter-spacing:.05em;white-space:nowrap}
  thead th.center,td.center{text-align:center}
  thead th.right,td.right{text-align:right}
  tbody td{padding:5px 8px;border-bottom:1px solid #e2e8f0;vertical-align:middle}
  tbody tr:last-child td{border-bottom:none}
  .td-name{font-weight:600;max-width:160px}
  .chip{background:#e8f0fb;color:#1e3a5f;border-radius:3px;padding:1px 5px;font-size:8px;font-weight:600;white-space:nowrap}
  .muted{color:#64748b}
  .red{color:#dc2626}
  .bold{font-weight:700}
  .right{text-align:right}
  .footer{margin-top:12px;padding-top:8px;border-top:1px solid #e2e8f0;display:flex;justify-content:space-between;font-size:7.5px;color:#94a3b8}
  @page{size:A4 landscape;margin:10mm 12mm}
  @media print{.content{padding:0}}
</style></head><body>
<div class="cover">
  <h1>Reporte de Inventario · Materiales</h1>
  <div class="sub">E-zyro — Sistema de Gestión de Inventarios &nbsp;·&nbsp; ${fecha}</div>
  <div class="kpis">
    <div class="kpi"><div class="val">${mats.length.toLocaleString('es-PE')}</div><div class="lbl">Registros</div></div>
    <div class="kpi grn"><div class="val">${(mats.length - alertas).toLocaleString('es-PE')}</div><div class="lbl">Stock OK</div></div>
    <div class="kpi red"><div class="val">${alertas.toLocaleString('es-PE')}</div><div class="lbl">Stock bajo</div></div>
    ${valorTotal > 0 ? `<div class="kpi"><div class="val">S/${valorTotal.toLocaleString('es-PE',{minimumFractionDigits:0,maximumFractionDigits:0})}</div><div class="lbl">Valor estimado</div></div>` : ''}
  </div>
</div>
<div class="accent"></div>
<div class="content">
  <div class="filtros">
    <span class="ftag">Filtro: ${this.filtroLabel()}</span>
    ${this.filtroCategoria !== 'todas' ? `<span class="ftag cat">Categoría: ${this.esc(this.filtroCategoria)}</span>` : ''}
    ${alertas > 0 ? `<span class="leg">⚠ Filas en rojo = stock bajo el mínimo</span>` : ''}
  </div>
  <table>
    <thead><tr>
      <th>Nombre</th><th>Marca</th><th>Categoría</th><th class="center">Unidad</th>
      <th class="center">Cant.</th><th class="center">Mín.</th>
      <th>N° Serie</th><th>Almacén / Zona</th><th class="right">Estado</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>
  <div class="footer">
    <span>E-zyro · Reporte generado el ${fecha}</span>
    <span>Total: ${mats.length} materiales${catLabel}</span>
  </div>
</div>
</body></html>`;

    await this.descargarPdf(html, `Materiales_${this.fechaHoy()}.pdf`);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PDF EQUIPOS — descarga directa
  // ══════════════════════════════════════════════════════════════════════════
  private async pdfEquipos(): Promise<void> {
    const eq    = this.datosFiltrados as EquipoHerramienta[];
    const fecha = new Date().toLocaleDateString('es-PE', { year:'numeric', month:'long', day:'numeric' });
    const cl = (c: string) => c==='equipo_tecnologico'?'Eq. TI':c==='herramienta'?'Herramienta':'Equipo';
    const el = (s: string) => ({ operativo:'Operativo', en_mantenimiento:'En mantenimiento', fuera_de_servicio:'Fuera de servicio', baja:'De baja' }[s]??s);
    const ec = (s: string) => ({ operativo:'#16a34a', en_mantenimiento:'#d97706', fuera_de_servicio:'#dc2626', baja:'#94a3b8' }[s]??'#1e293b');
    const catLabel = this.filtroCategoria !== 'todas' ? ` · Categoría: ${this.filtroCategoria}` : '';
    const operativos = eq.filter(e => e.estado === 'operativo').length;
    const enMant     = eq.filter(e => e.estado === 'en_mantenimiento').length;

    const rows = eq.map((e, i) => {
      const bajo = e.stockMinimo > 0 && e.cantidad <= e.stockMinimo;
      const bg   = i % 2 === 1 ? '#f8fafc' : '#ffffff';
      return `<tr style="background:${bg}">
        <td class="mono">${this.esc(e.codigo)}</td>
        <td class="td-name">${this.esc(e.nombre)}</td>
        <td><span class="clase-chip cl-${e.clase}">${cl(e.clase)}</span></td>
        <td class="muted">${this.esc(e.marca ?? '—')}${e.modelo ? `<br><span style="font-size:7.5px;color:#94a3b8">${this.esc(e.modelo)}</span>` : ''}</td>
        <td class="muted mono">${this.esc(e.numeroSerie ?? '—')}</td>
        <td class="center ${bajo ? 'red bold' : ''}">${e.cantidad}</td>
        <td style="color:${ec(e.estado)};font-weight:600">${el(e.estado)}</td>
      </tr>`;
    }).join('');

    const html = `<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Segoe UI',Arial,sans-serif;font-size:9.5px;color:#1e293b;background:#fff}
  .cover{background:linear-gradient(135deg,#1e3a5f 0%,#2d5b8e 100%);color:#fff;padding:22px 28px 18px}
  .cover h1{font-size:18px;font-weight:800;letter-spacing:.02em;margin-bottom:4px}
  .cover .sub{font-size:9px;opacity:.75;margin-bottom:14px}
  .kpis{display:flex;gap:14px;margin-top:4px}
  .kpi{background:rgba(255,255,255,.12);border-radius:8px;padding:8px 14px;min-width:90px}
  .kpi .val{font-size:20px;font-weight:800;line-height:1}
  .kpi .lbl{font-size:8px;opacity:.8;margin-top:2px;text-transform:uppercase;letter-spacing:.05em}
  .kpi.amb .val{color:#fde68a}
  .accent{height:3px;background:#3b82f6}
  .content{padding:14px 18px}
  .filtros{display:flex;gap:8px;margin-bottom:10px;flex-wrap:wrap}
  .ftag{background:#e8f0fb;color:#1e3a5f;border-radius:4px;padding:2px 8px;font-size:8.5px;font-weight:700}
  .ftag.cat{background:#ede9fe;color:#6d28d9}
  table{width:100%;border-collapse:collapse}
  thead tr{background:#1e3a5f}
  thead th{color:#fff;padding:6px 8px;text-align:left;font-size:8px;font-weight:700;text-transform:uppercase;letter-spacing:.05em;white-space:nowrap}
  td.center,th.center{text-align:center}
  tbody td{padding:5px 8px;border-bottom:1px solid #e2e8f0;vertical-align:middle}
  tbody tr:last-child td{border-bottom:none}
  .td-name{font-weight:600}
  .mono{font-family:monospace;font-size:8.5px}
  .muted{color:#64748b}
  .red{color:#dc2626}.bold{font-weight:700}
  .clase-chip{border-radius:3px;padding:2px 5px;font-size:8px;font-weight:600}
  .cl-equipo{background:#dbeafe;color:#1d4ed8}
  .cl-herramienta{background:#d1fae5;color:#065f46}
  .cl-equipo_tecnologico{background:#ede9fe;color:#6d28d9}
  .footer{margin-top:12px;padding-top:8px;border-top:1px solid #e2e8f0;display:flex;justify-content:space-between;font-size:7.5px;color:#94a3b8}
  @page{size:A4 landscape;margin:10mm 12mm}
</style></head><body>
<div class="cover">
  <h1>Reporte de Inventario · Equipos y Herramientas</h1>
  <div class="sub">E-zyro — Sistema de Gestión de Inventarios &nbsp;·&nbsp; ${fecha}</div>
  <div class="kpis">
    <div class="kpi"><div class="val">${eq.length.toLocaleString('es-PE')}</div><div class="lbl">Registros</div></div>
    <div class="kpi"><div class="val">${operativos}</div><div class="lbl">Operativos</div></div>
    <div class="kpi amb"><div class="val">${enMant}</div><div class="lbl">En mantenimiento</div></div>
  </div>
</div>
<div class="accent"></div>
<div class="content">
  <div class="filtros">
    <span class="ftag">Filtro: ${this.filtroLabel()}</span>
    ${this.filtroCategoria !== 'todas' ? `<span class="ftag cat">Categoría: ${this.esc(this.filtroCategoria)}</span>` : ''}
  </div>
  <table>
    <thead><tr>
      <th>Código</th><th>Nombre</th><th>Clase</th><th>Marca / Modelo</th>
      <th>N° Serie</th><th class="center">Cant.</th><th>Estado</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>
  <div class="footer">
    <span>E-zyro · Reporte generado el ${fecha}</span>
    <span>Total: ${eq.length} registros${catLabel}</span>
  </div>
</div>
</body></html>`;

    await this.descargarPdf(html, `Equipos_Herramientas_${this.fechaHoy()}.pdf`);
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

  private async descargarPdf(html: string, nombre: string): Promise<void> {
    const html2pdf = (await import('html2pdf.js') as any).default ?? (await import('html2pdf.js') as any);
    const el = document.createElement('div');
    el.innerHTML = html;
    el.style.position = 'absolute';
    el.style.left = '-9999px';
    document.body.appendChild(el);
    await html2pdf()
      .set({
        margin:       [8, 8, 8, 8],
        filename:     nombre,
        image:        { type: 'jpeg', quality: 0.98 },
        html2canvas:  { scale: 2, useCORS: true, logging: false },
        jsPDF:        { unit: 'mm', format: 'a4', orientation: 'landscape' },
        pagebreak:    { mode: ['avoid-all', 'css'] },
      })
      .from(el)
      .save();
    document.body.removeChild(el);
  }
}

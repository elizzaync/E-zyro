import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { DashboardService } from '../../../../core/services/dashboard.service';
import { RrhhService } from '../../../../core/services/rrhh.service';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

const MESES_MAP: Record<string, number> = {
  enero:0, febrero:1, marzo:2, abril:3, mayo:4, junio:5,
  julio:6, agosto:7, septiembre:8, octubre:9, noviembre:10, diciembre:11
};
const MESES_NOMBRE = [
  'Enero','Febrero','Marzo','Abril','Mayo','Junio',
  'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'
];

interface DiaCell {
  num: number | null;
  fecha: string;
  isHoy: boolean;
  isWeekend: boolean;
  tag: 'asistio' | 'tardanza' | 'falta' | 'permiso' | 'feriado' | 'libre' | '';
  horaIngreso: string;
  horaSalida: string;
  horasTrabajadas: number;
  permisoTipo: string;
  eventoOT: boolean;
  estadoOT: string;
  otNombre: string;
  otOrden: string;
  otCliente: string;
  tooltip: string;
  nombreFeriado: string;
}

@Component({
  selector: 'app-calendario',
  standalone: true,
  imports: [CommonModule, AppModalComponent],
  templateUrl: './calendario.component.html',
  styleUrls: ['./calendario.component.css']
})
export class CalendarioComponent implements OnInit, OnDestroy {
  private dashSvc  = inject(DashboardService);
  private rrhhSvc  = inject(RrhhService);
  private router   = inject(Router);

  cargando = true;
  fechaVista = new Date();

  diasSemana = ['Dom','Lun','Mar','Mié','Jue','Vie','Sáb'];
  diasMes: DiaCell[] = [];

  // KPI raw
  kpiAsistidos  = 0;
  kpiTardanzas  = 0;
  kpiFaltas     = 0;
  kpiHoras      = 0;
  kpiHorasExtra = 0;
  kpiPermisos   = 0;
  kpiLaborables = 0;

  diaDetalle: DiaCell | null = null;

  private registros: any[]  = [];
  private permisos:  any[]  = [];
  private servicios: any[]  = [];
  private feriadosSet = new Set<string>();   // 'YYYY-MM-DD'
  private feriadosNombreMap = new Map<string, string>();

  get mesLabel(): string {
    return `${MESES_NOMBRE[this.fechaVista.getMonth()]} ${this.fechaVista.getFullYear()}`;
  }
  get pctAsistencia(): number {
    return this.kpiLaborables > 0 ? Math.round((this.kpiAsistidos / this.kpiLaborables) * 100) : 0;
  }

  ngOnInit(): void {
    this.cargarDatos();
  }

  private cargarDatos(): void {
    this.cargando = true;
    let done = 0;
    const tick = () => { if (++done === 4) { this.cargando = false; this.rebuild(); } };

    const mes  = this.fechaVista.getMonth() + 1;
    const anio = this.fechaVista.getFullYear();

    this.dashSvc.getAsistencia(mes, anio).subscribe({
      next: (r: any) => {
        const arr = Array.isArray(r?.data?.registros) ? r.data.registros
          : Array.isArray(r?.registros) ? r.registros
          : Array.isArray(r?.data) ? r.data
          : Array.isArray(r) ? r : [];
        this.registros = arr; tick();
      },
      error: () => { this.registros = []; tick(); }
    });

    this.dashSvc.getPermisos().subscribe({
      next: (r: any) => {
        const arr = Array.isArray(r?.data) ? r.data
          : Array.isArray(r) ? r : [];
        this.permisos = arr; tick();
      },
      error: () => { this.permisos = []; tick(); }
    });

    this.dashSvc.getCalendarioEventos().subscribe({
      next: (r: any) => { this.servicios = r?.data?.servicios ?? []; tick(); },
      error: () => { this.servicios = []; tick(); }
    });

    this.rrhhSvc.getFeriados(anio).subscribe({
      next: (r) => {
        this.feriadosSet.clear(); this.feriadosNombreMap.clear();
        for (const f of r.feriados) {
          this.feriadosSet.add(f.fecha.slice(0, 10));
          this.feriadosNombreMap.set(f.fecha.slice(0, 10), f.nombre);
        }
        tick();
      },
      error: () => tick(),
    });
  }

  private rebuild(): void {
    const mes  = this.fechaVista.getMonth();
    const anio = this.fechaVista.getFullYear();
    const hoy  = new Date();

    // ── índices ─────────────────────────────────────────────────────
    const asistMap = new Map<string, any>();
    for (const r of this.registros) {
      // Usa el campo fecha ISO que retorna el backend; fallback al enfoque mes/dia
      if (r.fecha) {
        asistMap.set(r.fecha, r);
      } else {
        const mesNum = MESES_MAP[String(r.mes ?? '').toLowerCase().trim()];
        if (mesNum === undefined) continue;
        const f = `${r.anio}-${String(mesNum+1).padStart(2,'0')}-${String(r.dia).padStart(2,'0')}`;
        asistMap.set(f, r);
      }
    }

    const permisoMap = new Map<string, { tipo: string; aprobado: boolean; horasExtra: boolean }>();
    for (const p of this.permisos) {
      const estado = (p.estado_raw ?? p.estado ?? p.estadoActual ?? '').toLowerCase();
      const aprobado = estado === 'aprobada' || estado === 'aceptado';
      const tipo  = (p.tipo ?? p.titulo ?? 'Permiso').trim();
      const esExtra = tipo.toLowerCase().includes('extra');
      // Preferir campos ISO; fallback al texto formateado
      const fi = p.fecha_inicio_iso ?? p.fecha_inicio ?? p.fechaEmision ?? p.fecha ?? '';
      const ff = p.fecha_fin_iso ?? p.fecha_fin ?? fi;
      if (!fi) continue;
      const start = new Date(fi + 'T00:00:00');
      const end   = new Date(ff + 'T00:00:00');
      if (isNaN(start.getTime())) continue;
      for (const d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
        const key = this.iso(d);
        permisoMap.set(key, { tipo, aprobado, horasExtra: aprobado && esExtra });
      }
    }

    interface OTInfo { estado: string; nombre: string; orden: string; cliente: string; }
    const otMap = new Map<string, OTInfo>();
    for (const s of this.servicios) {
      const f = (s.fecha_programada ?? '').split('T')[0];
      if (f) otMap.set(f, {
        estado:  s.estado       ?? 'Pendiente',
        nombre:  s.nombre       ?? '',
        orden:   s.orden_trabajo ?? '',
        cliente: s.cliente      ?? '',
      });
    }

    // ── cuadrícula ───────────────────────────────────────────────────
    const primerDia  = new Date(anio, mes, 1).getDay();
    const diasEnMes  = new Date(anio, mes + 1, 0).getDate();
    this.diasMes = [];
    for (let i = 0; i < primerDia; i++) this.diasMes.push(this.emptyCell());

    let asistidos = 0, tardanzas = 0, faltas = 0, horasTot = 0, laborables = 0, permisosDias = 0;

    for (let d = 1; d <= diasEnMes; d++) {
      const mStr   = String(mes + 1).padStart(2, '0');
      const dStr   = String(d).padStart(2, '0');
      const fecha  = `${anio}-${mStr}-${dStr}`;
      const dow    = new Date(anio, mes, d).getDay();
      const isWeekend = dow === 0 || dow === 6;
      const isHoy  = fecha === this.iso(hoy);
      const isPast = new Date(anio, mes, d) <= hoy;

      const asist    = asistMap.get(fecha);
      const permData = permisoMap.get(fecha);
      const otInfo   = otMap.get(fecha);

      const entrada = asist?.entrada ?? null;
      // horas_trabajadas_num viene del backend (float); fallback a parsear texto
      const horasTrab = asist?.horas_trabajadas_num
        ?? (parseFloat(String(asist?.horas_trabajadas ?? '0')) || 0);

      // tardanza calculada en backend con el turno real del empleado
      const tardanza = asist?.tardanza ?? false;

      const esFeriado = this.feriadosSet.has(fecha);
      const nomFeriado = esFeriado ? (this.feriadosNombreMap.get(fecha) ?? 'Feriado') : '';

      let tag: DiaCell['tag'] = '';
      if (!isWeekend) {
        if (esFeriado) {
          tag = 'feriado';
          // feriados no cuentan como día laborable ni falta
        } else {
          laborables++;
          if (asist) {
            asistidos++;
            horasTot += horasTrab;
            tag = tardanza ? 'tardanza' : 'asistio';
            if (tardanza) tardanzas++;
          } else if (permData) {
            permisosDias++;
            tag = 'permiso';
          } else if (isPast) {
            faltas++;
            tag = 'falta';
          }
        }
      } else {
        tag = 'libre';
      }

      // tooltip para hover CSS
      let tooltip = '';
      if (tag === 'feriado')  tooltip = nomFeriado;
      if (tag === 'asistio')  tooltip = `${entrada ?? '--'} → ${asist?.salida ?? '--'} · ${horasTrab.toFixed(1)}h`;
      if (tag === 'tardanza') tooltip = `Tardanza · ${entrada ?? '--'} → ${asist?.salida ?? '--'}`;
      if (tag === 'falta')    tooltip = 'Sin marcación';
      if (tag === 'permiso')  tooltip = permData?.tipo ?? 'Permiso';
      if (otInfo)             tooltip += (tooltip ? ' · ' : '') + (otInfo.orden ? `${otInfo.orden}` : 'OT programada');

      this.diasMes.push({
        num: d, fecha, isHoy, isWeekend, tag,
        horaIngreso: entrada ?? '',
        horaSalida:  asist?.salida ?? '',
        horasTrabajadas: horasTrab,
        permisoTipo: permData?.tipo ?? '',
        eventoOT: !!otInfo,
        estadoOT: otInfo?.estado ?? '',
        otNombre:  otInfo?.nombre  ?? '',
        otOrden:   otInfo?.orden   ?? '',
        otCliente: otInfo?.cliente ?? '',
        tooltip,
        nombreFeriado: nomFeriado,
      });
    }

    // horas extra de permisos aprobados en este mes
    let horasExtra = 0;
    for (const p of this.permisos) {
      const estado = (p.estado_raw ?? p.estado ?? p.estadoActual ?? '').toLowerCase();
      if (estado !== 'aprobada' && estado !== 'aceptado') continue;
      const tipo = (p.tipo ?? p.titulo ?? '').toLowerCase();
      if (!tipo.includes('extra')) continue;
      const fi = p.fecha_inicio_iso ?? p.fecha_inicio ?? p.fechaEmision ?? p.fecha ?? '';
      if (!fi) continue;
      const d = new Date(fi + 'T00:00:00');
      if (isNaN(d.getTime())) continue;
      if (d.getFullYear() === anio && d.getMonth() === mes)
        horasExtra += parseFloat(String(p.horas_calculadas ?? p.horasCalculadas ?? '0')) || 0;
    }

    this.kpiAsistidos  = asistidos;
    this.kpiTardanzas  = tardanzas;
    this.kpiFaltas     = faltas;
    this.kpiHoras      = Math.round(horasTot);
    this.kpiHorasExtra = horasExtra;
    this.kpiPermisos   = permisosDias;
    this.kpiLaborables = laborables;
  }

  // ── Interacción ───────────────────────────────────────────────────
  cambiarMes(delta: number): void {
    const anioAntes = this.fechaVista.getFullYear();
    const d = new Date(this.fechaVista);
    d.setMonth(d.getMonth() + delta);
    this.fechaVista = d;
    // Siempre recarga asistencia para el nuevo mes
    this.cargarDatos();
    // Si también cambió el año, los feriados ya se recargan en cargarDatos()
    void anioAntes; // el cambio de año queda cubierto por cargarDatos
  }

  irHoy(): void {
    this.fechaVista = new Date();
    this.cargarDatos();
  }

  abrirDetalle(dia: DiaCell): void {
    if (!dia.num || (!dia.tag && !dia.eventoOT)) return;
    this.diaDetalle = dia;
    document.body.style.overflow = 'hidden';
  }

  cerrarDetalle(): void {
    this.diaDetalle = null;
    document.body.style.overflow = '';
  }

  ngOnDestroy(): void {
    document.body.style.overflow = '';
  }

  volver(): void { this.router.navigate(['/home']); }

  // ── Helpers ───────────────────────────────────────────────────────
  private iso(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  }
  private emptyCell(): DiaCell {
    return { num:null, fecha:'', isHoy:false, isWeekend:false, tag:'',
      horaIngreso:'', horaSalida:'', horasTrabajadas:0, permisoTipo:'',
      eventoOT:false, estadoOT:'', otNombre:'', otOrden:'', otCliente:'',
      tooltip:'', nombreFeriado:'' };
  }
}

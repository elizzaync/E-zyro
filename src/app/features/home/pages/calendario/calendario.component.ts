import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { DashboardService } from '../../../../core/services/dashboard.service';

interface DiaCalendario {
  num: number | null;
  fecha: string;
  isHoy: boolean;
  isWeekend: boolean;
  asistio: boolean;
  tardanza: boolean;
  falta: boolean;
  permiso: boolean;
  horasExtra: boolean;
  evento: boolean;
  estadoEvento: string;
  horaIngreso: string | null;
  horaSalida: string | null;
  horasTrabajadas: number;
  permisoTipo: string;
  tooltipLines: string[];
}

interface KpiCard {
  label: string;
  value: string | number;
  sub: string;
  icon: string;
  color: string;
}

const MESES_NOMBRE = [
  'Enero','Febrero','Marzo','Abril','Mayo','Junio',
  'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'
];

const MESES_MAP: Record<string, number> = {
  enero:0, febrero:1, marzo:2, abril:3, mayo:4, junio:5,
  julio:6, agosto:7, septiembre:8, octubre:9, noviembre:10, diciembre:11
};

@Component({
  selector: 'app-calendario',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './calendario.component.html',
  styleUrls: ['./calendario.component.css']
})
export class CalendarioComponent implements OnInit {
  private dashSvc = inject(DashboardService);
  private router  = inject(Router);

  // ── Estado ────────────────────────────────────────────────────────
  cargando = true;
  fechaVista = new Date();

  diasMes: DiaCalendario[] = [];
  diasSemana = ['Dom','Lun','Mar','Mié','Jue','Vie','Sáb'];

  // raw data
  private registrosAsistencia: any[] = [];
  private misPermisos: any[] = [];
  private eventosCalendario: any = null;

  // KPIs
  kpis: KpiCard[] = [];

  // detalle modal
  diaDetalle: DiaCalendario | null = null;

  get mesLabel(): string {
    return `${MESES_NOMBRE[this.fechaVista.getMonth()]} ${this.fechaVista.getFullYear()}`;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────
  ngOnInit(): void {
    this.cargarDatos();
  }

  private cargarDatos(): void {
    this.cargando = true;
    let loaded = 0;
    const check = () => { if (++loaded === 3) { this.cargando = false; this.buildAll(); } };

    this.dashSvc.getAsistencia().subscribe({
      next: (res: any) => {
        this.registrosAsistencia = res?.data ?? res ?? [];
        check();
      },
      error: () => { this.registrosAsistencia = []; check(); }
    });

    this.dashSvc.getPermisos().subscribe({
      next: (res: any) => {
        this.misPermisos = res?.data ?? res ?? [];
        check();
      },
      error: () => { this.misPermisos = []; check(); }
    });

    this.dashSvc.getCalendarioEventos().subscribe({
      next: (res: any) => {
        this.eventosCalendario = res?.data ?? null;
        check();
      },
      error: () => { this.eventosCalendario = null; check(); }
    });
  }

  // ── Build calendar + KPIs ─────────────────────────────────────────
  private buildAll(): void {
    this.buildCalendario();
    this.buildKpis();
  }

  private buildCalendario(): void {
    const hoy   = new Date();
    const mes   = this.fechaVista.getMonth();
    const anio  = this.fechaVista.getFullYear();
    const primerDia   = new Date(anio, mes, 1).getDay();
    const diasEnMes   = new Date(anio, mes + 1, 0).getDate();

    // index asistencia por fecha YYYY-MM-DD
    const asistMap = new Map<string, any>();
    for (const r of this.registrosAsistencia) {
      const mesNum = MESES_MAP[String(r.mes ?? '').toLowerCase().trim()];
      if (mesNum === undefined) continue;
      const f = `${r.anio}-${String(mesNum + 1).padStart(2,'0')}-${String(r.dia).padStart(2,'0')}`;
      asistMap.set(f, r);
    }

    // index permisos por rango de fechas
    const permisosDias = new Map<string, { tipo: string; horasExtra: boolean }>();
    for (const p of this.misPermisos) {
      const estado = (p.estado ?? p.estadoActual ?? '').toLowerCase();
      const esAprobado = estado === 'aprobada' || estado === 'aceptado';
      const tipo = (p.tipo ?? p.titulo ?? '').toLowerCase();
      const esHorasExtra = tipo.includes('extra') || tipo.includes('hora extra');
      const fi = p.fecha_inicio ?? p.fechaEmision ?? p.fecha ?? '';
      const ff = p.fecha_fin   ?? fi;
      if (!fi) continue;
      const start = new Date(fi + 'T00:00:00');
      const end   = new Date(ff + 'T00:00:00');
      for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
        const key = this.isoDate(d);
        if (!permisosDias.has(key) || (esAprobado && esHorasExtra)) {
          permisosDias.set(key, {
            tipo: p.tipo ?? p.titulo ?? 'Permiso',
            horasExtra: esAprobado && esHorasExtra
          });
        }
      }
    }

    // index eventos
    const eventosMap = new Map<string, string>();
    const servicios: any[] = this.eventosCalendario?.servicios ?? [];
    for (const srv of servicios) {
      const f = srv.fecha_programada?.split('T')[0];
      if (f) eventosMap.set(f, srv.estado ?? 'Pendiente');
    }

    this.diasMes = [];

    // empty cells
    for (let i = 0; i < primerDia; i++) {
      this.diasMes.push(this.emptyCell());
    }

    for (let i = 1; i <= diasEnMes; i++) {
      const mStr   = String(mes + 1).padStart(2,'0');
      const dStr   = String(i).padStart(2,'0');
      const fecha  = `${anio}-${mStr}-${dStr}`;
      const dow    = new Date(anio, mes, i).getDay();
      const isWeekend = dow === 0 || dow === 6;
      const isHoy  = fecha === this.isoDate(hoy);

      const asist      = asistMap.get(fecha);
      const permData   = permisosDias.get(fecha);
      const eventoEst  = eventosMap.get(fecha);

      const asistio = !!asist && !isWeekend;
      const entrada = asist?.entrada ?? null;
      const horasTrab = Number(asist?.horas_trabajadas ?? 0);

      // Tardanza: entrada después de 08:30
      let tardanza = false;
      if (asistio && entrada) {
        const [h, m] = entrada.split(':').map(Number);
        tardanza = h > 8 || (h === 8 && m > 30);
      }

      // Falta: día laborable (lun-vie) en el mes pasado/actual, sin asistencia, sin permiso de día completo
      const isPast  = new Date(anio, mes, i) < hoy || isHoy;
      const falta   = !isWeekend && isPast && !asistio && !permData;

      const tooltipLines: string[] = [];
      if (asistio) tooltipLines.push(`Entrada: ${entrada ?? '--'} · Salida: ${asist?.salida ?? '--'}`);
      if (horasTrab > 0) tooltipLines.push(`${horasTrab.toFixed(1)}h trabajadas`);
      if (tardanza) tooltipLines.push('Tardanza registrada');
      if (permData) tooltipLines.push(permData.tipo);
      if (eventoEst) tooltipLines.push(`OT: ${eventoEst}`);
      if (falta) tooltipLines.push('Sin marcación');

      this.diasMes.push({
        num: i,
        fecha,
        isHoy,
        isWeekend,
        asistio,
        tardanza,
        falta,
        permiso: !!permData && !permData.horasExtra,
        horasExtra: !!permData?.horasExtra,
        evento: !!eventoEst,
        estadoEvento: eventoEst ?? '',
        horaIngreso: entrada,
        horaSalida: asist?.salida ?? null,
        horasTrabajadas: horasTrab,
        permisoTipo: permData?.tipo ?? '',
        tooltipLines,
      });
    }
  }

  private buildKpis(): void {
    const mes  = this.fechaVista.getMonth();
    const anio = this.fechaVista.getFullYear();

    const diasValidos = this.diasMes.filter(d => d.num !== null && !d.isWeekend);

    const asistidos  = diasValidos.filter(d => d.asistio).length;
    const faltados   = diasValidos.filter(d => d.falta).length;
    const tardanzas  = diasValidos.filter(d => d.tardanza).length;
    const horasTot   = diasValidos.reduce((s, d) => s + d.horasTrabajadas, 0);

    // Horas extra: solo de permisos aprobados con tipo horas extra en este mes
    let horasExtraTot = 0;
    for (const p of this.misPermisos) {
      const estado = (p.estado ?? p.estadoActual ?? '').toLowerCase();
      if (estado !== 'aprobada' && estado !== 'aceptado') continue;
      const tipo = (p.tipo ?? p.titulo ?? '').toLowerCase();
      if (!tipo.includes('extra')) continue;
      const fi = p.fecha_inicio ?? p.fechaEmision ?? p.fecha ?? '';
      if (!fi) continue;
      const d = new Date(fi + 'T00:00:00');
      if (d.getFullYear() === anio && d.getMonth() === mes) {
        horasExtraTot += Number(p.horas_calculadas ?? p.horasCalculadas ?? 0);
      }
    }

    this.kpis = [
      {
        label: 'Días Asistidos',
        value: asistidos,
        sub: `de ${diasValidos.length} días laborables`,
        icon: 'check-circle',
        color: 'green'
      },
      {
        label: 'Horas Trabajadas',
        value: `${horasTot.toFixed(0)}h`,
        sub: `${(horasTot / 8).toFixed(1)} jornadas completas`,
        icon: 'clock',
        color: 'blue'
      },
      {
        label: 'Horas Extra',
        value: `${horasExtraTot.toFixed(1)}h`,
        sub: 'Permisos aprobados',
        icon: 'lightning',
        color: 'amber'
      },
      {
        label: 'Días Faltados',
        value: faltados,
        sub: faltados === 0 ? 'Sin inasistencias' : `${faltados} ausencias`,
        icon: 'x-circle',
        color: 'red'
      },
      {
        label: 'Tardanzas',
        value: tardanzas,
        sub: tardanzas === 0 ? 'Puntualidad perfecta' : `${tardanzas} llegadas tarde`,
        icon: 'warning',
        color: 'orange'
      },
    ];
  }

  // ── Navegación ────────────────────────────────────────────────────
  cambiarMes(delta: number): void {
    const d = new Date(this.fechaVista);
    d.setMonth(d.getMonth() + delta);
    this.fechaVista = d;
    this.buildAll();
  }

  irHoy(): void {
    this.fechaVista = new Date();
    this.buildAll();
  }

  // ── Modal detalle ─────────────────────────────────────────────────
  abrirDetalle(dia: DiaCalendario): void {
    if (!dia.num) return;
    this.diaDetalle = dia;
  }

  cerrarDetalle(): void {
    this.diaDetalle = null;
  }

  // ── Helpers ───────────────────────────────────────────────────────
  volver(): void {
    this.router.navigate(['/home']);
  }

  private isoDate(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  }

  private emptyCell(): DiaCalendario {
    return {
      num: null, fecha: '', isHoy: false, isWeekend: false,
      asistio: false, tardanza: false, falta: false, permiso: false,
      horasExtra: false, evento: false, estadoEvento: '', horaIngreso: null,
      horaSalida: null, horasTrabajadas: 0, permisoTipo: '', tooltipLines: []
    };
  }

  get porcentajeAsistencia(): number {
    const laborables = this.diasMes.filter(d => d.num !== null && !d.isWeekend).length;
    const asistidos  = this.diasMes.filter(d => d.num !== null && !d.isWeekend && d.asistio).length;
    return laborables > 0 ? Math.round((asistidos / laborables) * 100) : 0;
  }
}

import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { DashboardService } from '../../../../core/services/dashboard.service';
import { ToastService } from '../../../../core/services/toast.service';

type EstadoColor = 'pendiente' | 'en-proceso' | 'completado';
type RangePos    = 'single' | 'start' | 'mid' | 'end';

interface DiaCalendario {
  num:         number | null;
  isHoy:       boolean;
  hasEvent:    boolean;
  hasNote:     boolean;
  fechaStr:    string;
  tooltipText: string;
  eventColor:  EstadoColor | '';
  rangePos:    RangePos | '';
}

interface EventoFecha {
  estado: string;
  tipo:   'servicio' | 'proyecto';
}

@Component({
  selector: 'app-calendar-widget',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, SpinnerComponent, AppModalComponent],
  templateUrl: './calendar-widget.component.html',
  styleUrls: ['./calendar-widget.component.css']
})
export class CalendarWidgetComponent implements OnInit, OnDestroy {
  fechaVista = new Date();
  mesActual  = '';
  diasSemana = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];

  private toastService = inject(ToastService);
  private router       = inject(Router);

  diasMes:         DiaCalendario[] = [];
  notasGuardadas:  Record<string, string> = {};
  diasConServicio: string[] = [];
  proximosEventos: any[] = [];

  private eventosPorFecha = new Map<string, EventoFecha[]>();

  // Modal nota
  showModal        = false;
  diaSeleccionado: any = null;
  textoNota        = '';

  // Modal servicio
  showServicioModal = false;
  serviciosDelDia:  any[] = [];
  cargandoServicio  = false;
  servicioModoNota  = false;

  constructor(private dashboardService: DashboardService) {}

  ngOnInit(): void {
    this.generarCalendario();
    this.dashboardService.refreshWidgets$.subscribe(() => {
      this.cargarDatosCalendario();
    });
  }

  ngOnDestroy(): void {
    document.body.style.overflow = '';
  }

  // ── CARGA DE DATOS ───────────────────────────────────────────────
  cargarDatosCalendario(): void {
    this.dashboardService.getCalendarioEventos().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.proximosEventos = res.data.proximosEventos ?? [];
          this.notasGuardadas  = res.data.notas ?? {};
          this._procesarEventos(res.data);
          this.generarCalendario();
        }
      },
      error: (err) => console.error('Error cargando calendario', err)
    });
  }

  // ── TRANSFORMADOR: API → eventosPorFecha ─────────────────────────
  private _procesarEventos(data: any): void {
    this.eventosPorFecha.clear();

    // Servicios operativos: fecha_programada (día único) — fuente principal
    const servicios: any[] = data.servicios ?? [];
    for (const srv of servicios) {
      const fecha = srv.fecha_programada?.split('T')[0];
      if (!fecha) continue;
      const list = this.eventosPorFecha.get(fecha) ?? [];
      list.push({ estado: srv.estado ?? 'Pendiente', tipo: 'servicio' });
      this.eventosPorFecha.set(fecha, list);
    }

    // Retrocompat: si el backend aún no devuelve 'servicios', usar diasConServicio
    if (!servicios.length) {
      const fechasPlanas: string[] = data.diasConServicio ?? [];
      for (const fecha of fechasPlanas) {
        if (!this.eventosPorFecha.has(fecha)) {
          this.eventosPorFecha.set(fecha, [{ estado: 'Pendiente', tipo: 'servicio' }]);
        }
      }
    }

    // Nota: los rangos de Proyectos se muestran en el Cronograma (/operaciones/cronograma/:id)
    // y no se renderizan en este calendario para evitar confusión con los servicios.

    this.diasConServicio = [...this.eventosPorFecha.keys()];
  }

  // Prioridad visual: En_Proceso > Pendiente > Completado
  private _colorDominante(eventos: EventoFecha[]): EstadoColor {
    if (eventos.some(e => e.estado === 'En_Proceso')) return 'en-proceso';
    if (eventos.some(e => e.estado === 'Pendiente'))  return 'pendiente';
    return 'completado';
  }

  // ── GENERACIÓN DE LA CUADRÍCULA ──────────────────────────────────
  generarCalendario(): void {
    const hoy  = new Date();
    const mes  = this.fechaVista.getMonth();
    const anio = this.fechaVista.getFullYear();

    const meses = ['Enero','Febrero','Marzo','Abril','Mayo','Junio',
                   'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
    this.mesActual = `${meses[mes]} ${anio}`;

    const primerDia = new Date(anio, mes, 1).getDay();
    const diasEnMes = new Date(anio, mes + 1, 0).getDate();
    this.diasMes    = [];

    for (let i = 0; i < primerDia; i++) {
      this.diasMes.push({ num: null, isHoy: false, hasEvent: false, hasNote: false,
                          fechaStr: '', tooltipText: '', eventColor: '', rangePos: '' });
    }

    for (let i = 1; i <= diasEnMes; i++) {
      const isHoy    = i === hoy.getDate() && mes === hoy.getMonth() && anio === hoy.getFullYear();
      const mStr     = String(mes + 1).padStart(2, '0');
      const dStr     = String(i).padStart(2, '0');
      const fechaStr = `${anio}-${mStr}-${dStr}`;

      const eventos  = this.eventosPorFecha.get(fechaStr) ?? [];
      const nota     = this.notasGuardadas[fechaStr];
      const hasNote  = !!nota;
      const hasEvent = eventos.length > 0 || hasNote;

      let eventColor: EstadoColor | '' = '';
      let rangePos:   RangePos   | '' = '';

      if (eventos.length > 0) {
        eventColor = this._colorDominante(eventos);

        if (eventos.some(e => e.tipo === 'proyecto')) {
          const weekDay    = new Date(anio, mes, i).getDay();
          const isRowStart = weekDay === 0;
          const isRowEnd   = weekDay === 6;

          const prevKey     = i > 1        ? `${anio}-${mStr}-${String(i - 1).padStart(2, '0')}` : '';
          const nextKey     = i < diasEnMes ? `${anio}-${mStr}-${String(i + 1).padStart(2, '0')}` : '';
          const prevHasProy = prevKey ? (this.eventosPorFecha.get(prevKey)?.some(e => e.tipo === 'proyecto') ?? false) : false;
          const nextHasProy = nextKey ? (this.eventosPorFecha.get(nextKey)?.some(e => e.tipo === 'proyecto') ?? false) : false;

          const visualStart = !prevHasProy || isRowStart;
          const visualEnd   = !nextHasProy || isRowEnd;

          rangePos = visualStart && visualEnd ? 'single'
                   : visualStart              ? 'start'
                   : visualEnd                ? 'end'
                   :                           'mid';
        } else {
          rangePos = 'single';
        }
      }

      let tooltipText = '';
      if (hasEvent) {
        const tieneServicio = this.diasConServicio.includes(fechaStr);
        if (tieneServicio && nota) tooltipText = `📌 OT Programada\n📝 ${nota}`;
        else if (tieneServicio)   tooltipText = `📌 OT Programada`;
        else if (nota)            tooltipText = `📝 ${nota}`;
      }

      this.diasMes.push({ num: i, isHoy, hasEvent, hasNote, fechaStr, tooltipText, eventColor, rangePos });
    }
  }

  cambiarMes(delta: number): void {
    this.fechaVista.setMonth(this.fechaVista.getMonth() + delta);
    this.generarCalendario();
  }

  get servicioModalTitle(): string {
    if (this.cargandoServicio) return 'Cargando…';
    if (this.servicioModoNota) {
      const key = this.diaSeleccionado?.fechaStr;
      return key && this.notasGuardadas[key] ? 'Editar Nota' : 'Añadir Nota';
    }
    if (this.serviciosDelDia.length === 1) return this.serviciosDelDia[0].nombre ?? 'Detalle del Servicio';
    if (this.serviciosDelDia.length > 1)  return `${this.serviciosDelDia.length} Servicios`;
    return 'Detalle del Servicio';
  }

  get servicioModalSubtitle(): string {
    if (!this.diaSeleccionado) return '';
    return `${this.diaSeleccionado.num} de ${this.mesActual}`;
  }

  abrirModal(dia: any): void {
    if (!dia.num) return;
    this.diaSeleccionado = dia;

    if (this.diasConServicio.includes(dia.fechaStr)) {
      this.servicioModoNota  = false;
      this.serviciosDelDia   = [];
      this.cargandoServicio  = true;
      this.showServicioModal = true;
      document.body.style.overflow = 'hidden';
      this.dashboardService.getDetalleServicioDia(dia.fechaStr).subscribe({
        next: (res: any) => {
          this.serviciosDelDia  = res.data || [];
          this.cargandoServicio = false;
        },
        error: () => { this.cargandoServicio = false; }
      });
    } else {
      this.textoNota = this.notasGuardadas[dia.fechaStr] || '';
      this.showModal = true;
      document.body.style.overflow = 'hidden';
    }
  }

  cerrarModal(): void {
    this.showModal       = false;
    this.diaSeleccionado = null;
    document.body.style.overflow = '';
  }

  cerrarServicioModal(): void {
    this.showServicioModal = false;
    this.servicioModoNota  = false;
    this.serviciosDelDia   = [];
    document.body.style.overflow = '';
  }

  abrirNotaDesdeServicio(): void {
    this.servicioModoNota = true;
    this.textoNota = this.notasGuardadas[this.diaSeleccionado.fechaStr] || '';
  }

  verEnOperaciones(): void {
    if (this.serviciosDelDia.length === 1) {
      this.router.navigate(['/operaciones/servicio', this.serviciosDelDia[0].id]);
    } else {
      this.router.navigate(['/operaciones'], {
        queryParams: { fecha: this.diaSeleccionado?.fechaStr }
      });
    }
    this.cerrarServicioModal();
  }

  eliminarNota(): void {
    this.textoNota = '';
    this.guardarNota();
  }

  guardarNota(): void {
    const textoLimpio  = this.textoNota.trim();
    const notaOriginal = this.notasGuardadas[this.diaSeleccionado.fechaStr];

    let mensajeToast = '';
    if (!textoLimpio && notaOriginal) {
      mensajeToast = 'Evento eliminado correctamente';
    } else if (textoLimpio && notaOriginal && textoLimpio !== notaOriginal) {
      mensajeToast = 'Evento actualizado correctamente';
    } else if (textoLimpio && !notaOriginal) {
      mensajeToast = 'Evento creado correctamente';
    } else {
      this.servicioModoNota ? (this.servicioModoNota = false) : this.cerrarModal();
      return;
    }

    this.dashboardService.guardarNotaCalendario(this.diaSeleccionado.fechaStr, this.textoNota).subscribe({
      next: () => {
        if (this.servicioModoNota) {
          this.servicioModoNota = false;
        } else {
          this.cerrarModal();
        }
        this.toastService.mostrar(mensajeToast, 'success');
        this.dashboardService.refreshWidgets$.next(true);
      },
      error: () => this.toastService.mostrar('Error al procesar el evento', 'error')
    });
  }
}
